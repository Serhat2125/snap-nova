import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/camera_screen.dart';
import 'screens/education_setup_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/academic_planner.dart';
import 'screens/premium_screen.dart';
import 'screens/profile_screen.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'services/analytics.dart';
import 'services/auth_service.dart';
import 'services/locale_service.dart';
import 'services/theme_service.dart';
import 'services/tts_service.dart';
import 'services/voice_input_service.dart';
import 'services/connectivity_service.dart';
import 'services/country_resolver.dart';
import 'services/curriculum_catalog.dart';
import 'services/education_profile.dart';
import 'services/error_logger.dart';
import 'services/geolocation_service.dart';
import 'services/remote_config_service.dart';
import 'services/runtime_translator.dart';
import 'services/subscription_service.dart';
import 'widgets/smart_sidebar.dart';
import 'widgets/qualsar_splash_screen.dart';

/// Tüm uygulama için tek navigator (global sidebar buradan navigate eder)
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

/// Uygulama genelinde erişilebilen kamera listesi.
/// main() içinde bir kez doldurulur.
List<CameraDescription> globalCameras = [];

/// Uygulama genelinde erişilebilen dil servisi.
final localeService = LocaleService();

/// Uygulama genelinde erişilebilen tema servisi.
final themeService = ThemeService();

/// Ağ durumu servisi — snackbar, offline rozeti, API retry kararları.
final connectivityService = ConnectivityService();

