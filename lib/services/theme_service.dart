import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings_service.dart';
import 'preferences_sync_service.dart';

class ThemeService extends ChangeNotifier {
  static const _prefsKey = 'theme_mode_index';

  // Index varsayılanı 1 = Light. Kullanıcı bir kez seçim yapınca pref'te
  // saklanır ve sonraki açılışlarda korunur (aydınlıktan koyuya geçtiyse
  // koyu kalır). İlk kurulum / temiz install → aydınlık.
  int _index = 1;
  Timer? _autoDarkTimer;

  int get index => _index;

  /// Etkili tema modu. Eğer Otomatik Karanlık (AppSettings) aktifse saat
  /// aralığı kontrol edilir; aralık içindeyse dark, dışındaysa light dön.
  /// Manuel seçim (index) sadece otomatik mod kapalıyken etkili.
  ThemeMode get themeMode {
    if (AppSettingsService.instance.autoDarkEnabled) {
      return AppSettingsService.instance.shouldBeDarkNow
          ? ThemeMode.dark
          : ThemeMode.light;
    }
    return switch (_index) {
      0 => ThemeMode.dark,
      1 => ThemeMode.light,
      _ => ThemeMode.system,
    };
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_prefsKey);
    if (stored == null) {
      // Temiz kurulum → AÇIK mod. Pref'e HEMEN yaz: aksi halde bulut
      // senkronu (PreferencesSyncService) key'i bulamayıp "sistem" (2)
      // varsayar; cihaz sistem teması koyuysa uygulama yanlışlıkla koyu
      // kalır. Pref'i somutlaştırınca bu zincir kırılır.
      _index = 1;
      await prefs.setInt(_prefsKey, 1);
    } else {
      _index = stored;
    }
    notifyListeners();
    // AppSettings değişimlerini dinle — otomatik karanlık toggle/saat
    // değişince tema da hemen yansısın.
    AppSettingsService.instance.addListener(_onAppSettingsChanged);
    _scheduleAutoDarkTick();
  }

  /// Otomatik Karanlık aktifken her dakikada bir saati kontrol et — gece
  /// 19:00 olunca karanlığa geç, 07:00 olunca aydınlığa.
  void _scheduleAutoDarkTick() {
    _autoDarkTimer?.cancel();
    if (!AppSettingsService.instance.autoDarkEnabled) return;
    _autoDarkTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      notifyListeners();
    });
  }

  void _onAppSettingsChanged() {
    _scheduleAutoDarkTick();
    notifyListeners();
  }

  Future<void> setIndex(int i) async {
    if (i < 0 || i > 2 || i == _index) return;
    _index = i;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, i);
    notifyListeners();
    // Cloud sync — yeni cihazda tema tercihi korunur. Fire-and-forget.
    unawaited(PreferencesSyncService.syncFromLocal());
  }

  @override
  void dispose() {
    _autoDarkTimer?.cancel();
    AppSettingsService.instance.removeListener(_onAppSettingsChanged);
    super.dispose();
  }
}

class ThemeInherited extends InheritedNotifier<ThemeService> {
  const ThemeInherited({
    super.key,
    required ThemeService service,
    required super.child,
  }) : super(notifier: service);

  static ThemeService of(BuildContext context) {
    final w = context
        .dependOnInheritedWidgetOfExactType<ThemeInherited>();
    assert(w != null, 'ThemeInherited not found in context');
    return w!.notifier!;
  }
}
