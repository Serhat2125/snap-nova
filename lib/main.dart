import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/camera_screen.dart';
import 'theme/app_theme.dart';
import 'services/locale_service.dart';

/// Uygulama genelinde erişilebilen kamera listesi.
/// main() içinde bir kez doldurulur.
List<CameraDescription> globalCameras = [];

/// Uygulama genelinde erişilebilen dil servisi.
final localeService = LocaleService();

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

  runApp(const SnapNovaApp());
}

class SnapNovaApp extends StatelessWidget {
  const SnapNovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LocaleInherited(
      service: localeService,
      child: Builder(
        builder: (context) {
          // LocaleService değiştiğinde yeniden build edilir
          final _ = LocaleInherited.of(context);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'SnapNova',
            theme: AppTheme.dark,
            home: const CameraScreen(),
          );
        },
      ),
    );
  }
}