Future<void> main() async {
  // ═══════════════════════════════════════════════════════════════════════
  //  Global hata sınırı — çöken her widget / zone exception'ı
  //  ErrorLogger'a düşer, uygulama açık kalır.
  // ═══════════════════════════════════════════════════════════════════════
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp]);

    // ═══════════════════════════════════════════════════════════════════════
    //  ANLIK SPLASH — Firebase + 13 async init ~5-6 saniye sürüyor.
    //  Native white screen yerine QuAlsar splash'ı HEMEN göster; init arkada
    //  devam ederken kullanıcı yazıyı + dönen logoyu görür. Init bittiğinde
    //  ikinci runApp() gerçek QuAlsarApp ile yer değiştirir.
    // ═══════════════════════════════════════════════════════════════════════
    runApp(const _InstantSplashApp());
    // Bir frame bekle ki splash render edilsin, sonra heavy init başlasın.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    // ── 3D Model Lisansları (showLicensePage()'te görünür) ────────────────
    // DamagedHelmet CC BY 4.0 → attribution zorunlu. Diğerleri CC0/Apache.
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(
        ['3D Models · model_viewer_plus assets'],
        '''Bu uygulama Çalışma Arkadaşım ve Mars ekranında aşağıdaki 3D modellerin placeholder versiyonlarını kullanır:

• RobotExpressive.glb — © Google, modelviewer.dev/shared-assets (Apache 2.0)
• Astronaut.glb — © Google, modelviewer.dev/shared-assets (CC BY 4.0)
• DamagedHelmet.glb — theblueturtle_ / Khronos glTF Sample Models (CC BY 4.0)
• Duck.glb — Sony Computer Entertainment Inc. / Khronos (CC0 / Public Domain)
• BoomBox.glb — © Microsoft, Khronos glTF Sample Models (CC0)
• Lantern.glb — © Microsoft, Khronos glTF Sample Models (CC0)

CC BY 4.0 attribution: https://creativecommons.org/licenses/by/4.0/
Khronos Sample Models repo: https://github.com/KhronosGroup/glTF-Sample-Models''',
      );
    });

    // ── Firebase ───────────────────────────────────────────────────────
    //   `flutterfire configure` ile üretilen DefaultFirebaseOptions kullanılıyor.
    //   Henüz üretilmediyse stub bir hata fırlatır → catch'te yakalanır,
    //   uygulama Firebase olmadan açılmaya devam eder. FirebaseAuth (telefon)
    //   gibi özellikler bu durumda kullanıcıya net bir mesaj gösterir.
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      AuthService.firebaseReady = true;

      // ── App Check — Phone Auth + Firestore abuse koruması ─────────────
      // Play Integrity (Android prod), Debug provider (dev/debug build),
      // DeviceCheck (iOS). Phone Auth'un error 39 vermesini önler.
      // Token verification: Firebase Auth otomatik gönderir, App Check
      // backend doğrular. Enforce: Firebase Console → App Check'te ayarlanır.
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
          appleProvider: kDebugMode
              ? AppleProvider.debug
              : AppleProvider.deviceCheck,
        );
      } catch (e, st) {
        ErrorLogger.instance.capture(e, st, context: 'app_check_activate');
      }

      // Firestore offline cache — ağ kesikken son veriye erişim + yazma kuyruğu.
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      // Anonim Firebase Auth — Bilgi Ligi gibi yazmaları olan modüller
      // her kullanıcının uid'ye sahip olmasını gerektirir. currentUser
      // null ise tek seferlik anonim oturum aç. (Firebase Console →
      // Authentication → Sign-in method → "Anonymous" etkinleştirilmiş
      // olmalı.) Hata yutulur; ağ yoksa veya devre dışıysa offline akış sürer.
      try {
        if (fb_auth.FirebaseAuth.instance.currentUser == null) {
          await fb_auth.FirebaseAuth.instance.signInAnonymously();
        }
      } catch (_) {/* anonim auth başarısız → cloud yazımları atlanır */}
      // Analytics + Crashlytics — Firebase init başarılı olduktan SONRA.
      // Hata atmaz; init başarısızsa no-op'a düşer.
      await Analytics.init();
      Analytics.registerFlutterErrorHandler();
    } catch (e, st) {
      AuthService.firebaseReady = false;
      debugPrint('[Firebase] init başarısız: $e\n'
          'Çözüm: terminalde "flutterfire configure" çalıştırıp '
          'firebase_options.dart\'ı üret. Sonra google-services.json (Android) '
          've GoogleService-Info.plist (iOS) dosyalarının yerinde olduğundan '
          'emin ol.\n$st');
    }

    // ── Hata toplayıcı (Firestore opsiyonel) ──────────────────────────
    await ErrorLogger.instance.init();

    // ── Kamera, dil, tema, ağ, ülke, uzaktan ayar ─────────────────────
    try {
      globalCameras = await availableCameras();
    } catch (e, st) {
      globalCameras = [];
      ErrorLogger.instance.capture(e, st, context: 'camera_enumeration');
    }

    await localeService.init();
    await themeService.init();
    await connectivityService.init();
    // Voice & TTS — Sesli Komut için. Hata atmaz; başarısızsa no-op.
    unawaited(VoiceInputService.init());
    unawaited(TtsService.init());
    // Saklı oturumu yükle — auth_user_v1 prefs key'inden.
    await AuthService.init();
    // Runtime translator — kalıcı cache'i yükle + LocaleService'e hook bağla
    await RuntimeTranslator.instance.init();
    // bulkRegister ÇOK pahalı: 5000+ string'i set'e atar, 3sn sonra büyük
    // jsonEncode + SharedPreferences write yapar. Cihaz Türkçeyse hiçbir
    // çeviriye gerek olmadığı için tamamen atlanır. Diğer dillerde de
    // sadece dil değişiminde tetiklenir (setLocaleChangeHook altında),
    // her açılışta değil. Bu, startup'taki donmanın ana sebebiydi.
    LocaleService.setLocaleChangeHook((lang) async {
      // Her dil değişiminde önce tüm kaynakların kayıtlı olduğunu garanti et.
      RuntimeTranslator.instance
          .bulkRegister(LocaleService.allTrSourceStrings);
      await RuntimeTranslator.instance.preloadAll(lang);
    });
    // LocaleService.tr() içinde bir key'in çevirisi yoksa Türkçe kaynağı
    // runtime translator'dan geçirip cache'den okutsun.
    LocaleService.setRuntimeTranslateHook((source) {
      RuntimeTranslator.instance.register(source);
      return RuntimeTranslator.instance.lookup(source);
    });
    // Açılışta mevcut dil Türkçe değilse eksik çevirileri arka planda çek.
    // (Bulk register burada — sadece TR-dışı cihazlarda + arka planda.)
    if (localeService.localeCode != 'tr') {
      unawaited(() async {
        RuntimeTranslator.instance
            .bulkRegister(LocaleService.allTrSourceStrings);
        await RuntimeTranslator.instance.preloadAll(localeService.localeCode);
      }());
    }

    // IP geolocation arka planda (UI'ı bekletmez). Başarılıysa
    // locale'i ve ülke çözümleyiciyi yeniden değerlendir.
    unawaited(GeolocationService.resolve().then((geo) async {
      if (geo != null) {
        await localeService.reevaluateFromGeo(ipCountry: geo.country);
      }
      await CountryResolver.instance.refresh(locale: localeService);
    }));
    // Ülke çözümleyiciyi mevcut sinyallerle hemen doldur
    await CountryResolver.instance.init(locale: localeService);

    // Uzaktan ayar — cache anında, tazeleme arka planda
    await RemoteConfigService.instance.init();

    // Müfredat kataloğu → education_profile'a bağla
    initCurriculumCatalog();

    // İlk açılışsa cihaz locale'inden ülkeyi tespit et — onboarding'in ülke
    // seçicisi bu pref'i varsayılan olarak alır (kullanıcı manuel
    // değiştirebilir, ama pek çok kullanıcı için tek tıkla doğru ülke gelir).
    await EduProfile.autoDetectCountryIfMissing();

    // Mevcut öğrenci profilini cache'e yükle (AI prompt'larında kullanılır)
    await EduProfile.load();
    // AI'dan üretilmiş profil-özel müfredat varsa belleğe yükle (varsa).
    // Hem ders listesi (subjects) hem de konu haritası (topics) ayrı cache'lerde.
    await EduProfile.loadAiSubjectCache();
    await EduProfile.loadAiTopicsCache();

    // Önceki açılıştan kalan tamamlanmamış çalışma session'ı varsa kurtar.
    // (App kill / crash sonrası en kötü 30sn kayıpla session yine yazılır.)
    unawaited(StudySessionTracker.recoverPendingSession());

    // Play Billing / StoreKit purchase stream'ini başlat (async, blocking değil).
    // App startup'tan sonra ilk satın alma denenebilir; sub_service stream
    // dinleyiciyi bu çağrıyla bağlar.
    unawaited(SubscriptionService.instance.init());

    // ProviderScope: Yeni feature katmanları (lib/features/...) Riverpod
    // kullanır; eski ekranlar StatefulWidget+setState ile çalışmaya devam
    // eder — wrapper sadece yeni provider'ları aktive eder, eski koda
    // hiçbir etkisi yok.
    runApp(ProviderScope(child: QuAlsarApp()));
  }, (error, stack) {
    // Zone dışına sızan her şey — hem ErrorLogger hem Crashlytics'e gönder.
    ErrorLogger.instance.capture(
      error,
      stack,
      context: 'root_zone',
      fatal: true,
    );
    Analytics.recordError(error, stack, fatal: true, reason: 'root_zone');
  });
}

