// ============================================================
//  lib/screens/lesson_3d_screen.dart
//  3D interaktif ders ekranı (HTML + Three.js).
//
//  Asset olarak gömülen HTML dosyasını WebView'de açar.
//  loadFlutterAsset kullanılır — Android'de WebViewAssetLoader
//  üzerinden https://appassets.androidplatform.net/ ile sunulur,
//  böylece ES module import map'i (Three.js) düzgün çalışır.
//  İnternet gerektirmez.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/ai_quota_service.dart';
import '../services/analytics.dart';
import '../services/tts_service.dart';
import '../services/gemini_service.dart';
import '../services/locale_service.dart';
import '../services/runtime_translator.dart';
import 'academic_planner.dart';
import 'premium_screen.dart';

// Web'de webview_flutter desteklenmediği için HTML asset iframe ile gösterilir.
// Mobil/masaüstünde stub döner (kIsWeb ile dallanılır, çağrılmaz).
import 'html_asset_view_stub.dart'
    if (dart.library.html) 'html_asset_view_web.dart';

class Lesson3DScreen extends StatefulWidget {
  /// pubspec.yaml assets listesindeki HTML yolu
  /// (örn: 'assets/dunyanin-hareketleri.html')
  final String assetHtml;

  /// Üst çubukta görünecek başlık
  final String title;

  const Lesson3DScreen({
    super.key,
    required this.assetHtml,
    this.title = '3D Ders',
  });

  @override
  State<Lesson3DScreen> createState() => _Lesson3DScreenState();
}

class _Lesson3DScreenState extends State<Lesson3DScreen> {
  // Web'de WebViewController KULLANILMAZ (platform implementasyonu yok →
  // assertion hatası). Bu yüzden nullable ve sadece mobil/masaüstünde kurulur.
  WebViewController? _controller;
  bool _loading = true;
  String? _error;
  final GlobalKey _screenshotKey = GlobalKey();
  // Gelişim Paneli — 3D derste geçirilen süre (dispose'da yazılır).
  final DateTime _openedAt = DateTime.now();

  /// Web hedefinde iframe src'i: Flutter web asset'leri `assets/<assetKey>`
  /// yolundan sunar (assetKey zaten 'assets/...' ile başladığı için çift olur).
  String get _webAssetUrl => 'assets/${widget.assetHtml}';

