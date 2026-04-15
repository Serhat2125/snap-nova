import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const _prefsKey = 'theme_mode_index';

  int _index = 0;

  int get index => _index;

  ThemeMode get themeMode => switch (_index) {
        0 => ThemeMode.dark,
        1 => ThemeMode.light,
        _ => ThemeMode.system,
      };

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _index = prefs.getInt(_prefsKey) ?? 0;
    notifyListeners();
  }

  Future<void> setIndex(int i) async {
    if (i < 0 || i > 2 || i == _index) return;
    _index = i;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, i);
    notifyListeners();
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