/// İlk açılışta SharedPreferences'a bakarak onboarding gösterilecek mi,
/// eğitim profili seçimi gerekli mi, yoksa doğrudan CameraScreen'e mi
/// gidilecek karar verir.
class _StartupRouter extends StatefulWidget {
  const _StartupRouter();

  @override
  State<_StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<_StartupRouter> {
  Future<_StartupState>? _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<_StartupState> _resolve() async {
    // Splash en az 5000ms (5 saniye) görünsün — QuAlsar logo + harf intro +
    // disk animasyonu tam göstermeli; kullanıcı uygulamanın açıldığını net görsün.
    final minSplash = Future<void>.delayed(const Duration(milliseconds: 5000));
    final prefs = await SharedPreferences.getInstance();

    // Launch counter — her açılışta artar.
    final count = (prefs.getInt('app_launch_count_v2') ?? 0) + 1;
    await prefs.setInt('app_launch_count_v2', count);

    // İlk 10 giriş = "deneme/test" fazı:
    //   onboarding + eğitim setup TAMAMLANMAMIŞSA bu fazda mutlaka gösterilir.
    //   Tamamlandıysa atlanır.  11. açılıştan sonra normal akış.
    final inTrialPhase = count <= 10;

    final onboardingDone = prefs.getBool(OnboardingScreen.prefKey) ?? false;
    if (!onboardingDone) {
      await minSplash;
      return _StartupState.onboarding;
    }

    // Setup tamamlandı mı? mini_test_grade pref'inde grade kayıtlıysa OK.
    final hasGrade = (prefs.getString('mini_test_grade') ?? '').isNotEmpty;
    if (!hasGrade) {
      await minSplash;
      return _StartupState.educationSetup;
    }

    // İlk 10 girişte EduProfile.current henüz yüklenmemiş olabilir → yükle.
    if (inTrialPhase && EduProfile.current == null) {
      try {
        await EduProfile.load();
      } catch (_) {/* yok say */}
    }

    // Splash minimum süresini bekle — animasyon tamamlansın.
    await minSplash;
    return _StartupState.home;
  }

  void _onSetupSaved() {
    setState(() {
      _future = Future.value(_StartupState.home);
    });
  }

  Future<int> _currentTrialEntry() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('app_launch_count_v2') ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StartupState>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          // Native splash bittikten Flutter MaterialApp ilk frame'i çizene
          // kadar gösterilen marka açılış ekranı — beyaz titreme yok,
          // QuAlsar logosu + fütüristik harf girişi + dönen disk.
          return const QuAlsarSplashScreen();
        }
        switch (snap.data!) {
          case _StartupState.onboarding:
            return OnboardingScreen();
          case _StartupState.educationSetup:
            return FutureBuilder<int>(
              future: _currentTrialEntry(),
              builder: (_, s) => EducationSetupScreen(
                trialEntryNumber: s.data ?? 1,
                onSaved: _onSetupSaved,
              ),
            );
          case _StartupState.home:
            return _HomeRouter();
        }
      },
    );
  }
}