  @override
  void initState() {
    super.initState();
    Analytics.logFeatureOpen('3d_lesson');
    if (kIsWeb) {
      // iframe anında yüklenir; yükleme katmanı gösterme.
      _loading = false;
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF070B22))
      ..addJavaScriptChannel(
        'FlutterShare',
        onMessageReceived: (msg) => _handleShare(msg.message),
      )
      ..addJavaScriptChannel(
        'FlutterNativeShot',
        onMessageReceived: (_) => _takeNativeScreenshot(),
      )
      ..addJavaScriptChannel(
        // Sınav oluştur / AI'ya sor / Sesli anlatım köprüsü
        'FlutterBridge',
        onMessageReceived: (msg) => _handleBridge(msg.message),
      )
      ..addJavaScriptChannel(
        // 3D ders içeriği çeviri köprüsü: HTML görünür Türkçe metinleri
        // toplar, burada hedef dile çevrilip geri enjekte edilir.
        'FlutterI18n',
        onMessageReceived: (msg) => _handleI18nRequest(msg.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            if (mounted) setState(() => _loading = false);
            // Dil Türkçe değilse 3D ders içeriğini hedef dile çevir.
            await _injectI18n();
            if (!AiQuotaService.instance.isPremium) {
              await _injectPremiumGate();
            }
          },
          onWebResourceError: (err) {
            // ES module veya alt-frame hataları main frame'i bozmaz —
            // sadece main frame hatalarında banner göster.
            if (err.isForMainFrame == false) return;
            if (mounted) {
              setState(() {
                _loading = false;
                _error = '${'Yükleme hatası'.tr()}: ${err.description}';
              });
            }
          },
        ),
      )
      ..loadFlutterAsset(widget.assetHtml);
  }

  /// HTML'den gelen aksiyonlar: 'exam' → Sınav Oluştur sayfası,
  /// 'ai' → AI'ya Sor sohbeti, 'speak'/'stopSpeak' → sesli anlatım (TTS).
  Future<void> _handleBridge(String message) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final action = data['action'] as String? ?? '';
    if (action == 'speak') {
      final text = (data['text'] as String? ?? '').trim();
      if (text.isNotEmpty) {
        try {
          await TtsService.stop();
          // Cümlelere böl ve sırayla doğal (insansı) oku — uzun metinde de akıcı.
          final sentences = text
              .split(RegExp(r'(?<=[.!?…:])\s+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty);
          for (final s in sentences) {
            TtsService.enqueue(s);
          }
        } catch (_) {}
      }
      return;
    }
    if (action == 'stopSpeak') {
      try { await TtsService.stop(); } catch (_) {}
      return;
    }
    if (!mounted) return;
    if (action == 'exam') {
      // Kütüphanedeki Test Oluştur sayfası; o anki ders+konu ön seçili gelir.
      final subject = (data['subject'] as String? ?? '').trim();
      final topic = (data['topic'] as String? ?? '').trim();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AcademicPlanner(
            mode: LibraryMode.questions,
            autoOpenSubject: subject.isEmpty ? null : subject,
            autoOpenTopic: topic.isEmpty ? null : topic,
          ),
        ),
      );
    } else if (action == 'premiumGate') {
      _showPremiumGateSheet();
    } else if (action == 'ai') {
      // Koç akışı DEĞİL — doğrudan "Sana nasıl yardımcı olabilirim?" paneli.
      final topic = (data['topic'] as String? ?? '').trim();
      final level = (data['level'] as String? ?? '').trim();
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AskAiSheet(topic: topic, level: level),
      );
    }
  }

  /// JavaScript enjekte eder: sahne ileri/geri, Araçlar popup öğeleri ve
  /// Konu Rehberi dropdown öğelerini premium kapısına yönlendirir.
  /// Ücretsiz: spinBtn/labelBtn/animBtn (sol panel), btnHelp, btnLevel.
  Future<void> _injectPremiumGate() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    const js = r"""
(function(){
  "use strict";
  function _gate(f){try{window.FlutterBridge.postMessage(JSON.stringify({action:"premiumGate",feature:f}));}catch(e){}}
  function _block(el,f){if(!el||el._pg)return;el._pg=true;el.addEventListener("click",function(e){e.stopImmediatePropagation();e.preventDefault();_gate(f);},true);}
  _block(document.getElementById("navPrev"),"scene");
  _block(document.getElementById("navNext"),"scene");
  function _gArc(){
    var p=document.getElementById("araclarComboP");
    if(p&&!p._pg){p._pg=true;p.addEventListener("click",function(e){
      var it=e.target.closest(".combo-pop-item");
      if(it){e.stopImmediatePropagation();e.preventDefault();try{p.classList.remove("show");}catch(_){}try{var bl=document.getElementById("_popBlur");if(bl)bl.style.display="none";}catch(_){}_gate("tools");}
    },true);}
  }
  function _gTop(){
    var p=document.getElementById("panelTopic");
    if(p&&!p._pg){p._pg=true;p.addEventListener("click",function(e){
      var it=e.target.closest(".dropdown-item");
      if(it){e.stopImmediatePropagation();e.preventDefault();try{p.classList.remove("show");}catch(_){}_gate("topic");}
    },true);}
  }
  _gArc();_gTop();
  var _mo=new MutationObserver(function(){_gArc();_gTop();});
  _mo.observe(document.documentElement,{childList:true,subtree:true});
  setTimeout(function(){
    _gArc();_gTop();
    _block(document.getElementById("navPrev"),"scene");
    _block(document.getElementById("navNext"),"scene");
  },700);
  setTimeout(function(){_gArc();_gTop();},1600);
})();
""";
    try { await ctrl.runJavaScript(js); } catch (_) {}
  }

  // ── 3D DERS İÇERİĞİ ÇEVİRİSİ (i18n) ───────────────────────────────────────
  // Uygulama dili Türkçe değilse, HTML içindeki görünür Türkçe metinleri
  // toplayıp hedef dile çevirir ve geri enjekte eder. Çeviri RuntimeTranslator
  // üzerinden yapılır (cache + baked + Gemini); ikinci açılışta offline/anında.

  /// Hedef dili sayfaya bildir + i18n motorunu enjekte et.
  Future<void> _injectI18n() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final lang = LocaleService.global?.localeCode ?? 'tr';
    if (lang == 'tr') return; // kaynak dil — çeviriye gerek yok
    try {
      await ctrl.runJavaScript('window.__APP_LANG = ${jsonEncode(lang)};');
      await ctrl.runJavaScript(_i18nEngineJs);
    } catch (_) {}
  }

  /// WebView'dan gelen "şu Türkçe metinleri çevir" isteğini karşılar.
  Future<void> _handleI18nRequest(String message) async {
    final List<String> strings;
    final String lang;
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      lang = (data['lang'] as String?) ?? '';
      final raw = data['strings'];
      if (raw is! List) return;
      strings = raw.map((e) => e.toString()).toList();
    } catch (_) {
      return;
    }
    if (lang.isEmpty || lang == 'tr' || strings.isEmpty) return;

    // 1) Anında hazır olanları (cache + baked) hemen geri gönder.
    final instant = RuntimeTranslator.instance.peekCached(strings, lang);
    if (instant.isNotEmpty) await _pushI18n(instant);
    // 2) Eksikleri çevir (API) + kalıcılaştır. Her batch hazır olunca artımlı
    //    olarak enjekte et — kullanıcı tümünü beklemeden çevirileri görür.
    try {
      await RuntimeTranslator.instance.translateStrings(
        strings,
        lang,
        onBatch: (batch) => _pushI18n(batch),
      );
    } catch (_) {}
  }

  /// Çeviri haritasını WebView'a geri enjekte et.
  Future<void> _pushI18n(Map<String, String> map) async {
    final ctrl = _controller;
    if (!mounted || ctrl == null || map.isEmpty) return;
    // jsonEncode(map) → JSON metni; tekrar jsonEncode → güvenli JS string sabiti.
    final js =
        'window.__applyI18n && window.__applyI18n(${jsonEncode(jsonEncode(map))});';
    try { await ctrl.runJavaScript(js); } catch (_) {}
  }

  // i18n motoru (idempotent): DOM metinlerini + seçili attribute'ları toplar,
  // Flutter'a gönderir, gelen çeviriyi uygular ve MutationObserver ile dinamik
  // içeriği (sahne değişimi vb.) yeniden çevirir. Zaten çevrilmiş düğümleri
  // (__i18nOut) atlayarak çift-çeviri/döngü önlenir.
  static const String _i18nEngineJs = r"""
(function(){
  "use strict";
  if (window.__i18nReady) return;
  window.__i18nReady = true;
  var LANG = window.__APP_LANG || 'tr';
  if (LANG === 'tr') return;

  var DICT = Object.create(null);     // kaynak -> çeviri
  var PENDING = Object.create(null);  // Flutter'a soruldu, bekleniyor
  var QUEUE = Object.create(null);    // sıradaki istek
  var TEXT_NODES = [];                // benzersiz metin düğümü kayıtları
  var ATTR_NODES = [];               // benzersiz attribute kayıtları
  var applying = false;
  var SKIP = {SCRIPT:1, STYLE:1, NOSCRIPT:1, CANVAS:1, TEXTAREA:1, INPUT:1};
  var ATTRS = ['placeholder','title','aria-label','data-label'];

  function hasLetters(s){ return /[A-Za-zÀ-ɏĞğİıŞş]/.test(s); }
  function norm(s){ return (s||'').replace(/\s+/g,' ').trim(); }
  function want(src){ if (DICT[src] === undefined && !PENDING[src]) QUEUE[src] = true; }

  function applyText(r){
    var tr = DICT[r.src]; if (tr === undefined) return;
    var raw = r.n.nodeValue || '';
    var lead = (raw.match(/^\s*/)||[''])[0];
    var trail = (raw.match(/\s*$/)||[''])[0];
    var out = lead + tr + trail;
    if (r.n.nodeValue !== out){ applying = true; r.n.nodeValue = out; r.n.__i18nOut = out; applying = false; }
  }
  function applyAttr(r){
    var tr = DICT[r.src]; if (tr === undefined) return;
    if (r.el.getAttribute(r.a) !== tr){ r.el.setAttribute(r.a, tr); r.el['__i18nA_'+r.a] = tr; }
  }
  function applyAll(){
    for (var i=0;i<TEXT_NODES.length;i++) applyText(TEXT_NODES[i]);
    for (var k=0;k<ATTR_NODES.length;k++) applyAttr(ATTR_NODES[k]);
  }

  // Tek metin düğümünü işle — düğüm başına TEK kayıt tutar (değişince günceller),
  // böylece sık güncellenen sayaçlarda bile liste şişmez.
  function takeText(n){
    var p = n.parentNode;
    if (!p || SKIP[p.nodeName]) return;
    var cur = norm(n.nodeValue);
    if (cur.length < 2 || !hasLetters(cur)) return;
    if (n.__i18nOut && norm(n.__i18nOut) === cur) return; // bizim çıktımız → döngü yok
    var rec = n.__i18nRec;
    if (rec){ rec.src = cur; } else { rec = {n:n, src:cur}; n.__i18nRec = rec; TEXT_NODES.push(rec); }
    if (DICT[cur] !== undefined) applyText(rec); else want(cur);
  }
  function takeAttrs(el){
    if (!el.getAttribute) return;
    for (var j=0;j<ATTRS.length;j++){
      var a = ATTRS[j];
      var v = el.getAttribute(a);
      if (!v) continue;
      var s = norm(v);
      if (s.length < 2 || !hasLetters(s)) continue;
      if (el['__i18nA_'+a] && norm(el['__i18nA_'+a]) === s) continue;
      var rk = '__i18nRecA_'+a;
      var rec = el[rk];
      if (rec){ rec.src = s; } else { rec = {el:el, a:a, src:s}; el[rk] = rec; ATTR_NODES.push(rec); }
      if (DICT[s] !== undefined) applyAttr(rec); else want(s);
    }
  }

  // Bir alt-ağacı (yalnızca eklenen/değişen kısmı) tara — tüm DOM değil.
  function scanSubtree(root){
    if (!root) return;
    if (root.nodeType === 3){ takeText(root); return; }
    if (root.nodeType !== 1 || SKIP[root.nodeName]) return;
    takeAttrs(root);
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    var n; while ((n = walker.nextNode())) takeText(n);
    var els;
    try { els = root.querySelectorAll('[placeholder],[title],[aria-label],[data-label]'); }
    catch(e){ els = []; }
    for (var i=0;i<els.length;i++) takeAttrs(els[i]);
  }

  var flushT = null;
  function scheduleFlush(){ if (flushT) clearTimeout(flushT); flushT = setTimeout(flush, 200); }
  function flush(){
    var arr = Object.keys(QUEUE);
    if (!arr.length) return;
    QUEUE = Object.create(null);
    for (var i=0;i<arr.length;i++) PENDING[arr[i]] = true;
    try { FlutterI18n.postMessage(JSON.stringify({lang:LANG, strings:arr})); } catch(e){}
  }

  // Flutter'dan çeviri geldiğinde
  window.__applyI18n = function(json){
    try {
      var map = (typeof json === 'string') ? JSON.parse(json) : json;
      for (var key in map){ DICT[key] = map[key]; delete PENDING[key]; }
      applyAll();
    } catch(e){}
  };

  // İlk tam tarama (yalnız bir kez)
  scanSubtree(document.body);
  scheduleFlush();

  // Dinamik içerik: yalnızca değişen düğüm/alt-ağaç işlenir (tam yeniden tarama yok)
  try {
    var mo = new MutationObserver(function(muts){
      var changed = false;
      for (var i=0;i<muts.length;i++){
        var m = muts[i];
        if (m.type === 'characterData'){
          if (applying) continue;
          takeText(m.target); changed = true;
        } else if (m.type === 'childList' && m.addedNodes){
          for (var a=0;a<m.addedNodes.length;a++){ scanSubtree(m.addedNodes[a]); changed = true; }
        }
      }
      if (changed) scheduleFlush();
    });
    mo.observe(document.body, {childList:true, subtree:true, characterData:true});
  } catch(e){}
})();
""";

  void _showPremiumGateSheet() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF161B2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0xFF9D7FE6), width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              'Premium Özellik'.tr(),
              style: const TextStyle(
                color: Color(0xFFFFD166), fontSize: 20, fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Bu özellik Premium üyelere özeldir. Tüm sahnelere, araçlara ve konu rehberine sınırsız erişmek için Premium\'a geç.'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB9C2EE), fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PremiumScreen()),
                  );
                },
                child: Text(
                  'Premium\'a Geç'.tr(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Geri Dön'.tr(), style: const TextStyle(color: Color(0xFF8A93B0))),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Dersten çıkınca sesli anlatımı durdur.
    if (!kIsWeb) {
      try { TtsService.stop(); } catch (_) {}
    }
    // Gelişim Paneli — 3D ders süresini kaydet (type '3d').
    final sec = DateTime.now().difference(_openedAt).inSeconds;
    if (sec >= 5) {
      final t = widget.title.trim().isEmpty ? '3D Ders' : widget.title.trim();
      unawaited(logActivitySession(
        subject: t, topic: t, type: '3d', durationSec: sec));
    }
    super.dispose();
  }

  /// HTML tarafından gönderilen ekran görüntüsünü native paylaşım
  /// sayfasıyla paylaşır. WebView'de `navigator.share` desteklenmediği
  /// için paylaşım Flutter (share_plus) üzerinden yapılır.
  Future<void> _takeNativeScreenshot() async {
    try {
      final boundary = _screenshotKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/qualsar-3d.png');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Qualsar 3D',
      );
    } catch (_) {}
  }

  Future<void> _handleShare(String message) async {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final dataUrl = data['image'] as String? ?? '';
      final text = data['text'] as String? ?? '';
      final fileName = data['file'] as String? ?? 'qualsar-3d.png';

      final comma = dataUrl.indexOf(',');
      if (comma < 0) return;
      final bytes = base64Decode(dataUrl.substring(comma + 1));

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: text,
      );
    } catch (_) {
      // Paylaşım başarısızsa sessizce yut — kullanıcı tekrar deneyebilir.
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _screenshotKey,
      child: PopScope(
      // Mobilde geri tuşunu biz yönetiriz: önce HTML'deki açık pencereyi kapat.
      canPop: kIsWeb || _controller == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final ctrl = _controller;
        // Açık bir pencere/panel varsa WebView geçmişinde geri git → HTML popstate
        // SADECE o pencereyi kapatır (derse devam). Açık pencere yoksa dersten çık.
        if (ctrl != null && await ctrl.canGoBack()) {
          ctrl.goBack();
        } else if (mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF070B22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161D49),
        foregroundColor: const Color(0xFFFFF4DC),
        title: Text(widget.title.tr()),
        elevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (_error == null && kIsWeb) htmlAssetView(_webAssetUrl),
            if (_error == null && !kIsWeb && _controller != null)
              WebViewWidget(controller: _controller!),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF6B9D)),
                  ),
                ),
              ),
            if (_loading && _error == null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFFFB627)),
                    const SizedBox(height: 16),
                    Text(
                      '3D ders yükleniyor...'.tr(),
                      style: const TextStyle(color: Color(0xFFB9C2EE)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      ), // Scaffold
      ), // PopScope
    ); // RepaintBoundary
  }
}

