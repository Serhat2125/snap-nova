import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/camera_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/academic_planner.dart';
import 'screens/premium_screen.dart';
import 'screens/profile_screen.dart';
import 'theme/app_theme.dart';
import 'services/locale_service.dart';
import 'services/theme_service.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase henüz yapılandırılmamış — google-services.json eksik olabilir.
    // Uygulama Firebase olmadan da çalışır; feedback sessizce atlanır.
  }

  try {
    globalCameras = await availableCameras();
  } catch (_) {
    globalCameras = [];
  }

  // Dil tercihini yükle (SharedPreferences) veya cihaz dilini algıla
  await localeService.init();
  await themeService.init();

  runApp(const QuAlsarApp());
}

/// İlk açılışta SharedPreferences'a bakarak onboarding gösterilecek mi,
/// yoksa doğrudan CameraScreen'e mi gidilecek karar verir.
class _StartupRouter extends StatelessWidget {
  const _StartupRouter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasSeenOnboarding(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: SizedBox.shrink(),
          );
        }
        return snap.data! ? const CameraScreen() : const OnboardingScreen();
      },
    );
  }

  Future<bool> _hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(OnboardingScreen.prefKey) ?? false;
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
        child: Builder(
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
    );
  }
}
