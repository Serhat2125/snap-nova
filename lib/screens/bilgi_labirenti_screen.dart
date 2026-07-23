// ═══════════════════════════════════════════════════════════════════════════
//  BilgiLabirentiScreen — "Bilgi Labirenti'nden Kaçış: Yedi Mühür" oyunu.
//
//  Hazır, kendi kendine yeten bir HTML oyunu (React + Three.js r128 +
//  Tailwind — hepsi assets'e yerel gömülü, İNTERNETSİZ çalışır). Flutter
//  köprüsü YOK — sadece asset'i bir WebView'de gösterir.
//
//  Web hedefinde webview_flutter desteklenmez → htmlAssetView (iframe) ile
//  gösterilir; mobil/masaüstünde WebViewController kullanılır.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/curriculum_catalog.dart' show curriculumFor;
import '../services/education_profile.dart';
import '../services/exam_catalog.dart' show ExamDefinition, examGroupsFor;
import '../services/labirent_pool_service.dart';
import '../services/labyrinth_quiz_gen.dart';
import '../services/locale_service.dart';
import '../services/parent_preview.dart';
import '../services/school_structure.dart';
import '../services/runtime_translator.dart';
import '../services/tts_service.dart';
import '../widgets/exam_mode_widgets.dart';

// Web'de webview_flutter desteklenmediği için HTML asset iframe ile gösterilir.
// Mobil/masaüstünde stub döner (kIsWeb ile dallanılır, çağrılmaz).
import 'html_asset_view_stub.dart'
    if (dart.library.html) 'html_asset_view_web.dart';

class BilgiLabirentiScreen extends StatefulWidget {
  const BilgiLabirentiScreen({super.key});

  @override
  State<BilgiLabirentiScreen> createState() => _BilgiLabirentiScreenState();
}