enum _StartupState { onboarding, educationSetup, home }

/// Kullanıcı tercihine göre Kamera veya Kütüphane açan router.
/// Ayarlar > Uygulamayı Kişiselleştir sekmesinde seçilir.
/// SharedPreferences key: `startup_screen` → 'camera' (varsayılan) veya 'library'
/// Minimal MaterialApp — Firebase/locale init beklemeden hemen
/// QuAlsarSplashScreen'i gösterir. main() heavy init bittiğinde gerçek
/// QuAlsarApp ile yer değiştirir (ikinci runApp çağrısı).
///
/// Önemli: Splash içindeki widget'lar AppPalette → ThemeInherited.of()
/// kullanıyor; bu yüzden minimal ama ThemeInherited wrapper'lı bir tree
/// kuruluyor. ThemeService default light mode ile başlar (SharedPref'ten
/// yüklemeden), yeterli çünkü splash görseli zaten beyaz.
class _InstantSplashApp extends StatelessWidget {
  const _InstantSplashApp();
  @override
  Widget build(BuildContext context) {
    return ThemeInherited(
      service: themeService, // global instance — light default
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: QuAlsarSplashScreen(),
      ),
    );
  }
}

class _HomeRouter extends StatelessWidget {
  // ignore: unused_element_parameter
  const _HomeRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: SharedPreferences.getInstance()
          .then((p) => p.getString('startup_screen') ?? 'camera'),
      builder: (_, snap) {
        if (!snap.hasData) return const QuAlsarSplashScreen();
        if (snap.data == 'library') return const LibraryLanding();
        return CameraScreen();
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  GlobalSidebarOverlay — Tüm sayfalarda görünen sürüklenebilir yan panel
// ═══════════════════════════════════════════════════════════════════════════
class _GlobalSidebarOverlay extends StatefulWidget {
  const _GlobalSidebarOverlay();
  @override
  State<_GlobalSidebarOverlay> createState() =>
      _GlobalSidebarOverlayState();
}

class _GlobalSidebarOverlayState extends State<_GlobalSidebarOverlay>
    with WidgetsBindingObserver {
  List<SidebarItem> _summarySubjects = [];
  List<SidebarItem> _questionSubjects = [];

  static const _kBlue = Color(0xFF2563EB);
  static const _kOrange = Color(0xFFFF6A00);
  static const _kPurple = Color(0xFF8B5CF6);
  static const _kPink = Color(0xFFEC4899);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSubjects();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Resume'da reload'u throttle et — kullanıcı hızlıca app'e girip çıkarsa
  // her seferinde 100+ JSON parse + tüm sidebar setState yapma.
  DateTime? _lastResumeReload;
  String? _lastSummaryHash;
  String? _lastQuestionHash;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastResumeReload != null &&
          now.difference(_lastResumeReload!) < const Duration(seconds: 30)) {
        return;
      }
      _lastResumeReload = now;
      _loadSubjects();
    }
  }

  Future<void> _loadSubjects() async {
    final prefs = await SharedPreferences.getInstance();
    final summaryRaw = prefs.getStringList('library_subjects_v2') ?? [];
    final qRaw = prefs.getStringList('library_subjects_questions_v2') ?? [];

    // İçerik aynıysa parse + setState yapma — gereksiz rebuild önlenir.
    final summaryHash =
        '${summaryRaw.length}|${summaryRaw.isNotEmpty ? summaryRaw.last.length : 0}';
    final qHash = '${qRaw.length}|${qRaw.isNotEmpty ? qRaw.last.length : 0}';
    if (summaryHash == _lastSummaryHash && qHash == _lastQuestionHash) {
      return;
    }
    _lastSummaryHash = summaryHash;
    _lastQuestionHash = qHash;

    if (!mounted) return;
    setState(() {
      _summarySubjects = _parseSubjects(summaryRaw, _kBlue);
      _questionSubjects = _parseSubjects(qRaw, _kOrange);
    });
  }

  List<SidebarItem> _parseSubjects(List<String> rawList, Color color) {
    final out = <SidebarItem>[];
    for (final s in rawList) {
      try {
        final j = jsonDecode(s) as Map<String, dynamic>;
        final name = j['name'] as String;
        final summaries = (j['summaries'] as List?) ?? [];
        out.add(SidebarItem(
          title: name,
          color: color,
          children: summaries.map<SidebarItem>((e) {
            final em = e as Map<String, dynamic>;
            final topic = em['topic'] as String;
            final content = (em['content'] as String?) ?? '';
            return SidebarItem(
              title: topic,
              color: color,
              pageBuilder: (_) => _SimplePreviewPage(
                title: topic,
                subtitle: name,
                color: color,
                content: content,
              ),
              openFullscreen: () {
                _push(_SimplePreviewPage(
                  title: topic,
                  subtitle: name,
                  color: color,
                  content: content,
                ));
              },
            );
          }).toList(),
        ));
      } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'main'); }
    }
    return out;
  }

  void _push(Widget page) {
    final nav = globalNavigatorKey.currentState;
    nav?.push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return SmartSidebar(
      items: [
        // ── 1. Profilim ana başlık ────────────────────────────────────────
        SidebarItem(
          title: localeService.tr('my_profile'),
          color: _kBlue,
          pageBuilder: (_) => ProfileScreen(),
          openFullscreen: () => _push(ProfileScreen()),
          children: [
            SidebarItem(
              title: localeService.tr('upgrade_unlimited'),
              color: _kPurple,
              pageBuilder: (_) => PremiumScreen(),
              openFullscreen: () => _push(PremiumScreen()),
            ),
            SidebarItem(
              title: localeService.tr('invite_friends_short'),
              color: _kPink,
              pageBuilder: (_) => InvitePage(),
              openFullscreen: () => _push(InvitePage()),
            ),
            SidebarItem(
              title: localeService.tr('language_selection'),
              color: _kBlue,
              pageBuilder: (_) => ProfileScreen(),
              openFullscreen: () => _push(ProfileScreen()),
            ),
            SidebarItem(
              title: localeService.tr('appearance'),
              color: _kPurple,
              pageBuilder: (_) => ProfileScreen(),
              openFullscreen: () => _push(ProfileScreen()),
            ),
          ],
        ),

        // ── 2. Kütüphanem ana başlık ──────────────────────────────────────
        SidebarItem(
          title: localeService.tr('my_library'),
          color: _kBlue,
          pageBuilder: (_) => LibraryLanding(),
          openFullscreen: () => _push(LibraryLanding()),
          children: [
            SidebarItem(
              title: localeService.tr('create_topic_summary'),
              color: _kBlue,
              pageBuilder: (_) =>
                  AcademicPlanner(mode: LibraryMode.summary),
              openFullscreen: () => _push(
                  AcademicPlanner(mode: LibraryMode.summary)),
              children: _summarySubjects,
            ),
            SidebarItem(
              title: localeService.tr('create_exam_questions'),
              color: _kOrange,
              pageBuilder: (_) =>
                  AcademicPlanner(mode: LibraryMode.questions),
              openFullscreen: () => _push(
                  AcademicPlanner(mode: LibraryMode.questions)),
              children: _questionSubjects,
            ),
            SidebarItem(
              title: localeService.tr('my_study_calendar'),
              color: _kPurple,
              pageBuilder: (_) => StudyCalendarPage(),
              openFullscreen: () => _push(StudyCalendarPage()),
            ),
          ],
        ),
      ],
    );
  }
}

