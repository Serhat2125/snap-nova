// ═══════════════════════════════════════════════════════════════════════════
//  ParentalControlsService — Çocuk cihazında ebeveyn kontrolü ENFORCEMENT.
//
//  Ebeveyn `parental_controls/{childUid}`'e yazar (panelden). Bu servis çocuğun
//  CİHAZINDA o ayarları okuyup uygular:
//    • Günlük süre limiti  → bugünkü kullanım dakikası limiti aşınca kilitle.
//    • Sessiz saatler      → belirtilen saat aralığında kilitle.
//
//  Yalnızca ÖĞRENCİ hesabında çalışır (öğretmen/ebeveyn asla kilitlenmez).
//  Ayarlar offline çalışsın diye SharedPreferences'a da cache'lenir.
//  Kullanım dakikası gün-bazlı SharedPreferences'ta tutulur (pc_usage_<gün>).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_service.dart';
import 'parent_link_service.dart';

enum LockReason { none, quietHours, limitReached }

class _QuietRange {
  final int start;
  final int end;
  const _QuietRange(this.start, this.end);
}

class ParentalControlsService extends ChangeNotifier {
  ParentalControlsService._();
  static final ParentalControlsService instance = ParentalControlsService._();

  bool _timeLimitEnabled = false;
  int _dailyLimitMinutes = 120;
  bool _quietEnabled = false;
  int _quietStart = 21 * 60;
  int _quietEnd = 7 * 60;
  // Birden fazla bağlı ebeveyn (anne+baba) farklı sessiz saat aralıkları
  // belirleyebilir — hepsi ayrı ayrı kontrol edilir (en kısıtlayıcı: HERHANGİ
  // biri aktifse kilitli). _quietStart/_quietEnd tekil ebeveyn/offline cache
  // fallback'i için hâlâ tutuluyor.
  List<_QuietRange> _quietRanges = const [];
  bool _loaded = false;

  bool get hasAnyControl => _timeLimitEnabled || _quietEnabled;

