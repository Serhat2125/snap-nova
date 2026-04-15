import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/camera_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';
import 'services/locale_service.dart';
import 'services/theme_service.dart';

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
            final _ = LocaleInherited.of(context);
            final theme = ThemeInherited.of(context);
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'QuAlsar',
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: theme.themeMode,
              home: const _StartupRouter(),
            );
          },
        ),
      ),
    );
  }
}
