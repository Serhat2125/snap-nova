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
import 'screens/qualsar_arena_screen.dart';
import 'screens/notifications_inbox_screen.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'services/analytics.dart';
import 'services/ai_provider_service.dart';
import 'services/ai_quota_service.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';
import 'services/local_reminder_service.dart';
import 'services/deep_link_service.dart';
import 'services/usage_quota.dart';
import 'services/pomodoro_stats.dart';
import 'services/account_service.dart';
import 'services/app_settings_service.dart';
import 'screens/parent_intro_screen.dart';
import 'screens/parent_shell_screen.dart';
import 'screens/teacher_shell_screen.dart';
import 'services/preferences_sync_service.dart';
import 'services/user_profile_service.dart';
import 'screens/app_lock_screen.dart';
import 'screens/invite_accept_screen.dart';
import 'screens/group_contest_screen.dart';
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
import 'widgets/parental_control_gate.dart';

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

/// QuAlsarApp tek seferlik başlatma guard'ı — safety-net Timer ile normal
/// flow yarış halinde olabilir; flag her iki yolun da çift runApp atmasını
/// engeller.
bool _appLaunched = false;
void _launchAppOnce() {
  if (_appLaunched) return;
  _appLaunched = true;
  runApp(ProviderScope(child: QuAlsarApp()));
}