/// 3D dersten 🤖 ile açılan hafif soru-cevap paneli.
/// Koç akışı yok: "Sana nasıl yardımcı olabilirim?" der, kullanıcı sorar, cevap gelir.
class _AskAiSheet extends StatefulWidget {
  final String topic;
  final String level;
  const _AskAiSheet({this.topic = '', this.level = ''});

  // Profesyonel ders uzmanı biçim kuralları (yıldız/markdown YASAK).
  static const String styleRules =
      'Sen alanında uzman, profesyonel bir ders öğretmenisin. Şu kurallara KESİNLİKLE uy:\n'
      '• Yıldız (*), kare (#), alt çizgi (_), backtick (`), markdown ve garip sembol KULLANMA.\n'
      '• KISA ve NET cevap ver: en fazla birkaç cümle ya da 3-5 kısa madde; gereksiz uzatma, tekrar etme.\n'
      '• Doğrudan sorunun cevabına odaklan; gereksiz giriş/özet ekleme.\n'
      '• Gerektiğinde maddeleri tek tek, her satır "• " ile yaz.\n'
      '• Alt başlık gerekiyorsa kısa yaz ve sonuna iki nokta üst üste koy (örn. "Tanım:").\n'
      '• Yerinde, az sayıda emoji kullanabilirsin (🌍, 🔭, 💡 gibi).\n'
      '• Cevabı yalnızca düz metin olarak ver.';

