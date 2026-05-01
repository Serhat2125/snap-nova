import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'widgets/smart_sidebar.dart';

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

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp]);

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
      // Firestore offline cache — ağ kesikken son veriye erişim + yazma kuyruğu.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      // Analytics + Crashlytics — Firebase init başarılı olduktan SONRA.
      // Hata atmaz; init başarısızsa no-op'a düşer.
      await Analytics.init();
      Analytics.registerFlutterErrorHandler();
    } catch (e, st) {
      AuthService.firebaseReady = false;
      // ignore: avoid_print
      print('[Firebase] init başarısız: $e\n'
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
    // Açılışta TÜM TR kaynak string'lerini runtime translator'a kaydet —
    // her dil değişiminde hepsi birden preload edilecek.
    for (final src in LocaleService.allTrSourceStrings) {
      RuntimeTranslator.instance.register(src);
    }

    LocaleService.setLocaleChangeHook((lang) async {
      // Her dil değişiminde önce tüm kaynakların kayıtlı olduğunu garanti et.
      for (final src in LocaleService.allTrSourceStrings) {
        RuntimeTranslator.instance.register(src);
      }
      await RuntimeTranslator.instance.preloadAll(lang);
    });
    // LocaleService.tr() içinde bir key'in çevirisi yoksa Türkçe kaynağı
    // runtime translator'dan geçirip cache'den okutsun.
    LocaleService.setRuntimeTranslateHook((source) {
      RuntimeTranslator.instance.register(source);
      return RuntimeTranslator.instance.lookup(source);
    });
    // Açılışta mevcut dil Türkçe değilse eksik çevirileri arka planda çek.
    if (localeService.localeCode != 'tr') {
      unawaited(RuntimeTranslator.instance.preloadAll(localeService.localeCode));
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

    // ProviderScope: Yeni feature katmanları (lib/features/...) Riverpod
    // kullanır; eski ekranlar StatefulWidget+setState ile çalışmaya devam
    // eder — wrapper sadece yeni provider'ları aktive eder, eski koda
    // hiçbir etkisi yok.
    runApp(const ProviderScope(child: QuAlsarApp()));
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
    // ── Geçici: onboarding + educationSetup atlandı, doğrudan ana ekran. ──
    // Kullanıcı isteği üzerine giriş ve tanıtım yazıları şimdilik gizli.
    // Geri getirmek için: aşağıdaki return'ü kaldırıp eski mantığı (her
    // açılışta onboarding) yeniden aktive et, ya da
    // 'onboarding_launch_count_v3' bazlı şartı geri tak.
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
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: SizedBox.shrink(),
          );
        }
        switch (snap.data!) {
          case _StartupState.onboarding:
            return const OnboardingScreen();
          case _StartupState.educationSetup:
            return FutureBuilder<int>(
              future: _currentTrialEntry(),
              builder: (_, s) => EducationSetupScreen(
                trialEntryNumber: s.data ?? 1,
                onSaved: _onSetupSaved,
              ),
            );
          case _StartupState.home:
            return const CameraScreen();
        }
      },
    );
  }
}

enum _StartupState { onboarding, educationSetup, home }

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSubjects();
    }
  }

  Future<void> _loadSubjects() async {
    final prefs = await SharedPreferences.getInstance();
    final summaryRaw = prefs.getStringList('library_subjects_v2') ?? [];
    final qRaw = prefs.getStringList('library_subjects_questions_v2') ?? [];

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
      } catch (_) {}
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
          pageBuilder: (_) => const ProfileScreen(),
          openFullscreen: () => _push(const ProfileScreen()),
          children: [
            SidebarItem(
              title: localeService.tr('upgrade_unlimited'),
              color: _kPurple,
              pageBuilder: (_) => const PremiumScreen(),
              openFullscreen: () => _push(const PremiumScreen()),
            ),
            SidebarItem(
              title: localeService.tr('invite_friends_short'),
              color: _kPink,
              pageBuilder: (_) => const InvitePage(),
              openFullscreen: () => _push(const InvitePage()),
            ),
            SidebarItem(
              title: localeService.tr('language_selection'),
              color: _kBlue,
              pageBuilder: (_) => const ProfileScreen(),
              openFullscreen: () => _push(const ProfileScreen()),
            ),
            SidebarItem(
              title: localeService.tr('appearance'),
              color: _kPurple,
              pageBuilder: (_) => const ProfileScreen(),
              openFullscreen: () => _push(const ProfileScreen()),
            ),
          ],
        ),

        // ── 2. Kütüphanem ana başlık ──────────────────────────────────────
        SidebarItem(
          title: localeService.tr('my_library'),
          color: _kBlue,
          pageBuilder: (_) => const LibraryLanding(),
          openFullscreen: () => _push(const LibraryLanding()),
          children: [
            SidebarItem(
              title: localeService.tr('create_topic_summary'),
              color: _kBlue,
              pageBuilder: (_) =>
                  const AcademicPlanner(mode: LibraryMode.summary),
              openFullscreen: () => _push(
                  const AcademicPlanner(mode: LibraryMode.summary)),
              children: _summarySubjects,
            ),
            SidebarItem(
              title: localeService.tr('create_exam_questions'),
              color: _kOrange,
              pageBuilder: (_) =>
                  const AcademicPlanner(mode: LibraryMode.questions),
              openFullscreen: () => _push(
                  const AcademicPlanner(mode: LibraryMode.questions)),
              children: _questionSubjects,
            ),
            SidebarItem(
              title: localeService.tr('my_study_calendar'),
              color: _kPurple,
              pageBuilder: (_) => const StudyCalendarPage(),
              openFullscreen: () => _push(const StudyCalendarPage()),
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
      backgroundColor: const Color(0xFFF5F6FA),
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
              style: const TextStyle(
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
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Text(
            content,
            style: const TextStyle(
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
        child: AnimatedBuilder(
          // RuntimeTranslator notifyListeners → tüm uygulama rebuild
          // (preload parça parça bittikçe UI otomatik günceller)
          animation: RuntimeTranslator.instance,
          builder: (context, _) => Builder(
            builder: (context) {
              final locale = LocaleInherited.of(context);
              final theme = ThemeInherited.of(context);
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
                if (device != null) {
                  for (final s in supported) {
                    if (s.languageCode == device.languageCode) return s;
                  }
                }
                return const Locale('en');
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
      ),
    );
  }
}