Future<void> main() async {
  // ═══════════════════════════════════════════════════════════════════════
  //  Global hata sınırı — çöken her widget / zone exception'ı
  //  ErrorLogger'a düşer, uygulama açık kalır.
  // ═══════════════════════════════════════════════════════════════════════
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ErrorWidget — release'de sessiz boş alan (kullanıcıya kırmızı kutu
    // gösterme); debug'da KIRMIZI KUTUYU KORU çünkü geliştirme sırasında
    // hatayı gizlemek "beyaz ekran sebebini bulamamak" demek.
    if (kReleaseMode) {
      ErrorWidget.builder = (FlutterErrorDetails details) {
        FlutterError.reportError(details);
        return const SizedBox.shrink();
      };
    }

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
    // Splash'ın render olmasına yetecek kadar bekle. 16ms tek frame için sınırda;
    // 80ms = ~5 frame ile splash garanti çizilir, sonra heavy init başlasın.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    // ═══════════════════════════════════════════════════════════════════════
    //  SAFETY NET — Heavy init'in herhangi bir yerinde sonsuz takılırsa
    //  20 saniye sonra QuAlsarApp ZORLA başlatılır; beyaz ekranda asla
    //  takılıp kalınmaz. Init başarıyla biterse aşağıdaki normal runApp
    //  bu Timer'dan ÖNCE atar; _launchedApp guard'ı çift runApp'ı engeller.
    // ═══════════════════════════════════════════════════════════════════════
    Timer(const Duration(seconds: 20), () {
      if (_appLaunched) return;
      debugPrint('[main] SAFETY NET: heavy init 20sn\'den uzun sürdü → '
          'QuAlsarApp zorla başlatılıyor.');
      _launchAppOnce();
    });

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
      // Firebase init — 8sn timeout ile; ağ yoksa donma yerine offline aç.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 8));
      AuthService.firebaseReady = true;

      // ── App Check — Phone Auth + Firestore abuse koruması ─────────────
      // Play Integrity (Android prod), Debug provider (dev/debug build),
      // DeviceCheck (iOS). Phone Auth'un error 39 vermesini önler.
      // ARKA PLANDA: ağ çağrısıdır; splash'ı bekletmesin (eskiden 4sn'e
      // kadar açılışı uzatıyordu — "bazen donuyor" şikayetinin parçası).
      unawaited(() async {
        try {
          await FirebaseAppCheck.instance.activate(
            androidProvider: kDebugMode
                ? AndroidProvider.debug
                : AndroidProvider.playIntegrity,
            appleProvider: kDebugMode
                ? AppleProvider.debug
                : AppleProvider.deviceCheck,
          ).timeout(const Duration(seconds: 8));
        } catch (e, st) {
          ErrorLogger.instance.capture(e, st, context: 'app_check_activate');
        }
      }());

      // Firestore offline cache — ağ kesikken son veriye erişim + yazma kuyruğu.
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      // Anonim Firebase Auth — Bilgi Ligi gibi yazmaları olan modüller
      // her kullanıcının uid'ye sahip olmasını gerektirir. currentUser
      // null ise tek seferlik anonim oturum aç. ARKA PLANDA: ağ çağrısı,
      // yavaş ağda 5sn'e kadar splash'ı bekletiyordu; cloud yazan modüller
      // uid'yi kullanım anında zaten kontrol ediyor.
      unawaited(() async {
        try {
          if (fb_auth.FirebaseAuth.instance.currentUser == null) {
            await fb_auth.FirebaseAuth.instance
                .signInAnonymously()
                .timeout(const Duration(seconds: 10));
          }
        } catch (_) {/* anonim auth başarısız → cloud yazımları atlanır */}
      }());
      // Analytics + Crashlytics — Firebase init başarılı olduktan SONRA.
      // Hata atmaz; init başarısızsa no-op'a düşer. Arka planda: açılışı
      // bekletmez, handler kaydı init biter bitmez yapılır.
      unawaited(Analytics.init().then((_) {
        Analytics.registerFlutterErrorHandler();
      }).catchError((_) {}));
    } catch (e, st) {
      AuthService.firebaseReady = false;
      debugPrint('[Firebase] init başarısız: $e\n'
          'Çözüm: terminalde "flutterfire configure" çalıştırıp '
          'firebase_options.dart\'ı üret. Sonra google-services.json (Android) '
          've GoogleService-Info.plist (iOS) dosyalarının yerinde olduğundan '
          'emin ol.\n$st');
    }

    // ── Hata toplayıcı (Firestore opsiyonel) ──────────────────────────
    // KRİTİK: Aşağıdaki awaits HERHANGI BİRİ throw atarsa son
    // runApp(QuAlsarApp) HİÇ ÇALIŞMAZ ve kullanıcı sonsuza dek beyaz
    // splash görür. Bu yüzden her adımı KENDI try/catch'inde sarmala —
    // bir tanesi patlayıp init devam etsin, runApp() garanti çalışsın.
    try {
      await ErrorLogger.instance.init();
    } catch (e, st) {
      // ErrorLogger'ın kendisi patladıysa capture() no-op olur; konsola yaz.
      debugPrint('[init] ErrorLogger.init başarısız: $e\n$st');
    }

    // ── Kamera, dil, tema, ağ, ülke, uzaktan ayar ─────────────────────
    // PARALEL: bu init'lerin hepsi birbirinden bağımsız (çoğu SharedPreferences
    // okuması). Eskiden sıralı await zinciriydi → toplam süre = hepsinin
    // TOPLAMI; şimdi en yavaş olanı kadar. Her görev kendi try/catch'inde:
    // biri patlarsa diğerleri ve boot devam eder.
    Future<void> guarded(String ctx, Future<void> Function() task) async {
      try {
        await task();
      } catch (e, st) {
        ErrorLogger.instance.capture(e, st, context: ctx);
      }
    }

    // Voice & TTS — Sesli Komut için. Hata atmaz; başarısızsa no-op.
    unawaited(VoiceInputService.init());
    unawaited(TtsService.init());

    await Future.wait<void>([
      guarded('camera_enumeration', () async {
        globalCameras = await availableCameras();
      }),
      guarded('locale_init', localeService.init),
      guarded('theme_init', themeService.init),
      guarded('connectivity_init', connectivityService.init),
      guarded('ai_provider_load', AiProviderService.loadSelection),
      guarded('ai_quota_init', () => AiQuotaService.instance.init()),
      // Saklı oturumu yükle — auth_user_v1 prefs key'inden.
      guarded('auth_init', AuthService.init),
      // AppSettings (sessiz saatler, otomatik karanlık, ses, kilit, vb.)
      guarded('app_settings_init', () => AppSettingsService.instance.init()),
      // Hesap tipi (öğrenci/ebeveyn/öğretmen) — _HomeRouter yönlendirme için
      // okur. init() prefs'ten yükler + Firestore'dan async senkronize.
      guarded('account_init', () => AccountService.instance.init()),
    ]);
    // Premium-aware kota — UsageQuota.limits PremiumStatus revision değişince
    // otomatik FREE ↔ PREMIUM arasında swap edilir. Ödemeden sonra anında
    // yeni kotaya geçer; init'te de mevcut durum okunur.
    unawaited(UsageQuota.initPremiumListener());
    // Pomodoro istatistikleri cloud restore — yerel boşsa cloud'dan al,
    // yeni telefonda streak + toplam faz + rozet korunur.
    unawaited(PomodoroStats.restoreFromCloudIfEmpty());
    // Çalışma aktivite geçmişi cloud restore — yerel boşsa cloud'dan al;
    // yeni cihazda Gelişim Paneli/haftalık özet, takvim açılmadan da dolu gelir.
    unawaited(restoreActivityFromCloudIfEmpty());
    // Uygulama Tercihleri cloud restore (dil/tema/bildirim/açılış ekranı)
    // — yerel eksikse cloud'daki kullanıcı tercihlerini yere yaz, yeni
    // telefonda kullanıcı ayarlarını tekrar yapmasın.
    unawaited(PreferencesSyncService.restoreFromCloudIfEmpty());
    // AppSettings + AccountService yukarıdaki PARALEL Future.wait bloğunda
    // init edildi (tekrar await etmeye gerek yok; her ikisi idempotent olsa
    // da çift init = çift prefs okuması demek).
    // Username + display name + avatar — Firestore stream ile canlı.
    // Cache hızlı; offline'da bile username görünür.
    unawaited(UserProfileService.instance.init());
    // FCM push + local notifications — Firebase init başarılıysa.
    // Bildirim izni dialog'u burada çıkar; arka planda çalışır, UI bloklamaz.
    if (AuthService.firebaseReady) {
      unawaited(PushService.init(onTap: (payload) {
        // Bildirime basınca türüne göre ilgili sayfaya yönlendir.
        final type = payload['type']?.toString() ?? '';
        final nav = globalNavigatorKey.currentState;
        if (nav == null) return;
        switch (type) {
          case 'friend_request':
          case 'friend_accepted':
            nav.push(MaterialPageRoute(
                builder: (_) =>
                    QuAlsarArenaScreen(openAction: 'friendRequests')));
            break;
          case 'duelo_invite':
            nav.push(MaterialPageRoute(
                builder: (_) =>
                    QuAlsarArenaScreen(openAction: 'dueloInvites')));
            break;
          default:
            // Diğer türler: bildirim kutusunu aç.
            nav.push(MaterialPageRoute(
                builder: (_) => const NotificationsInboxScreen()));
        }
      }).then((_) {
        // Öğrenci hatırlatıcılarını (çalışma/seri/sınav) planla + yeni rozet
        // bildirimlerini eşitle. Öğretmen/ebeveyn için bunları iptal et.
        //
        // ÖNEMLİ: Sadece boot anında değil, hesap tipi SONRADAN değişince de
        // (taze giriş / onboarding'de "öğrenci" seçimi / Firestore senkronu)
        // tekrar çalışmalı. Boot'ta henüz öğrenci olmayan (çıkışta açılan) bir
        // kullanıcı oturum içinde giriş yapınca restart beklemeden hatırlatıcı
        // kurulsun. AccountService ChangeNotifier olduğundan tipi dinliyoruz;
        // [lastStudent] guard'ı gereksiz tekrar planlamayı (her notify'da) önler.
        bool? lastStudent;
        void syncStudentReminders() {
          final isStu = AccountService.instance.isStudent;
          if (isStu == lastStudent) return;
          lastStudent = isStu;
          if (isStu) {
            unawaited(LocalReminderService.rescheduleAll());
            unawaited(LocalReminderService.syncAchievements());
          } else {
            unawaited(LocalReminderService.cancelAll());
          }
        }

        AccountService.instance.addListener(syncStudentReminders);
        syncStudentReminders(); // mevcut durumu hemen uygula
      }));
    }
    // Deep link davet handler — uygulamayı linkten açana profil/davet sayfasını gösterir.
    unawaited(DeepLinkService.instance.init());
    // Runtime translator — kalıcı cache'i yükle + LocaleService'e hook bağla
    try { await RuntimeTranslator.instance.init(); } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'runtime_translator_init');
    }
    // bulkRegister ÇOK pahalı: 5000+ string'i set'e atar, 3sn sonra büyük
    // jsonEncode + SharedPreferences write yapar. Cihaz Türkçeyse hiçbir
    // çeviriye gerek olmadığı için tamamen atlanır. Diğer dillerde de
    // sadece dil değişiminde tetiklenir (setLocaleChangeHook altında),
    // her açılışta değil. Bu, startup'taki donmanın ana sebebiydi.
    try {
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
          await RuntimeTranslator.instance
              .preloadAll(localeService.localeCode);
        }());
      }
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'locale_hook_setup');
    }

    // IP geolocation arka planda (UI'ı bekletmez). Başarılıysa
    // locale'i ve ülke çözümleyiciyi yeniden değerlendir.
    // onError ile zone'a sızıntı engellenir.
    unawaited(GeolocationService.resolve().then((geo) async {
      if (geo != null) {
        await localeService.reevaluateFromGeo(ipCountry: geo.country);
      }
      await CountryResolver.instance.refresh(locale: localeService);
    }).catchError((_) {}));
    // Ülke çözümleyiciyi mevcut sinyallerle hemen doldur
    try {
      await CountryResolver.instance.init(locale: localeService);
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'country_resolver_init');
    }

    // Uzaktan ayar — cache anında, tazeleme arka planda. ARKA PLANDA:
    // tasarımı zaten cache-first; ilk açılışta fetch yavaş ağda 4sn'e kadar
    // splash'ı bekletiyordu. Değerleri okuyan modüller kullanım anında
    // cache/varsayılan görür, fetch bitince güncellenir.
    unawaited(() async {
      try {
        await RemoteConfigService.instance
            .init()
            .timeout(const Duration(seconds: 10));
      } catch (e, st) {
        ErrorLogger.instance.capture(e, st, context: 'remote_config_init');
      }
    }());

    // Müfredat kataloğu → education_profile'a bağla
    try { initCurriculumCatalog(); } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'curriculum_catalog_init');
    }

    // İlk açılışsa cihaz locale'inden ülkeyi tespit et — onboarding'in ülke
    // seçicisi bu pref'i varsayılan olarak alır (kullanıcı manuel
    // değiştirebilir, ama pek çok kullanıcı için tek tıkla doğru ülke gelir).
    try { await EduProfile.autoDetectCountryIfMissing(); } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'auto_detect_country');
    }

    // Mevcut öğrenci profilini cache'e yükle (AI prompt'larında kullanılır)
    try { await EduProfile.load(); } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'edu_profile_load');
    }
    // AI'dan üretilmiş profil-özel müfredat varsa belleğe yükle (varsa).
    // Hem ders listesi (subjects) hem de konu haritası (topics) ayrı cache'lerde.
    try { await EduProfile.loadAiSubjectCache(); } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'edu_ai_subject_cache');
    }
    try { await EduProfile.loadAiTopicsCache(); } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'edu_ai_topics_cache');
    }

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
    _launchAppOnce();
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