// Tam ekran içerik sayfası (Tam Ekran butonundan açılır)
class _SimplePreviewPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final String content;
  const _SimplePreviewPage({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              subtitle,
              style: TextStyle(
                  fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Color(0xFFE5E7EB)),
          ),
          child: Text(
            content,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF1F2937),
            ),
          ),
        ),
      ),
    );
  }
}

class QuAlsarApp extends StatelessWidget {
  const QuAlsarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LocaleInherited(
      service: localeService,
      child: ThemeInherited(
        service: themeService,
        child: Builder(
          builder: (context) {
            final locale = LocaleInherited.of(context);
            final theme = ThemeInherited.of(context);
            // NOT: Önceden RuntimeTranslator.instance'ı dinleyen bir
            // AnimatedBuilder MaterialApp'ı sarıyordu. Her preload chunk
            // notify'ı tüm navigation stack'i rebuild ediyor, donmaya
            // yol açıyordu. LocaleService kendi notify'ı yapıyor ve
            // LocaleInherited bağımlılıkları zaten dil değişimini taşıyor;
            // RuntimeTranslator preload bittiğinde mevcut sayfa hâlâ
            // kaynak TR gösterse de bir sonraki rota geçişinde otomatik
            // doğru çeviri gelir — global rebuild'in maliyetine değmiyor.
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'QuAlsar',
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: theme.themeMode,
              navigatorKey: globalNavigatorKey,
              locale: Locale(locale.localeCode),
              supportedLocales: LocaleService.supportedLocales
                  .map((c) => Locale(c))
                  .toList(),
              localeResolutionCallback: (device, supported) {
                // 1) Önce uygulamanın aktif dilini supportedLocales içinde
                //    bulup döndür — bu Flutter'a RTL tespitini yaptırır.
                for (final s in supported) {
                  if (s.languageCode == locale.localeCode) return s;
                }
                // 2) Cihazın dili supported içindeyse
                if (device != null) {
                  for (final s in supported) {
                    if (s.languageCode == device.languageCode) return s;
                  }
                }
                return Locale('en');
              },
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (child != null) child,
                    const _GlobalSidebarOverlay(),
                  ],
                );
              },
              home: const _StartupRouter(),
            );
          },
        ),
      ),
    );
  }
}