  String _todayKey() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'pc_usage_${n.year}-${two(n.month)}-${two(n.day)}';
  }

  /// Sadece öğrenci hesabında enforcement uygulanır.
  bool get _appliesToThisAccount =>
      AccountService.instance.type == AccountType.student;

  /// Ayarları Firestore'dan oku (offline cache fallback). Uygulama açılışında
  /// ve ebeveyn değişiklik yapmış olabileceği için arada bir çağrılır.
  Future<void> refresh() async {
    if (!_appliesToThisAccount) {
      _timeLimitEnabled = false;
      _quietEnabled = false;
      _loaded = true;
      notifyListeners();
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final prefs = await SharedPreferences.getInstance();
    // Önce cache'ten yükle (offline / hızlı ilk değer).
    _readFromPrefs(prefs);
    if (uid != null) {
      try {
        // TÜM bağlı ebeveynlerin kısıtlarını oku — birden fazla ebeveyn
        // varsa (anne+baba) en kısıtlayıcısı uygulanır: HERHANGİ biri süre
        // limiti/sessiz saat açtıysa etkindir; süre limiti varsa EN KÜÇÜK
        // (en kısıtlayıcı) dakika kullanılır; tüm aktif sessiz aralıklar
        // ayrı ayrı kontrol edilir.
        final docs = await ParentLinkService.readAllParentalControls(uid);
        if (docs.isEmpty) {
          _timeLimitEnabled = false;
          _quietEnabled = false;
          _quietRanges = const [];
        } else {
          bool timeOn = false;
          int? minDaily;
          bool quietOn = false;
          final ranges = <_QuietRange>[];
          for (final m in docs) {
            if ((m['timeLimitEnabled'] ?? false) == true) {
              timeOn = true;
              final v = (m['dailyLimitMinutes'] ?? 120) as int;
              if (minDaily == null || v < minDaily) minDaily = v;
            }
            if ((m['quietHoursEnabled'] ?? false) == true) {
              quietOn = true;
              ranges.add(_QuietRange(
                (m['quietStartMinutes'] ?? 21 * 60) as int,
                (m['quietEndMinutes'] ?? 7 * 60) as int,
              ));
            }
          }
          _timeLimitEnabled = timeOn;
          _dailyLimitMinutes = minDaily ?? 120;
          _quietEnabled = quietOn;
          _quietRanges = ranges;
          if (ranges.isNotEmpty) {
            _quietStart = ranges.first.start;
            _quietEnd = ranges.first.end;
          }
        }
        await _writeToPrefs(prefs);
      } catch (e) {
        debugPrint('[ParentalControls] refresh fail (cache kullanılıyor): $e');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  void _readFromPrefs(SharedPreferences p) {
    _timeLimitEnabled = p.getBool('pc_cache_time_enabled') ?? false;
    _dailyLimitMinutes = p.getInt('pc_cache_daily') ?? 120;
    _quietEnabled = p.getBool('pc_cache_quiet_enabled') ?? false;
    _quietStart = p.getInt('pc_cache_quiet_start') ?? 21 * 60;
    _quietEnd = p.getInt('pc_cache_quiet_end') ?? 7 * 60;
  }

  Future<void> _writeToPrefs(SharedPreferences p) async {
    await p.setBool('pc_cache_time_enabled', _timeLimitEnabled);
    await p.setInt('pc_cache_daily', _dailyLimitMinutes);
    await p.setBool('pc_cache_quiet_enabled', _quietEnabled);
    await p.setInt('pc_cache_quiet_start', _quietStart);
    await p.setInt('pc_cache_quiet_end', _quietEnd);
  }

  /// Ön planda geçirilen süreyi bugünkü kullanıma ekler.
  Future<void> addUsageSeconds(int seconds) async {
    if (!_appliesToThisAccount || !_timeLimitEnabled || seconds <= 0) return;
    try {
      final p = await SharedPreferences.getInstance();
      final key = _todayKey();
      final cur = p.getInt(key) ?? 0;
      await p.setInt(key, cur + seconds);
    } catch (_) {}
  }

  Future<int> usedMinutesToday() async {
    try {
      final p = await SharedPreferences.getInstance();
      return ((p.getInt(_todayKey()) ?? 0) / 60).floor();
    } catch (_) {
      return 0;
    }
  }

  /// Bir aralık şu an aktif mi (gece yarısını sarmayı destekler).
  bool _rangeActive(int start, int end, int now) {
    if (start == end) return false;
    if (start < end) return now >= start && now < end;
    // Gece sarması: 21:00 → 07:00
    return now >= start || now < end;
  }

  /// Sessiz saat aralığı şu an aktif mi — birden fazla bağlı ebeveynin
  /// aralıkları varsa HERHANGİ biri aktifse kilitli (en kısıtlayıcı).
  bool _inQuietHours() {
    if (!_quietEnabled) return false;
    final now = DateTime.now().hour * 60 + DateTime.now().minute;
    if (_quietRanges.isEmpty) {
      return _rangeActive(_quietStart, _quietEnd, now);
    }
    return _quietRanges.any((r) => _rangeActive(r.start, r.end, now));
  }

  /// Şu an kilit gerekiyor mu? Senkron (kullanım dakikası önceden hesaplanır).
  LockReason lockFor(int usedMinutes) {
    if (!_appliesToThisAccount || !_loaded) return LockReason.none;
    if (_inQuietHours()) return LockReason.quietHours;
    if (_timeLimitEnabled && usedMinutes >= _dailyLimitMinutes) {
      return LockReason.limitReached;
    }
    return LockReason.none;
  }

  // Kilit ekranında gösterim için yardımcılar.
  int get dailyLimitMinutes => _dailyLimitMinutes;
  String get quietRangeLabel {
    String f(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    return '${f(_quietStart)} – ${f(_quietEnd)}';
  }
}