  // Eğitim seviyesine göre dil/derinlik talimatı.
  static String levelRule(String level) {
    switch (level) {
      case 'İlkokul':
        return 'Öğrenci İLKOKUL seviyesinde. Çok basit, günlük dille, kısa cümlelerle ve somut örneklerle anlat. Terimleri sadeleştir.';
      case 'Ortaokul':
        return 'Öğrenci ORTAOKUL seviyesinde. Sade ama biraz daha açıklayıcı; temel terimleri kısaca tanımla.';
      case 'Lise':
        return 'Öğrenci LİSE seviyesinde. Doğru terimleri kullan, nedenleriyle kısaca açıkla.';
      case 'Sınavlara Hazırlık':
        return 'Öğrenci SINAVLARA HAZIRLIK seviyesinde. Sınavda çıkan ayrıntılara ve sık yapılan hatalara kısa ve net değin.';
      case 'Üniversite':
        return 'Öğrenci ÜNİVERSİTE seviyesinde. Akademik terimlerle, doğru ve derinlemesine ama yine de KISA cevap ver.';
      default:
        return 'Öğrencinin seviyesine uygun konuş; basitten gerekirse derine in.';
    }
  }

  @override
  State<_AskAiSheet> createState() => _AskAiSheetState();
}

/// LLM cevabındaki markdown/garip sembolleri temizler, düz profesyonel metne çevirir.
String _cleanReply(String s) {
  var t = s;
  t = t.replaceAll('\r\n', '\n');
  // Kalın/italik/başlık işaretleri
  t = t.replaceAll(RegExp(r'\*\*|__'), '');
  t = t.replaceAll(RegExp(r'`+'), '');
  t = t.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  // Satır başı madde işaretlerini "• " yap
  t = t.replaceAll(RegExp(r'^\s*[\*\-]\s+', multiLine: true), '• ');
  t = t.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '• ');
  // Kalan tekil yıldızlar
  t = t.replaceAll('*', '');
  // Fazla boş satırlar
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}