class _StartupRouterState extends State<_StartupRouter>
    with WidgetsBindingObserver {
  Future<_StartupState>? _future;
  // Uygulama kilidi (AppSettings.appLockEnabled) açıksa onboarding/setup
  // sonrası home'a geçmeden bu PIN doğrulanmalı.
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
    // Uygulama kilidini arka plandan dönünce yeniden kurmak için yaşam
    // döngüsünü dinle (aksi halde kilit yalnızca soğuk açılışta korurdu).
    WidgetsBinding.instance.addObserver(this);
    // Deep link davet listener — link gelince /davet/{username} → push.
    DeepLinkService.instance.pendingInvite.addListener(_handleInvite);
    // Grup yarışı daveti — /grup/{contestId} → GroupContestScreen (autoJoin).
    DeepLinkService.instance.pendingGroupContest
        .addListener(_handleGroupContest);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeepLinkService.instance.pendingInvite.removeListener(_handleInvite);
    DeepLinkService.instance.pendingGroupContest
        .removeListener(_handleGroupContest);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama tamamen arka plana geçtiğinde (paused) kilidi yeniden kur —
    // böylece geri dönünce PIN/biyometrik yeniden istenir. Sadece kilit
    // aktif + PIN kuruluysa anlamlı; aksi halde no-op.
    if (state == AppLifecycleState.paused &&
        _unlocked &&
        AppSettingsService.instance.appLockEnabled &&
        AppSettingsService.instance.hasAppLockPin) {
      setState(() => _unlocked = false);
    }
  }

  void _handleGroupContest() {
    final id = DeepLinkService.instance.pendingGroupContest.value;
    if (id == null || id.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = globalNavigatorKey.currentState;
      if (nav == null) return;
      DeepLinkService.instance.clearGroupContest();
      nav.push(MaterialPageRoute(
        builder: (_) => GroupContestScreen(contestId: id, autoJoin: true),
      ));
    });
  }

  void _handleInvite() {
    final username = DeepLinkService.instance.pendingInvite.value;
    if (username == null || username.isEmpty) return;
    // Navigator hazır olmasını bekle (post-frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = globalNavigatorKey.currentState;
      if (nav == null) return;
      DeepLinkService.instance.clearInvite();
      nav.push(MaterialPageRoute(
        builder: (_) => InviteAcceptScreen(username: username),
      ));
    });
  }

  Future<_StartupState> _resolve() async {
    // Splash en az süresi. Eskiden 5sn'di — "uygulama yavaş açılıyor"
    // şikayetinin en büyük parçası YAPAY bekleme çıktı. 2.2sn: başlık anında,
    // dönen disk ~0.8sn'de belirir (qualsar_splash_screen._logoRevealAfter),
    // marka anı korunur ama açılış 2.8sn kısalır. TEST modunda 0.5sn.
    final minSplash = Future<void>.delayed(
        Duration(milliseconds: kTestBypassAuth ? 500 : 2200));
    final prefs = await SharedPreferences.getInstance();

    // ── GELİŞTİRME BYPASS (yapım aşaması) ──────────────────────────────
    // Debug modda (flutter run) onboarding + giriş yöntemleri + eğitim
    // seçimi ekranlarını atlayıp doğrudan ana uygulamaya (CameraScreen) gir.
    // Release/profile build'i ETKİLEMEZ. Yayına çıkarken bu blok kalabilir.
    // Test modu açıkken bu bloğu ATLA — debug'da da rol seçim akışı gelsin
    // (aksi halde flutter run her zaman öğrenciye zorluyordu).
    if (kDebugMode && !kTestBypassAuth) {
      // İçerik EduProfile'a bağlı olduğundan eksikse varsayılan profil tohumla.
      if ((prefs.getString('mini_test_grade') ?? '').isEmpty) {
        await prefs.setString('mini_test_country', 'tr');
        await prefs.setString('mini_test_level', 'lise');
        await prefs.setString('mini_test_grade', '11');
      }
      await prefs.setBool(OnboardingScreen.prefKey, true);
      try {
        await EduProfile.load();
      } catch (_) {/* yok say */}
      // Kısa splash (animasyonu görmeden hızlı gir)
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return _StartupState.home;
    }
    // ───────────────────────────────────────────────────────────────────

    // ── TEST MODU (giriş/auth atlanır) ─────────────────────────────────
    // Tester'lar onboarding/giriş görmeden doğrudan rol + kullanıcı adı
    // seçer. Öğrenci home'u kamera olsun diye startup_screen='camera'.
    if (kTestBypassAuth) {
      await prefs.setString('startup_screen', 'camera');
      final done = prefs.getBool(OnboardingScreen.prefKey) ?? false;
      if (!done) {
        await minSplash;
        // OnboardingScreen UserSetup slaytından (rol+kullanıcı adı) açılır.
        return _StartupState.onboarding;
      }
      // Kurulum bitti → role göre: öğretmen/ebeveyn panel, öğrenci kamera.
      if (AccountService.instance.type != AccountType.student) {
        await minSplash;
        return _StartupState.home;
      }
      final hasGradeT = (prefs.getString('mini_test_grade') ?? '').isNotEmpty;
      await minSplash;
      return hasGradeT ? _StartupState.home : _StartupState.educationSetup;
    }
    // ───────────────────────────────────────────────────────────────────

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

    // Öğretmen/Ebeveyn'in öğrenci sınıf (grade) seçimine ihtiyacı yok —
    // grade kapısı yalnızca öğrenciye uygulanır. Aksi halde grade'i olmayan
    // öğretmen her açılışta öğrenci kurulum ekranına düşüp panele ulaşamıyordu.
    // (AccountService.instance.init() main()'de zaten await edildi; tip hazır.)
    if (AccountService.instance.type != AccountType.student) {
      await minSplash;
      return _StartupState.home;
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
            // Test modunda doğrudan rol+kullanıcı adı slaytından (2) başla;
            // normalde 0'dan (hero+giriş) başlar.
            return OnboardingScreen(initialPage: kTestBypassAuth ? 2 : 0);
          case _StartupState.educationSetup:
            return FutureBuilder<int>(
              future: _currentTrialEntry(),
              builder: (_, s) => EducationSetupScreen(
                trialEntryNumber: s.data ?? 1,
                onSaved: _onSetupSaved,
              ),
            );
          case _StartupState.home:
            // Uygulama kilidi açıksa önce PIN/biyometrik doğrulama
            if (AppSettingsService.instance.appLockEnabled &&
                AppSettingsService.instance.hasAppLockPin &&
                !_unlocked) {
              return AppLockScreen(
                onUnlocked: () => setState(() => _unlocked = true),
              );
            }
            return _HomeRouter();
        }
      },
    );
  }
}