class _BilgiLabirentiScreenState extends State<BilgiLabirentiScreen>
    with WidgetsBindingObserver {
  static const _assetHtml = 'assets/bilgi-labirenti-yedi-muhur.html';
  static const _bg = Color(0xFF0B0A14); // oyun koyu temalı

  // Web'de WebViewController KULLANILMAZ (platform implementasyonu yok →
  // assertion hatası). Nullable ve sadece mobil/masaüstünde kurulur.
  WebViewController? _controller;
  bool _loading = true;
  String? _error;
  // Sınav modu: seçilen sınava özel sorular AI ile üretilirken true.
  bool _generating = false;
  /// Paylaşım için ekran görüntüsü sınırı (sertifika / başarı tablosu).
  final GlobalKey _shotKey = GlobalKey();

  /// Web hedefinde iframe src'i.
  String get _webAssetUrl => 'assets/$_assetHtml';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      _loading = false;
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_bg)
      // Oyun içi seviye kartına basılınca oyun buraya haber verir; sınıf
      // seçimi + soru üretimi Flutter'da yapılıp oyun başlatılır.
      ..addJavaScriptChannel('FlutterMode',
          onMessageReceived: (m) => _onGameMode(m.message))
      // Bilgi Panosu "Sesli Oku": Android WebView'da window.speechSynthesis
      // bulunmadığından oyun metni bu kanala yollar; native TTS okur.
      ..addJavaScriptChannel('FlutterTTS',
          onMessageReceived: (m) => _onTtsMessage(m.message))
      // Veli Raporu: oyun her profil kaydında özetini yollar; Firestore'a
      // yazılır ki bağlı ebeveyn kendi panelinden görebilsin.
      ..addJavaScriptChannel('FlutterVeliRapor',
          onMessageReceived: (m) => _onVeliRapor(m.message))
      // "Başarımı Paylaş" / Başarı Tablosu paylaşımı: WebView'da
      // navigator.share yok (file:// güvenli bağlam değil) → oyun panoya
      // kopyalayıp ham alert() gösteriyordu ('"file://" adresindeki sayfa…').
      // Bu kanal ekranın görüntüsünü alıp sistemin paylaş menüsünü açar.
      ..addJavaScriptChannel('FlutterNativeShot',
          onMessageReceived: (_) => _shareScreenshot())
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            // GLOBAL: menü kartlarını ülkenin okul yapısı/sınavlarıyla eşle.
            unawaited(_pushLevelMeta());
            // GLOBAL: oyun içi metinleri kullanıcının diline çevir.
            unawaited(_pushGameI18n());
          },
          onWebResourceError: (err) {
            // Alt-frame / kaynak hataları ana çerçeveyi bozmaz — sadece ana
            // çerçeve hatasında uyarı göster.
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
      ..loadFlutterAsset(_assetHtml);
  }

  /// Uygulama arka plana alınınca oyun döngüsünü/sesini durdurmaya çalış
  /// (oyun window.__appPaused'ı dinliyorsa; dinlemiyorsa zararsız).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null) return;
    final paused = state != AppLifecycleState.resumed;
    if (paused) unawaited(TtsService.stop()); // arka planda sesli okuma sussun
    try {
      ctrl.runJavaScript(
        'window.__appPaused=$paused;'
        '${paused ? '' : 'if(window.__appResume)window.__appResume();'}',
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(TtsService.stop()); // ekran kapanınca okuma yarıda kesilsin
    super.dispose();
  }

  /// Son yazılan rapor JSON'u — aynı içerik tekrar gelirse Firestore'a
  /// gereksiz yazım yapılmaz (oyun her soru sonrası kaydediyor).
  String? _lastVeliRapor;

  /// Oyundan gelen Veli Raporu özetini `users/{uid}/game_reports/labyrinth`
  /// dokümanına yazar. Firestore kuralları gereği bu yolu sahibi yazar,
  /// AKTİF bağlı ebeveyn salt-okur — ebeveyn paneli oradan gösterir.
  void _onVeliRapor(String msg) {
    if (msg == _lastVeliRapor) return;
    _lastVeliRapor = msg;
    unawaited(() async {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        final data = jsonDecode(msg);
        if (data is! Map) return;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('game_reports')
            .doc('labyrinth')
            .set({
          ...Map<String, dynamic>.from(data),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {/* rapor senkronu kritik değil; sessizce geç */}
    }());
  }

  /// Oyundan gelen sesli okuma isteği: {action:'speak', text, lang} | {action:'stop'}.
  void _onTtsMessage(String msg) {
    try {
      final data = jsonDecode(msg);
      if (data is! Map) return;
      final action = (data['action'] ?? '').toString();
      if (action == 'speak') {
        final text = (data['text'] ?? '').toString().trim();
        if (text.isEmpty) return;
        final lang = (data['lang'] ?? 'tr').toString().split('-').first;
        // Önceki okuma varsa kes, yenisini başlat.
        unawaited(TtsService.stop()
            .then((_) => TtsService.speak(text, langCode: lang))
            .catchError((_) {/* TTS hatası kritik değil; sessizce geç */}));
      } else if (action == 'stop') {
        unawaited(TtsService.stop());
      }
    } catch (_) {}
  }


  /// Oyun içi seviye kartına basılınca gelen mesaj: {type:'class', level}.
  /// O seviye için sınıf/alan seçtirip sorular üretir ve oyunu başlatır.
  /// Ekran görüntüsünü alıp sistemin paylaş menüsünü açar (sertifika,
  /// başarı tablosu vb.). Oyun tarafı `FlutterNativeShot.postMessage('1')`
  /// çağırır; böylece ekranda ne varsa aynen paylaşılır.
  Future<void> _shareScreenshot() async {
    try {
      final boundary = _shotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/bilgi-labirenti.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Bilgi Labirenti',
      );
    } catch (_) {}
  }

  /// Bir seçim/soru-üretim akışı sürerken oyunun ikinci bir kart mesajı
  /// göndermesini yok say — çift-tık (profil ilk yüklenirken açık overlay
  /// yokken) iki paralel akış başlatıp üst üste sheet + çift enjeksiyon +
  /// erken overlay kapanmasına yol açıyordu.
  bool _flowBusy = false;

  void _onGameMode(String msg) {
    if (_flowBusy) return;
    try {
      final data = jsonDecode(msg);
      if (data is! Map) return;
      if (data['type'] == 'class') {
        final level = (data['level'] ?? '').toString();
        if (level.isNotEmpty) {
          _flowBusy = true;
          _pickAndInjectClass(presetLevel: level)
              .whenComplete(() => _flowBusy = false);
        }
      } else if (data['type'] == 'exam') {
        _flowBusy = true;
        _pickAndInjectExam().whenComplete(() => _flowBusy = false);
      }
    } catch (_) {}
  }

  /// Oyunun labirent seviye anahtarı ↔ sınıf seviyesi.
  static const _levelNamesTr = {
    'ilkokul': 'İlkokul',
    'ortaokul': 'Ortaokul',
    'lise': 'Lise',
    'üniversite': 'Üniversite',
    'universite': 'Üniversite',
  };

  /// SINAVLAR: Sınav grubu → DERS(LER) seç (tek veya çoklu; KONU seçilmez,
  /// seçilen dersin tüm konularından) → seçime özel AI soruları → sınava
  /// uygun labirent seviyesini başlat.
  Future<void> _pickAndInjectExam() async {
    if (_controller == null) return;
    // Profil henüz belleğe yüklenmemişse yükle — yoksa tık sessizce yutuluyordu.
    if (EduProfile.current == null) {
      try {
        await EduProfile.load();
      } catch (_) {}
    }
    if (!mounted) return;
    // Ülke kataloğu yoksa TR kataloğuna düş (oyun kartı da TR sınavlarını
    // listeler); o da yoksa kullanıcıya söyle — ölü buton bırakma.
    final groups = examGroupsFor(EduProfile.current?.country) ??
        examGroupsFor('TR');
    if (groups == null || groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Bu ülke için sınav kataloğu henüz yok.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final exam = await showDialog<ExamDefinition>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ExamGroupPickerDialog(groups: groups),
    );
    if (exam == null || !mounted) return;
    // Sınav → labirent seviyesi (tema/zorluk): LGS ortaokul, TYT/AYT lise,
    // DGS/KPSS üniversite.
    final ek = exam.key.toLowerCase();
    // NOT: Oyunda yalnız ilkokul/ortaokul/lise labirent teması var —
    // 'üniversite' gönderilirse oyun çakılıyordu; DGS/KPSS lise temasında oynar.
    final startKey = ek.startsWith('lgs') ? 'ortaokul' : 'lise';
    // ÖNCE offline bake edilmiş sınav havuzu (varsa) — internetsiz, anında,
    // ders seçtirmeden (havuz zaten o sınavın derslerini kapsıyor).
    setState(() => _generating = true);
    final bundled = await LabyrinthQuizGen.loadBundledExam(exam.key);
    if (!mounted) return;
    setState(() => _generating = false);
    if (bundled != null) {
      await _injectAndStart(
        questions:
            (bundled['questions'] as List).cast<Map<String, dynamic>>(),
        facts: (bundled['facts'] as List).cast<String>(),
        label: exam.displayName,
        startLevelKey: startKey,
      );
      return;
    }
    // TOPLULUK HAVUZU: ülke × sınav × dil havuzu hazırsa içerik oradan gelir
    // (ders seçtirmeden — havuz sınavın tüm derslerini kapsar; bundled ile
    // aynı UX). Hazır değilse AI üretir ve havuza da yazar.
    final examPoolMeta = LabirentPoolMeta(
      country: (EduProfile.current?.country ?? 'tr').toLowerCase(),
      level: 'exam',
      grade: exam.key.toLowerCase(),
      kind: 'exam',
      subjectsHint: exam.subjects.map((s) => s.displayName).join(' · '),
      curriculumSig: LabirentPoolService.curriculumSigFrom(
          [exam.key, for (final s in exam.subjects) s.key]),
      optionCount: exam.optionCount.clamp(3, 5),
    );
    setState(() => _generating = true);
    final pooled = await LabirentPoolService.drawBundle(examPoolMeta);
    if (!mounted) return;
    setState(() => _generating = false);
    if (pooled != null) {
      await _injectAndStart(
        questions: (pooled['questions'] as List).cast<Map<String, dynamic>>(),
        facts: (pooled['facts'] as List).cast<String>(),
        label: exam.displayName,
        startLevelKey: startKey,
      );
      return;
    }
    // Havuz hazır değil: ders(ler) seç — tek de çoklu da olur (konu
    // seçtirmiyoruz: tüm konular) → AI ile üret + havuzu organik doldur.
    final picked = await _chooseMany(
      '${exam.displayName} · ${"Ders seç".tr()}',
      [for (final s in exam.subjects) '${s.emoji}  ${s.displayName}'],
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final subjects = [for (final i in picked) exam.subjects[i]];
    await _generateAndInject(
      () async {
        final b = await LabyrinthQuizGen.generateForExam(
            exam: exam, subjects: subjects, count: 24);
        final qs =
            (b['questions'] as List? ?? const []).cast<Map<String, dynamic>>();
        final facts = (b['facts'] as List? ?? const []).cast<String>();
        if (qs.isNotEmpty) {
          unawaited(LabirentPoolService.insertBundle(examPoolMeta, qs, facts));
          unawaited(LabirentPoolService.cacheBundle(examPoolMeta, qs, facts));
          return b;
        }
        // AI üretemedi (offline / kota) → cihazda biriken içerikten oyna.
        return await LabirentPoolService.cachedBundle(examPoolMeta) ?? b;
      },
      '${exam.displayName} · ${subjects.length} ${"ders".tr()}',
      startLevelKey: startKey,
      // AI + havuz başarısızsa uygulamayla gelen sınav havuzuyla oyna.
      lastResort: () => LabyrinthQuizGen.loadBundledExam(exam.key),
    );
  }

  /// GLOBAL i18n: oyun içi metinler için sözlük (`assets/labirent_i18n/<dil>.json`,
  /// anahtar = Türkçe kaynak) + DOM gözlemci çevirmen enjekte eder.
  /// Sözlük React'in her yeniden çiziminde metin düğümlerini birebir eşleşmeyle
  /// çevirir; dil dosyası yoksa İngilizce'ye düşer (Türkçe asla görünmez).
  Future<void> _pushGameI18n() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final code = LocaleService.global?.localeCode ?? 'tr';
    if (code == 'tr') return; // oyunun ana dili zaten Türkçe
    String? raw;
    try {
      raw = await rootBundle.loadString('assets/labirent_i18n/$code.json');
    } catch (_) {}
    if (raw == null) {
      try {
        raw = await rootBundle.loadString('assets/labirent_i18n/en.json');
      } catch (_) {}
    }
    if (raw == null) return;
    // Gözlemci: metin düğümlerini sözlükten çevirir; React yeniden çizince
    // rAF toplu yeniden tarama yapar. Kendi değişikliği döngü yaratmaz
    // (çevrilmiş metin sözlükte anahtar değildir).
    const observer = '''
(function(){if(window.__i18nInstalled)return;window.__i18nInstalled=true;
var D=window.__gameI18n||{};
var SUB=D['__sub']||{};var SUBK=Object.keys(SUB).sort(function(a,b){return b.length-a.length;});
function txl(n){var t=n.data;if(!t)return;var k=t.trim();if(!k)return;var r=D[k];if(r&&r!==k){n.data=t.replace(k,r);return;}
if(/[0-9]/.test(k)){var s2=t,ch=false;for(var i=0;i<SUBK.length;i++){var kk=SUBK[i];if(s2.indexOf(kk)>=0){s2=s2.split(kk).join(SUB[kk]);ch=true;}}if(ch&&s2!==t)n.data=s2;}}
function walk(){try{var w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,null);var n;while((n=w.nextNode()))txl(n);
var els=document.querySelectorAll('[title]');for(var i=0;i<els.length;i++){var v=els[i].getAttribute('title');var r2=D[v&&v.trim()];if(r2)els[i].setAttribute('title',r2);}}catch(e){}}
var pend=false;var obs=new MutationObserver(function(){if(pend)return;pend=true;requestAnimationFrame(function(){pend=false;walk();});});
obs.observe(document.body,{childList:true,subtree:true,characterData:true});walk();})();''';
    try {
      // __ttsLang: tarayıcı-içi TTS (web fallback) sabit "tr-TR" okumasın —
      // kullanıcının dilini kullansın. (Mobilde native TTS zaten doğru dili
      // alıyor; bu satır yalnız speechSynthesis yolunu düzeltir.)
      await ctrl.runJavaScript(
          'window.__ttsLang=${jsonEncode(code)};window.__gameI18n=$raw;$observer');
    } catch (_) {}
  }

  /// GLOBAL menü uyarlaması: oyunun seviye kartlarını (ad, sınıf aralığı,
  /// alanlar) ve Sınavlar kartı alt yazısını ülkenin gerçek yapısıyla değiştirir.
  /// TR + Türkçe'de oyunun kendi metinleri zaten doğru → dokunulmaz.
  Future<void> _pushLevelMeta() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (EduProfile.current == null) {
      try {
        await EduProfile.load();
      } catch (_) {}
    }
    final country = (EduProfile.current?.country ?? 'tr').toLowerCase();
    final langIsTr = (LocaleService.global?.localeCode ?? 'tr') == 'tr';
    if (country == 'tr' && langIsTr) return;
    final ss = schoolStructureFor(country);
    String rng(String k) {
      final g = ss.gradesOf(k);
      return '${g.first}-${g.last}';
    }

    final groups = examGroupsFor(EduProfile.current?.country);
    final examLabel = (groups == null || groups.isEmpty)
        ? null
        : groups.map((g) => g.displayName).take(5).join(' · ');
    final meta = <String, dynamic>{
      'ilkokul': {
        'name': 'İlkokul'.tr(),
        'sub': '${rng('primary')}. ${'sınıf'.tr()}',
        'tracks': 'Tek alan'.tr(),
      },
      'ortaokul': {
        'name': 'Ortaokul'.tr(),
        'sub': '${rng('middle')}. ${'sınıf'.tr()}',
        'tracks': 'Tek alan'.tr(),
      },
      'lise': {
        'name': 'Lise'.tr(),
        'sub': '${rng('high')}. ${'sınıf'.tr()}',
        if (ss.tracks.isNotEmpty)
          'tracks': ss.tracks.map((t) => t.label).join(' · '),
      },
      if (examLabel != null) 'examLabel': examLabel,
    };
    final js = jsonEncode(meta);
    try {
      await ctrl.runJavaScript(
          'window.__levelMeta=$js;if(window.__setLevelMeta)window.__setLevelMeta(window.__levelMeta);');
    } catch (_) {}
  }

  /// SINIFLAR: (seviye kartından gelen) seviye için Sınıf → (alan sistemi
  /// olan ülkelerde Alan) → o ülkenin O SINIFTAKİ müfredat dersleriyle soru
  /// üret ve labirenti başlat. GLOBAL: sınıf sayıları/alanlar ülkeye göre
  /// (school_structure.dart), dersler curriculum_catalog'dan, içerik dili
  /// kullanıcının uygulama dili.
  Future<void> _pickAndInjectClass({required String presetLevel}) async {
    if (_controller == null) return;
    if (EduProfile.current == null) {
      try {
        await EduProfile.load();
      } catch (_) {}
    }
    if (!mounted) return;
    final country = (EduProfile.current?.country ?? 'tr').toLowerCase();
    final isTR = country == 'tr';
    final ss = schoolStructureFor(country);
    // Oyun anahtarını normalize et (üniversite = universite).
    final level = presetLevel == 'universite' ? 'üniversite' : presetLevel;
    final genLevel = level == 'üniversite' ? 'lise' : level; // üretim şablonu
    // Oyun tema anahtarı → yapısal kademe anahtarı.
    final structKey = level == 'ilkokul'
        ? 'primary'
        : level == 'ortaokul'
            ? 'middle'
            : 'high';
    final grades = level == 'üniversite'
        ? [1, 2, 3, 4] // üniversite sınıfları (ülkeden bağımsız)
        : ss.gradesOf(structKey);
    final label0 = _levelNamesTr[level] ?? level;
    final gi = await _chooseOne('${label0.tr()} · ${"Sınıf seç".tr()}',
        [for (final g in grades) '$g. ${"sınıf".tr()}']);
    if (gi == null || !mounted) return;
    final grade = grades[gi];
    // Alan seçimi: ülkenin alan sistemi varsa ve bu sınıfta geçerliyse.
    String? track; // TR bundled dosya son eki için üretici etiketi
    String? trackKey; // curriculum_catalog anahtarı ('sayisal','jayeon'…)
    String? trackLabel; // ekranda görünen (endonim) ad
    if (level == 'lise' && ss.tracksApply(grade)) {
      final opts = ss.tracks;
      final ti = await _chooseOne('Alan seç'.tr(),
          [for (final t in opts) '${t.emoji}  ${t.label}']);
      if (ti == null || !mounted) return;
      trackKey = opts[ti].key;
      trackLabel = opts[ti].label;
      if (isTR) {
        track = const {
          'sayisal': 'Sayısal',
          'sozel': 'Sözel',
          'esit_agirlik': 'Eşit Ağırlık',
        }[trackKey];
      }
    }
    final label =
        '${label0.tr()} $grade${trackLabel != null ? " · $trackLabel" : ""}';
    // ÖNCE offline bake edilmiş içerik — YALNIZ TR (dosyalar TR müfredatı ve
    // Türkçe; başka ülkeye/dile servis edilmez). Yoksa/değilse AI ile üret.
    if (isTR && (LocaleService.global?.localeCode ?? 'tr') == 'tr') {
      setState(() => _generating = true);
      final bundled =
          await LabyrinthQuizGen.loadBundled(genLevel, grade, track: track);
      if (!mounted) return;
      setState(() => _generating = false);
      if (bundled != null) {
        await _injectAndStart(
          questions:
              (bundled['questions'] as List).cast<Map<String, dynamic>>(),
          facts: (bundled['facts'] as List).cast<String>(),
          label: label,
          startLevelKey: level,
        );
        return;
      }
    }
    // Ülke müfredatından bu sınıfın dersleri + konuları (statik katalog;
    // 150 ülke, yoksa international şablonu).
    var subjects = curriculumFor(EduProfile(
      country: country,
      level: structKey,
      grade: '$grade',
      track: trackKey,
    ));
    // Quiz oyununa uygun akademik çekirdek: müzik/beden/görsel sanatlar gibi
    // uygulamalı dersleri prompt'a sokma (soru kalitesini düşürür).
    const nonAcademic = {
      'muzik', 'gorsel_sanatlar', 'beden', 'pe', 'music', 'art',
      'physical_education', 'sports', 'crafts',
    };
    final core = [
      for (final s in subjects)
        if (!nonAcademic.contains(s.key)) s
    ];
    if (core.isNotEmpty) subjects = core;
    String? countryName;
    for (final c in kAllCountries) {
      if (c.key == country) {
        countryName = c.name;
        break;
      }
    }
    // TOPLULUK HAVUZU: ülke × kademe × sınıf × dil havuzu hazırsa (≥300 soru
    // + ≥500 bilgi) içerik ORADAN gelir — AI yok, maliyet 0, anında açılır.
    // Hazır değilse AI üretir ve sonuç havuza da yazılır (organik doluş);
    // CF generator arka planda hedefe tamamlar.
    final poolMeta = LabirentPoolMeta(
      country: country,
      level: level == 'üniversite' ? 'uni' : structKey,
      grade: '$grade',
      track: trackKey,
      kind: 'class',
      subjectsHint: subjects
          .map((s) => s.topics.isEmpty
              ? s.displayName
              : '${s.displayName} (${s.topics.take(6).join(', ')})')
          .join(' · '),
      curriculumSig: LabirentPoolService.curriculumSigFrom(
          [for (final s in subjects) '${s.key}:${s.topics.join(',')}']),
      optionCount: genLevel == 'ilkokul'
          ? 3
          : genLevel == 'ortaokul'
              ? 4
              : 5,
    );
    setState(() => _generating = true);
    final pooled = await LabirentPoolService.drawBundle(poolMeta);
    if (!mounted) return;
    setState(() => _generating = false);
    if (pooled != null) {
      await _injectAndStart(
        questions: (pooled['questions'] as List).cast<Map<String, dynamic>>(),
        facts: (pooled['facts'] as List).cast<String>(),
        label: label,
        startLevelKey: level,
      );
      return;
    }
    await _generateAndInject(
      () async {
        final b = await LabyrinthQuizGen.generateForClass(
            level: genLevel,
            grade: grade,
            track: isTR ? track : trackLabel,
            count: 24,
            countryName: countryName,
            subjects: isTR ? null : subjects);
        final qs =
            (b['questions'] as List? ?? const []).cast<Map<String, dynamic>>();
        final facts = (b['facts'] as List? ?? const []).cast<String>();
        if (qs.isNotEmpty) {
          unawaited(LabirentPoolService.insertBundle(poolMeta, qs, facts));
          unawaited(LabirentPoolService.cacheBundle(poolMeta, qs, facts));
          return b;
        }
        // AI üretemedi (offline / kota) → cihazda biriken içerikten oyna.
        return await LabirentPoolService.cachedBundle(poolMeta) ?? b;
      },
      label,
      startLevelKey: level,
      // AI + havuz başarısızsa uygulamayla gelen sınıf havuzuyla oyna
      // (ülke/dil ne olursa olsun oyun AÇILIR; içerik TR müfredatı olabilir).
      lastResort: () =>
          LabyrinthQuizGen.loadBundledFallback(genLevel, grade, track: track),
    );
  }

  /// Basit tek-seçim alt sayfası; seçilen indeksi döner (iptalde null).
  /// Zemin SOLUK BEYAZ, öğe kartları BEYAZ (kullanıcı isteği).
  Future<int?> _chooseOne(String title, List<String> options) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFFF3F1EA), // soluk beyaz
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    color: Color(0xFF1B1B1F),
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            for (int i = 0; i < options.length; i++)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(ctx).pop(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 15),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE3DFD3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(options[i],
                                style: const TextStyle(
                                    color: Color(0xFF1B1B1F),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: Color(0xFFC9A24B)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  /// Çoklu seçim alt sayfası (en az 1). Seçilen indeksleri döner (iptalde null).
  Future<List<int>?> _chooseMany(String title, List<String> options) {
    final sel = <int>{};
    return showModalBottomSheet<List<int>>(
      context: context,
      backgroundColor: const Color(0xFFF3F1EA),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFF1B1B1F),
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
              Text('Birden fazla ders seçebilirsin'.tr(),
                  style: const TextStyle(
                      color: Color(0xFF6B6B72), fontSize: 12)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (int i = 0; i < options.length; i++)
                      CheckboxListTile(
                        value: sel.contains(i),
                        activeColor: const Color(0xFFC9A24B),
                        title: Text(options[i],
                            style: const TextStyle(
                                color: Color(0xFF1B1B1F),
                                fontWeight: FontWeight.w700)),
                        onChanged: (v) => setLocal(() {
                          if (v == true) {
                            sel.add(i);
                          } else {
                            sel.remove(i);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFC9A24B),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: sel.isEmpty
                        ? null
                        : () => Navigator.of(ctx).pop(sel.toList()..sort()),
                    child: Text('Devam'.tr(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ortak: soruları üret, oyuna enjekte et; [startLevelKey] verilirse o
  /// labirent seviyesini oyunda başlatır (window.__startLevel).
  Future<void> _generateAndInject(
    Future<Map<String, dynamic>> Function() gen,
    String label, {
    String? startLevelKey,
    // SON ÇARE: AI ve havuz başarısızsa uygulamayla gelen (bundled) içerik.
    // Bunsuz, kredi bitikken/offline'da oyun HİÇ açılmıyordu; artık her
    // koşulda oynanabilir bir labirent başlar.
    Future<Map<String, dynamic>?> Function()? lastResort,
  }) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _generating = true);
    // AI üretimi asla sonsuza asılmasın: 25 sn'de kes (kredi bitik/offline ise
    // spinner takılıp kalmaz; son çare içeriğine hızlıca geçilir).
    List<Map<String, dynamic>> qs;
    List<String> facts;
    try {
      final b = await gen().timeout(const Duration(seconds: 25));
      qs = (b['questions'] as List? ?? const []).cast<Map<String, dynamic>>();
      facts = (b['facts'] as List? ?? const []).cast<String>();
    } catch (_) {
      qs = const [];
      facts = const [];
    }
    if (qs.isEmpty && lastResort != null) {
      try {
        final fb = await lastResort();
        if (fb != null) {
          qs = (fb['questions'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          facts = (fb['facts'] as List? ?? const []).cast<String>();
        }
      } catch (_) {/* son çare de yoksa aşağıda uyarı gösterilir */}
    }
    if (!mounted) return;
    setState(() => _generating = false);
    if (qs.isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(
            'Sorular şu an üretilemedi. İnternet bağlantını kontrol et veya birazdan tekrar dene.'
                .tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    await _injectAndStart(
        questions: qs,
        facts: facts.isEmpty ? null : facts,
        label: label,
        startLevelKey: startLevelKey);
  }

  /// Soruları (+ varsa bilgileri) oyuna enjekte eder ve [startLevelKey]
  /// verilirse o labirent seviyesini başlatır. (Offline bundled + AI ortak.)
  Future<void> _injectAndStart({
    required List<Map<String, dynamic>> questions,
    List<String>? facts,
    required String label,
    String? startLevelKey,
  }) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    try {
      await ctrl.runJavaScript(
          'window.__externalQuestions=${jsonEncode(questions)};window.__extQIdx=0;');
      if (facts != null && facts.isNotEmpty) {
        await ctrl.runJavaScript(
            'window.__externalFacts=${jsonEncode(facts)};window.__extFIdx=0;');
      }
      if (startLevelKey != null) {
        await ctrl.runJavaScript(
            'if(window.__startLevel)window.__startLevel(${jsonEncode(startLevelKey)});');
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label — ${questions.length} ${"soru yüklendi!".tr()}'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Ebeveyn önizlemesi: oyun OYNANMAZ — yalnız ne olduğu anlatılır.
    if (ParentPreview.active) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: const Color(0xFFF3E9D2),
          elevation: 0,
          title: Text('Bilgi Labirenti'.tr()),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('👁️', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                Text(
                  'Öğrenci paneli önizlemesi — oyunlar yalnızca öğrenci '
                          'hesabında oynanabilir. Çocuğun burada 3D labirentte '
                          'ilerleyip müfredat sorularını çözerek öğrenir.'
                      .tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFFF3E9D2), fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return RepaintBoundary(
      key: _shotKey,
      child: PopScope(
      // Mobilde geri tuşu: önce oyunun KENDİ adımında geri git (açık panel/
      // alt ekran kapanır ya da menüye dönülür). Oyun "kök"teyse (ana menü,
      // açık bir şey yok) ekrandan çıkıp bir önceki Flutter sayfasına döner —
      // yani doğrudan Kütüphanem'e atlamaz, hangi adımdan gelindiyse oraya.
      canPop: kIsWeb || _controller == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final ctrl = _controller;
        if (ctrl != null) {
          bool handled = false;
          try {
            final res = await ctrl.runJavaScriptReturningResult(
                'window.__gameBack ? window.__gameBack() : false');
            final s = res.toString().toLowerCase();
            handled = s == 'true' || s == '1';
          } catch (_) {}
          if (handled) return; // oyun içi bir adım geri gidildi
        }
        if (mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: const Color(0xFFF3E9D2),
          elevation: 0,
          title: Text('Bilgi Labirenti'.tr()),
          // Sınavlar artık oyun içinde "Lise" kartının altındaki sekmeden
          // açılıyor; üst-sağdaki buton kaldırıldı.
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
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFFC9A24B)),
                ),
              // Sınav soruları üretilirken tam ekran örtü.
              if (_generating)
                Container(
                  color: Colors.black.withValues(alpha: 0.62),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                            color: Color(0xFFC9A24B)),
                        const SizedBox(height: 16),
                        Text('Sınav soruların hazırlanıyor...'.tr(),
                            style: const TextStyle(
                                color: Color(0xFFF3E9D2),
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