class _AskAiSheetState extends State<_AskAiSheet> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<({bool user, String text})> _msgs = [];
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _ctrl.text).trim();
    if (q.isEmpty || _sending) return;
    _ctrl.clear();
    // Geçmişi mevcut soruyu EKLEMEDEN önce topla (tekrar göndermeyelim).
    final history = <Map<String, String>>[];
    for (final m in _msgs) {
      history.add({'role': m.user ? 'user' : 'assistant', 'text': m.text});
    }
    setState(() {
      _msgs.add((user: true, text: q));
      _sending = true;
    });
    _scrollDown();
    try {
      // Profesyonel ders uzmanı kimliği + temiz biçim kuralları + konu bağlamı.
      final ctxMsg =
          '${_AskAiSheet.styleRules}\n'
          '${_AskAiSheet.levelRule(widget.level)}\n\n'
          '${widget.level.isEmpty ? '' : '[SEVİYE: ${widget.level}]\n'}'
          '${widget.topic.isEmpty ? '' : '[KONU: ${widget.topic}]\n'}'
          'Öğrencinin sorusu: $q';
      final reply = await GeminiService.chatWithCoach(
        userMessage: ctxMsg,
        history: history,
      );
      if (!mounted) return;
      setState(() => _msgs.add((user: false, text: _cleanReply(reply))));
    } catch (_) {
      if (!mounted) return;
      setState(() => _msgs.add((
            user: false,
            text: 'Şu an cevap veremedim. İnternet bağlantını kontrol edip tekrar dene.'.tr()
          )));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  // AI cevabını profesyonel biçimde render et: alt başlık (renkli), madde (• ikon), düz metin.
  Widget _formattedAnswer(String text) {
    final lines = text.split('\n');
    final widgets = <Widget>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) { widgets.add(const SizedBox(height: 6)); continue; }
      final isSub = line.endsWith(':') && line.length <= 42 && !line.startsWith('•');
      if (isSub) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(line,
              style: const TextStyle(
                  color: Color(0xFFFFD166), fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.3)),
        ));
      } else if (line.startsWith('•')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 3, left: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ',
                  style: TextStyle(color: Color(0xFF4FD6E0), fontSize: 13.5, fontWeight: FontWeight.w800)),
              Expanded(
                child: Text(line.substring(1).trim(),
                    style: const TextStyle(color: Color(0xFFEEF0FF), fontSize: 13.5, height: 1.4)),
              ),
            ],
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(line,
              style: const TextStyle(color: Color(0xFFEEF0FF), fontSize: 13.5, height: 1.42)),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: widgets);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Color(0xFF161B2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: Color(0xFF9D7FE6), width: 2)),
        ),
        child: Column(
          children: [
            // Başlık
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '🤖 Size nasıl yardımcı olabilirim?'.tr(),
                      style: const TextStyle(
                        color: Color(0xFFFFD166),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFB9C2EE)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF2F3A5F)),
            // Mesajlar / boş durumda ipucu
            Expanded(
              child: _msgs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.topic.isNotEmpty
                              ? '${widget.topic} ${'hakkında merak ettiğin her şeyi sorabilirsin.'.tr()}'
                              : 'Bu konuda merak ettiğin her şeyi sorabilirsin.'.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF8A93B0), fontSize: 13, height: 1.4),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) {
                        final m = _msgs[i];
                        return Align(
                          alignment:
                              m.user ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.78),
                            decoration: BoxDecoration(
                              color: m.user
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF1F2540),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: m.user
                                ? Text(
                                    m.text,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13.5, height: 1.4),
                                  )
                                : _formattedAnswer(m.text),
                          ),
                        );
                      },
                    ),
            ),
            if (_sending)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('AI yazıyor…'.tr(),
                    style: const TextStyle(color: Color(0xFF8A93B0), fontSize: 12)),
              ),
            // Giriş satırı
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(color: Color(0xFFEEF0FF), fontSize: 14),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: _msgs.isEmpty ? '' : 'istediğin herhangi bir şeyi sorabilirsin'.tr(),
                          hintStyle: const TextStyle(color: Color(0xFF8A93B0)),
                          filled: true,
                          fillColor: const Color(0xFF1F2540),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sending ? null : () => _send(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _sending
                              ? const Color(0xFF3A4668)
                              : const Color(0xFFFFD166),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.send_rounded,
                            color: _sending ? const Color(0xFF8A93B0) : const Color(0xFF0A1420)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