/// TEST MODU — true iken giriş/auth (Google/e-posta) ekranı ATLANIR:
/// uygulama doğrudan rol + kullanıcı adı seçimiyle başlar, öğrenci her
/// açılışta "Fotoğraf Çek" (kamera) ekranına açılır. Test bitince/yayına
/// çıkarken false yap → normal onboarding + giriş akışı geri gelir.
/// KAPALI TEST: false → "Başla" → giriş yöntemi seç (Google) → kullanıcı kurulumu.
const bool kTestBypassAuth = false;

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
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (_, snap) {
        if (!snap.hasData) return const QuAlsarSplashScreen();
        final prefs = snap.data!;
        final startupScreen = prefs.getString('startup_screen') ?? 'library';
        // Hesap tipine göre yönlendir.
        // AccountService.init() main.dart açılışta çağrıldığı için type hazır.
        final type = AccountService.instance.type;
        if (type == AccountType.teacher) {
          return const TeacherShellScreen();
        }
        // Ebeveyn kökü: öğretmen kalıbındaki ParentShellScreen (Çocuklarım
        //   + orta ➕ FAB + "Öğrenci Paneli" önizleme sekmesi). 3 slaytlık
        //   intro'yu (çocuk nasıl eklenir anlatan TEK yer) hiç
        //   tamamlamadıysa önce onu göster.
        if (type == AccountType.parent) {
          if (prefs.getBool('parent_intro_completed') != true) {
            return const ParentIntroScreen();
          }
          return const ParentShellScreen();
        }
        // Öğrenci: varsayılan Kütüphanem; kullanıcı kamera seçtiyse kamera.
        if (startupScreen == 'camera') return CameraScreen();
        return const _LibraryEntryShell();
      },
    );
  }
}

