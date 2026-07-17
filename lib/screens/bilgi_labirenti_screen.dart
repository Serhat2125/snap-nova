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

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/education_profile.dart';
import '../services/exam_catalog.dart' show ExamDefinition, examGroupsFor;
import '../services/labyrinth_quiz_gen.dart';
import '../services/runtime_translator.dart';
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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
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
    super.dispose();
  }


  /// Oyun içi seviye kartına basılınca gelen mesaj: {type:'class', level}.
  /// O seviye için sınıf/alan seçtirip sorular üretir ve oyunu başlatır.
  void _onGameMode(String msg) {
    try {
      final data = jsonDecode(msg);
      if (data is! Map) return;
      if (data['type'] == 'class') {
        final level = (data['level'] ?? '').toString();
        if (level.isNotEmpty) _pickAndInjectClass(presetLevel: level);
      } else if (data['type'] == 'exam') {
        _pickAndInjectExam();
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
    final groups = examGroupsFor(EduProfile.current?.country);
    if (groups == null || groups.isEmpty || !mounted) return;
    final exam = await showDialog<ExamDefinition>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ExamGroupPickerDialog(groups: groups),
    );
    if (exam == null || !mounted) return;
    // Sınav → labirent seviyesi (tema/zorluk): LGS ortaokul, TYT/AYT lise,
    // DGS/KPSS üniversite.
    final ek = exam.key.toLowerCase();
    final startKey = ek.startsWith('lgs')
        ? 'ortaokul'
        : (ek.startsWith('dgs') || ek.startsWith('kpss'))
            ? 'üniversite'
            : 'lise';
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
    // Bundled yoksa: ders(ler) seç — tek de çoklu da olur (konu seçtirmiyoruz:
    // tüm konular) → AI ile üret.
    final picked = await _chooseMany(
      '${exam.displayName} · ${"Ders seç".tr()}',
      [for (final s in exam.subjects) '${s.emoji}  ${s.displayName}'],
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final subjects = [for (final i in picked) exam.subjects[i]];
    await _generateAndInject(
      () => LabyrinthQuizGen.generateForExam(
          exam: exam, subjects: subjects, count: 24),
      '${exam.displayName} · ${subjects.length} ${"ders".tr()}',
      startLevelKey: startKey,
    );
  }

  /// SINIFLAR: (seviye kartından gelen) seviye için Sınıf → (Lise 10+ alan) →
  /// o sınıfa özel sorular üret ve o labirent seviyesini başlat.
  Future<void> _pickAndInjectClass({required String presetLevel}) async {
    if (_controller == null) return;
    // Oyun anahtarını normalize et (üniversite = universite).
    final level = presetLevel == 'universite' ? 'üniversite' : presetLevel;
    final genLevel = level == 'üniversite' ? 'lise' : level; // üretim şablonu
    final grades = level == 'ilkokul'
        ? [1, 2, 3, 4]
        : level == 'ortaokul'
            ? [5, 6, 7, 8]
            : level == 'lise'
                ? [9, 10, 11, 12]
                : [1, 2, 3, 4]; // üniversite sınıfları
    final label0 = _levelNamesTr[level] ?? level;
    final gi = await _chooseOne('$label0 · ${"Sınıf seç".tr()}',
        [for (final g in grades) '$g. ${"sınıf".tr()}']);
    if (gi == null || !mounted) return;
    final grade = grades[gi];
    // Lise 10 ve sonrası: alan seçimi (Türkiye).
    String? track;
    if (level == 'lise' && grade >= 10) {
      const tracks = ['Sayısal', 'Sözel', 'Eşit Ağırlık'];
      final ti = await _chooseOne('Alan seç'.tr(),
          [for (final t in tracks) t.tr()]);
      if (ti == null || !mounted) return;
      track = tracks[ti];
    }
    final label =
        '$label0 $grade${track != null ? " · $track" : ""}';
    // ÖNCE offline bake edilmiş içerik (assets/labirent_content) — internetsiz,
    // anında, ücretsiz. Yoksa AI ile üret.
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
    await _generateAndInject(
      () => LabyrinthQuizGen.generateForClass(
          level: genLevel, grade: grade, track: track, count: 24),
      label,
      startLevelKey: level,
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
    Future<List<Map<String, dynamic>>> Function() gen,
    String label, {
    String? startLevelKey,
  }) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _generating = true);
    final qs = await gen();
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
        questions: qs, label: label, startLevelKey: startLevelKey);
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
    return PopScope(
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
    );
  }
}