// LibraryLanding root olarak açıldığında (kullanıcı startup_screen=library
// seçtiyse) geri tuşu APP'TEN ÇIKMAMALI — asıl ana sayfa CameraScreen
// (alt sekmeli sayfa) açılmalı. PopScope ile back'i intercept edip
// pushReplacement ile CameraScreen'e geç. CameraScreen'den sonraki back
// (sistem davranışı) artık uygulamadan çıkar — bu beklenen.
class _LibraryEntryShell extends StatelessWidget {
  const _LibraryEntryShell();
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => CameraScreen()),
        );
      },
      child: const LibraryLanding(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _GlobalTapSound — "Buton tıklama sesi" ayarı için uygulama-geneli tap sesi.
//  Listener gesture'ları engellemez (sadece gözlemler). Pointer down→up arası
//  hareket küçükse (gerçek tıklama, scroll/sürükleme değil) click sesi çalar.
// ═══════════════════════════════════════════════════════════════════════════
class _GlobalTapSound extends StatefulWidget {
  final Widget child;
  const _GlobalTapSound({required this.child});
  @override
  State<_GlobalTapSound> createState() => _GlobalTapSoundState();
}

class _GlobalTapSoundState extends State<_GlobalTapSound> {
  Offset? _downPos;
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _downPos = e.position,
      onPointerUp: (e) {
        final d = _downPos;
        _downPos = null;
        if (d == null) return;
        if ((e.position - d).distance > 12) return; // sürükleme → tıklama değil
        if (AppSettingsService.instance.clickSound) {
          unawaited(AppSettingsService.instance.playClick());
        }
      },
      child: widget.child,
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
            // NOT: RuntimeTranslator preload bittiğinde global rebuild ile
            // String.tr() çağrılarının ANINDA yeni dile geçmesini garanti
            // ederiz. RuntimeTranslator içinde _scheduleNotify 1.5 sn debounce
            // ettiği için preload chunk'larında donma olmaz; sadece nihai
            // sonuçta tek bir rebuild olur.
            return ListenableBuilder(
              listenable: RuntimeTranslator.instance,
              builder: (context, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'QuAlsar',
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: theme.themeMode,
              navigatorKey: globalNavigatorKey,
              // Bilgi Yarışı "Yarışlarım" kayıtlarını yarış sonrası tazelemek
              // için (RouteAware didPopNext).
              navigatorObservers: [arenaRouteObserver],
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
                // Global "Buton tıklama sesi" — ayar açıksa her GERÇEK tıklamada
                // (sürükleme/scroll değil) sistem click sesi çalar.
                return _GlobalTapSound(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (child != null) child,
                      const _GlobalSidebarOverlay(),
                      // Ebeveyn kontrolü kilidi (yalnız öğrenci hesabı + ayar
                      // varsa görünür). Her şeyin ÜSTÜNDE.
                      const ParentalControlGate(),
                    ],
                  ),
                );
              },
              home: const _StartupRouter(),
            ),
            );
          },
        ),
      ),
    );
  }
}
