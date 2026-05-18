// ignore_for_file: unused_element, unused_element_parameter

import '../services/runtime_translator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show localeService;
import '../services/analytics.dart';
import '../services/error_logger.dart';
import '../services/summary_cache_service.dart';
import '../widgets/summary_rating_table.dart';
import '../services/usage_quota.dart';
import '../features/offline/domain/offline_subject_pack.dart';
import '../features/offline/providers/offline_pack_provider.dart';
import '../services/curriculum_catalog.dart';
import '../services/education_profile.dart';
import '../services/gemini_service.dart';
import '../services/rag_service.dart';
import '../widgets/latex_text.dart';
import '../widgets/qualsar_loading_widget.dart';
import 'test_page.dart';
import 'green_colony_screen.dart';
import 'history_screen.dart';
import 'qualsar_arena_screen.dart';
import 'bilgi_ligi_screen.dart';
import '../widgets/study_toolbar.dart';
import 'qualsar_mars_screen.dart';
import '../services/pomodoro_stats.dart';

import '../theme/app_theme.dart';
// ═══════════════════════════════════════════════════════════════════════════════
//  Kütüphane — Ders bazlı kart sistemi
//  • Her + kartı bir ders. İlk basışta ders adı + ilk konu istenir.
//  • Kart dolunca bir daha basılınca SADECE yeni konu istenir, o derse eklenir.
//  • Başka ders için başka + kartına basılır.
//  • Özet AI (Gemini) tarafından öğrencinin sınav seviyesine göre üretilir.
// ═══════════════════════════════════════════════════════════════════════════════

// Geliştirme sürecinde sınırsız — yayına alırken tekrar 15 yap.
const _monthlyLimit = 100000;
const _blue = Color(0xFF2563EB);
const _orange = Color(0xFFFF6A00);
const _indigo = Color(0xFF6366F1);
const _cardSlots = 3;

// ═══════════════════════════════════════════════════════════════════════════
//  Activity store — detaylı kayıt (tarih + saat + ders + konu + tip)
// ═══════════════════════════════════════════════════════════════════════════
class _ActivityEntry {
  final DateTime when;
  final String subject;
  final String topic;
  final String type; // 'özet' | 'soru'
  /// Sayfada geçirilen AKTİF süre (saniye). Idle pause'lar düşülmüştür;
  /// yalnızca kullanıcının etkileşim içinde olduğu zaman.
  final int durationSec;

  /// Aynı oturumda hareketsizlik (idle) yüzünden duraklatılan süre.
  /// Ebeveyn panelinde "Pasif Zaman" olarak raporlanır. 0 → ya tam
  /// aktif geçti ya da eski kayıt (geriye uyumlu).
  final int idleSec;

  _ActivityEntry({
    required this.when,
    required this.subject,
    required this.topic,
    required this.type,
    this.durationSec = 0,
    this.idleSec = 0,
  });

  Map<String, dynamic> toJson() => {
        'when': when.toIso8601String(),
        'subject': subject,
        'topic': topic,
        'type': type,
        if (durationSec > 0) 'durationSec': durationSec,
        if (idleSec > 0) 'idleSec': idleSec,
      };

  factory _ActivityEntry.fromJson(Map<String, dynamic> j) => _ActivityEntry(
        when: DateTime.parse(j['when'] as String),
        subject: j['subject'] as String,
        topic: j['topic'] as String,
        type: (j['type'] as String?) ?? 'özet',
        durationSec: (j['durationSec'] as int?) ?? 0,
        idleSec: (j['idleSec'] as int?) ?? 0,
      );
}

class _ActivityStore {
  static const _key = 'library_activity_log_v2';
  // SharedPreferences'taki aktif log cap. Bu sayıyı aşan kayıtlar arşive
  // taşınır → kullanıcı haftalar geçtikten sonra "kaybolan" veri görmesin.
  // Önceki 200 cap, aktif kullanıcılarda 2 haftada veri kaybına yol açıyordu.
  static const int _activeCap = 1000;
  // Cap aşıldığında arşive taşınacak miktar — en eski _archiveSpill kayıt
  // disk dosyasına eklenir (append-only).
  static const int _archiveSpill = 500;
  static const String _archiveFileName = 'library_activity_archive_v1.jsonl';

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Tüm write ops sıralı kuyrukta — SolutionsStorage._serialize pattern.
  // SharedPreferences read-modify-write concurrent çağrılarında entry kaybı
  // oluşmasın. Async append archive de aynı lock altında.
  static Future<void> _writeLock = Future.value();
  static Future<T> _serialize<T>(Future<T> Function() task) {
    final prev = _writeLock;
    final c = Completer<T>();
    _writeLock = prev.then((_) async {
      try {
        final r = await task();
        c.complete(r);
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  static Future<File> _archiveFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_archiveFileName');
  }

  static _ActivityEntry? _parseLine(String s) {
    try {
      return _ActivityEntry.fromJson(
          jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Hem SharedPreferences'taki aktif log'u hem arşiv dosyasını okuyup
  /// birleşik liste döner. Bozuk satırlar partial-recovery ile atlanır.
  static Future<List<_ActivityEntry>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final activeList = prefs.getStringList(_key) ?? [];
    final out = <_ActivityEntry>[];
    for (final s in activeList) {
      final e = _parseLine(s);
      if (e != null) out.add(e);
    }
    // Arşiv dosyasını oku — JSON Lines (her satır bir entry). I/O fail
    // olursa sadece prefs verisi döner.
    try {
      final f = await _archiveFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        for (final line in const LineSplitter().convert(raw)) {
          if (line.trim().isEmpty) continue;
          final e = _parseLine(line);
          if (e != null) out.add(e);
        }
      }
    } catch (e) {
      debugPrint('[ActivityStore] archive read fail: $e');
    }
    return out;
  }

  // Mevcut hafta için günlere göre gruplayarak döner
  static Future<Map<String, List<_ActivityEntry>>> readWeekGrouped() async {
    final all = await readAll();
    final out = <String, List<_ActivityEntry>>{};
    for (final e in all) {
      final k = dayKey(e.when);
      out.putIfAbsent(k, () => []).add(e);
    }
    for (final v in out.values) {
      v.sort((a, b) => b.when.compareTo(a.when));
    }
    return out;
  }

  // İç yardımcı — cap aştığında eski kayıtları arşiv dosyasına taşır.
  // Çağıran zaten _serialize altındadır, ek lock yok.
  static Future<List<String>> _trimAndArchive(List<String> list) async {
    if (list.length <= _activeCap) return list;
    final overflow = list.length - (_activeCap - _archiveSpill);
    if (overflow <= 0) return list;
    final toArchive = list.sublist(0, overflow);
    try {
      final f = await _archiveFile();
      // Append (line-by-line). Bir entry başarısız yazılsa diğerleri korunur.
      final sink = f.openWrite(mode: FileMode.append);
      try {
        for (final line in toArchive) {
          sink.writeln(line);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return list.sublist(overflow);
    } catch (e) {
      debugPrint('[ActivityStore] archive append fail: $e — eski kayıtlar trimlenmedi');
      // Fail durumunda silme yapma — kullanıcı verisi kaybolmasın. Cap aşılı
      // kalır ama veri korunur.
      return list;
    }
  }

  static Future<void> log({
    required String subject,
    required String topic,
    required String type,
  }) {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = List<String>.from(prefs.getStringList(_key) ?? []);
        final entry = _ActivityEntry(
          when: DateTime.now(),
          subject: subject,
          topic: topic,
          type: type,
        );
        list.add(jsonEncode(entry.toJson()));
        final trimmed = await _trimAndArchive(list);
        await prefs.setStringList(_key, trimmed);
      } catch (e) {
        debugPrint('[ActivityStore] log fail: $e');
      }
    });
  }

  /// Kullanıcı bir sayfayı kapattığında çağrılır — geçirilen süreyle
  /// birlikte yeni bir entry yazar. Çok kısa açılışlar (< 5 sn) atılır.
  /// `startedAt` verilirse entry zamanı session başlangıcına yazılır
  /// (gece yarısı geçişlerinde session başladığı güne sayılır).
  /// idleSec → o oturumda hareketsizlik yüzünden duraklatılan süre.
  static Future<void> logSession({
    required String subject,
    required String topic,
    required String type,
    required int durationSec,
    int idleSec = 0,
    DateTime? startedAt,
  }) {
    return _serialize(() async {
      if (durationSec < 5) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = List<String>.from(prefs.getStringList(_key) ?? []);
        final entry = _ActivityEntry(
          // Gece yarısı bug'ı için session start time. Yoksa now() —
          // backwards compatible (eski callsite'lar etkilenmez).
          when: startedAt ?? DateTime.now(),
          subject: subject,
          topic: topic,
          type: type,
          durationSec: durationSec,
          idleSec: idleSec,
        );
        list.add(jsonEncode(entry.toJson()));
        final trimmed = await _trimAndArchive(list);
        await prefs.setStringList(_key, trimmed);
      } catch (e) {
        debugPrint('[ActivityStore] logSession fail: $e');
      }
      StudySessionTracker.instance._notifyDataChanged();
    });
  }
}

/// Pomodoro / Yeşil Koloni ekranlarından çalışma takvimine session
/// yazmak için public bridge. Ders adı yok — özel "Pomodoro" subject ile
/// loglanır ki "Çalışma Takvimim"de Pomodoro kategorisi olarak görünsün.
Future<void> logPomodoroSessionToCalendar({
  required int durationSec,
  String? label,
}) {
  if (durationSec < 5) return Future.value();
  // Default label runtime'da kullanıcının diline çevrilir.
  final resolvedLabel = label ?? 'Odak Seansı'.tr();
  return _ActivityStore.logSession(
    subject: 'Pomodoro',
    topic: resolvedLabel,
    type: 'pomodoro',
    durationSec: durationSec,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  StudySessionTracker — kullanıcının özet/test sayfasında geçirdiği süreyi
//  ölçer; sayfa kapanınca _ActivityStore'a yazar. ChangeNotifier sayesinde
//  takvim sekmesi anlık veriyi dinler.
//
//  GÜVENLİK / DOĞRULAMA KATMANLARI (hayalet süre engelleme):
//   1) ETKİLEŞİM KONTROLÜ: Kullanıcı 2 dakika hareketsiz kalırsa süre
//      otomatik durdurulur, "Hâlâ burada mısın?" uyarısı çıkar. Bir tap
//      veya kaydırma ile süre kaldığı yerden devam eder.
//   2) UYGULAMA YAŞAM DÖNGÜSÜ: Uygulama arka plana atıldığında veya ekran
//      kapandığında süre anında dondurulur (WidgetsBindingObserver).
//   3) BİRİKİMSEL SÜRE: Tek bir _startedAt yerine "biriken saniye + aktif
//      segment başlangıcı" tutulur — pause/resume süreyi kaybetmeden çalışır.
// ═══════════════════════════════════════════════════════════════════════════
class StudySessionTracker extends ChangeNotifier
    with WidgetsBindingObserver {
  StudySessionTracker._();
  static final StudySessionTracker instance = StudySessionTracker._();

  /// Kullanıcı hareketsiz kaldığında otomatik pause eşiği.
  static const Duration idleThreshold = Duration(minutes: 2);

  /// Checkpoint anahtarı — devam eden session'ın SharedPreferences snapshot'u.
  /// App lifecycle detached / crash sonrası kurtarma için.
  static const String _ckptKey = 'study_tracker_checkpoint_v1';
  /// Her N saniyede bir checkpoint güncellenir — crash'te en kötü kayıp.
  static const int _ckptIntervalSec = 30;
  int _tickCounter = 0;

  String? _subject;
  String? _topic;
  String? _type; // 'özet' | 'soru'

  /// İlk start() çağrısının zamanı — entry.when'i bu değere göre yazıyoruz
  /// ki gece yarısı sınırını geçen session başladığı güne sayılsın.
  DateTime? _sessionStartedAt;

  /// Şu ana kadar BİRİKEN saniye (önceki run segment'lerinin toplamı).
  int _accumulatedSec = 0;

  /// Şu anki "çalışıyor" segment'inin başlangıcı; null ise paused.
  DateTime? _runStart;

  // Tek timer — her saniyede hem UI notify hem idle increment.
  Timer? _ticker;
  // Legacy field — _stopTicker mevcut callsite'larda hâlâ null-cancel
  // yapabilsin diye tutuluyor; aktif kullanılmıyor.
  Timer? _idleTimer;

  /// Etkileşimden geçen saniye. idleThreshold'u aşınca pause(byIdle:true).
  int _idleSec = 0;

  /// Bu oturumda idle (hareketsizlik) yüzünden duraklatılmış toplam süre.
  /// resume çağrısında pause süresinin tamamı buraya eklenir; ebeveyn
  /// raporundaki "Pasif Zaman" verisi bunu kullanır.
  int _sessionIdleSec = 0;
  DateTime? _idlePauseStart;

  bool _paused = false;
  bool _pausedByIdle = false;

  bool get isActive => _subject != null;
  bool get isRunning => isActive && !_paused;
  bool get isPaused => _paused;
  bool get isPausedByIdle => _pausedByIdle;

  String? get currentSubject => _subject;
  String? get currentTopic => _topic;
  String? get currentType => _type;

  /// Toplam oturum saniyesi (biriken + aktif segment uzunluğu).
  int get liveSec {
    final running = _runStart != null
        ? DateTime.now().difference(_runStart!).inSeconds
        : 0;
    return _accumulatedSec + running;
  }

  /// Yeni bir oturum başlat. Önceki oturum hâlâ açıksa kapatılıp yazılır.
  Future<void> start({
    required String subject,
    required String topic,
    required String type,
  }) async {
    if (isActive) await end();
    _subject = subject;
    _topic = topic;
    _type = type;
    _accumulatedSec = 0;
    final now = DateTime.now();
    _sessionStartedAt = now;
    _runStart = now;
    _paused = false;
    _pausedByIdle = false;
    _idleSec = 0;
    _sessionIdleSec = 0;
    _idlePauseStart = null;
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
    // İlk checkpoint hemen — crash 30sn içinde olursa bile son durum kayıtlı.
    // ignore: discarded_futures
    _writeCheckpoint();
    notifyListeners();
  }

  /// Aktif oturumu kapat — süre _ActivityStore'a yazılır.
  Future<void> end() async {
    if (!isActive) return;
    final s = _subject!;
    final t = _topic!;
    final ty = _type!;
    final startedAt = _sessionStartedAt;
    final elapsed = liveSec;
    // Hâlâ idle pause'da bitiyorsa, biriken idle süresine son aralığı ekle.
    if (_idlePauseStart != null) {
      _sessionIdleSec +=
          DateTime.now().difference(_idlePauseStart!).inSeconds;
      _idlePauseStart = null;
    }
    final idle = _sessionIdleSec;
    _stopTicker();
    WidgetsBinding.instance.removeObserver(this);
    _subject = null;
    _topic = null;
    _type = null;
    _sessionStartedAt = null;
    _accumulatedSec = 0;
    _runStart = null;
    _paused = false;
    _pausedByIdle = false;
    _idleSec = 0;
    _sessionIdleSec = 0;
    notifyListeners();
    await _ActivityStore.logSession(
      subject: s,
      topic: t,
      type: ty,
      durationSec: elapsed,
      idleSec: idle,
      startedAt: startedAt,
    );
    // Checkpoint'i temizle — session başarıyla yazıldı.
    await _clearCheckpoint();
  }

  /// Süreyi durdur. byIdle=true → kullanıcı hareketsizliği nedeniyle.
  /// Aktif segment uzunluğu birikenlere eklenir; ticker durdurulur.
  void pause({bool byIdle = false}) {
    if (!isActive || _paused) return;
    if (_runStart != null) {
      _accumulatedSec +=
          DateTime.now().difference(_runStart!).inSeconds;
      _runStart = null;
    }
    _paused = true;
    _pausedByIdle = byIdle;
    if (byIdle) {
      _idlePauseStart = DateTime.now();
    }
    _stopTicker();
    notifyListeners();
  }

  /// Süreyi kaldığı yerden başlat. Idle sayacı sıfırlanır.
  void resume() {
    if (!isActive || !_paused) return;
    // Idle'da kalınan süreyi pasif zamana ekle.
    if (_idlePauseStart != null) {
      _sessionIdleSec +=
          DateTime.now().difference(_idlePauseStart!).inSeconds;
      _idlePauseStart = null;
    }
    _runStart = DateTime.now();
    _paused = false;
    _pausedByIdle = false;
    _idleSec = 0;
    _startTicker();
    notifyListeners();
  }

  /// Etkileşim sinyali — herhangi bir tap, scroll, drag bunu çağırır.
  /// • Idle sayacını sıfırlar.
  /// • Eğer idle yüzünden pause olunduysa otomatik resume.
  void notifyInteraction() {
    if (!isActive) return;
    _idleSec = 0;
    if (_pausedByIdle) {
      resume();
    }
  }

  /// Lifecycle observer — uygulama arka plana atıldığında / ekran
  /// kapandığında süreyi durdur; geri dönünce devam ettir.
  /// (Idle yüzünden duraklamış olanları otomatik resume etme; kullanıcı
  /// uyarıyı kapatsın.)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isActive) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (!_paused) pause(byIdle: false);
        break;
      case AppLifecycleState.resumed:
        if (_paused && !_pausedByIdle) resume();
        break;
      case AppLifecycleState.detached:
        // Uygulama öldürülüyor — biriken süreyi disk'e yaz.
        end();
        break;
    }
  }

  // İki ayrı Timer.periodic'i tek tick'e indirdik — her saniyede
  // hem UI bildirimi hem idle sayacı yapılır. Ayrıca her 30sn'de bir
  // checkpoint SharedPreferences'a yazılır (lifecycle detached için).
  void _startTicker() {
    _ticker?.cancel();
    _idleTimer?.cancel();
    _tickCounter = 0;
    _ticker = Timer.periodic(Duration(seconds: 1), (_) {
      _idleSec += 1;
      if (_idleSec >= idleThreshold.inSeconds) {
        pause(byIdle: true);
        return; // pause çağrısı ticker'ı zaten durduracak
      }
      _tickCounter++;
      if (_tickCounter >= _ckptIntervalSec) {
        _tickCounter = 0;
        // Fire-and-forget — UI bloklamasın.
        // ignore: discarded_futures
        _writeCheckpoint();
      }
      notifyListeners();
    });
  }

  /// Devam eden session'ı SharedPreferences'a snapshot et. App kill edilirse
  /// bir sonraki boot'ta `recoverPendingSession` bunu okur ve logSession ile
  /// commit eder. En kötü kayıp: _ckptIntervalSec (30sn).
  Future<void> _writeCheckpoint() async {
    if (!isActive || _sessionStartedAt == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ckptKey, jsonEncode({
        'subject': _subject,
        'topic': _topic,
        'type': _type,
        'startedAt': _sessionStartedAt!.toIso8601String(),
        'durationSec': liveSec,
        'idleSec': _sessionIdleSec,
      }));
    } catch (e) {
      debugPrint('[Tracker] checkpoint fail: $e');
    }
  }

  /// App start'ta çağrılır — önceki crash/kill'den kalan checkpoint varsa
  /// logSession ile commit eder + checkpoint'i temizler.
  static Future<void> recoverPendingSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_ckptKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      await prefs.remove(_ckptKey);
      final subject = m['subject'] as String?;
      final topic = m['topic'] as String?;
      final type = m['type'] as String?;
      final startedAtStr = m['startedAt'] as String?;
      final duration = (m['durationSec'] as num?)?.toInt() ?? 0;
      final idle = (m['idleSec'] as num?)?.toInt() ?? 0;
      if (subject == null || topic == null || type == null || duration < 5) {
        return;
      }
      final startedAt = startedAtStr != null
          ? DateTime.tryParse(startedAtStr)
          : null;
      await _ActivityStore.logSession(
        subject: subject,
        topic: topic,
        type: type,
        durationSec: duration,
        idleSec: idle,
        startedAt: startedAt,
      );
      debugPrint('[Tracker] pending session recovered: $subject/$topic '
          '(${duration}s)');
    } catch (e) {
      debugPrint('[Tracker] recoverPendingSession fail: $e');
    }
  }

  Future<void> _clearCheckpoint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_ckptKey);
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// External data refresh — log yazıldığında dinleyicilere haber ver.
  void _notifyDataChanged() {
    notifyListeners();
  }

  /// Bir dersin BUGÜN için 'özet' ve 'soru' sürelerini saniye cinsinden
  /// döner — log'lanmış entry'lerin toplamı + (aktif session aynı ders/tip
  /// ise) anlık liveSec eklenir. NoteCreatorPage gibi diğer ekranlardan
  /// public erişim için.
  static Future<({int summarySec, int questionSec})> todayTotalsForSubject(
      String subject) async {
    final all = await _ActivityStore.readAll();
    final today = DateTime.now();
    final dk = _ActivityStore.dayKey(today);
    int sum = 0;
    int qst = 0;
    for (final e in all) {
      if (e.subject != subject) continue;
      if (_ActivityStore.dayKey(e.when) != dk) continue;
      if (e.type == 'soru') {
        qst += e.durationSec;
      } else {
        sum += e.durationSec;
      }
    }
    final tr = StudySessionTracker.instance;
    if (tr.isActive && tr.currentSubject == subject) {
      if (tr.currentType == 'soru') {
        qst += tr.liveSec;
      } else {
        sum += tr.liveSec;
      }
    }
    return (summarySec: sum, questionSec: qst);
  }
}

// NOT: Eski `_WeeklyCalendar` + `_DayCell` widget'ları silindi — `StudyCalendarPage`
// kendi gün hücrelerini `_buildDayFrame` üzerinden üretiyor; dead code idi.

// ═══════════════════════════════════════════════════════════════════════════
//  Çalışma Takvimim — haftalık takvim + günlük detay listeleri
// ═══════════════════════════════════════════════════════════════════════════
class StudyCalendarPage extends StatefulWidget {
  const StudyCalendarPage({super.key});
  @override
  State<StudyCalendarPage> createState() => _StudyCalendarPageState();
}

class _StudyCalendarPageState extends State<StudyCalendarPage> {
  Map<String, List<_ActivityEntry>> _grouped = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Yeni session tamamlandığında otomatik tazele — kullanıcı sayfayı
    // pop+push yapmadan değişiklikleri görsün.
    StudySessionTracker.instance.addListener(_onTrackerChanged);
  }

  @override
  void dispose() {
    StudySessionTracker.instance.removeListener(_onTrackerChanged);
    super.dispose();
  }

  bool _wasActive = false;
  void _onTrackerChanged() {
    final isActive = StudySessionTracker.instance.isActive;
    // Active → kapalı geçişi (session sona erdi) → yeniden yükle.
    if (_wasActive && !isActive) {
      _load();
    }
    _wasActive = isActive;
  }

  Future<void> _load() async {
    final g = await _ActivityStore.readWeekGrouped();
    if (!mounted) return;
    setState(() {
      _grouped = g;
      _loading = false;
    });
  }

  // ── Haftalık özet metrikleri ─────────────────────────────────────────────
  /// Mevcut haftaya ait toplam süre, en çok çalışılan ders, günlük ortalama
  /// ve ardışık-gün (streak) sayısı.
  ({int totalSec, String topSubject, int dayAvgSec, int streak})
      _weeklySummary() {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    int totalSec = 0;
    int activeDays = 0;
    final perSubject = <String, int>{};
    final activeDayKeys = <String>{};
    for (var i = 0; i < 7; i++) {
      final d = monday.add(Duration(days: i));
      final dk = _ActivityStore.dayKey(d);
      final entries = _grouped[dk] ?? const [];
      int daySec = 0;
      for (final e in entries) {
        daySec += e.durationSec;
        perSubject[e.subject] =
            (perSubject[e.subject] ?? 0) + e.durationSec;
      }
      if (daySec > 0) {
        totalSec += daySec;
        activeDays++;
        activeDayKeys.add(dk);
      }
    }
    String topSubject = '—';
    int topSec = 0;
    perSubject.forEach((k, v) {
      if (v > topSec) {
        topSec = v;
        topSubject = k;
      }
    });
    final dayAvgSec = activeDays == 0 ? 0 : totalSec ~/ activeDays;
    // Streak — bugünden geriye gidip _ActivityStore'daki tüm günlere bak.
    int streak = 0;
    for (var i = 0; i < 365; i++) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final dk = _ActivityStore.dayKey(d);
      final entries = _grouped[dk] ?? const [];
      final has = entries.any((e) => e.durationSec > 0);
      if (has) {
        streak++;
      } else if (i > 0) {
        // Bugün boş ama dün dolu olabilir → bugünü atla, dünden başla.
        if (i == 0) continue;
        break;
      } else {
        // i==0 ve bugün boş → streak 0
        break;
      }
    }
    return (
      totalSec: totalSec,
      topSubject: topSubject,
      dayAvgSec: dayAvgSec,
      streak: streak,
    );
  }

  String _fmtDur(int sec) {
    if (sec <= 0) return '0 dk';
    if (sec < 60) return '$sec sn';
    if (sec < 3600) return '${sec ~/ 60} dk';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    return m == 0 ? '$h sa' : '$h sa $m dk';
  }

  /// Aktivite olan tamamlanmış geçmiş haftaların pazartesi günleri,
  /// yeniden yeniye sıralı.
  List<DateTime> _completedPastWeekMondays() {
    final mondays = <DateTime>{};
    for (final entries in _grouped.values) {
      for (final e in entries) {
        final w = e.when;
        final m = DateTime(w.year, w.month, w.day)
            .subtract(Duration(days: w.weekday - 1));
        mondays.add(m);
      }
    }
    final now = DateTime.now();
    final thisMonday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return mondays
        .where((m) => m.isBefore(thisMonday))
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  // Aktif dile çevrilen 3 harfli ay adları (Ocak→Oca, Jan, Янв, vb.)
  static List<String> get _monthShort => const [
        'month_jan_short', 'month_feb_short', 'month_mar_short',
        'month_apr_short', 'month_may_short', 'month_jun_short',
        'month_jul_short', 'month_aug_short', 'month_sep_short',
        'month_oct_short', 'month_nov_short', 'month_dec_short',
      ].map((k) => k.tr()).toList(growable: false);

  /// Entry listesinin toplam süresini kısa formatta döndürür ("1.5sa", "45dk").
  /// 0 saniye veya hiç süre yoksa '—' döner. Static — _PastWeekDayCell'den de
  /// kullanılır.
  static String _totalDurationLabel(List<_ActivityEntry> entries) {
    int total = 0;
    for (final e in entries) {
      total += e.durationSec;
    }
    if (total <= 0) return '—';
    if (total < 60) return '${total}sn';
    if (total < 3600) return '${total ~/ 60}dk';
    final h = total / 3600;
    return '${h.toStringAsFixed(h % 1 == 0 ? 0 : 1)}sa';
  }

  String _weekRangeLabel(DateTime monday) {
    final sunday = monday.add(Duration(days: 6));
    if (monday.month == sunday.month) {
      return '${monday.day}-${sunday.day} ${_monthShort[monday.month - 1]}';
    }
    return '${monday.day} ${_monthShort[monday.month - 1]} - '
        '${sunday.day} ${_monthShort[sunday.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final dayNames = [
      localeService.tr('day_mon_full'),
      localeService.tr('day_tue_full'),
      localeService.tr('day_wed_full'),
      localeService.tr('day_thu_full'),
      localeService.tr('day_fri_full'),
      localeService.tr('day_sat_full'),
      localeService.tr('day_sun_full'),
    ];
    final pastMondays = _completedPastWeekMondays();

    final summary = _loading ? null : _weeklySummary();
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Text(
          localeService.tr('my_study_calendar'),
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: [
                Center(
                  child: Text(
                    'Haftalık Performansın'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                SizedBox(height: 12),
                // Haftalık özet metrik kartı — toplam süre, en çok ders,
                // günlük ortalama, streak.
                if (summary != null) _weeklySummaryCard(summary),
                SizedBox(height: 14),
                // Takvim çerçevesi — bu haftanın 7 günü + sağ tarafa tamamlanmış
                // geçmiş haftaların özet sekmeleri (en yeni en başta).
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppPalette.card(context),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: AppPalette.textPrimary(context),
                        width: 1.4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.72,
                    children: [
                      for (var i = 0; i < 7; i++)
                        _buildDayFrame(
                            monday.add(Duration(days: i)), dayNames[i]),
                      for (final m in pastMondays)
                        _buildPastWeekCell(m),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// Haftalık özet kartı — 4 metrik (toplam, ortalama, top ders, streak).
  Widget _weeklySummaryCard(
      ({int totalSec, String topSubject, int dayAvgSec, int streak}) s) {
    Widget metric(String label, String value, IconData icon, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
              ),
              SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textSecondary(context),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        metric('Toplam'.tr(), _fmtDur(s.totalSec),
            Icons.timer_rounded, _indigo),
        SizedBox(width: 8),
        metric('Ortalama/gün'.tr(), _fmtDur(s.dayAvgSec),
            Icons.show_chart_rounded, _blue),
        SizedBox(width: 8),
        metric('Streak'.tr(), '${s.streak} ${'gün'.tr()}',
            Icons.local_fire_department_rounded, _orange),
        SizedBox(width: 8),
        metric(
            'En çok'.tr(),
            s.topSubject.length > 8
                ? '${s.topSubject.substring(0, 8)}…'
                : s.topSubject,
            Icons.workspace_premium_rounded,
            Color(0xFFA855F7)),
      ],
    );
  }

  Widget _buildPastWeekCell(DateTime monday) {
    final label = _weekRangeLabel(monday);
    int total = 0;
    for (var i = 0; i < 7; i++) {
      final d = monday.add(Duration(days: i));
      total += (_grouped[_ActivityStore.dayKey(d)] ?? const []).length;
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PastWeekPage(
            monday: monday,
            entriesByDay: _grouped,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _indigo.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _indigo.withValues(alpha: 0.55),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _indigo.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Geçen Hafta'.tr(),
                      maxLines: 1,
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _indigo.withValues(alpha: 0.85),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: _indigo,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 22,
                        color: _indigo,
                      ),
                      SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          total > 0
                              ? '$total ${'aktivite'.tr()}'
                              : '—',
                          maxLines: 1,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textSecondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Aç'.tr(),
                      maxLines: 1,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: _indigo,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: _indigo,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayFrame(DateTime day, String dayName) {
    final entries = _grouped[_ActivityStore.dayKey(day)] ?? const [];
    final dateText =
        '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final isToday = day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _DayDetailPage(
            day: day,
            dayName: dayName,
            entries: entries,
          ),
        ),
      ),
      child: _buildDayFrameInner(
        day, dayName, dateText, entries, isToday),
    );
  }

  Widget _buildDayFrameInner(DateTime day, String dayName,
      String dateText, List<_ActivityEntry> entries, bool isToday) {
    // Son aktivite saati; yoksa "—" (bugün boş ise "şu an saati" göstermek
    // yanıltıcı — sanki yeni bir aktivite olmuş gibi).
    String timeText;
    if (entries.isNotEmpty) {
      final last = entries.first.when;
      timeText =
          '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}';
    } else {
      timeText = '—';
    }

    return Container(
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isToday
              ? _indigo
              : Color(0xFFE5E7EB),
          width: isToday ? 1.6 : 1.0,
        ),
        boxShadow: isToday
            ? [
                BoxShadow(
                  color: _indigo.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık bandı: gün, saat, tarih
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _indigo.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
                SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 10, color: Colors.black),
                      SizedBox(width: 3),
                      Text(
                        timeText,
                        maxLines: 1,
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.calendar_today_rounded,
                          size: 9, color: Colors.black),
                      SizedBox(width: 3),
                      Text(
                        dateText,
                        maxLines: 1,
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Aktivite listesi (kompakt)
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        localeService.tr('no_activity_today'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                    child: ListView(
                      physics: BouncingScrollPhysics(),
                      padding: EdgeInsets.zero,
                      children: entries
                          .map((e) => _compactActivityRow(e))
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _compactActivityRow(_ActivityEntry e) {
    final isQ = e.type == 'soru';
    final accent = isQ ? _orange : _blue;
    final dur = e.durationSec;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isQ ? Icons.quiz_rounded : Icons.menu_book_rounded,
            size: 10,
            color: accent,
          ),
          SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(context),
                    height: 1.15,
                  ),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        e.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 8.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    if (dur > 0) ...[
                      SizedBox(width: 4),
                      Text('·',
                          style: GoogleFonts.poppins(
                              fontSize: 8.5,
                              color: Colors.grey.shade400)),
                      SizedBox(width: 4),
                      Text(
                        _shortDur(dur),
                        style: GoogleFonts.poppins(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Kompakt süre formatı — "45sn" / "12dk" / "1.5sa".
  static String _shortDur(int sec) {
    if (sec < 60) return '${sec}sn';
    if (sec < 3600) return '${sec ~/ 60}dk';
    final h = sec / 3600;
    return '${h.toStringAsFixed(h % 1 == 0 ? 0 : 1)}sa';
  }

}

// ═════════════════════════════════════════════════════════════════════════════
//  _PastWeekPage — tamamlanmış geçmiş bir haftanın 7 günlük detay sayfası.
//  Pazartesi..Pazar grid'i; her gün hücresine basınca o günün aktivite
//  listesi (_DayDetailPage) açılır.
// ═════════════════════════════════════════════════════════════════════════════
class _PastWeekPage extends StatelessWidget {
  final DateTime monday;
  final Map<String, List<_ActivityEntry>> entriesByDay;
  const _PastWeekPage({
    required this.monday,
    required this.entriesByDay,
  });

  // Aktif dile çevrilen 3 harfli ay adları (Ocak→Oca, Jan, Янв, vb.)
  static List<String> get _monthShort => const [
        'month_jan_short', 'month_feb_short', 'month_mar_short',
        'month_apr_short', 'month_may_short', 'month_jun_short',
        'month_jul_short', 'month_aug_short', 'month_sep_short',
        'month_oct_short', 'month_nov_short', 'month_dec_short',
      ].map((k) => k.tr()).toList(growable: false);

  String _weekRangeLabel() {
    final sunday = monday.add(Duration(days: 6));
    if (monday.month == sunday.month) {
      return '${monday.day}-${sunday.day} ${_monthShort[monday.month - 1]}';
    }
    return '${monday.day} ${_monthShort[monday.month - 1]} - '
        '${sunday.day} ${_monthShort[sunday.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final dayNames = [
      localeService.tr('day_mon_full'),
      localeService.tr('day_tue_full'),
      localeService.tr('day_wed_full'),
      localeService.tr('day_thu_full'),
      localeService.tr('day_fri_full'),
      localeService.tr('day_sat_full'),
      localeService.tr('day_sun_full'),
    ];
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Text(
          _weekRangeLabel(),
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
            color: AppPalette.card(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppPalette.textPrimary(context), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
              children: [
                for (var i = 0; i < 7; i++)
                  _PastWeekDayCell(
                    day: monday.add(Duration(days: i)),
                    dayName: dayNames[i],
                    entries: entriesByDay[
                            _ActivityStore.dayKey(monday.add(Duration(days: i)))] ??
                        const [],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PastWeekDayCell extends StatelessWidget {
  final DateTime day;
  final String dayName;
  final List<_ActivityEntry> entries;
  const _PastWeekDayCell({
    required this.day,
    required this.dayName,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final dateText =
        '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _DayDetailPage(
            day: day,
            dayName: dayName,
            entries: entries,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppPalette.border(context),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _indigo.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                  SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 9, color: Colors.black),
                        SizedBox(width: 3),
                        Text(
                          dateText,
                          maxLines: 1,
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entries.isEmpty
                            ? Icons.remove_circle_outline_rounded
                            : Icons.check_circle_rounded,
                        size: 22,
                        color: entries.isEmpty
                            ? Colors.black26
                            : Color(0xFF10B981),
                      ),
                      SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          entries.isEmpty
                              ? '—'
                              : '${entries.length} ${'aktivite'.tr()}',
                          maxLines: 1,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textSecondary(context),
                          ),
                        ),
                      ),
                      // Günlük toplam süre — "0sn" gibi yararsızsa gizle.
                      if (entries.isNotEmpty) ...[
                        SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _StudyCalendarPageState._totalDurationLabel(entries),
                            maxLines: 1,
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: _indigo,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  _DayDetailPage — bir güne tıklandığında açılan tam sayfa.
//  Sağ üstte renkli "Renk Seç" pill; başlık çerçevesi + dersler çerçevesi
//  ayrı ayrı renklendirilebilir. Renkler kalıcı (SharedPreferences).
// ═════════════════════════════════════════════════════════════════════════════
class _DayDetailPage extends StatefulWidget {
  final DateTime day;
  final String dayName;
  final List<_ActivityEntry> entries;
  const _DayDetailPage({
    required this.day,
    required this.dayName,
    required this.entries,
  });

  @override
  State<_DayDetailPage> createState() => _DayDetailPageState();
}

class _DayDetailPageState extends State<_DayDetailPage> {
  bool _showColorPicker = false;
  String _colorTarget = 'header'; // 'header' | 'subjects' | 'topics' | 'bg'
  Color? _headerBg;
  Color? _subjectsBg;
  // Konu kartlarının (entry kartlarının) iç arka plan rengi.
  // Renk seç → "Konular" hedefiyle tüm konu kartları aynı renge boyanır.
  Color? _topicCardBg;
  Color? _pageBg;

  /// Süre paneli için anlık entry listesi — initial widget.entries'den
  /// başlar, tracker tetiklendikçe (yeni session yazıldığında) yenilenir.
  late List<_ActivityEntry> _liveEntries;

  /// Konu kartında "Çalışma Süresi" badge'i için BU GÜN'e özel toplam
  /// süreler. Eski sürümde haftalık toplam tutuluyordu — kullanıcı gün
  /// detay sayfasında haftalık metrik görüyordu, yanıltıcıydı.
  /// Anahtar: "subject|topic"  →  o günkü saniye toplamı.
  Map<String, int> _topicDayTotal = const {};

  /// O günkü tüm aktivitelerin toplamı (özet + soru). Header altındaki
  /// "Bugün toplam" özet satırı için.
  int _dayTotalSec = 0;
  int _daySummarySec = 0;
  int _dayQuestionSec = 0;

  String _topicKey(String subject, String topic) => '$subject|$topic';

  static const _palette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  String get _dayKey =>
      '${widget.day.year}-${widget.day.month.toString().padLeft(2, '0')}-${widget.day.day.toString().padLeft(2, '0')}';
  String get _headerKey => 'day_header_color_$_dayKey';
  String get _subjectsKey => 'day_subjects_color_$_dayKey';
  String get _topicCardKey => 'day_topic_card_color_$_dayKey';
  String get _pageKey => 'day_page_color_$_dayKey';

  @override
  void initState() {
    super.initState();
    _liveEntries = List.of(widget.entries);
    _loadColors();
    _loadDayStats();
    StudySessionTracker.instance.addListener(_onTrackerTick);
  }

  /// Sadece görüntülenen GÜN için (subject, topic) toplamlarını hesaplar.
  /// Aynı konuya birden fazla session açıldıysa süreler toplanır.
  /// Ayrıca header altı "Bugün toplam" özet satırı için günlük totalleri
  /// (toplam / özet / soru) tutar.
  Future<void> _loadDayStats() async {
    final all = await _ActivityStore.readAll();
    final dk = _ActivityStore.dayKey(widget.day);
    final total = <String, int>{};
    int day = 0;
    int summary = 0;
    int question = 0;
    for (final e in all) {
      if (e.durationSec <= 0) continue;
      if (_ActivityStore.dayKey(e.when) != dk) continue;
      final key = _topicKey(e.subject, e.topic);
      total[key] = (total[key] ?? 0) + e.durationSec;
      day += e.durationSec;
      if (e.type == 'soru') {
        question += e.durationSec;
      } else {
        summary += e.durationSec;
      }
    }
    if (!mounted) return;
    setState(() {
      _topicDayTotal = total;
      _dayTotalSec = day;
      _daySummarySec = summary;
      _dayQuestionSec = question;
    });
  }

  @override
  void dispose() {
    StudySessionTracker.instance.removeListener(_onTrackerTick);
    super.dispose();
  }

  bool _wasActive = false;
  void _onTrackerTick() {
    if (!mounted) return;
    final tr = StudySessionTracker.instance;
    final isActive = tr.isActive;
    // Aktif → kapalı geçişi (session sona erdi) → entries'i yeniden yükle.
    // Bu setState yapılmadan refreshEntries setState ile zaten rebuild eder.
    if (_wasActive && !isActive) {
      _wasActive = isActive;
      _refreshEntries();
      return;
    }
    _wasActive = isActive;
    // Saniyelik tick → rebuild yalnızca aktif session bu sayfanın gününe ve
    // bir konusuna denk geliyorsa anlamlı (liveSec değişimi orada görünür).
    // Aksi halde tüm ağacı her saniye yeniden çizmek ısrarsız battery drain.
    if (!isActive) return;
    final dk = _ActivityStore.dayKey(widget.day);
    final today = _ActivityStore.dayKey(DateTime.now());
    if (dk != today) return;
    // Listede aktif konunun karşılığı yoksa rebuild faydasız.
    final subj = tr.currentSubject;
    final topic = tr.currentTopic;
    final hasMatching = _liveEntries.any(
        (e) => e.subject == subj && e.topic == topic);
    if (!hasMatching) return;
    setState(() {});
  }

  Future<void> _refreshEntries() async {
    final all = await _ActivityStore.readAll();
    final dk = _ActivityStore.dayKey(widget.day);
    final filtered =
        all.where((e) => _ActivityStore.dayKey(e.when) == dk).toList()
          ..sort((a, b) => b.when.compareTo(a.when));
    if (!mounted) return;
    setState(() => _liveEntries = filtered);
    // Gün istatistiklerini de tazele — yeni session tamamlanınca konu
    // kartı badge'i ve header'daki "Bugün toplam" anında güncellenir.
    await _loadDayStats();
  }

  Future<void> _loadColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final h = prefs.getInt(_headerKey);
      final s = prefs.getInt(_subjectsKey);
      final t = prefs.getInt(_topicCardKey);
      final p = prefs.getInt(_pageKey);
      if (!mounted) return;
      setState(() {
        if (h != null) _headerBg = Color(h);
        if (s != null) _subjectsBg = Color(s);
        if (t != null) _topicCardBg = Color(t);
        if (p != null) _pageBg = Color(p);
      });
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  Future<void> _saveColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Future<void> set(String k, Color? c) async {
        if (c == null) {
          await prefs.remove(k);
        } else {
          await prefs.setInt(k, c.toARGB32());
        }
      }

      await set(_headerKey, _headerBg);
      await set(_subjectsKey, _subjectsBg);
      await set(_topicCardKey, _topicCardBg);
      await set(_pageKey, _pageBg);
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  void _applyColor(Color c) {
    setState(() {
      switch (_colorTarget) {
        case 'header':
          _headerBg = c;
          break;
        case 'subjects':
          _subjectsBg = c;
          break;
        case 'topics':
          _topicCardBg = c;
          break;
        case 'bg':
          _pageBg = c;
          break;
      }
    });
    _saveColors();
  }

  void _applyToHeader(Color c) {
    setState(() => _headerBg = c);
    _saveColors();
  }

  void _applyToSubjects(Color c) {
    setState(() => _subjectsBg = c);
    _saveColors();
  }

  void _applyToTopicCard(Color c) {
    setState(() => _topicCardBg = c);
    _saveColors();
  }

  bool _isDark(Color c) {
    final l = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
    return l < 0.55;
  }

  @override
  Widget build(BuildContext context) {
    final dateText = '${widget.day.day.toString().padLeft(2, '0')}'
        '.${widget.day.month.toString().padLeft(2, '0')}'
        '.${widget.day.year}';
    final pageBg = AppPalette.resolvePageBg(context, _pageBg);
    final headerBg = AppPalette.resolveCardBg(context, _headerBg);
    final subjectsBg = AppPalette.resolveInnerBg(context, _subjectsBg);
    final headerInk =
        _isDark(headerBg) ? Colors.white : Colors.black;
    final headerInkMute = _isDark(headerBg)
        ? Colors.white70
        : Colors.black54;
    final subjInk =
        _isDark(subjectsBg) ? Colors.white : Colors.black;
    final subjInkMute = _isDark(subjectsBg)
        ? Colors.white70
        : Colors.black54;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Text(
          widget.dayName,
          style: GoogleFonts.poppins(
              fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
                vertical: 8, horizontal: 12),
            child: GestureDetector(
              onTap: () => setState(
                  () => _showColorPicker = !_showColorPicker),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFF6A00),
                      Color(0xFFDB2777),
                      Color(0xFF7C3AED),
                      Color(0xFF2563EB),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showColorPicker
                          ? Icons.close_rounded
                          : Icons.palette_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      _showColorPicker
                          ? 'Kapat'.tr()
                          : 'Renk Seç'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showColorPicker) _buildColorPanel(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // Başlık çerçevesi — gün + tarih
                DragTarget<Color>(
                  onAcceptWithDetails: (d) =>
                      _applyToHeader(d.data),
                  builder: (ctx, cand, _) {
                    final hovering = cand.isNotEmpty;
                    return AnimatedContainer(
                      duration: Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: headerBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: hovering
                              ? Color(0xFFFF6A00)
                              : _indigo.withValues(alpha: 0.35),
                          width: hovering ? 2 : 1.4,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              widget.dayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: headerInk,
                                height: 1.1,
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Icon(Icons.calendar_today_rounded,
                              size: 14, color: headerInkMute),
                          SizedBox(width: 6),
                          Text(
                            dateText,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: headerInkMute,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                SizedBox(height: 10),
                // Günlük toplam özet — header'ın altında 3 metrik:
                //   ⏱ toplam · 📖 özet · 📝 soru
                if (_dayTotalSec > 0) _dayTotalsRow(headerInk, headerInkMute),
                SizedBox(height: 14),
                // "Çalışılan Dersler" başlığı — çerçevenin ÜSTÜNDE,
                // sayfa genişliğince ortalanmış olarak konumlanır.
                Center(
                  child: Text(
                    'Çalışılan Dersler'.tr(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: subjInk,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Çalışılan dersler çerçevesi
                DragTarget<Color>(
                  onAcceptWithDetails: (d) =>
                      _applyToSubjects(d.data),
                  builder: (ctx, cand, _) {
                    final hovering = cand.isNotEmpty;
                    return AnimatedContainer(
                      duration: Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: subjectsBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: hovering
                              ? Color(0xFFFF6A00)
                              : Colors.black.withValues(alpha: 0.12),
                          width: hovering ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          if (_liveEntries.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.all(12),
                              child: Center(
                                child: Text(
                                  localeService
                                      .tr('no_activity_today'),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: subjInkMute,
                                  ),
                                ),
                              ),
                            )
                          else
                            for (final group in _groupedBySubject())
                              _subjectCard(group, subjInk, subjInkMute),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Günlük toplam özet — header altında küçük 3 metrik (toplam, özet, soru).
  /// 0 ise satır gizli (build içinde koşul var).
  Widget _dayTotalsRow(Color ink, Color inkMute) {
    Widget chip(IconData icon, String label, int sec, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              SizedBox(width: 6),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      _entryDurationText(sec),
                      maxLines: 1,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: ink,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(Icons.timer_rounded, 'Toplam'.tr(), _dayTotalSec, _indigo),
        SizedBox(width: 8),
        chip(Icons.menu_book_rounded, 'Özet'.tr(), _daySummarySec, _blue),
        SizedBox(width: 8),
        chip(Icons.quiz_rounded, 'Soru'.tr(), _dayQuestionSec, _orange),
      ],
    );
  }

  /// Bir entry'nin durationSec değerini "12 dk" / "45sn" / "—" olarak formatlar.
  String _entryDurationText(int sec) {
    if (sec <= 0) return '—';
    final m = sec ~/ 60;
    final s = sec % 60;
    if (m == 0) return '${s}sn';
    if (m < 60) return s == 0 ? '$m dk' : '$m dk $s sn';
    final h = m ~/ 60;
    final mm = m % 60;
    return mm == 0 ? '$h sa' : '$h sa $mm dk';
  }

  /// (subject, topic, type) → o kombinasyon için kaç oturum log'landı.
  /// _groupedBySubject hesaplaması sırasında doldurulur; _entryRow rozet
  /// olarak gösterir ("3 oturum" gibi).
  final Map<String, int> _sessionCountByDedupKey = {};

  String _dedupKey(String subject, String topic, String type) =>
      '$subject|$topic|$type';

  /// Entries'i ders bazında gruplar — sıra: en son aktiviteye göre.
  /// Aynı (subject, topic, type) kombinasyonu için tek temsilci tutulur
  /// ama session sayısı `_sessionCountByDedupKey` haritasında biriktirilir
  /// — _entryRow "× N" rozetiyle aynı konuya kaç oturum çalışıldığını
  /// gösterir. Önceden tekrarlar UI'da görünmeden yutuluyordu.
  List<({String subject, List<_ActivityEntry> entries})> _groupedBySubject() {
    _sessionCountByDedupKey.clear();
    final subjectOrder = <String>[];
    final unique = <String, _ActivityEntry>{};
    final perSubjectKeys = <String, List<String>>{};
    for (final e in _liveEntries) {
      final dk = _dedupKey(e.subject, e.topic, e.type);
      _sessionCountByDedupKey[dk] =
          (_sessionCountByDedupKey[dk] ?? 0) + 1;
      final existing = unique[dk];
      if (existing == null) {
        unique[dk] = e;
        if (!perSubjectKeys.containsKey(e.subject)) {
          perSubjectKeys[e.subject] = [];
          subjectOrder.add(e.subject);
        }
        perSubjectKeys[e.subject]!.add(dk);
      } else if (e.when.isAfter(existing.when)) {
        unique[dk] = e;
      }
    }
    return subjectOrder
        .map((s) => (
              subject: s,
              entries: perSubjectKeys[s]!.map((k) => unique[k]!).toList(),
            ))
        .toList();
  }

  Widget _subjectCard(
    ({String subject, List<_ActivityEntry> entries}) g,
    Color ink,
    Color inkMute,
  ) {
    // Ders bloğu artık dış çerçevesiz — sadece üstte ders adı, altında o
    // derse ait konu kartları (her biri kendi çerçevesinde) alt alta dizilir.
    // _groupedBySubject() zaten aynı dersi tek kayıt altında topluyor; bu
    // yüzden ders adı listede yalnızca bir kez görünür.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ders adı — sade başlık, çerçeve yok.
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
            child: Text(
              g.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ink,
                letterSpacing: 0.1,
              ),
            ),
          ),
          // Konu kartları — kendi çerçevelerinde, alt alta.
          for (final e in g.entries) _entryRow(e, ink, inkMute),
        ],
      ),
    );
  }

  Widget _entryRow(_ActivityEntry e, Color ink, Color inkMute) {
    final isQ = e.type == 'soru';
    final accent = isQ ? _orange : _blue;
    // Bu konunun BU GÜNKÜ toplam çalışma süresi (saniye). Aynı topiğin
    // birden fazla session'ı varsa tümü toplanır; yoksa entry'nin kendi
    // durationSec değerine düşülür (eski kayıtlarla uyum).
    final dayTotalSec =
        _topicDayTotal[_topicKey(e.subject, e.topic)] ?? e.durationSec;
    // Konu kartı arka plan + metin rengi — kullanıcı renk seçici "Konular"
    // hedefiyle özel renk verdiyse onu, yoksa varsayılan accent tonunu
    // kullan. Koyu zeminde metin beyaza çevrilir.
    final cardBg = _topicCardBg ?? accent.withValues(alpha: 0.06);
    final cardInk = _topicCardBg != null
        ? (_isDark(_topicCardBg!) ? Colors.white : Colors.black87)
        : ink;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      // Renk paletinden bir rengin sürüklenip kart üzerine bırakılması
      // ile hedef = "Konular" olmasa bile direkt boyama yapılabilir.
      child: DragTarget<Color>(
        onAcceptWithDetails: (d) => _applyToTopicCard(d.data),
        builder: (ctx, cand, _) => GestureDetector(
        onTap: () => _openActivityEntry(e),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: cand.isNotEmpty
                  ? Color(0xFFFF6A00)
                  : accent.withValues(alpha: 0.35),
              width: cand.isNotEmpty ? 2 : 1,
            ),
          ),
          // 2 yatay satır:
          //   1) Konu adı  ←→  Çalışma Süresi (etiket + süre)
          //   2) Konu Özeti rozeti  ←→  Çalış + ›
          // Her satırda sol-sağ çift aynı yatay hizada (Row crossAxisAlignment).
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 1. SATIR: konu adı (+ session count rozeti) | Çalışma Süresi
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            e.topic,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: cardInk,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if ((_sessionCountByDedupKey[
                                    _dedupKey(e.subject, e.topic, e.type)] ??
                                1) >
                            1) ...[
                          SizedBox(width: 6),
                          // Aynı konuya N oturum çalışıldı rozeti.
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.14),
                                borderRadius:
                                    BorderRadius.circular(999),
                              ),
                              child: Text(
                                '× ${_sessionCountByDedupKey[_dedupKey(e.subject, e.topic, e.type)]}',
                                style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: accent,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  // Çalışma Süresi etiketi → konu adıyla aynı hizada.
                  // Süre değeri ise hemen altında, sağa hizalı.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 11, color: accent),
                          SizedBox(width: 4),
                          Text(
                            'Çalışma Süresi'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accent,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2),
                      Text(
                        _entryDurationText(dayTotalSec),
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: accent,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 10),
              // ── 2. SATIR: Konu Özeti rozeti | Çalış + › ───────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      isQ ? 'Sınav Soruları'.tr() : 'Konu Özeti'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Spacer(),
                  Text(
                    'Çalış'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(Icons.chevron_right_rounded,
                      size: 22, color: accent),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  // Aktivite kartına basılınca — özet veya teste DOĞRUDAN yönlendir.
  // 'özet' → _SummaryDetailPage, 'soru' → son test denemesi
  // (tamamlandıysa TestResultPage, değilse TestPage).
  Future<void> _openActivityEntry(_ActivityEntry e) async {
    final isQ = e.type == 'soru';
    final key =
        isQ ? 'library_subjects_questions_v2' : 'library_subjects_v2';
    try {
      final prefs = await SharedPreferences.getInstance();
      final listRaw = prefs.getStringList(key) ?? const [];
      final subjects = listRaw
          .map((s) {
            try {
              return _Subject.fromJson(
                  jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<_Subject>()
          .toList();

      // Ders eşleştir — önce birebir eşleşme, sonra case-insensitive
      _Subject? subject;
      for (final s in subjects) {
        if (s.name == e.subject) {
          subject = s;
          break;
        }
      }
      if (subject == null) {
        final target = e.subject.toLowerCase();
        for (final s in subjects) {
          if (s.name.toLowerCase() == target) {
            subject = s;
            break;
          }
        }
      }

      // Konu (özet) eşleştir
      _Summary? summary;
      if (subject != null) {
        for (final sum in subject.summaries) {
          if (sum.topic == e.topic) {
            summary = sum;
            break;
          }
        }
        if (summary == null) {
          final target = e.topic.toLowerCase();
          for (final sum in subject.summaries) {
            if (sum.topic.toLowerCase() == target) {
              summary = sum;
              break;
            }
          }
        }
      }

      if (!mounted) return;

      // Kayıt bulunamadıysa kütüphaneye fallback, kullanıcı kendi bulsun.
      if (subject == null || summary == null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AcademicPlanner(
            mode: isQ ? LibraryMode.questions : LibraryMode.summary,
          ),
        ));
        return;
      }

      if (isQ) {
        // En son oluşturulmuş test denemesi
        if (summary.tests.isEmpty) {
          // Hiç test denemesi yoksa kütüphaneye düş
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                AcademicPlanner(mode: LibraryMode.questions),
          ));
          return;
        }
        final attempt = summary.tests.last;
        if (attempt.completed) {
          final questions = parseTestQuestions(attempt.content);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TestResultPage(
              questions: questions,
              answers: attempt.answers,
              subjectName: subject!.name,
              topic: summary!.topic,
            ),
          ));
        } else {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TestPage(
              rawContent: attempt.content,
              subjectName: subject!.name,
              topic: summary!.topic,
              initialAnswers: attempt.answers,
              timeLimit: attempt.timeLimit,
              onFinish: (answers) async {
                attempt.answers = Map<int, String?>.from(answers);
                attempt.completed = true;
                // Değişiklikleri diske yaz
                try {
                  final prefs2 =
                      await SharedPreferences.getInstance();
                  final updated = subjects
                      .map((s) => jsonEncode(s.toJson()))
                      .toList();
                  await prefs2.setStringList(key, updated);
                } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
              },
            ),
          ));
        }
      } else {
        // Konu özeti — detay sayfası
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _SummaryDetailPage(
            summary: summary!,
            subjectName: subject!.name,
          ),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AcademicPlanner(
          mode: isQ ? LibraryMode.questions : LibraryMode.summary,
        ),
      ));
    }
  }

  Widget _buildColorPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.textPrimary(context), width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded,
                  size: 16, color: Colors.black),
              SizedBox(width: 6),
              Text('Renk'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
              Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _headerBg = null;
                    _subjectsBg = null;
                    _topicCardBg = null;
                    _pageBg = null;
                  });
                  _saveColors();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppPalette.cardMuted(context),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text('Sıfırla'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.black54)),
                ),
              ),
            ],
          ),
          // Hedef chip'leri — Başlık / Dersler / Arka plan. Açıklama yazısı
          // ve renk paleti "Başlık" çerçevesinin sol kenarıyla aynı hizadan
          // başlasın diye tam genişlikte ayrı satırda.
          SizedBox(height: 8),
          _targetToggle(),
          SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin çerçeveye bırak.'
                .tr(),
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
                height: 1.3),
          ),
          SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _palette.length,
              itemBuilder: (_, i) =>
                  _draggableColor(_palette[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetToggle() {
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = id),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? _orange.withValues(alpha: 0.12)
                  : Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _orange : Colors.black12,
                width: active ? 1.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: active ? _orange : Colors.black),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('header', 'Başlık'.tr()),
        SizedBox(width: 6),
        chip('subjects', 'Dersler'.tr()),
        SizedBox(width: 6),
        chip('topics', 'Konular'.tr()),
        SizedBox(width: 6),
        chip('bg', 'Arka plan'.tr()),
      ],
    );
  }

  Widget _draggableColor(Color c) {
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _dot(c)),
      child: GestureDetector(
        onTap: () => _applyColor(c),
        child: _dot(c),
      ),
    );
  }

  Widget _dot(Color c) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border(context), width: 1),
      ),
    );
  }
}

// (_DayCell silindi — _WeeklyCalendar ile birlikte dead code'du.)

// ═══════════════════════════════════════════════════════════════════════════════
//  LibraryLanding — Kütüphanem karşılama ekranı
//  • Ortalanmış "Kütüphanem" başlığı + ikon
//  • Altında 2 eşit beyaz çerçeve: Konu Özeti / Sınav Soruları
// ═══════════════════════════════════════════════════════════════════════════════
class LibraryLanding extends StatefulWidget {
  const LibraryLanding({super.key});

  @override
  State<LibraryLanding> createState() => _LibraryLandingState();
}

class _LibraryLandingState extends State<LibraryLanding> {
  // ── Renk özelleştirme — diğer sayfalardakiyle aynı format ─────────────
  bool _showColorPicker = false;
  String _colorMode = 'frame'; // 'frame' | 'text'
  // Aktif renk hedefi: 'bg' veya kartın slug'ı (summary/questions/...).
  // Her kart için ayrı renk — paletten basıldığında SADECE o kart boyanır.
  String _colorTarget = 'bg';
  Color? _pageBgOverride;
  // Kart bazında arka plan rengi — slug → color.
  final Map<String, Color> _cardBgs = {};
  // Kart bazında metin rengi — slug → color.
  final Map<String, Color> _cardInks = {};

  // Tüm kart slug'ları — Renk Seç panelindeki hedef seçici bu listeyi
  // kullanır; her birine ayrı renk verilebilir.
  static const _cardSlugs = <String, String>{
    'summary': 'Konu Özeti',
    'questions': 'Sınav Soruları',
    'history': 'Çözümlerim',
    'contest': 'Bilgi Yarışı',
    'calendar': 'Çalışma Takvimi',
    'league': 'Dünya Sıralaması',
  };

  static const _libraryColorsKey = 'library_colors_v1';
  static const _libraryPalette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  @override
  void initState() {
    super.initState();
    _loadLibraryColors();
  }

  Future<void> _loadLibraryColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_libraryColorsKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        Color? read(String k) {
          final v = m[k];
          return v is num ? Color(v.toInt()) : null;
        }
        _pageBgOverride = read('bg');
        // Her kartın kendi rengi — eski "cards" tek-renk verisi varsa
        // tüm kartlara fallback olarak yedirilir (geriye uyum).
        final legacyBg = read('cards');
        final legacyInk = read('cardsText');
        _cardBgs.clear();
        _cardInks.clear();
        for (final slug in _cardSlugs.keys) {
          final bg = read('bg_$slug') ?? legacyBg;
          if (bg != null) _cardBgs[slug] = bg;
          final ink = read('ink_$slug') ?? legacyInk;
          if (ink != null) _cardInks[slug] = ink;
        }
      });
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  Future<void> _saveLibraryColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = <String, int>{};
      void put(String k, Color? c) {
        if (c != null) m[k] = c.toARGB32();
      }
      put('bg', _pageBgOverride);
      _cardBgs.forEach((slug, c) => put('bg_$slug', c));
      _cardInks.forEach((slug, c) => put('ink_$slug', c));
      if (m.isEmpty) {
        await prefs.remove(_libraryColorsKey);
      } else {
        await prefs.setString(_libraryColorsKey, jsonEncode(m));
      }
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  /// target = 'bg' → sayfa arka planı; aksi halde kart slug'ı.
  /// _colorMode = 'text' iken aynı slug için metin (ink) rengi atanır.
  void _applyLibraryColor(String target, Color c) {
    setState(() {
      if (target == 'bg') {
        // Sayfa arka planı — text modu ile çalışmaz, hep bg uygular.
        _pageBgOverride = c;
      } else {
        if (_colorMode == 'text') {
          _cardInks[target] = c;
        } else {
          _cardBgs[target] = c;
        }
      }
    });
    _saveLibraryColors();
  }

  void _resetLibraryColors() {
    setState(() {
      _pageBgOverride = null;
      _cardBgs.clear();
      _cardInks.clear();
    });
    _saveLibraryColors();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.resolvePageBg(context, _pageBgOverride),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        centerTitle: false,
        titleSpacing: 8,
        automaticallyImplyLeading: false,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_library_rounded,
                color: _blue, size: 22),
            SizedBox(width: 8),
            Text(
              localeService.tr('my_library'),
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          // Aile/Ebeveyn butonu Profil sayfasına taşındı (Davet kartının
          // hemen altında).
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(
              child: GestureDetector(
                onTap: () => setState(
                    () => _showColorPicker = !_showColorPicker),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFF6A00),
                        Color(0xFFDB2777),
                        Color(0xFF7C3AED),
                        Color(0xFF2563EB),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showColorPicker
                            ? Icons.close_rounded
                            : Icons.palette_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        _showColorPicker
                            ? localeService.tr('close')
                            : 'Renk Seç',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showColorPicker) _buildLibraryColorPanel(),
            if (_showColorPicker) SizedBox(height: 10),
            // ── 1. satır: Konu Özeti (sol) | Sınav Soruları (sağ) ────
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.auto_stories_rounded,
                    title: localeService.tr('create_topic_summary'),
                    color: _blue,
                    customBg: _cardBgs['summary'],
                    customTextColor: _cardInks['summary'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('summary', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AcademicPlanner(
                            mode: LibraryMode.summary),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _LandingCard(
                    icon: Icons.quiz_rounded,
                    title: localeService.tr('create_exam_questions'),
                    color: _orange,
                    customBg: _cardBgs['questions'],
                    customTextColor: _cardInks['questions'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('questions', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AcademicPlanner(
                            mode: LibraryMode.questions),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            // ── 2. satır: Çözümlerim (sol) | Bilgi Yarışı (sağ) ──────
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.check_circle_rounded,
                    title: 'Çözümlerim'.tr(),
                    color: Color(0xFF3B82F6),
                    customBg: _cardBgs['history'],
                    customTextColor: _cardInks['history'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('history', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HistoryScreen(),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _LandingCard(
                    icon: Icons.emoji_events_rounded,
                    title: 'Bilgi Yarışı'.tr(),
                    color: Color(0xFFFFB800),
                    customBg: _cardBgs['contest'],
                    customTextColor: _cardInks['contest'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('contest', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DueloLobbyScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            // ── 3. satır: Çalışma Takvimim (sol) | Bilgi Ligi (sağ) ──
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.calendar_month_rounded,
                    title: localeService.tr('my_study_calendar'),
                    color: _indigo,
                    customBg: _cardBgs['calendar'],
                    customTextColor: _cardInks['calendar'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('calendar', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StudyCalendarPage(),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _LandingCard(
                    icon: Icons.leaderboard_rounded,
                    title: 'Dünya Sıralaması'.tr(),
                    color: Color(0xFF7C3AED),
                    customBg: _cardBgs['league'],
                    customTextColor: _cardInks['league'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('league', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BilgiLigiScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            // ── 4. satır: Pomodoro (sol) | boş yer (sağ) ─────────────
            // Tek kart ama diğer satırlardaki kartlarla aynı genişlikte
            // olsun diye Row + Expanded(SizedBox) ile sağ yarı rezerve.
            // Tıklanınca Yeşil Koloni + Mars Protokolü seçim sayfası açılır.
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.rocket_launch_rounded,
                    title: 'Pomodoro Tekniği'.tr(),
                    color: Color(0xFFFF6A3C),
                    customBg: _cardBgs['pomodoro'],
                    customTextColor: _cardInks['pomodoro'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('pomodoro', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const _PomodoroTechniquePage(),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(child: SizedBox.shrink()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════ Renk seçim paneli — diğer sayfalar ile aynı format ═══════════════
  Widget _buildLibraryColorPanel() {
    const orange = Color(0xFFFF6A00);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.textPrimary(context), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded, size: 16, color: Colors.black),
              SizedBox(width: 6),
              Text('Renk'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
              SizedBox(width: 10),
              Expanded(child: _libraryModeToggle(orange)),
              SizedBox(width: 8),
              GestureDetector(
                onTap: _resetLibraryColors,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppPalette.cardMuted(context),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text('Sıfırla'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.black54)),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          _libraryTargetToggle(orange),
          SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin yere bırak.'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
                height: 1.3),
          ),
          SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _libraryPalette.length,
              itemBuilder: (_, i) => _libraryDraggableColor(_libraryPalette[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _libraryModeToggle(Color orange) {
    Widget box(String id, IconData icon, String label) {
      final active = _colorMode == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorMode = id),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: active
                  ? orange.withValues(alpha: 0.12)
                  : Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? orange : Colors.black,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: active ? orange : Colors.black),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active ? orange : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        box('text', Icons.text_fields_rounded, 'Yazı'),
        SizedBox(width: 8),
        box('frame', Icons.crop_square_rounded, 'Çerçeve'),
      ],
    );
  }

  Widget _libraryTargetToggle(Color orange) {
    // Yatay scrollable bir listede kullanıldığı için chip kendi
    // genişliğine göre ayarlanır — Expanded yok.
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return GestureDetector(
        onTap: () => setState(() => _colorTarget = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: active
                ? orange.withValues(alpha: 0.12)
                : Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? orange : Colors.black12,
              width: active ? 1.4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: active ? orange : Colors.black),
          ),
        ),
      );
    }

    // Hedef listesi: sayfa arka planı + her kart için ayrı chip.
    // Yatay scroll ile sığar; her chip basınca _colorTarget değişir,
    // ardından paletten basılan renk yalnız o hedefe uygulanır.
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('bg', 'Arka plan'),
          SizedBox(width: 6),
          for (final entry in _cardSlugs.entries) ...[
            // Her kart için kendi chip'i — slug → görünen ad eşlemesi.
            // Slug ad'ları default Türkçe; .tr() ile aktif dile çevrilir.
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 80),
              child: chip(entry.key, entry.value.tr()),
            ),
            SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _libraryDraggableColor(Color c) {
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _libraryDot(c)),
      child: GestureDetector(
        onTap: () => _applyLibraryColor(_colorTarget, c),
        child: _libraryDot(c),
      ),
    );
  }

  Widget _libraryDot(Color c) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border(context), width: 1),
      ),
    );
  }
}

class _LandingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;
  final Color? customBg;
  final Color? customTextColor;
  final ValueChanged<Color>? onColorAccept;
  /// 3'lü yatay sıralama için kompakt mod — kart yüksekliği + içerik küçülür.
  final bool compact;
  const _LandingCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.customBg,
    this.customTextColor,
    this.onColorAccept,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasSub = subtitle != null && subtitle!.isNotEmpty;
    // Library landing kartları (Konu Özeti / Sınav Soruları / vb.) — koyu
    // modda saf siyah, aydınlıkta kullanıcı override veya beyaz.
    final bgColor = customBg ??
        (AppPalette.isDark(context) ? Colors.black : Colors.white);
    final lum = 0.299 * bgColor.r + 0.587 * bgColor.g + 0.114 * bgColor.b;
    final isDark = lum < 0.55;
    final titleColor =
        customTextColor ?? (isDark ? Colors.white : Colors.black);
    final subtitleColor = customTextColor ??
        (isDark ? Colors.white70 : Colors.black54);

    final cardHeight = compact ? 102.0 : 128.0;
    final iconBox = compact ? 38.0 : (hasSub ? 40.0 : 48.0);
    final iconSize = compact ? 20.0 : (hasSub ? 22.0 : 26.0);
    final titleFs = compact ? 11.0 : (hasSub ? 12.5 : 13.0);

    return DragTarget<Color>(
      onAcceptWithDetails: (d) => onColorAccept?.call(d.data),
      builder: (ctx, cand, _) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 160),
          height: cardHeight,
          padding: EdgeInsets.symmetric(
              horizontal: 8, vertical: hasSub ? 10 : (compact ? 10 : 14)),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: cand.isNotEmpty
                ? Border.all(color: Color(0xFFFF6A00), width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(compact ? 11 : (hasSub ? 12 : 14)),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: iconSize),
              ),
              SizedBox(height: compact ? 8 : (hasSub ? 6 : 10)),
              Text(
                title,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: titleFs,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                  height: 1.15,
                ),
              ),
              if (hasSub && !compact) ...[
                SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: subtitleColor,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Model ──────────────────────────────────────────────────────────────────
// Konu başına 3 adet test hakkı. Her _TestAttempt bir testi temsil eder:
// JSON içeriği + kullanıcının seçimleri + tamamlanma durumu.
class _TestAttempt {
  final String id;
  final String content;
  Map<int, String?> answers;
  bool completed;
  final DateTime createdAt;
  // Soru başına saniye. 0 = süresiz (relax). 90 = normal, 45 = race.
  final int timeLimit;
  // Seçilen zorluk — UI'da rozet olarak gösterilebilir.
  final String difficulty;
  // Soru başına kalan saniye — kullanıcı testten çıkıp tekrar girdiğinde
  // her sorunun süresinin kaldığı yerden devam etmesi için persist.
  // Boş map (varsayılan) → ilk açılışta TestPage timeLimit'ten doldurur.
  Map<int, int> perQuestionRemaining;

  _TestAttempt({
    required this.id,
    required this.content,
    required this.answers,
    required this.completed,
    required this.createdAt,
    this.timeLimit = 0,
    this.difficulty = 'medium',
    Map<int, int>? perQuestionRemaining,
  }) : perQuestionRemaining = perQuestionRemaining ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'answers': answers
            .map((k, v) => MapEntry(k.toString(), v)),
        'completed': completed,
        'createdAt': createdAt.toIso8601String(),
        'timeLimit': timeLimit,
        'difficulty': difficulty,
        'pqr': perQuestionRemaining
            .map((k, v) => MapEntry(k.toString(), v)),
      };

  factory _TestAttempt.fromJson(Map<String, dynamic> j) {
    final raw = (j['answers'] as Map?) ?? const {};
    final parsed = <int, String?>{};
    raw.forEach((k, v) {
      final key = int.tryParse(k.toString());
      if (key != null) parsed[key] = v?.toString();
    });
    final rawPqr = (j['pqr'] as Map?) ?? const {};
    final pqr = <int, int>{};
    rawPqr.forEach((k, v) {
      final key = int.tryParse(k.toString());
      final val = (v is num) ? v.toInt() : int.tryParse(v.toString());
      if (key != null && val != null) pqr[key] = val;
    });
    return _TestAttempt(
      id: (j['id'] ?? DateTime.now().millisecondsSinceEpoch.toString())
          .toString(),
      content: (j['content'] ?? '').toString(),
      answers: parsed,
      completed: (j['completed'] as bool?) ?? false,
      createdAt:
          DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      timeLimit: (j['timeLimit'] as num?)?.toInt() ?? 0,
      difficulty: (j['difficulty'] ?? 'medium').toString(),
      perQuestionRemaining: pqr,
    );
  }
}

// Test oluşturma sihirbazının son adımındaki yapılandırma.
class _TestConfig {
  int count = 10;
  String difficulty = 'medium'; // 'easy' | 'medium' | 'hard'
  String timeMode = 'relax'; // 'relax' | 'normal' | 'race'

  int get timeLimitSeconds {
    switch (timeMode) {
      case 'normal':
        return 90;
      case 'race':
        return 45;
      default:
        return 0;
    }
  }
}

/// Özet uzunluk türü — her konunun en fazla 2 özeti olur (kısa + kapsamlı).
/// Eski kayıtlar için varsayılan: `short` (daha önce tek tip vardı, yeni
/// sistemde bu eski özetler "kısa" sayılır; kullanıcı kapsamlı versiyonu
/// ekstra olarak oluşturabilir).
enum _SummaryLength { short, comprehensive }

class _Summary {
  final String id;
  final String topic;
  // Streaming akışı sırasında parça parça doldurulduğu için `content`
  // mutable. Stream tamamlandığında nihai metin atanır + persist edilir.
  String content;
  final DateTime createdAt;
  // Questions mode için test denemeleri (max 3). Summary mode boş kalır.
  List<_TestAttempt> tests;
  // Doğrulama Etiketi metaverisi — özet üretildiği anda kullanılan
  // ülke + sınıf + RAG durumu. Eski özetler için null kalabilir; UI
  // mevcut profile'ı fallback olarak gösterir.
  final String? country;
  final String? gradeLabel;
  final bool ragHit;
  // Topluluk cache metaverisi — rating widget'ı bunları kullanır.
  // Eski (cache öncesi) özetlerde null kalır → rating UI gösterilmez.
  // Streaming sonrası post-write için MUTABLE.
  String? cacheDocId;
  String? candidateDocId;
  bool isCanonical;
  /// Kısa veya Kapsamlı özet türü. Aynı konuda her ikisinden bir tane
  /// oluşturulabilir (toplam max 2). Eski özetlerde null kalır → kısa kabul edilir.
  final _SummaryLength length;
  _Summary({
    required this.id,
    required this.topic,
    required this.content,
    required this.createdAt,
    List<_TestAttempt>? tests,
    this.country,
    this.gradeLabel,
    this.ragHit = false,
    this.cacheDocId,
    this.candidateDocId,
    this.isCanonical = false,
    this.length = _SummaryLength.short,
  }) : tests = tests ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'tests': tests.map((t) => t.toJson()).toList(),
        if (country != null) 'country': country,
        if (gradeLabel != null) 'gradeLabel': gradeLabel,
        'ragHit': ragHit,
        if (cacheDocId != null) 'cacheDocId': cacheDocId,
        if (candidateDocId != null) 'candidateDocId': candidateDocId,
        if (isCanonical) 'isCanonical': true,
        'length': length.name, // 'short' veya 'comprehensive'
      };

  factory _Summary.fromJson(Map<String, dynamic> j) {
    final rawTests = (j['tests'] as List?) ?? const [];
    final tests = rawTests
        .whereType<Map>()
        .map((e) => _TestAttempt.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final rawLength = j['length'] as String?;
    final length = rawLength == 'comprehensive'
        ? _SummaryLength.comprehensive
        : _SummaryLength.short;
    return _Summary(
      id: j['id'] as String,
      topic: j['topic'] as String,
      content: j['content'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      tests: tests,
      country: j['country'] as String?,
      gradeLabel: j['gradeLabel'] as String?,
      ragHit: (j['ragHit'] as bool?) ?? false,
      cacheDocId: j['cacheDocId'] as String?,
      candidateDocId: j['candidateDocId'] as String?,
      isCanonical: (j['isCanonical'] as bool?) ?? false,
      length: length,
    );
  }
}

class _Subject {
  final String id;
  String name;
  List<_Summary> summaries;
  _Subject({required this.id, required this.name, required this.summaries});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'summaries': summaries.map((s) => s.toJson()).toList(),
      };

  factory _Subject.fromJson(Map<String, dynamic> j) => _Subject(
        id: j['id'] as String,
        name: j['name'] as String,
        summaries: ((j['summaries'] as List?) ?? [])
            .map((e) => _Summary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// Seviye → kısaltma (sınav tipi)
String _examShort(String grade) {
  switch (grade) {
    case 'LGS Hazırlık': return 'LGS';
    case 'TYT Hazırlık': return 'TYT';
    case 'AYT Hazırlık': return 'AYT';
    case 'KPSS Hazırlık': return 'KPSS';
    case 'Lise 9-10':    return 'TYT';
    default:             return 'Sınav';
  }
}

// ── Sınıf seviyesine göre içerik stratejisi ──────────────────────────────
// İki strateji:
//  • examFocus      → 8 (LGS), 12 (YKS), KPSS, mezun, exam_prep — dershane
//                     mantığı, taktik, çıkmış soru tipleri, cheat sheet.
//  • schoolBalanced → 5/6/7/9/10/11 ara sınıflar — okul yazılısı + temel
//                     sınav hazırlığı, akademik tanım + klasik öğretmen
//                     soruları + sınavda çıkacak temel kısım.
enum _PromptStrategy { schoolBalanced, examFocus }

_PromptStrategy _strategyFor(String grade) {
  // 1) Açık sınav hazırlık etiketleri.
  switch (grade) {
    case 'LGS Hazırlık':
    case 'TYT Hazırlık':
    case 'AYT Hazırlık':
    case 'KPSS Hazırlık':
      return _PromptStrategy.examFocus;
  }
  // 2) EduProfile.current üzerinden sınav grubu / son sınıf tespiti.
  final p = EduProfile.current;
  if (p != null) {
    if (p.level == 'exam_prep') return _PromptStrategy.examFocus;
    final n = RegExp(r'(\d{1,2})').firstMatch(p.grade);
    if (n != null) {
      final num = int.tryParse(n.group(1) ?? '');
      // 8 = LGS senesi, 12 = YKS senesi → exam focus.
      if (num == 8 || num == 12) return _PromptStrategy.examFocus;
    }
    // Mezun / hazırlık ifadeleri.
    final g = p.grade.toLowerCase();
    if (g.contains('mezun') ||
        g.contains('graduate') ||
        g.contains('alumni') ||
        g.contains('hazırlık') ||
        g.contains('prep')) {
      return _PromptStrategy.examFocus;
    }
  }
  // 3) Eski _grade enum'undan kalan hint'ler.
  final g = grade.toLowerCase();
  if (g.contains('mezun') ||
      g.contains('hazırlık') ||
      g.contains('hazirlik')) {
    return _PromptStrategy.examFocus;
  }
  return _PromptStrategy.schoolBalanced;
}

/// Strateji blok metnini üretir — prompt'un EN BAŞINA eklenir, AI'ın tonunu
/// tek hamlede belirler. `exam` bilinmiyorsa "Sınav" geçer.
String _strategyBlock(_PromptStrategy s, String exam) {
  if (s == _PromptStrategy.examFocus) {
    return '''
[STRATEJİ: HEDEF SINAV / DERSHANE MANTIĞI]
Sen uzman bir sınav koçusun. Öğrenci $exam için hazırlanıyor — sadece
sınavda NET KAZANDIRACAK stratejik bilgiyi ver. Akademik kitap dilini
minimuma indir; dershane dili öne çıksın.

ZORUNLU TUTUM:
• Akademik tanım yalnızca 1 satırda geçer; gerisi taktiktir.
• "Sınavda en çok çıkan", "can alıcı nokta", "şu tuzağa düşme",
  "kısa yol" / "süper hız" satırlarını ÖN PLANA çıkar.
• Çıkmış soru tipi varsa kısa anekdot olarak ver: "$exam'de bu konudan
  genelde '... mı / değil mi?' tarzı sorulur."
• Püf nokta / cheat sheet formatı: kısa, vurucu, ezber-dostu maddeler.
• "Şu formül ezberlenir, gerisi türetilir" mantığı; ispat şişirme YOK.
• Detay ya da "ileride lazım olabilir" türü bilgi verme; sadece
  $exam-net-kazandıran bilgiyi koru.
''';
  }
  return '''
[STRATEJİ: OKUL YAZILISI + TEMEL SINAV HAZIRLIĞI]
Öğrenci ara sınıfta — hem okul yazılısından iyi not almalı hem de gelecek
sınava temel oluşturmalı. Orta yollu yaklaş; ne kuru akademi ne sırf taktik.

ZORUNLU TUTUM:
• MEB müfredatındaki AKADEMİK TANIM ve klasikleşmiş öğretmen soruları
  mutlaka yer alsın (yazılıda kesin sorulan tipler).
• "Hocan yazılıda bunu kesin sorar" diyebileceğin klasik kalıpları işaretle.
• Konunun sınavda çıkan temel kısmını da göster — "bu, ileride $exam'de
  de karşına çıkar" gibi köprü kur.
• Tanım → örnek → uygulama sırası net; yazılı için sınav-tipik örnek
  kullan, taktik bilgiyi de yedekle.
• Detaydan kaçma; hem yazılı puanına hem temel sınav hazırlığına hizmet
  eden DENGELİ özet/test çıkar.
''';
}

// Seviye → bağlam metni
String _contextFromGrade(String grade) {
  switch (grade) {
    case 'LGS Hazırlık':
      return 'Öğrenci LGS (8. sınıf merkezî sınav) için hazırlanıyor.';
    case 'TYT Hazırlık':
      return 'Öğrenci TYT (YKS Temel Yeterlilik Testi) için hazırlanıyor.';
    case 'AYT Hazırlık':
      return 'Öğrenci AYT (YKS Alan Yeterlilik Testi) için hazırlanıyor.';
    case 'KPSS Hazırlık':
      return 'Öğrenci KPSS için hazırlanıyor.';
    case 'Lise 9-10':
      return 'Lise 9-10 öğrencisi, TYT mantığında çalışıyor.';
    case 'Ortaokul':
      return 'Ortaokul düzeyinde, basit dille anlat.';
    case 'İlkokul':
      return 'İlkokul düzeyinde çok basit anlat.';
    case 'Üniversite':
      return 'Üniversite düzeyinde akademik anlat.';
    default:
      return 'Lise/TYT düzeyinde anlat.';
  }
}

// Ders → konu placeholder ipucu (locale-aware)
String _topicHintForSubject(String subject) {
  final s = subject.toLowerCase();
  if (s.contains('matem') || s.contains('math')) return localeService.tr('topic_hint_math');
  if (s.contains('fiz') || s.contains('phys')) return localeService.tr('topic_hint_physics');
  if (s.contains('kim') || s.contains('chem')) return localeService.tr('topic_hint_chemistry');
  if (s.contains('biyo') || s.contains('bio')) return localeService.tr('topic_hint_biology');
  if (s.contains('coğraf') || s.contains('geo')) return localeService.tr('topic_hint_geography');
  if (s.contains('tar') || s.contains('hist')) return localeService.tr('topic_hint_history');
  if (s.contains('edeb') || s.contains('lit')) return localeService.tr('topic_hint_literature');
  if (s.contains('türk') || s.contains('gram')) return localeService.tr('topic_hint_grammar');
  if (s.contains('feles') || s.contains('phil')) return localeService.tr('topic_hint_philosophy');
  if (s.contains('ingil') || s.contains('engl')) return localeService.tr('topic_hint_english');
  return localeService.tr('topic_hint_generic');
}

enum LibraryMode { summary, questions }

class AcademicPlanner extends StatefulWidget {
  final LibraryMode mode;
  // İlk açılışta otomatik açılması istenen ders+konu. Test sonuç sayfasındaki
  // "Kısa bir tekrar" butonu kullanır: özet varsa direkt açılır; yoksa o
  // konuda özet üretim akışı tetiklenir.
  final String? autoOpenSubject;
  final String? autoOpenTopic;
  const AcademicPlanner({
    super.key,
    this.mode = LibraryMode.summary,
    this.autoOpenSubject,
    this.autoOpenTopic,
  });
  @override
  State<AcademicPlanner> createState() => _AcademicPlannerState();
}

class _AcademicPlannerState extends State<AcademicPlanner> {
  String get _subjectsKey => widget.mode == LibraryMode.summary
      ? 'library_subjects_v2'
      : 'library_subjects_questions_v2';
  static const _usageKey = 'topic_summary_usage';

  // _title artık AppBar'da kullanılmıyor (başlık kaldırıldı). Diğer
  // ekranlarda tekrar gerekirse buradan üretilebilir.
  String get _title => widget.mode == LibraryMode.summary
      ? localeService.tr('topic_summaries')
      : localeService.tr('exam_questions');
  String get _headline => widget.mode == LibraryMode.summary
      ? localeService.tr('create_summary_hint')
      : 'İstediğin konudan test oluştur'.tr();

  String _grade = '';
  int _monthUsed = 0;
  String _monthKey = '';
  List<_Subject> _subjects = [];
  bool _generating = false;
  // Loader sırasında kullanıcı "İptal"e bastıysa true — solveHomework Future'ı
  // arka planda devam eder ama sonucu yutulur + kota iade edilir.
  bool _generatingCancelled = false;
  // Loader aşama metinleri + sembol akışı için aktif üretim bilgisi.
  String _generatingTopic = '';
  String _generatingSubject = '';

  SubjectDomain get _generatingDomain {
    final layer = _subjectLayer(_generatingSubject);
    return layer == 'verbal' ? SubjectDomain.verbal : SubjectDomain.numeric;
  }

  // "Diğer Dersler" overlay sheet — modal değil, böylece arka plandaki
  // ilk 8 ders kareleri tıklanabilir/sürüklenebilir kalır.
  bool _showOtherSheet = false;
  // Bir ders sürüklenirken sheet'i şeffaflaştırmak için.
  bool _draggingFromSheet = false;

  // Renk özelleştirme — kullanıcı AppBar'daki palet butonundan açar.
  // İki mod: 'frame' (arka plan/çerçeve/ders kareleri zeminleri) ·
  // 'text' (başlık ve ders kartlarındaki yazı rengi).
  // Üç hedef: 'bg' (sayfa arka planı) · 'frame' (dersleri çevreleyen dış
  // çerçeve / başlık) · 'subjects' (ders kareleri). Renk tek dokunuşla
  // uygulanabilir ya da sürükleyip bırakılabilir.
  bool _showColorPicker = false;
  String _colorMode = 'frame'; // 'frame' | 'text'
  String _colorTarget = 'bg'; // 'bg' | 'frame' | 'subjects'
  Color? _pageBgOverride;
  Color? _frameOverride;
  Color? _frameTextOverride;
  // Manuel eklenen dersler için ayrı çerçeve rengi (drag-drop ile uygulanır)
  Color? _customFrameOverride;
  final Map<String, Color> _subjectTileColors = {};
  final Map<String, Color> _subjectTileTextColors = {};
  static const _planColorPalette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  // SharedPreferences anahtarları — kayıt mode bazlı (özet/test ayrı renk
  // seti). Anahtar adında mode.name kullanıyoruz.
  String get _bgColorKey =>
      'planner_bg_color_${widget.mode.name}';
  String get _frameColorKey =>
      'planner_frame_color_${widget.mode.name}';
  String get _frameTextColorKey =>
      'planner_frame_text_color_${widget.mode.name}';
  String get _tileColorsKey =>
      'planner_tile_colors_${widget.mode.name}';
  String get _tileTextColorsKey =>
      'planner_tile_text_colors_${widget.mode.name}';
  String get _subjectOrderKey =>
      'planner_subject_order_${widget.mode.name}';
  String get _summaryCardColorsKey =>
      'planner_summary_card_colors_${widget.mode.name}';
  String get _customFrameColorKey =>
      'planner_custom_frame_color_${widget.mode.name}';

  // Alt kartların (oluşturulmuş özet/test ders kartları) ayrı renk map'i.
  final Map<String, Color> _summaryCardColors = {};

  Future<void> _loadSummaryCardColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_summaryCardColorsKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _summaryCardColors.clear();
      m.forEach((k, v) {
        if (v is num) _summaryCardColors[k] = Color(v.toInt());
      });
      if (mounted) setState(() {});
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  Future<void> _saveSummaryCardColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_summaryCardColors.isEmpty) {
        await prefs.remove(_summaryCardColorsKey);
      } else {
        await prefs.setString(
            _summaryCardColorsKey,
            jsonEncode(_summaryCardColors
                .map((k, v) => MapEntry(k, v.toARGB32()))));
      }
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  void _applyColorToSummaryCard(String subjectId, Color c) {
    setState(() => _summaryCardColors[subjectId] = c);
    _saveSummaryCardColors();
  }

  Future<void> _loadCustomSubjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_customSubjectsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final loaded = <EduSubject>[];
      for (final m in list) {
        final key = (m['key'] as String?) ?? '';
        final name = (m['name'] as String?) ?? '';
        final emoji = (m['emoji'] as String?) ?? '📚';
        final colorVal = m['color'];
        if (key.isEmpty || name.isEmpty) continue;
        final color = colorVal is num ? Color(colorVal.toInt()) : _blue;
        loaded.add(EduSubject(key, emoji, name, color));
      }
      if (!mounted) return;
      setState(() => _customSubjects = loaded);
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  Future<void> _saveCustomSubjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _customSubjects
          .map((s) => {
                'key': s.key,
                'name': s.name,
                'emoji': s.emoji,
                'color': s.color.toARGB32(),
              })
          .toList();
      await prefs.setString(_customSubjectsKey, jsonEncode(list));
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  Future<void> _loadSubjectOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_subjectOrderKey);
      if (raw == null || raw.isEmpty) return;
      // _inlineEduSubjects yüklendiyse buna göre yeniden sırala.
      if (_inlineEduSubjects.isEmpty) return;
      final byKey = {for (final s in _inlineEduSubjects) s.key: s};
      final reordered = <EduSubject>[];
      for (final k in raw) {
        final s = byKey.remove(k);
        if (s != null) reordered.add(s);
      }
      // raw'da olmayan yeni dersler sona eklenir.
      reordered.addAll(byKey.values);
      if (!mounted) return;
      setState(() => _inlineEduSubjects = reordered);
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  Future<void> _saveSubjectOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _subjectOrderKey,
        _inlineEduSubjects.map((s) => s.key).toList(),
      );
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  // İki dersin yerini değiştir + kaydet. Drag bitince sheet'i de kapat.
  void _swapSubjects(String draggedKey, String targetKey) {
    if (draggedKey == targetKey) return;
    final list = List<EduSubject>.from(_inlineEduSubjects);
    final from = list.indexWhere((s) => s.key == draggedKey);
    final to = list.indexWhere((s) => s.key == targetKey);
    if (from < 0 || to < 0) return;
    final tmp = list[from];
    list[from] = list[to];
    list[to] = tmp;
    setState(() {
      _inlineEduSubjects = list;
      _draggingFromSheet = false;
    });
    _saveSubjectOrder();
  }

  Future<void> _loadColorPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bgInt = prefs.getInt(_bgColorKey);
      final frameInt = prefs.getInt(_frameColorKey);
      final frameTextInt = prefs.getInt(_frameTextColorKey);
      final customFrameInt = prefs.getInt(_customFrameColorKey);
      final tilesRaw = prefs.getString(_tileColorsKey);
      final tilesTextRaw = prefs.getString(_tileTextColorsKey);
      if (!mounted) return;
      setState(() {
        if (bgInt != null) _pageBgOverride = Color(bgInt);
        if (frameInt != null) _frameOverride = Color(frameInt);
        if (frameTextInt != null) _frameTextOverride = Color(frameTextInt);
        if (customFrameInt != null) _customFrameOverride = Color(customFrameInt);
        if (tilesRaw != null && tilesRaw.isNotEmpty) {
          try {
            final m = jsonDecode(tilesRaw) as Map<String, dynamic>;
            _subjectTileColors.clear();
            m.forEach((k, v) {
              if (v is num) _subjectTileColors[k] = Color(v.toInt());
            });
          } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
        }
        if (tilesTextRaw != null && tilesTextRaw.isNotEmpty) {
          try {
            final m = jsonDecode(tilesTextRaw) as Map<String, dynamic>;
            _subjectTileTextColors.clear();
            m.forEach((k, v) {
              if (v is num) _subjectTileTextColors[k] = Color(v.toInt());
            });
          } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
        }
      });
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  Future<void> _saveColorPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pageBgOverride == null) {
        await prefs.remove(_bgColorKey);
      } else {
        await prefs.setInt(_bgColorKey, _pageBgOverride!.toARGB32());
      }
      if (_frameOverride == null) {
        await prefs.remove(_frameColorKey);
      } else {
        await prefs.setInt(_frameColorKey, _frameOverride!.toARGB32());
      }
      if (_frameTextOverride == null) {
        await prefs.remove(_frameTextColorKey);
      } else {
        await prefs.setInt(
            _frameTextColorKey, _frameTextOverride!.toARGB32());
      }
      if (_customFrameOverride == null) {
        await prefs.remove(_customFrameColorKey);
      } else {
        await prefs.setInt(
            _customFrameColorKey, _customFrameOverride!.toARGB32());
      }
      if (_subjectTileColors.isEmpty) {
        await prefs.remove(_tileColorsKey);
      } else {
        final json = jsonEncode(_subjectTileColors
            .map((k, v) => MapEntry(k, v.toARGB32())));
        await prefs.setString(_tileColorsKey, json);
      }
      if (_subjectTileTextColors.isEmpty) {
        await prefs.remove(_tileTextColorsKey);
      } else {
        final json = jsonEncode(_subjectTileTextColors
            .map((k, v) => MapEntry(k, v.toARGB32())));
        await prefs.setString(_tileTextColorsKey, json);
      }
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  void _applyColorTo(String target, Color c) {
    setState(() {
      if (_colorMode == 'text') {
        // Yazı modu — renk metne uygulanır.
        if (target == 'subjects') {
          for (final s in _inlineEduSubjects) {
            _subjectTileTextColors[s.key] = c;
          }
        } else {
          // 'bg' ya da 'frame' → çerçeve başlık yazısı.
          _frameTextOverride = c;
        }
      } else {
        // Çerçeve modu — zemine uygulanır (mevcut davranış).
        if (target == 'bg') {
          _pageBgOverride = c;
        } else if (target == 'frame') {
          _frameOverride = c;
        } else {
          for (final s in _inlineEduSubjects) {
            _subjectTileColors[s.key] = c;
          }
        }
      }
    });
    _saveColorPrefs();
  }

  void _applyColorToTile(String subjectKey, Color c) {
    setState(() {
      if (_colorMode == 'text') {
        _subjectTileTextColors[subjectKey] = c;
      } else {
        _subjectTileColors[subjectKey] = c;
      }
    });
    _saveColorPrefs();
  }

  Widget _buildColorPickerPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.textPrimary(context), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst satır: sol "Renk" başlığı · ortada Yazı/Çerçeve mod seçici ·
          // sağda Sıfırla. Target chips bir alttaki satırda.
          Row(
            children: [
              Icon(Icons.palette_rounded,
                  size: 16, color: Colors.black),
              SizedBox(width: 6),
              Text(
                'Renk'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.black),
              ),
              SizedBox(width: 10),
              Expanded(child: _modeToggle()),
              SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _pageBgOverride = null;
                    _frameOverride = null;
                    _frameTextOverride = null;
                    _customFrameOverride = null;
                    _subjectTileColors.clear();
                    _subjectTileTextColors.clear();
                    _summaryCardColors.clear();
                  });
                  _saveColorPrefs();
                  _saveSummaryCardColors();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppPalette.cardMuted(context),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    'Sıfırla'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.black54),
                  ),
                ),
              ),
            ],
          ),
          // Hedef chip'leri — "Arka plan / Çerçeve / Ders alanı". Tam
          // genişlikte tek satır; altındaki açıklama yazısı ve renk paleti
          // "Arka plan" çerçevesinin sol kenarı ile aynı hizadan başlar.
          SizedBox(height: 8),
          _targetToggle(),
          SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin kareye veya arka plana bırak.'
                .tr(),
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
                height: 1.3),
          ),
          SizedBox(height: 8),
          // Çift sıra, yatay kaydırılabilir · her renk Draggable.
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _planColorPalette.length,
              itemBuilder: (_, i) =>
                  _draggableColor(_planColorPalette[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetToggle() {
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? _orange.withValues(alpha: 0.12)
                  : Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _orange : Colors.black12,
                width: active ? 1.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: active ? _orange : Colors.black),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('bg', 'Arka plan'.tr()),
        SizedBox(width: 6),
        chip('frame', 'Çerçeve'.tr()),
        SizedBox(width: 6),
        chip('subjects', 'Ders alanı'.tr()),
      ],
    );
  }

  // Yazı / Çerçeve mod seçici — Renk başlığının altında iki küçük kutu.
  Widget _modeToggle() {
    Widget box(String id, IconData icon, String label) {
      final active = _colorMode == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorMode = id),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 140),
            padding:
                const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: active
                  ? _orange.withValues(alpha: 0.12)
                  : Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _orange : Colors.black,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 13,
                    color: active ? _orange : Colors.black),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active ? _orange : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        box('text', Icons.text_fields_rounded, 'Yazı'.tr()),
        SizedBox(width: 8),
        box('frame', Icons.crop_square_rounded, 'Çerçeve'.tr()),
      ],
    );
  }

  Widget _draggableColor(Color c) {
    final selected = (_colorMode == 'frame') &&
        ((_colorTarget == 'bg' && _pageBgOverride == c) ||
            (_colorTarget == 'frame' && _frameOverride == c));
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: _colorDot(c, faded: true, selected: false),
      child: GestureDetector(
        onTap: () => _applyColorTo(_colorTarget, c),
        child: _colorDot(c, selected: selected),
      ),
    );
  }

  Widget _colorDot(Color c,
      {bool faded = false, bool selected = false}) {
    return Opacity(
      opacity: faded ? 0.3 : 1.0,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _orange : Colors.black26,
            width: selected ? 2.4 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check_rounded,
                size: 16, color: _orange)
            : null,
      ),
    );
  }

  // Inline ders ekle paneli (sürekli açık, modal yok)
  EduProfile? _inlineProfile;
  List<EduSubject> _inlineEduSubjects = [];

  // Kullanıcının kendi eklediği kalıcı dersler — modlar arası paylaşılır
  // (özet ve test sayfasında aynı liste görünür).
  static const _customSubjectsKey = 'planner_custom_subjects_v1';
  List<EduSubject> _customSubjects = [];



  @override
  void initState() {
    super.initState();
    _load();
    _loadColorPrefs();
    _loadSummaryCardColors();
    _loadCustomSubjects();
    // Inline panel profili hemen yükle
    EduProfile.load().then((p) async {
      if (!mounted) return;
      // AI cache pref'ten yükle (uygulama yeniden başlatıldıysa olabilir).
      await EduProfile.loadAiSubjectCache();
      if (!mounted) return;
      setState(() {
        _inlineProfile = p;
        _inlineEduSubjects = _subjectsForProfileAllTracks(p);
      });
      // Varsayılan sıra: çekirdek dersler kullanım azalan + seçmeliler sona.
      // Kullanıcı manuel sürükle-bırak yapmışsa _loadSubjectOrder bunu ezer.
      await _applyDefaultUsageOrder();
      _loadSubjectOrder();
      // Cache yoksa AI'dan profile özel ders listesi çek + güncelle.
      if (p != null && EduProfile.aiCachedSubjects(p) == null) {
        unawaited(_fetchAiCurriculum(p));
      }
    });
  }

  Future<void> _applyDefaultUsageOrder() async {
    final usage = await SubjectUsageStats.load();
    if (!mounted) return;
    setState(() {
      _inlineEduSubjects =
          orderSubjectsByUsage(_inlineEduSubjects, usage);
    });
  }

  /// AI'dan o profilin müfredatını çek + cache'le + UI'yi yenile.
  /// `fetchProfileCurriculum` ders + konuları beraber döndürür → 131 ülkenin
  /// her biri için (static catalog'a bakmaksızın) ülke-spesifik müfredat üretir.
  Future<void> _fetchAiCurriculum(EduProfile p) async {
    try {
      final result = await GeminiService.fetchProfileCurriculum(p);
      if (result.subjects.isEmpty) return;
      await EduProfile.saveAiSubjectCache(p, result.subjects);
      if (result.topicsBySubject.isNotEmpty) {
        await EduProfile.saveAiTopicsCache(p, result.topicsBySubject);
      }
      if (!mounted) return;
      setState(() {
        _inlineEduSubjects = _subjectsForProfileAllTracks(p);
      });
      await _applyDefaultUsageOrder();
      _loadSubjectOrder();
    } catch (_) {
      // Sessizce başarısız — kullanıcı static fallback listesini görür.
    }
  }

  /// subjectsForProfile'ı tüm track varyasyonları üzerinde UNION'lar.
  /// Kullanıcı profilinde "Eşit Ağırlık" seçse bile diğer alanlardaki
  /// dersler de grid'te görünür — hepsi tıklanabilir.
  List<EduSubject> _subjectsForProfileAllTracks(EduProfile? p) {
    // Profil yoksa varsayılan: Türkiye Lise 11 (alan: tüm tracks).
    // Kullanıcı eğitim profili kurulumuna girmeden derslere doğrudan
    // erişebilsin diye gate yerine fallback gösteriyoruz.
    final eff = p ??
        EduProfile(
          country: 'tr',
          level: 'high',
          grade: '11',
        );
    final seen = <String>{};
    final seenNames = <String>{};
    final all = <EduSubject>[];
    void addList(List<EduSubject> list) {
      for (final s in list) {
        // Hem key hem displayName ile dedup et — farklı track'lerde aynı
        // ders adı (örn. "Coğrafya") farklı key ile gelebilir, 2x görünürdü.
        final nameKey = s.name.trim().toLowerCase();
        if (seen.contains(s.key) || seenNames.contains(nameKey)) continue;
        seen.add(s.key);
        seenNames.add(nameKey);
        all.add(s);
      }
    }
    addList(subjectsForProfile(eff));
    if (eff.level == 'high') {
      const knownTracks = <String>[
        'sayisal', 'esit_agirlik', 'sozel', 'dil',
        'science', 'commerce', 'arts',
        'ipa', 'ips',
      ];
      for (final t in knownTracks) {
        if (eff.track == t) continue;
        addList(subjectsForProfile(EduProfile(
          country: eff.country,
          level: eff.level,
          grade: eff.grade,
          track: t,
          faculty: eff.faculty,
        )));
      }
    }
    return all;
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Depolama ─────────────────────────────────────────────────────────────
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final grade = prefs.getString('user_grade_level') ?? '';

    final now = DateTime.now();
    final mkey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    // Geliştirme sürecinde aylık kota sıfırlanıyor: tüm cihazlarda bir kez
    // sıfıra çekmek için sayaç yok sayılır. Yayına alırken bu bloğu kaldır.
    var used = 0;
    await prefs.setString(
      _usageKey,
      jsonEncode({'month': mkey, 'count': 0}),
    );

    final listRaw = prefs.getStringList(_subjectsKey) ?? [];
    final list = listRaw
        .map((s) {
          try {
            return _Subject.fromJson(
                jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<_Subject>()
        .toList();

    // Eski kayıtları yeni modele taşı: Questions mode'da tests boşsa
    // ama content doluysa, content'i ilk deneme olarak kabul et.
    if (widget.mode == LibraryMode.questions) {
      for (final subj in list) {
        for (final sum in subj.summaries) {
          if (sum.tests.isEmpty && sum.content.isNotEmpty) {
            sum.tests.add(_TestAttempt(
              id: '${sum.id}_legacy',
              content: sum.content,
              answers: {},
              completed: false,
              createdAt: sum.createdAt,
            ));
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _grade = grade;
      _monthKey = mkey;
      _monthUsed = used;
      _subjects = list;
    });
    // Test sonuç sayfasından "Kısa bir tekrar" ile açıldıysa hedef konuyu
    // otomatik aç (varsa özetini, yoksa üretim akışını).
    _maybeAutoOpen();
  }

  bool _autoOpenHandled = false;

  void _maybeAutoOpen() {
    if (_autoOpenHandled) return;
    final s = widget.autoOpenSubject;
    final t = widget.autoOpenTopic;
    if (s == null || s.trim().isEmpty || t == null || t.trim().isEmpty) {
      return;
    }
    _autoOpenHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _Subject? subjectRef;
      final target = _normSubjectName(s);
      for (final sb in _subjects) {
        if (_normSubjectName(sb.name) == target) {
          subjectRef = sb;
          break;
        }
      }
      _Summary? summary;
      if (subjectRef != null) {
        for (final sum in subjectRef.summaries) {
          if (sum.topic.toLowerCase() == t.trim().toLowerCase()) {
            summary = sum;
            break;
          }
        }
      }
      if (summary != null) {
        _openSummary(summary, subjectRef!.name);
      } else {
        await _runGenerateWithSetup(subjectName: s, topic: t);
      }
    });
  }

  Future<void> _persistUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _usageKey,
      jsonEncode({'month': _monthKey, 'count': _monthUsed}),
    );
  }

  Future<void> _persistSubjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _subjectsKey,
      _subjects.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }





  // Public: detail page'in çağırdığı "yeni konu ekle" akışı (page açık kalır)
  Future<bool> _generateForExistingSubject(
      _Subject subject, String topic,
      {_TestConfig? config}) async {
    final isQuestions = widget.mode == LibraryMode.questions;
    final cfg = config ?? _TestConfig();

    // ── KOTA: günlük + aylık global (UsageQuota tek doğru kaynak) ─────────
    final kind = isQuestions ? QuotaKind.testQuestions : QuotaKind.topicSummary;
    final quota = await UsageQuota.get(kind);
    if (quota.isExhausted) {
      Analytics.logQuotaExhausted(kind.name);
      _showSnack(quota.isDailyExhausted
          ? 'Günlük AI sınırına ulaştın (${quota.dailyLimit}). '
              'Yarın tekrar dene veya Premium\'a geç.'
          : 'Aylık AI sınırına ulaştın (${quota.monthlyLimit}). '
              'Ay başında sıfırlanır.');
      return false;
    }

    // Questions mode: aynı konu varsa 3 hakkını kontrol et + attempt ekle.
    _Summary? existingSummary;
    if (isQuestions) {
      for (final s in subject.summaries) {
        if (s.topic.toLowerCase() == topic.toLowerCase()) {
          existingSummary = s;
          break;
        }
      }
      if (existingSummary != null && existingSummary.tests.length >= 3) {
        _showSnack(
            'Bu konu için 3 test hakkın da bitti. Başka bir konu dene.'.tr());
        return false;
      }
    }

    // Pre-check geçti — şimdi kotayı artır. Hata olursa decrement edilecek.
    await UsageQuota.increment(kind);

    try {
      final profile = await EduProfile.load();
      final baseCtx = _contextFromGrade(_grade);
      final profileCtx = educationContext(profile);
      final ctx = profileCtx.isEmpty ? baseCtx : '$baseCtx\n$profileCtx';
      final exam = _examShort(_grade);
      final built = await _buildPrompt(
        subject: subject.name,
        topic: topic,
        ctx: ctx,
        exam: exam,
        count: cfg.count,
        difficulty: cfg.difficulty,
      );
      final prompt = built.prompt;
      final ragHit = built.ragHit;
      final content = await GeminiService.solveHomework(
        question: prompt,
        solutionType: isQuestions ? 'TestSorulari' : 'KonuÖzeti',
        subject: subject.name,
      );

      // Questions mode'da JSON validate; bozuksa attempt'ı saklama, kotayı iade et.
      if (isQuestions && parseTestQuestions(content).isEmpty) {
        await UsageQuota.decrement(kind);
        if (mounted) {
          _showSnack(
              'AI testi bozuk biçimde döndü. Tekrar dene.'.tr());
        }
        return false;
      }
      final cleanContent = isQuestions ? content : _stripMarkdown(content);

      if (isQuestions && existingSummary != null) {
        existingSummary.tests.add(_TestAttempt(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: cleanContent,
          answers: {},
          completed: false,
          createdAt: DateTime.now(),
          timeLimit: cfg.timeLimitSeconds,
          difficulty: cfg.difficulty,
        ));
      } else {
        final summary = _Summary(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          topic: topic,
          content: cleanContent,
          createdAt: DateTime.now(),
          country: EduProfile.current?.country,
          gradeLabel: _grade.isNotEmpty ? _grade : EduProfile.current?.grade,
          ragHit: ragHit,
          tests: isQuestions
              ? [
                  _TestAttempt(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    content: cleanContent,
                    answers: {},
                    completed: false,
                    createdAt: DateTime.now(),
                    timeLimit: cfg.timeLimitSeconds,
                    difficulty: cfg.difficulty,
                  ),
                ]
              : null,
        );
        subject.summaries.insert(0, summary);
      }
      // _monthUsed dead-code; UsageQuota tek doğru kaynak.
      await _persistSubjects();
      await _ActivityStore.log(
        subject: subject.name,
        topic: topic,
        type: isQuestions ? 'soru' : 'özet',
      );
      if (mounted) setState(() {});
      return true;
    } on GeminiException catch (e) {
      await UsageQuota.decrement(kind);
      if (mounted) _showSnack(e.userMessage);
      return false;
    } catch (e) {
      await UsageQuota.decrement(kind);
      if (mounted) _showSnack('${localeService.tr('error_label')}: $e');
      return false;
    }
  }

  // Questions mode — var olan _Summary'e yeni bir test hakkı ekler.
  // 3 hak dolunca engellenir. Tamamlandığında TestPage'i açar.
  // Loader state'i _SubjectDetailPage kendi yönetir; burada sadece veri işi.
  Future<void> _generateAttemptForSummary(
      _Subject subject, _Summary summary,
      {_TestConfig? config}) async {
    if (widget.mode != LibraryMode.questions) return;
    // ── KOTA: günlük + aylık global ──────────────────────────────────────
    final quota = await UsageQuota.get(QuotaKind.testQuestions);
    if (quota.isExhausted) {
      Analytics.logQuotaExhausted(QuotaKind.testQuestions.name);
      _showSnack(quota.isDailyExhausted
          ? 'Günlük AI sınırına ulaştın (${quota.dailyLimit}). '
              'Yarın tekrar dene veya Premium\'a geç.'
          : 'Aylık AI sınırına ulaştın (${quota.monthlyLimit}). '
              'Ay başında sıfırlanır.');
      return;
    }
    if (summary.tests.length >= 3) {
      _showSnack(
          'Bu konu için 3 test hakkın da bitti. Başka bir konu dene.'.tr());
      return;
    }
    final cfg = config ?? _TestConfig();
    await UsageQuota.increment(QuotaKind.testQuestions);
    try {
      final profile = await EduProfile.load();
      final baseCtx = _contextFromGrade(_grade);
      final profileCtx = educationContext(profile);
      final ctx = profileCtx.isEmpty ? baseCtx : '$baseCtx\n$profileCtx';
      final exam = _examShort(_grade);
      final ragRes = await _fetchRag(
          subject: subject.name, topic: summary.topic);
      final ragBlock = RagService.buildContextBlock(ragRes);
      final prompt = _buildQuestionsPrompt(
        subject: subject.name,
        topic: summary.topic,
        ctx: ctx,
        exam: exam,
        count: cfg.count,
        difficulty: cfg.difficulty,
        strategy: _strategyFor(_grade),
        ragBlock: ragBlock,
        ragHit: !ragRes.usedFallback,
      );
      final content = await GeminiService.solveHomework(
        question: prompt,
        solutionType: 'TestSorulari',
        subject: subject.name,
      );
      // JSON validate; bozuksa attempt'ı saklama, kotayı iade et.
      if (parseTestQuestions(content).isEmpty) {
        await UsageQuota.decrement(QuotaKind.testQuestions);
        if (mounted) {
          _showSnack(
              'AI testi bozuk biçimde döndü. Tekrar dene.'.tr());
        }
        return;
      }
      final attempt = _TestAttempt(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: content,
        answers: {},
        completed: false,
        createdAt: DateTime.now(),
        timeLimit: cfg.timeLimitSeconds,
        difficulty: cfg.difficulty,
      );
      summary.tests.add(attempt);
      // _monthUsed dead-code; UsageQuota tek doğru kaynak.
      await _persistSubjects();
      await _ActivityStore.log(
        subject: subject.name,
        topic: summary.topic,
        type: 'soru',
      );
      if (!mounted) return;
      setState(() {});
      _openTestAttempt(summary, attempt, subject.name);
    } on GeminiException catch (e) {
      await UsageQuota.decrement(QuotaKind.testQuestions);
      if (mounted) _showSnack(e.userMessage);
    } catch (e) {
      await UsageQuota.decrement(QuotaKind.testQuestions);
      if (mounted) _showSnack('${localeService.tr('error_label')}: $e');
    }
  }

  // Questions mode — önce _TestSetupPage aç, sonra _generate.
  // Summary mode — setup'a gerek yok, doğrudan üret.
  Future<void> _runGenerateWithSetup({
    required String subjectName,
    required String topic,
  }) async {
    if (widget.mode != LibraryMode.questions) {
      await _generate(
          subjectName: subjectName, topic: topic, newSubject: true);
      return;
    }
    // Var olan konu için sonraki attempt index'ini bul; 3 dolduysa engelle.
    int nextIdx = 0;
    for (final s in _subjects) {
      if (s.name.toLowerCase() == subjectName.toLowerCase()) {
        for (final sum in s.summaries) {
          if (sum.topic.toLowerCase() == topic.toLowerCase()) {
            nextIdx = sum.tests.length;
            break;
          }
        }
        break;
      }
    }
    if (nextIdx >= 3) {
      _showSnack(
          'Bu konu için 3 test hakkın da bitti. Başka bir konu dene.'.tr());
      return;
    }
    // Küçük zorluk seçici dialog — arka plan flu + 3 kutu + Tamam butonu.
    final cfg = await _showDifficultyDialog();
    if (cfg == null) return;
    await _generate(
      subjectName: subjectName,
      topic: topic,
      newSubject: true,
      config: cfg,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Zorluk seçici dialog — Kolay · Orta · Zor + Tamam butonu.
  //  Arka plan BackdropFilter ile fludur. Kullanıcı bir zorluğa basınca
  //  seçili olur; "Tamam"a basınca _TestConfig döner.
  // ══════════════════════════════════════════════════════════════════════════
  Future<_TestConfig?> _showDifficultyDialog() {
    return showGeneralDialog<_TestConfig>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.2),
      transitionDuration: Duration(milliseconds: 200),
      pageBuilder: (ctx, a1, a2) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: const _DifficultyPickerDialog(),
      ),
    );
  }

  /// Kullanıcıya "Özetiniz kısa mı olsun kapsamlı mı olsun?" diye sorar.
  /// Ekranın ortasında küçük bir dialog açar. İptal edilirse null döner.
  Future<_SummaryLength?> _askSummaryLength(BuildContext ctx) {
    return showGeneralDialog<_SummaryLength>(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: 'Özet türü',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogCtx, a1, a2) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(dialogCtx).size.width * 0.85,
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            decoration: BoxDecoration(
              color: AppPalette.card(dialogCtx),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Özetiniz kısa mı olsun kapsamlı mı olsun?'.tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(dialogCtx),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(dialogCtx)
                            .pop(_SummaryLength.short),
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF22C55E),
                                Color(0xFF16A34A),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.30),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.flash_on_rounded,
                                  color: Colors.white, size: 22),
                              const SizedBox(height: 4),
                              Text(
                                'Kısa Özet'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(dialogCtx)
                            .pop(_SummaryLength.comprehensive),
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF3B82F6),
                                Color(0xFF2563EB),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF3B82F6)
                                    .withValues(alpha: 0.30),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.menu_book_rounded,
                                  color: Colors.white, size: 22),
                              const SizedBox(height: 4),
                              Text(
                                'Kapsamlı Özet'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── AI çağrısı ve özet kayıt (yeni ders kartı için) ──────────────────────
  Future<void> _generate({
    required String subjectName,
    required String topic,
    required bool newSubject,
    _Subject? existingSubject,
    _TestConfig? config,
  }) async {
    final isQuestions = widget.mode == LibraryMode.questions;
    final cfg = config ?? _TestConfig();

    // Subject ref'i ÖNCE bul — sonraki check'lerin (per-subject limit, varolan
    // summary lookup) buna ihtiyacı var. Türkçe karakterlere dayanıklı normalize.
    _Subject? subjectRef = existingSubject;
    if (subjectRef == null || subjectRef.id.isEmpty) {
      final target = _normSubjectName(subjectName);
      for (final s in _subjects) {
        if (_normSubjectName(s.name) == target) {
          subjectRef = s;
          break;
        }
      }
    }

    // ── ÖZET UZUNLUK ROUTING (kısa vs kapsamlı) ──────────────────────────
    // Aynı konuda max 2 özet: 1 kısa + 1 kapsamlı.
    //  • İkisi de varsa: snack ile bilgi ver, üretmez.
    //  • Sadece biri varsa: dialog ATLA, otomatik diğer türü üret.
    //  • Hiçbiri yoksa: dialog ile sor.
    _SummaryLength? chosenLength;
    if (!isQuestions) {
      bool hasShort = false;
      bool hasComp = false;
      if (subjectRef != null) {
        for (final s in subjectRef.summaries) {
          if (s.topic.toLowerCase() == topic.toLowerCase()) {
            if (s.length == _SummaryLength.short) hasShort = true;
            if (s.length == _SummaryLength.comprehensive) hasComp = true;
          }
        }
      }
      if (hasShort && hasComp) {
        _showSnack(
            'Bu konunun hem kısa hem kapsamlı özeti zaten var. Tekrar oluşturulamaz.'
                .tr());
        return;
      }
      if (hasShort && !hasComp) {
        chosenLength = _SummaryLength.comprehensive;
      } else if (hasComp && !hasShort) {
        chosenLength = _SummaryLength.short;
      } else {
        // Hiçbiri yok — kullanıcıya sor
        chosenLength = await _askSummaryLength(context);
        if (chosenLength == null) return; // iptal
      }
    }

    // ── LIMIT KADEMELERİ ────────────────────────────────────────────────
    // 1) Yeni quota sistemi (UsageQuota): günlük + aylık global sınır.
    //    Hem konu özeti (200/ay) hem test (300/ay) ayrı sayaçlar tutar.
    //    Eski `_monthUsed` ve per-subject 4/ay limitleri KALDIRILDI —
    //    UsageQuota tek doğru kaynak. (Önceden 3 katman çakışıyordu;
    //    kullanıcı 4+ özet üretince "oluşturulamıyor" oluyordu.)
    final kind = isQuestions ? QuotaKind.testQuestions : QuotaKind.topicSummary;
    final quota = await UsageQuota.get(kind);
    if (quota.isExhausted) {
      Analytics.logQuotaExhausted(kind.name);
      _showSnack(quota.isDailyExhausted
          ? 'Günlük AI sınırına ulaştın (${quota.dailyLimit}). '
              'Yarın tekrar dene veya Premium\'a geç.'
          : 'Aylık AI sınırına ulaştın (${quota.monthlyLimit}). '
              'Ay başında sıfırlanır.');
      return;
    }
    // ── /LIMIT ───────────────────────────────────────────────────────────
    _Summary? existingSummary;
    if (isQuestions && subjectRef != null && subjectRef.id.isNotEmpty) {
      for (final s in subjectRef.summaries) {
        if (s.topic.toLowerCase() == topic.toLowerCase()) {
          existingSummary = s;
          break;
        }
      }
    }
    if (isQuestions &&
        existingSummary != null &&
        existingSummary.tests.length >= 3) {
      _showSnack(
          'Bu konu için 3 test hakkın da bitti. Başka bir konu dene.'.tr());
      return;
    }

    // Tüm pre-check'ler geçti — şimdi quota counter'ı artır + Analytics event.
    // Daha önce burada quota erkenden artırılıyordu; engellenen op'larda boşa
    // sayaç tüketiyordu (kullanıcı limite çabuk takılıyordu).
    await UsageQuota.increment(kind);
    Analytics.logEvent(
      isQuestions ? 'test_questions_generated' : 'topic_summary_generated',
      params: {
        'subject': subjectName,
        'topic': topic,
      },
    );

    // KonuÖzeti modunda STREAMING kullanılır — sayfa anında açılır,
    // AI yazdıkça içerik dolar. TestSorulari modunda JSON full yanıt
    // bekleyen klasik akış.
    final profile = await EduProfile.load();
    final baseCtx = _contextFromGrade(_grade);
    final profileCtx = educationContext(profile);
    final ctx = profileCtx.isEmpty ? baseCtx : '$baseCtx\n$profileCtx';
    final exam = _examShort(_grade);
    final strategy = _strategyFor(_grade);
    final ragRes = await _fetchRag(subject: subjectName, topic: topic);
    final ragBlock = RagService.buildContextBlock(ragRes);
    final ragHit = !ragRes.usedFallback;
    final prompt = isQuestions
        ? _buildQuestionsPrompt(
            subject: subjectName,
            topic: topic,
            ctx: ctx,
            exam: exam,
            count: cfg.count,
            difficulty: cfg.difficulty,
            strategy: strategy,
            ragBlock: ragBlock,
            ragHit: ragHit,
          )
        : _buildSummaryPrompt(
            subject: subjectName,
            topic: topic,
            ctx: ctx,
            exam: exam,
            grade: _grade,
            strategy: strategy,
            ragBlock: ragBlock,
            ragHit: ragHit,
            length: chosenLength ?? _SummaryLength.short,
          );

    if (!isQuestions) {
      // ── CACHE-FIRST: TOPLULUK ÖZETİ KONTROL ────────────────────────────
      // Aynı seviye+ders+konu için cache'te canonical/yüksek-puanlı aday
      // varsa AI çağrısı YAPILMADAN direkt göster. Yoksa streaming yapıp
      // sonra cache'e aday olarak ekle.
      final profile = EduProfile.current;
      CachedSummary? cached;
      if (profile != null) {
        try {
          cached = await SummaryCacheService.read(
            profile: profile,
            subject: subjectName,
            topic: topic,
          );
        } catch (e, st) {
          ErrorLogger.instance.capture(e, st, context: 'planner_cache_read');
        }
      }

      if (cached != null && cached.body.isNotEmpty) {
        // CACHE HIT — anında göster, stream'siz
        final summary = _Summary(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          topic: topic,
          content: cached.body,
          createdAt: DateTime.now(),
          country: EduProfile.current?.country,
          gradeLabel:
              _grade.isNotEmpty ? _grade : EduProfile.current?.grade,
          ragHit: ragHit,
          cacheDocId: cached.cacheDocId,
          candidateDocId: cached.candidateDocId,
          isCanonical: cached.isCanonical,
        );
        if (subjectRef != null && subjectRef.id.isNotEmpty) {
          subjectRef.summaries.insert(0, summary);
        } else {
          _subjects.add(_Subject(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: subjectName,
            summaries: [summary],
          ));
        }
        await _persistSubjects();
        await _ActivityStore.log(
            subject: subjectName, topic: topic, type: 'özet');
        if (!mounted) return;
        setState(() {});
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _SummaryDetailPage(
            summary: summary,
            subjectName: subjectName,
          ),
        ));
        return;
      }

      // ── STREAMING AKIŞI (KonuÖzeti) — cache miss ───────────────────────
      // 1) Boş özet oluştur, _subjects'e ekle, persist et.
      // 2) Sayfayı HEMEN aç + stream'i ona ver.
      // 3) Stream bitince summary.content güncellenir + cache'e yazılır.
      final summary = _Summary(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        topic: topic,
        content: '',
        createdAt: DateTime.now(),
        country: EduProfile.current?.country,
        gradeLabel: _grade.isNotEmpty ? _grade : EduProfile.current?.grade,
        ragHit: ragHit,
        length: chosenLength ?? _SummaryLength.short,
      );
      if (subjectRef != null && subjectRef.id.isNotEmpty) {
        subjectRef.summaries.insert(0, summary);
      } else {
        _subjects.add(_Subject(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: subjectName,
          summaries: [summary],
        ));
      }
      // NOT: `_monthUsed += 1` çıkarıldı — UsageQuota tek doğru kaynak
      // (4366'da artırıldı). _monthlyLimit=100000 zaten devre dışı,
      // _persistUsage dead-code idi. Çift sayım UI'ı yanıltıyordu.
      await _persistSubjects();
      await _ActivityStore.log(
        subject: subjectName,
        topic: topic,
        type: 'özet',
      );

      if (!mounted) return;
      setState(() {});

      Stream<String> newStream() => GeminiService.solveHomeworkStream(
            question: prompt,
            solutionType: 'KonuÖzeti',
            subject: subjectName,
          );

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _SummaryDetailPage(
          summary: summary,
          subjectName: subjectName,
          stream: newStream(),
          onStreamComplete: (finalContent) async {
            summary.content = _stripMarkdown(finalContent);
            // Cache'e aday olarak ekle — gelecek kullanıcılar bu içeriği
            // de görsün (eğer yeterli puan alırsa canonical olabilir).
            if (profile != null) {
              try {
                final candidateId =
                    await SummaryCacheService.addCandidate(
                  profile: profile,
                  subject: subjectName,
                  topic: topic,
                  body: summary.content,
                );
                if (candidateId != null) {
                  summary.candidateDocId = candidateId;
                  summary.cacheDocId = SummaryCacheService.makeCacheKey(
                    profile: profile,
                    subject: subjectName,
                    topic: topic,
                  );
                }
              } catch (e, st) {
                ErrorLogger.instance.capture(e, st,
                    context: 'planner_cache_write');
              }
            }
            await _persistSubjects();
            if (mounted) setState(() {});
          },
          // Stream hiç chunk üretmeden fail / boş yanıt → kotayı iade et
          // ve boş özet kaydını listeden temizle.
          onEarlyFailure: () async {
            await UsageQuota.decrement(kind);
            // Boş özeti listeden çıkar — kullanıcı boş kart görmesin.
            for (final s in _subjects) {
              s.summaries.removeWhere((sum) => sum.id == summary.id);
            }
            _subjects.removeWhere((s) => s.summaries.isEmpty);
            await _persistSubjects();
            if (mounted) setState(() {});
          },
          // Sayfa içi "Tekrar Dene" — yeni stream üret, kotayı tekrar say.
          onRetry: () {
            // ignore: discarded_futures
            UsageQuota.increment(kind);
            return newStream();
          },
        ),
      )).then((_) {
        if (mounted) setState(() {});
      });
      return;
    }

    // ── KLASİK AKIŞ (TestSorulari) — JSON tam yanıt gerekir ──────────
    setState(() {
      _generating = true;
      _generatingTopic = topic;
      _generatingSubject = subjectName;
      _generatingCancelled = false;
    });
    try {
      final content = await GeminiService.solveHomework(
        question: prompt,
        solutionType: 'TestSorulari',
        subject: subjectName,
      );

      // Kullanıcı bekleme sırasında "İptal"e bastıysa sonucu yutmadan dön.
      if (!mounted) return;
      if (_generatingCancelled) {
        // Kotayı geri al — kullanıcı testi görmedi.
        await UsageQuota.decrement(kind);
        setState(() {
          _generating = false;
          _generatingCancelled = false;
        });
        return;
      }

      // AI yanıtı boş veya çok kısa geldiyse — kaydetme, hata göster + retry.
      if (content.trim().length < 40) {
        await UsageQuota.decrement(kind);
        if (!mounted) return;
        setState(() => _generating = false);
        _showRetrySnack(
          'AI yanıt veremedi. Tekrar denemek ister misin?',
          () => _generate(
            subjectName: subjectName,
            topic: topic,
            newSubject: newSubject,
            existingSubject: existingSubject,
            config: config,
          ),
        );
        return;
      }

      // JSON parse pre-check — AI cevabı geçerli bir test mi?
      // parseTestQuestions boş dönerse attempt'ı saklama, kotayı iade et.
      // (3-hak slotu boşa harcanmasın + kullanıcı boş test görmesin.)
      final parsedCheck = parseTestQuestions(content);
      if (parsedCheck.isEmpty) {
        await UsageQuota.decrement(kind);
        if (!mounted) return;
        setState(() => _generating = false);
        _showRetrySnack(
          'AI testi bozuk biçimde döndü. Tekrar denemek ister misin?',
          () => _generate(
            subjectName: subjectName,
            topic: topic,
            newSubject: newSubject,
            existingSubject: existingSubject,
            config: config,
          ),
        );
        return;
      }

      final cleanContent = content;

      // Bu noktaya yalnız TestSorulari modunda ulaşılır (KonuÖzeti yukarıda
      // streaming akışıyla erken return etti).
      final _Summary targetSummary;
      final _TestAttempt createdAttempt;

      if (existingSummary != null) {
        createdAttempt = _TestAttempt(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: cleanContent,
          answers: {},
          completed: false,
          createdAt: DateTime.now(),
          timeLimit: cfg.timeLimitSeconds,
          difficulty: cfg.difficulty,
        );
        existingSummary.tests.add(createdAttempt);
        targetSummary = existingSummary;
      } else {
        final summary = _Summary(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          topic: topic,
          content: cleanContent,
          createdAt: DateTime.now(),
          country: EduProfile.current?.country,
          gradeLabel: _grade.isNotEmpty ? _grade : EduProfile.current?.grade,
          ragHit: ragHit,
        );
        createdAttempt = _TestAttempt(
          id: summary.id,
          content: cleanContent,
          answers: {},
          completed: false,
          createdAt: summary.createdAt,
          timeLimit: cfg.timeLimitSeconds,
          difficulty: cfg.difficulty,
        );
        summary.tests.add(createdAttempt);
        if (subjectRef != null && subjectRef.id.isNotEmpty) {
          subjectRef.summaries.insert(0, summary);
        } else {
          _subjects.add(_Subject(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: subjectName,
            summaries: [summary],
          ));
        }
        targetSummary = summary;
      }

      // NOT: `_monthUsed += 1` + `_persistUsage` çıkarıldı — UsageQuota tek
      // doğru kaynak (4366'da artırıldı). Dead-code temizliği.
      await _persistSubjects();
      await _ActivityStore.log(
        subject: subjectName,
        topic: topic,
        type: 'soru',
      );

      if (!mounted) return;
      setState(() => _generating = false);
      _openTestAttempt(targetSummary, createdAttempt, subjectName);
    } on GeminiException catch (e) {
      // İstek hata verdi → kotayı geri al (kullanıcı boş yere yememeli).
      await UsageQuota.decrement(kind);
      if (!mounted) return;
      setState(() => _generating = false);
      _showRetrySnack(
        e.userMessage,
        () => _generate(
          subjectName: subjectName,
          topic: topic,
          newSubject: newSubject,
          existingSubject: existingSubject,
          config: config,
        ),
      );
    } catch (e) {
      await UsageQuota.decrement(kind);
      if (!mounted) return;
      setState(() => _generating = false);
      _showRetrySnack(
        '${localeService.tr('error_label')}: $e',
        () => _generate(
          subjectName: subjectName,
          topic: topic,
          newSubject: newSubject,
          existingSubject: existingSubject,
          config: config,
        ),
      );
    }
  }

  Future<({String prompt, bool ragHit})> _buildPrompt({
    required String subject,
    required String topic,
    required String ctx,
    required String exam,
    int count = 10,
    String difficulty = 'medium',
  }) async {
    final strategy = _strategyFor(_grade);
    final rag = await _fetchRag(subject: subject, topic: topic);
    final ragBlock = RagService.buildContextBlock(rag);
    final ragHit = !rag.usedFallback;
    if (widget.mode == LibraryMode.questions) {
      return (
        prompt: _buildQuestionsPrompt(
          subject: subject,
          topic: topic,
          ctx: ctx,
          exam: exam,
          count: count,
          difficulty: difficulty,
          strategy: strategy,
          ragBlock: ragBlock,
          ragHit: ragHit,
        ),
        ragHit: ragHit
      );
    }
    return (
      prompt: _buildSummaryPrompt(
        subject: subject,
        topic: topic,
        ctx: ctx,
        exam: exam,
        grade: _grade,
        strategy: strategy,
        ragBlock: ragBlock,
        ragHit: ragHit,
      ),
      ragHit: ragHit
    );
  }

  /// Mevcut profile + topic için RAG çağrısı. RAG kapalı/erişilemez ise
  /// usedFallback=true döner, prompt builder fallback satırı ekler.
  Future<RagResult> _fetchRag({
    required String subject,
    required String topic,
  }) async {
    final profile = EduProfile.current;
    final country = profile?.country ?? 'tr';
    final grade = _grade.isNotEmpty ? _grade : (profile?.grade ?? '');
    return RagService.fetchCurriculumChunks(
      country: country,
      grade: grade,
      subject: subject,
      topic: topic,
    );
  }

  static String _buildQuestionsPrompt({
    required String subject,
    required String topic,
    required String ctx,
    required String exam,
    int count = 10,
    String difficulty = 'medium',
    _PromptStrategy strategy = _PromptStrategy.schoolBalanced,
    String? ragBlock,
    bool ragHit = false,
  }) {
    final layer = _subjectLayer(subject);
    final isNumeric = layer == 'numeric';
    final isVerbal = layer == 'verbal';
    final layerLine = isNumeric
        ? '• Katman 1 (Sayısal): "sol" alanında formül + sembol/birim + işlem '
            'basamakları (algoritma) sırasıyla yer alsın. Biyoloji ise genetik '
            'çaprazlama (Aa × Aa) ve biyokimyasal formüller (\\( C_6H_{12}O_6 \\)) '
            'kusursuz gösterilsin.'
        : isVerbal
            ? '• Katman 2 (Sözel): "sol" alanında akıcı bir profesör dili kullan; '
                'tarihte kesin yıl/antlaşma, edebiyatta yazar-eser-dönem bağı, '
                'felsefede argüman→sentez şeması bulunsun. LaTeX kullanma.'
            : '• Konu sayısalsa formül+birim, sözelse kronolojik/kavramsal bağ '
                'biçiminde "sol" alanını kur.';
    final diffLine = () {
      switch (difficulty) {
        case 'easy':
          return '• "d" alanı: tüm sorular "easy". Sorular temel seviyede, '
              'tanım ve basit uygulama odaklı.';
        case 'hard':
          return '• "d" alanı: tüm sorular "hard". Sorular zorlayıcı — çok '
              'adımlı, kavramsal derinlik, istisnalar ve tuzak şıklar içersin.';
        case 'medium':
        default:
          return '• "d" alanı: tüm sorular "medium". Tipik sınav zorluğunda, '
              'dengeli.';
      }
    }();
    // Sınıf seviyesine göre soru üslubu — examFocus dershane/çıkmış soru
    // mantığı, schoolBalanced klasik yazılı + temel hazırlık.
    final strategyStyleLine = strategy == _PromptStrategy.examFocus
        ? '• ÜSLUP: $exam dershanesinde çıkmış soru tipi taklit et — tuzaklı '
            'çeldiriciler, hız/kısa yol gerektiren çözümler, sınava özgü kalıplar. '
            'Akademik kitap sorusu YAZMA; kahraman dershane sorusu yaz.'
        : '• ÜSLUP: Klasik okul yazılısı + temel hazırlık karışımı — ${exam == 'Sınav' ? 'gelecek sınav' : exam} '
            'temellerini hazırlayacak, öğretmenin yazılıda klasikleşmiş soracağı '
            'tipte sorular. Tanım + uygulama dengeli; aşırı tuzak YOK.';
    final ragSection = ragBlock ??
        '[MÜFREDAT VERİSİ — RAG]\n'
            '(Bu konu için yerel müfredat veritabanında eşleşme bulunamadı; '
            'sistem genel bilgileri kullanıyor.)\n';
    return '''
${_strategyBlock(strategy, exam)}
$ragSection
[TEST — $count SORU · JSON]
Ders: $subject
Konu: $topic
Bağlam: $ctx
Zorluk: $difficulty
Katman: ${isNumeric ? 'SAYISAL (formül + sembol + birim)' : isVerbal ? 'SÖZEL (anlatı + kronoloji + bağlam)' : 'KARMA'}

GÖREVİN: Bu konu için $exam stiline uygun TAM OLARAK $count soru üret.
Tüm sorular $difficulty zorluk seviyesinde olsun.
QuAlsar Akademik İçerik Protokolü'nü uygula:
$layerLine
SADECE geçerli bir JSON array döndür — başka hiçbir metin, açıklama,
markdown fence (```json), emoji başlık yok.

KRİTİK — SELAMLAMA / GİRİZGÂH YASAK:
• "Tabii", "Tabii ki", "İşte", "Hadi", "Elbette" gibi GİRİŞ kelimeleriyle
  başlama. Cevabın İLK karakteri "[" olmalı.
• Cevap sonunda "Başarılar", "İyi çalışmalar", "Umarım yardımcı olur"
  gibi KAPANIŞ paragrafı YOK. Son karakter "]" olmalı.
• Bunlar parser'a takılıyor — ihlal edilirse cevap GEÇERSİZ sayılır.

Format (array, $count eleman):
[
  {
    "q": "soru metni — ÇOK kısa ve net, en fazla 1 kısa cümle. Formül/sembol gerekiyorsa LaTeX: \\\\( ... \\\\) veya \\\\[ ... \\\\] kullan; düz x^2 yazma.",
    "opts": {"A": "...", "B": "...", "C": "...", "D": "...", "E": "..."},
    "ans": "B",
    "hint": "tek cümle yol gösterici ipucu — cevabı VERME, sadece yöntem/ilke. LaTeX serbest.",
    "sol": "2-3 cümle çözüm. Formüller LaTeX ile, hesap ADIMI gösterilsin. Akış için → oku kullan (örn. F=ma → a=F/m → 3 m/s²).",
    "d": "$difficulty"
  },
  ...
]

ZORUNLU KURALLAR:
• TAM $count soru, ne eksik ne fazla.
• "opts" her zaman 5 şık: A, B, C, D, E.
• "ans" şık harfi: "A" | "B" | "C" | "D" | "E".
• Soru metni (q) ÇOK KISA — ideal 1 kısa cümle, maksimum 15 kelime.
  Uzun anlatım, hikâye, gereksiz detay EKLEME.
• "hint" tek cümle — kullanıcıya "nereden başlamalı" diye yol göster.
  Cevabı açıkça söyleme; sadece yöntem veya anahtar kavram ver.
• "sol" 2-3 cümle — sorunun çözüm mantığını kısa ver.
$diffLine
$strategyStyleLine
• ÇELDİRİCİLER (ÖSYM/LGS mantığı): Yanlış şıklar RASTGELE büyük sayı değil,
  öğrencinin GERÇEKTEN yapabileceği hatalar olmalı:
   – işaret hatası (artıyı eksiyle karıştırma)
   – birim/ondalık karışıklığı
   – formülün yanlış uygulanması (örn. yarıçap yerine çap, çevre yerine alan)
   – paydanın sıfır olduğu özel durumu atlama
   – eksik koşul (ör. \\( x \\neq 0 \\)) görmemek
   – sık yapılan kavramsal karıştırma
  En az 2 çeldirici bu tipte olmalı; yalnız bir doğru cevap.
• Dolar işareti (\$) kullanma — LaTeX için \\\\( ... \\\\) ve \\\\[ ... \\\\].
• Markdown yıldız (**) veya başlık (#) YAZMA.
• Emoji başlık (📝 📖 🔑) EKLEME.
• "Sonuç:" / "Püf Nokta:" yazma.
• FORMÜL/SEMBOL EKSIKSIZ: Sayısal soruda formül varsa "q", "opts" ve "sol"
  alanlarında SADECE LaTeX kullan — düz "x^2 + 3x" YASAK; ya \\\\( x^2 + 3x \\\\) ya
  da \\\\[ x^2 + 3x \\\\]. Birim/sembol eksiksiz: m/s², N, mol/L, ²⁻ vs.
• KİMYA: Bileşik formülleri LaTeX altıyazılı: \\\\( H_2O \\\\), \\\\( CO_2 \\\\),
  \\\\( C_6H_{12}O_6 \\\\). Düz "H2O" YASAK.
• AKIŞ ŞEMASI: "sol" alanında çok adımlı çözümde "→" ok'lu zincir kullan
  (örn. "F=ma → a=12/4 → a=3 m/s²"). Adımlar arası mantığı bu şekilde göster.
• Türkçe. $exam stiline uygun, tek doğru cevaplı.
• Çıktın tek başına geçerli bir JSON array olmalı — baştan sondan fazla
  whitespace, açıklama, backtick fence YOK.
''';
  }

  // ── Ders adı normalizasyonu — aynı ders altında özet birleştirme ────────
  // "Coğrafya" / "coğrafya" / "  COĞRAFYA  " / "Cografya" gibi varyasyonlar
  // tek kart altında birleşsin diye eşleştirme normalize anahtarla yapılır.
  static String _normSubjectName(String s) {
    var t = s.trim().toLowerCase();
    // Türkçe ve yaygın aksanlı karakterleri ASCII karşılığına indir
    const map = {
      'ç': 'c', 'ğ': 'g', 'ı': 'i', 'i̇': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
      'â': 'a', 'î': 'i', 'û': 'u', 'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o',
      'ú': 'u', 'ñ': 'n', 'ä': 'a', 'ë': 'e', 'ï': 'i',
    };
    map.forEach((k, v) => t = t.replaceAll(k, v));
    // Birden fazla boşluk → tek boşluk
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  // ── QuAlsar Akademik İçerik Protokolü — ders katmanı tespiti ───────────
  // Sayısal: Matematik, Geometri, Fizik, Kimya, Biyoloji
  // Sözel:   Tarih, Coğrafya, Edebiyat, Felsefe, Türkçe, Sanat Tarihi,
  //          Din Kültürü, Mantık (+ İngilizce/Yabancı Dil)
  static String _subjectLayer(String subject) {
    final s = subject.toLowerCase();
    bool any(List<String> ks) => ks.any(s.contains);
    if (any([
      'matematik', 'math', 'geometri', 'geometry',
      'fizik', 'physics', 'kimya', 'chem',
      'biyoloji', 'biology',
      '数学', '物理', '化学', '生物', '几何',
    ])) {
      return 'numeric';
    }
    if (any([
      'tarih', 'history', 'coğraf', 'cografya', 'geograph',
      'edebiyat', 'literature', 'türk dili', 'türkçe', 'turkish',
      'felsefe', 'philosoph', 'sanat tarihi', 'art history',
      'din kült', 'religion', 'mantık', 'logic',
      'ingiliz', 'english', 'yabancı dil',
      '历史', '地理', '文学', '哲学',
    ])) {
      return 'verbal';
    }
    return 'mixed';
  }

  // ── Prompt builder — paylaşılan ─────────────────────────────────────────
  static String _buildSummaryPrompt({
    required String subject,
    required String topic,
    required String ctx,
    required String exam,
    String grade = '',
    _PromptStrategy strategy = _PromptStrategy.schoolBalanced,
    String? ragBlock,
    bool ragHit = false,
    _SummaryLength length = _SummaryLength.short,
  }) {
    final layer = _subjectLayer(subject);
    final isNumeric = layer == 'numeric';
    final isVerbal = layer == 'verbal';

    // Eğitim seviyesine göre çoktan seçmeli şık sayısı:
    //   İlkokul        → 3 şık (A, B, C)        — basit
    //   Ortaokul / LGS → 4 şık (A, B, C, D)     — gerçek LGS formatı
    //   Lise/TYT/AYT/KPSS/Üniversite → 5 şık (A, B, C, D, E) — YKS formatı
    final int choiceCount;
    final String choiceLetters;
    final g = grade.toLowerCase();
    if (g.contains('ilkokul') || g.contains('primary')) {
      choiceCount = 3;
      choiceLetters = 'A, B, C';
    } else if (g.contains('ortaokul') ||
        g.contains('lgs') ||
        g.contains('middle')) {
      choiceCount = 4;
      choiceLetters = 'A, B, C, D';
    } else {
      // Lise 9-10, TYT, AYT, KPSS, Üniversite, default
      choiceCount = 5;
      choiceLetters = 'A, B, C, D, E';
    }

    // ─── KATMAN 1 — SAYISAL: Mantık, Sembol ve Formül Disiplini ─────────────
    final numericProtocol = '''
[QUALSAR — AKADEMİK DERİNLİK PROTOKOLÜ · KATMAN 1: SAYISAL BRANŞ]
Bu dersin EN YETKİN UZMANI gibi yaz: profesyonel, akıcı, otoriter.
Hedef: YKS derecesi yapacak öğrencinin başka kaynağa ihtiyaç duymayacağı
"Nihai Özet". Anlatım mimarisi:
  • ATOMİK ANALİZ: Konuyu en küçük yapı taşına kadar parçala
    (örn. çarpanlara ayırma basamakları, kuvvet bileşenleri, mol-kütle dönüşümü).
  • MANTIK TEMELİ: "Neden?" sorusuna bilimsel yanıt.
  • GÖRSELLEŞTİRİLMİŞ FORMÜLLER: Her formül belirgin ve açıklamalı; her
    sembolün anlamı + BİRİMİ açıkça verilsin.
    Örn: \\( F = m \\cdot a \\)  →  F: kuvvet (N), m: kütle (kg), a: ivme (m/s²).
  • HÜCRELİ ANLATIM: Her formül/kuralın HEMEN ALTINDA "🧪 Uygulama Örneği"
    ile mini bir soru çöz; çözüm adım adım (algoritmik) gösterilsin.
  • TAMLIK İLKESİ: Sadece ana bilgi DEĞİL — istisnalar (örn. \\( 0! = 1 \\)),
    pozitif/negatif bölenler, uç durumlar, sınavda hata yaptıran ince
    detaylar kapsansın. Sembol galerisi: \\( \\sum, \\int, \\Delta, \\Omega, \\nabla \\) bağlamında.
  • BİYOLOJİK SEMBOLİZM: Genetik çaprazlama (Aa × Aa → 1 AA : 2 Aa : 1 aa)
    ve biyokimyasal formüller (\\( C_6H_{12}O_6 \\), \\( CO_2 \\), \\( H_2O \\)) kusursuz.
''';

    // ─── KATMAN 2 — SÖZEL: Anlatı, Akıcılık, Derinlik ─────────────────────
    final verbalProtocol = '''
[QUALSAR — AKADEMİK DERİNLİK PROTOKOLÜ · KATMAN 2: SÖZEL BRANŞ]
Bu dersin EN YETKİN UZMANI/profesörü gibi yaz: hitabet gücüyle, akıcı,
büyüleyici. Hedef: YKS derecesi yapacak öğrencinin başka kaynağa ihtiyaç
duymayacağı "Nihai Özet". Anlatım mimarisi:
  • HİYERARŞİK YAPI: Ana başlıklar → alt başlıklar → maddeler; konuyu
    mantıksal sıraya diz, karmaşayı önle.
  • SEBEP-SONUÇ DETAYI: Olayları kuru ezber DEĞİL, "dönemin ruhu"yla
    sebep→sonuç zincirine yedirerek anlat — ANA BAŞLIKLARIN İÇİNDE.
  • ENTELEKTÜEL DERİNLİK: Felsefede kavramsal analiz, edebiyatta sanatsal
    yorum, tarihte dönemsel analiz — profesyonel dilde harmanlı.
  • LaTeX KULLANMA — düz, akıcı Türkçe paragraf/maddeler.
''';

    final protocolBlock = isNumeric
        ? numericProtocol
        : isVerbal
            ? verbalProtocol
            : '''
[QUALSAR — AKADEMİK DERİNLİK PROTOKOLÜ · KARMA BRANŞ]
Konu sayısal işlem gerektiriyorsa Katman 1 (atomik analiz, görselleştirilmiş
formüller, hücreli anlatım, tamlık ilkesi) kurallarını; kavramsal/anlatı
ağırlıklıysa Katman 2 (hiyerarşi + sebep-sonuç + derinlik) kurallarını
uygula. "Nihai Özet" hedefini koru.
''';

    // Ortak format zenginlikleri — her iki katman için geçerli
    const richFormatBlock = '''
ZENGİN FORMAT (gerektiğinde KULLAN):
  • TABLO: Karşılaştırma/sınıflandırma gerektiren bilgiler için sade
    Markdown tablosu (örn. asit/baz, dönem akımları, formül-birim eşleşmesi).
  • ÖNEMLİ BİLGİ KUTUSU: Tuzak/istisna/uzman içgörüsü varsa
    "💡 Önemli Bilgi: …" satırı ekle (UI bunu vurgulu kutuda gösterir).
  • AKIŞ ŞEMASI: Karmaşık süreçleri (Fotosentez, Fransız İhtilali aşamaları,
    glikoliz vb.) → ok'lu maddelerle göster:  Adım 1 → Adım 2 → Adım 3.
  • GÖRSEL/ŞEKİL/GRAFİK ANLATIMI: Konuda bir şekil, diyagram, grafik,
    moleküler yapı, devre, harita ya da haritalanması gereken kavramsal
    şema varsa, bunu MUTLAKA betimle: hangi eksende ne, hangi parça ne
    işe yarar, hangi etiket nereye düşer — öğrenci görseli zihninde
    canlandırabilsin. Yalnız "şu grafikte görülür" deyip geçme; tüm
    parçaları açıkla.
  • FORMÜL DETAYI: Bir formül veriliyorsa her sembolün anlamı + birimi
    + tipik değer aralığı + ne durumda kullanılır mutlaka belirtilsin.
''';

    final formulasBlock = isNumeric
        ? '''
📐 FORMÜL KARTI GALERİSİ + 🧪 UYGULAMA ÖRNEĞİ

Her formül için ZORUNLU "FORMÜL KARTI" yapısı (bu yapıyı bozma):

🟢 **FORMÜL ADI** (örn: Newton'un 2. Yasası)
\\[ F = m \\cdot a \\]
📌 **Sembol Çözümü:**
| Sembol | Tanım | Birim | Tipik Değer |
|--------|-------|-------|-------------|
| F      | Kuvvet | N (Newton) | 1–10⁵ |
| m      | Kütle | kg | nesne kütlesi |
| a      | İvme | m/s² | g=9.81 (yer) |

🧠 **Şöyle Düşün:** Bir cisme ne kadar kuvvet uygularsan o kadar hızlanır;
   ama ağırsa daha az hızlanır. F doğru orantılı m'le, ters orantılı bu nedenle
   a = F/m olarak da yazılabilir.

🧪 **Uygulama Örneği:**
   2 kg bir cisme 10 N kuvvet uygulanırsa ivmesi nedir?
   ▸ Adım 1: F = 10 N, m = 2 kg → \\( a = F/m \\)
   ▸ Adım 2: \\( a = 10\\,\\mathrm{N} / 2\\,\\mathrm{kg} \\)
   ▸ Adım 3: \\( a = 5\\,\\mathrm{m/s^2} \\) ✓ (birim doğrulaması)

⚡ **Kısa Yol:** F=ma'da m sabitse F ile a doğru orantılı; F→2F olursa a→2a.
🔴 **Tuzak:** Sürtünme varsa "net kuvvet" hesaba kat: \\( F_{net} = F - F_s \\).

═══════════════════════════════════════

KURAL — Bu KART YAPISINI bozmadan en az 3 anahtar formül ver:
  • LaTeX ZORUNLU: \\( ... \\) veya \\[ ... \\]
  • Her sembol için **TABLO** (sembol/tanım/birim/tipik değer)
  • 🧠 Şöyle Düşün satırı (sezgisel mantık — 1-2 cümle)
  • 🧪 Uygulama Örneği (numaralı 2-4 adım, birim takibi)
  • ⚡ Kısa Yol veya 🔴 Tuzak (en az birini ver)
  • Türetilebilir formülde 1-2 adım türetim göster
  • Birim/boyut analizi en az 1 formülde açıkça yapılır

ÖZEL DURUMLAR:
  • Genetik: Aa × Aa → tablo ile (Punnett karesi: 1 AA | 2 Aa | 1 aa)
  • Biyokimya: \\( C_6H_{12}O_6 + 6O_2 \\to 6CO_2 + 6H_2O \\) tam denklemi
  • TAMLIK: istisnalar (\\( 0! = 1 \\)), uç durumlar (n=0, payda=0)
    mutlaka 🔴 veya ⚪ marker'ı ile vurgulanır
  • Ondalık virgül (3{,}14), bilim notasyonu LaTeX içinde
'''
        : isVerbal
            ? '''
DETAY VE SEBEP-SONUÇ AKIŞI (formüller yerine, ana başlık içinde)
Sözel branş — kuru ezber YERİNE detaylı bağlam ver:
  • Sebep → Sonuç zinciri (yıllarla, en az 4-6 ok'lu adım) — ana başlığın
    gövdesinde, AYRI BÖLÜM AÇMA.
  • Karmaşık süreçler için akış şeması mantığı:
      Adım 1 → Adım 2 → Adım 3 → Sonuç
    (örn. Fransız İhtilali aşamaları, Tanzimat süreci, fotosentez evreleri).
  • Felsefe ise: Argüman → Karşı argüman → Sentez.
  • Karşılaştırma/sınıflandırma için sade Markdown TABLO kullan
    (örn. dönem-akım-temsilci-eser; antlaşma-yıl-taraflar).
  • Görselle anlatılması daha verimli olan kavram (harita, kronolojik
    çizgi, kavramsal şema) varsa METİNLE betimle: ne nereye düşer,
    hangi öge neyi temsil eder.
  • LaTeX kullanma; düz metin maddeler.
'''
            : '''
📐 FORMÜLLER / DETAY (varsa)
Konu sayısalsa "🧪 Uygulama Örneği" ile hücreli anlat; sözelse sebep→sonuç
zinciri ver. Karşılaştırma için Markdown tablo serbest. Şekil/diyagram
varsa metinle betimle.
''';

    final ragSection = ragBlock ??
        '[MÜFREDAT VERİSİ — RAG]\n'
            '(Bu konu için yerel müfredat veritabanında eşleşme bulunamadı; '
            'sistem genel bilgileri kullanıyor.)\n';

    // ── ÖZET UZUNLUK DİREKTİFİ — kullanıcı seçimine göre kısa veya kapsamlı
    final lengthDirective = length == _SummaryLength.short
        ? '''
[ÖZET UZUNLUĞU — KISA]
KULLANICI KISA ÖZET istedi. Hedef: 400-700 kelime (≈2-3 ekran).
• Konunun TANIMINI, EN ÖNEMLİ 3-5 NOKTASINI ve KRİTİK FORMÜLLERİNİ ver.
• Detaylı türetmeler, çok sayıda örnek soru, uzun tarihsel arka plan ver-ME.
• Tablo/şema kullan ama sınırlı (1-2 tane).
• Görsel betimlemesi maksimum 1 tane.
• Çıktın YOĞUN ve KESKİN olsun — hızlı okuyup özünü kavrasın.
'''
        : '''
[ÖZET UZUNLUĞU — KAPSAMLI]
KULLANICI KAPSAMLI ÖZET istedi. Hedef: 1500-3000 kelime (uzun, derinlemesine).
• Tüm alt başlıkları, istisnaları, uç durumları, dönem analizini AÇIK AÇIK ver.
• Çoklu örnek sorular ("🧪 Uygulama Örneği" hücreleri) zorunlu.
• Tablolar, karşılaştırmalar, sebep-sonuç zincirleri detaylı.
• Görsel betimlemesi 2-4 tane (uygun yerlerde).
• Sınavda hata yaptıran ince detaylar + ileri seviye notlar ekle.
• Çıktın bir DERSHANE KİTABI BÖLÜMÜ kalitesinde olmalı.
''';

    return '''
$lengthDirective
${_strategyBlock(strategy, exam)}
$ragSection
[KONU ÖZETİ — DERSHANE KİTABI TARZI]
Ders: $subject
Konu: $topic
Bağlam: $ctx

[EVRENSEL UZMAN EĞİTMEN KİMLİĞİ]
Sen 55 dilde akıcı, 130 ülkenin müfredatına hâkim, dünya çapında seçkin bir
ÇOK DİSİPLİNLİ UZMAN EĞİTMENSİN. Bu konu için **rolün otomatik adapte olur**:

• Matematik / Fizik / Kimya → Sen bir akademisyen-mühendissin. Önce TEMEL
  MANTIK, sonra LaTeX'le formül, sonra "Adım Adım Analiz" ile çözümlü örnek.
• Biyoloji / Tıp → Sen bir araştırmacı biyologsun. Karşılaştırmalı tablolar
  ZORUNLU. Hücresel/anatomik yapılar için "metin içi görsel betimleme" ekle.
• Tarih / Coğrafya → Sen bir tarih profesörüsün. Sebep-sonuç zinciri +
  kronolojik akış + harita/dönem detayları zorunlu.
• Edebiyat / Felsefe / Sosyal → Sen bir entelektüelsin. Argüman → karşı
  argüman → sentez yapısı. Akım, yıl, temsilci, eser dörtlüsünü TABLO yap.
• Dil / Yabancı dil → Sen bir dilbilimcisin. Kural → istisna → örnek.
  İki dilli karşılaştırma tabloları kullan.

GÖRSEL BETİMLEMESİ PROTOKOLÜ (Wikipedia'dan otomatik görsel):
Her özet sadece METİN değil, KONUYU GÖRSELLEŞTİREN ŞEMALARLA desteklenir.
Görsel etiket formatı (TEK SATIR — başka satıra bölme):
   [Görsel Betimlemesi: <Wikipedia'da aranabilir TEK kavram adı> — <kısa açıklama>]
   • Sol kısım (— öncesi): Wikipedia'da aranacak SAF, STANDART BİLİMSEL
     terim (1-3 kelime). Wikipedia'da bu adla ya da çok yakın varyantıyla
     ANSIKLOPEDİK SAYFASI BULUNAN bir terim olmalı. UI bu metinle
     wikipedia.org'dan otomatik thumbnail çeker.
     ✅ DOĞRU: "Faz diyagramı", "Bohr atom modeli", "Hayvan hücresi",
        "Fotosentez", "Newton yasaları", "Periyodik tablo", "Mitoz"
     ❌ YANLIŞ: "Saf madde hal değişim grafiği" (uzun + ders kitabı dili,
        Wikipedia sayfası yok), "Maddenin hallerinin görseli", "Bohr
        modelinin şeması" (gereksiz "şema/görsel/grafik/tablo" eki).
     KURAL: "grafiği", "şeması", "diyagramı", "modeli", "tablosu",
     "haritası", "yapısı", "formülü" gibi DECORATOR kelimeleri EKLEME —
     Wikipedia sayfaları çıplak terim adıyla açılır. ("Hayvan hücresi"
     evet, "Hayvan hücresi şeması" hayır.)
     KURAL: Türkçe Wikipedia'da olmayabilecek yerel ifadeler yerine
     ULUSLARARASI BİLİMSEL TERİMİ tercih et ("Faz diyagramı", "Newton
     yasaları"). Sistem bulamadığında otomatik olarak EN sayfasına da
     bakacak; bu yüzden terim hem TR hem EN Wikipedia'da var olan
     standart formda olmalı.
   • Sağ kısım (— sonrası): öğrenciye 1-2 cümlelik KISA + EĞİTİCİ caption;
     görselin neyi gösterdiğini, hangi parçaya odaklanılacağını söyle.

YERLEŞİM (KRİTİK):
Görsel etiketi, ilgili kavramın ANLATILDIĞI metin bloğunun HEMEN ALTINA
yerleştirilir — kavram tanımlandıktan/açıklandıktan sonraki ilk boş satıra.
ASLA ana başlığın hemen altına toplu liste olarak yazma; her görsel ait
olduğu kavramın yanında dursun.

DERS BAZLI MİNİMUM SAYI (kesin alt sınır — daha fazlası serbest):
• Biyoloji / Kimya / Fizik / Anatomi / Tıp → EN AZ 2 detaylı görsel.
  Hücre yapısı, organeller, atom modeli, periyodik tablo kesiti, deney
  düzeneği, devre şeması, dolaşım/sinir sistemi gibi yapı odaklı kısımlara
  öncelik ver.
• Coğrafya → EN AZ 3-4 görsel. Yer şekilleri (vadi, mendere, plato),
  iklim tipleri, harita kesitleri, atmosfer katmanları, levha hareketleri
  gibi farklı tiplerin her birini ayrı görselle göster.
• Tarih → EN AZ 2 görsel: dönem haritası (savaş/antlaşma/imparatorluk
  sınırları) + önemli şahsiyet portresi.
• Edebiyat / Felsefe / Sosyal → EN AZ 2 görsel: önemli şahsiyet/eser
  görseli + kavram haritası niteliğinde mind-map etiketi
  (Örn: [Görsel Betimlemesi: Tanzimat edebiyatı — Akım, temsilciler ve
   eserler arasındaki ilişki ağı]).
• Matematik (saf) → görsel zorunlu DEĞİL; geometri/fonksiyon grafikleri
  uygunsa 1 görsel ekle.
• Yabancı dil → görsel zorunlu DEĞİL.

FALLBACK (Wikipedia'dan görsel çekilemezse):
UI etiketin sağ kısmındaki açıklamayı "Diyagram Çerçevesi" placeholder
olarak gösterir. Bu yüzden caption KENDİ BAŞINA bilgi verecek kadar
TEKNİK ve net olmalı: "şu parça nerede, hangi renk, hangi etiket". Tek
satırlık jenerik açıklama yerine; "üstte X, altta Y, ortada Z" gibi
konumsal anlatım yaz.

NUMARALI / ETİKETLİ DİYAGRAMLAR (KRİTİK):
Wikipedia'dan gelen pek çok bilim diyagramı parçaları 1, 2, 3 ya da
A, B, C ile NUMARALANDIRMIŞ olur ama görselin üzerinde lejant
yoktur. Bu yüzden caption mutlaka numara/etiket → açıklama
eşlemesini içermeli ki kullanıcı her parçanın ne olduğunu bilsin.

Format (caption sonunda eşleme bloğu):
   [Görsel Betimlemesi: <kavram> — <kısa anlatım>; 1: <parça adı>,
    2: <parça adı>, 3: <parça adı>]

Örnek (hücre):
   [Görsel Betimlemesi: Hayvan hücresi — temel organellerin konumu;
    1: çekirdek, 2: mitokondri, 3: golgi aygıtı, 4: ribozom,
    5: hücre zarı, 6: endoplazmik retikulum]

Örnek (atom modeli):
   [Görsel Betimlemesi: Bohr atom modeli — elektron yörüngeleri ve
    çekirdek; 1: çekirdek (proton+nötron), 2: K kabuğu, 3: L kabuğu,
    4: M kabuğu]

Örnek (kalp anatomisi):
   [Görsel Betimlemesi: İnsan kalbi — odacıklar ve büyük damarlar;
    1: sağ kulakçık, 2: sağ karıncık, 3: sol kulakçık, 4: sol karıncık,
    5: aort, 6: pulmoner arter]

KURALLAR:
• Diyagram numara/harf etiketleri içeriyorsa caption SONUNA "; 1: …,
  2: …" formatında eşleme EKLE — atlamak YASAK.
• Eşleme satırı ders kitabındaki "Şekil X: lejant" karşılığıdır.
• Numara yerine A, B, C kullanılıyorsa aynı format: "A: …, B: …".
• Görselin "ne olduğu + ne işe yaradığı" caption'ın ilk yarısında
  net şekilde anlatılmalı; "Bohr modeli — elektron yörüngeleri ve
  çekirdeğin..." gibi.

ÖRNEKLER:
[Görsel Betimlemesi: Fotosentez — Yaprakta klorofil üzerinde güneş ışığı +
CO₂ + su → glikoz + O₂ reaksiyonu; girdiler solda, ürünler sağda]
[Görsel Betimlemesi: Vadi — Akarsu aşındırmasıyla oluşmuş "V" şekilli yer
şekli; tabanı dar, yamaçlar dik]
[Görsel Betimlemesi: Mitokondri — Çift zarlı organel; iç zarda kristalar,
matrikste ATP üretimi]
[Görsel Betimlemesi: Hayvan hücresi — Çekirdek ortada, ribozom serpiştirilmiş,
golgi sağda, mitokondri yanda]
[Görsel Betimlemesi: Periyodik tablo — Sol alkali metaller, sağ asal gazlar,
ortada geçiş metalleri; gruplar yukarıdan aşağı, periyotlar soldan sağa]

KESİN KURALLAR:
• Bir özet boyunca yukarıdaki minimum sayıya ULAŞ — "1 tane yeter" yok.
• Aynı kavramın görseli 2 kez tekrar EDİLMEZ.
• "Wikipedia'da aranabilir" kısmı NETLEŞTİR — "Türkiye'nin enlem boylamı"
  yerine "Enlem ve boylam" yaz.
• Bu satır metin akışını bozmaz; ANA BÖLÜM olarak yazma — Konu İşlenişi
  içine yedir.

SEVİYE OTOMASYONU:
Müfredat bağlamına bakıp terminolojiyi seviyeye uyarla:
• İlkokul/ortaokul → günlük analoji + basit cümle + sıfır jargon.
• Lise → uygun teknik terim + örnek + denklemler.
• Üniversite/sınav (YKS/KPSS/TUS vb.) → tam akademik dil + ileri formül +
  ince ayar tuzaklar.

[AKADEMİK EDİTÖR — KATI FORMAT PROTOKOLÜ]
Sen bir akademik editörsün. Aşağıdaki kurallar HARFİ HARFİNE uygulanır;
herhangi biri ihlal edilirse çıktı GEÇERSİZDİR.

0) SELAMLAMA / GİRİZGÂH YASAK (KRİTİK):
   • "Tabii ki", "Harika soru!", "Hemen başlayalım", "Şimdi seninle bu konuyu
     işleyelim", "Elbette", "Tabii", "Tabii ki!", "Bu konuyu sana açıklayacağım"
     gibi giriş cümleleri YAZMA. Doğrudan ilk başlıkla (📖 / 📚 / 🎯 / 📐 …) başla.
   • İlk satır MUTLAKA bir emoji başlığı olmalı — düz cümleyle başlatma.
   • Kapanışta "Umarım yardımcı olur", "Başka sorun varsa sor", "Özetle…" gibi
     veda paragrafı YOK. Son başlık biter, içerik orada kapanır.
   • Bu kural sebepsiz değil: sayfa ilk açıldığında AI girişi başlık alanını
     dolduruyor ve kullanıcı asıl içeriği görene kadar bekliyor. Doğrudan
     konuya gir.

1) GÖRSEL TEMİZLİK — HAM MARKDOWN YASAK:
   • Asla satır başında çıplak "#", "##", "###" yazma. Başlıkları sadece bu
     promptta tanımlı YAPI (📖, 📚, ▸ 1., 🟢 vb.) ile ver.
     Yanlış: "### Tanım"  /  Doğru: "📖 Tanım"
   • "**" sadece **anahtar terimleri** vurgulamak için kullan; süs olarak
     paragrafta serpiştirme. UI bold render eder; ancak fazla * → kirli görünür.
   • Tek "*" YASAK (italik render edilmiyor → metinde yıldız kalıyor).
     Vurgulamak istediğin kelime varsa **çift yıldız** kullan veya hiç kullanma.
   • "—" tek tireyle veya boşluksuz "-" KULLANMA; uzun tire (–) ya da
     "—" olarak boşluklu yaz: "Sembol — Tanım".
   • Satır başlarında "* maddeler" değil "• maddeler" kullan (kural format).

   ◆ RENKLİ KALEM ARAÇLARI (UI desteği — seçici kullan, "bazı yerlerde"):
     • SARI FOSFORLU KALEM (üstünü renkli yapma): ==metin==
       → UI sarı arka plan ile render eder. Sadece bir paragraftaki TEK BİR
         kritik anahtar kavramı ya da hatırlanması zorunlu kısa ifadeyi
         işaretle. Kart başına en fazla 1-2 kez.
       Örnek: Hücrede ==enerji üretimi== mitokondride gerçekleşir.
     • KIRMIZI ALTI ÇİZME KALEMİ: __metin__
       → UI kırmızı altı çizili render eder. Tanım ya da kuralın TAM
         karşılığı olan ifadeyi işaretle. Kart başına en fazla 1-2 kez.
       Örnek: Newton'un birinci yasası __eylemsizlik yasası__ olarak bilinir.
     • Bu iki marker İÇ İÇE GEÇMEZ (==__x__== gibi yazma).
     • Tüm cümleyi işaretleme; sadece kritik 1-3 kelimelik ifadeyi sar.
     • "**" (bold) ile karıştırma — bold = anahtar terim adı; == = vurgu;
       __ = tanım. Her birinin ayrı amacı var.

2) GELİŞMİŞ FORMÜL YAPISI — LATEX + SEMBOL TANIMLAMA ZORUNLU:
   • Tüm matematiksel/fiziksel/kimyasal formüller LaTeX içinde verilir.
   • SATIR İÇİ formül: \\( ... \\)  → "ivme \\( a = F/m \\) olarak yazılır"
   • BAĞIMSIZ formül: \\[ ... \\]  → her zaman AYRI bir satırda, önce/sonra
     boş satır bırakılarak. Birden fazla denklem aynı satıra YAZILMAZ.
   • Birim/sayı LaTeX dışında değil İÇİNDE: \\( a = 5\\,\\mathrm{m/s^2} \\)
   • Düz metin "E = mc^2" YASAK — \\( E = mc^2 \\) ya da \\[ E = mc^2 \\] olur.
   • Kimyasal denklemler de LaTeX: \\( C_6H_{12}O_6 + 6O_2 \\to 6CO_2 + 6H_2O \\)

   ◆ SEMBOL TANIMLAMA KURALI (KRİTİK — DERS DİSİPLİNİNDEN BAĞIMSIZ):
     Bir formül VEYA "şu şöyle hesaplanır" cümlesi yazıldıysa, AYNI BLOĞUN
     hemen ALTINA formülde geçen HER HARFİN/SEMBOLÜN ne anlama geldiğini
     "Burada:" başlığıyla bullet listele. Birim varsa onu da ekle.
     Bu fizik/kimya/matematik/biyoloji ayrımı OLMAKSIZIN her zaman zorunlu.

     Örnek (Fizik — Atom kütle numarası):
       \\[ A = Z + N \\]
       Burada:
       • \\( A \\) — Kütle numarası (toplam nükleon sayısı)
       • \\( Z \\) — Atom numarası (proton sayısı)
       • \\( N \\) — Nötron sayısı

     Örnek (Fizik — Newton 2. yasa):
       \\[ F = m \\cdot a \\]
       Burada:
       • \\( F \\) — Kuvvet, birimi Newton (\\( \\mathrm{N} \\))
       • \\( m \\) — Kütle, birimi kilogram (\\( \\mathrm{kg} \\))
       • \\( a \\) — İvme, birimi metre/saniye² (\\( \\mathrm{m/s^2} \\))

     Örnek (Kimya — mol hesabı):
       \\[ n = \\frac{m}{M} \\]
       Burada:
       • \\( n \\) — Mol sayısı (mol)
       • \\( m \\) — Madde kütlesi (g)
       • \\( M \\) — Molar kütle (g/mol)

     Örnek (Matematik — ikinci dereceden denklem kökleri):
       \\[ x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a} \\]
       Burada:
       • \\( a, b, c \\) — \\( ax^2 + bx + c = 0 \\) denkleminin katsayıları
       • \\( \\Delta = b^2 - 4ac \\) — Diskriminant
       • \\( x \\) — Denklemin kökleri

     Örnek (Biyoloji — popülasyon büyüme oranı):
       \\[ r = \\frac{B - D}{N} \\]
       Burada:
       • \\( r \\) — Birey başına büyüme oranı
       • \\( B \\) — Doğum sayısı (zaman aralığında)
       • \\( D \\) — Ölüm sayısı (zaman aralığında)
       • \\( N \\) — Popülasyon büyüklüğü

     KURALLAR:
     • "Burada:" sözcüğü AYNEN kullanılır (caption ipucu olarak UI'da arar).
     • Her sembol satırı: \\( SEMBOL \\) — açıklama (varsa birim parantez içinde).
     • Sembolde belirsizlik bırakma — "x bir sayı" YASAK; "x — denklemin kökü"
       gibi iş yükünü taşıyan tanım ver.
     • Sadece kavram-tanımı maddesinde formül yazıp altta tanım vermemek YASAK.
     • Aynı formül daha önce tanımlanmışsa (özette ikinci kez geçiyorsa)
       tekrar listeleme zorunlu değil — ilk geçişte tanımlı olsun yeter.

3) MANTIKSAL ÇÖZÜMLEME — ADIM 1 / ADIM 2 / ADIM 3 ZORUNLU:
   • Bir problem ya da çıkarım anlatırken sadece sonucu verme — **adımlandır**:
       Adım 1: [verilen / başlangıç durumu]
       Adım 2: [hangi yasa/kural/formül uygulandı + neden]
       Adım 3: [hesaplama veya çıkarım]
       Sonuç: [birim doğrulamasıyla birlikte]
   • Her adımda "neden" sorusunu da cevapla: "Newton'un 2. yasasını uyguluyoruz
     çünkü cisme net kuvvet etki ediyor." → bağlam olmadan adım atlama.
   • En az 1 örnek problem her sayısal konuda Adım 1-2-3 yapısıyla çözülür.
   • Sözel konularda "neden → nasıl → sonuç" zinciri aynı zorunluluk taşır.

4) ÇIKTI HEDEFİ — DERS KİTABI KALİTESİ:
   • Çıktı bir ders kitabı sayfasıdır: temiz, hiyerarşik, formülleri teknik
     olarak hatasız.
   • Boyut/birim hatası YASAK (\\( F = ma \\) için F→N, m→kg, a→m/s²).
   • Ondalık ayraç olarak Türkçe virgül LaTeX içinde "{,}" yazılır:
     \\( \\pi \\approx 3{,}14 \\). Düz metinde "3.14" değil "3,14".
   • Hiçbir bölümü "vb. detaylar..." gibi yarım bırakma; bilgi MUTLAKA
     somut sayı/yıl/isim/formülle desteklenir.

$protocolBlock
$richFormatBlock
GÖREVİN: Konuyu standart bir DERSHANE KİTABINDAKİ gibi işle. Önce kısa
tanım, ardından konuyu mantıksal ana başlıklara böl ve her ana başlığın
altında alt başlıkları/maddeleri ver — tıpkı bir ders kitabının
"konu işlenişi" sayfası gibi. Hedef: "Nihai Özet" kalitesi.

⚠️ ÇIKTI ZORUNLU OLARAK 4 BÖLÜMÜN HEPSİNİ İÇERİR (sırayla):
   1) 📖 Tanım
   2) 📚 Konu İşlenişi   ← ana başlıklar + alt maddeler (asla atlama)
   3) ${isNumeric ? '📐 Formül Galerisi + 🧪 Uygulama Örneği' : isVerbal ? '(Konu İşlenişi içine yedirilen detaylı sebep-sonuç akışı yeterli)' : '📐 Formül / Akış (varsa)'}
   4) ⭐ Özet — 5 Bilgi
HERHANGİ BİR BÖLÜM EKSİK OLURSA cevap GEÇERSİZDİR — özellikle "Konu
İşlenişi" sadece tanımdan sonra durup BİTİRME, mutlaka ana başlıklarla
devam et.

İlk satır "📖 Tanım" başlığı olmalıdır; öncesinde HİÇBİR selamlama
("Harika!", "Tabii ki", "Hemen başlayalım", "Bu konuyu inceleyelim") YOK.
Tanım satırından sonra DOĞRUDAN "📚 Konu İşlenişi" gelir, ardından diğer
bölümler — TÜM bölümler tamamlanana dek bitirme.

ÖZEL ÇERÇEVE YOK — "⚠️ KRİTİK UYARI / 🔬 QuAlsar Notu" diye AYRI bir bölüm
açma. Tuzak/istisna/uzman içgörüsü gerekiyorsa Konu İşlenişi içinde
"💡 Önemli Bilgi: ..." satırı olarak inline yedir (UI bunu kutuda gösterir).

YAPI (aşağıdaki başlıkları BİREBİR kullan — sırayla):

📖 Tanım
[TEK kısa cümle. Süsleme YOK, dolambaç YOK.]

📚 Konu İşlenişi
[Konunun doğal mantığına göre ${isNumeric ? '4-6' : '5-7'} ANA BAŞLIK belirle ve
 her ana başlığın altında ${isNumeric ? '4-7' : '5-8'} alt madde ver.
 Yapı, ders kitaplarındaki bir ünitenin DETAYLI işlenişi gibidir —
 yüzeysel kalmaz, ezberlenecek anahtar bilgileri spesifik isimler /
 yıllar / formüller / örneklerle besler.

   ▸ 1. {Konuyla uyumlu emoji} Başlık Adı
     • {emoji} **Anahtar Terim** — açıklama (tek cümle, somut bilgi)
     • {emoji} **Bir başka kavram** — yıl, isim, sayı veya formül içeren cümle
     • ...

   ▸ 2. {emoji} Başlık Adı
     • ...

 BAŞLIK FORMAT KURALLARI:
 • ANA BAŞLIK: "▸ N. {emoji} Başlık Adı" — N=1,2,3...; başlık önünde
   konuya uygun TEK emoji + Title Case başlık (sadece kelime başları
   büyük, TÜMÜ BÜYÜK YAZMA YASAK).
   Doğru: "▸ 1. 📍 Matematiksel ve Özel Konum"
          "▸ 2. ⛰️ Yeryüzü Şekilleri"
          "▸ 3. ⚔️ Savaşın Tarafları"
   Yanlış: "▸ 1. MATEMATIKSEL KONUM" / "▸ 1. matematiksel konum"
 • ALT MADDE: 2 boşluk girinti + "• {emoji} **Anahtar terim** — açıklama"
   - Anahtar terim **çift yıldız** ile (UI bold render eder).
   - Açıklamada SOMUT bilgi: yıl, sayı, isim, yer, formül, birim.
   - Tek cümle (8-22 kelime arası — yüzeysel değil, dolu olsun).

 ZENGİNLEŞTİRİCİ ÖGELER — TEMBELLİK YASAK, gerektiğinde MUTLAKA kullan:

 ▶ TABLO (KARŞILAŞTIRMA/SINIFLAMA İÇİN ZORUNLU):
   • Aşağıdaki durumlarda MUTLAKA Markdown tablosu kullan:
     - 2+ kavramın özelliklerini karşılaştırırken (Asit vs Baz, mitoz vs mayoz)
     - Sınıflandırma yaparken (canlı sınıflandırması, akım/dönem/temsilciler)
     - Formül-birim-değer eşleşmeleri (her satır: sembol | tanım | birim)
     - Tarihsel olaylar (yıl | olay | sonuç sütunları)
     - Bileşik özellikleri (renk, çözünürlük, pH vb.)
   • 2-4 sütun, 3-8 satır. İlk sütun KALIN (anahtar).
   • Tablo başlığı çok değerli olduğunda 1 cümle bağlam ver, sonra tablo.

 ▶ RENK KODLU SEKSİYON ROZETLERİ (her ana başlıkta TEK rozet):
   🔵 = TANIM/KAVRAM      — yeni bilgi tanıtımı
   🟢 = FORMÜL/KURAL       — sayısal ilişki, fizik yasası
   🟡 = ÖRNEK/UYGULAMA     — somut örnek, problem
   🟣 = TARİH/AKIM         — kronoloji, dönemsel bilgi
   🔴 = TUZAK/UYARI        — sınavda hata yaptıran ince nokta
   🟠 = SEBEP-SONUÇ        — neden→nasıl→sonuç zinciri
   ⚪ = İSTİSNA/UÇ DURUM   — kuralın geçersiz olduğu hâl
   Örn: "▸ 3. 🟢 Newton'un 2. Yasası" — F=ma'yı işliyorsa 🟢
        "▸ 4. 🔴 Sınav Tuzakları" — sık yapılan hatalar 🔴

 ▶ PEDAGOJİK İÇGÖRÜ MARKER'LARI (inline, paragraf ortasında):
   💡 Önemli Bilgi: ...     → vurgulu kutu (uzman içgörüsü)
   🎓 Püf Nokta: ...         → öğrencinin atlayacağı kritik detay
   ⚡ Kısa Yol: ...          → sınavda zaman kazandıran shortcut
   📦 Hatırlatma: ...        → mavi çerçeveli inline not
   🧠 Şöyle Düşün: ...       → mantık temelini sezgisel açıklama
   🔍 Dikkat: ...            → çeldirici / yanıltıcı seçenek uyarısı
   Hepsi tek satır + bir tane "..." içerikle. Birden fazla marker'ı
   üst üste KULLANMA — bilgi seyreltme yapar.

 ▶ ŞEKİL/GRAFİK/DİYAGRAM BETİMLEMESİ:
   Konuda diyagram, grafik, harita, moleküler yapı, devre vb. kavramsal
   şema varsa, parça parça METİNLE betimle:
     • Eksenler (x: zaman, y: hız)
     • Etiketler (her noktada ne yazıyor)
     • Renkli alanlar (mavi: katı, yeşil: gaz)
     • Hangi parça ne işe yarar
   Sadece "şu grafikte görülür" deyip GEÇME.

 ▶ AKIŞ ŞEMASI (süreç/aşama için):
   "Adım 1 → Adım 2 → Adım 3 → Sonuç" oklu zincir.
   Karmaşık süreçlerde dallanma:
     Reaktif → [hız belirleyen] → Aktif kompleks → Ürün
                                     ↓
                                 [yan ürün]

 ${isNumeric ? 'SAYISAL ÖZEL: Her ana başlıkta mümkünse 1 formül kutusu \\\\[ ... \\\\] '
        've altında "🧪 Uygulama Örneği:" ile 2-4 adımlık mini çözüm. Sembol+birim eksiksiz.' : ''}
 ${isVerbal ? 'SÖZEL ÖZEL: Tarih kronolojik akış (yıl→yıl); edebiyat dönem→akım→'
        'temsilci→eser→özellik silsilesi; felsefe kavram→argüman→eleştiri. '
        'Her ana başlıkta en az 1 spesifik tarih/yer/isim geçsin.' : ''}
 ${!isNumeric && !isVerbal ? 'KARMA: yapıyı konuya göre seç.' : ''}

 KAPSAM: Yüzeysel listeleme YASAK. Bir öğrenci bu özeti okuduğunda
 KONUYU TAMAMEN öğrenmiş olmalı; başka kaynağa ihtiyaç DUYMAMALI.]

$formulasBlock

⭐ Özet — 5 Bilgi
[Konunun en önemli 5 bilgisini DOĞRUDAN bilgi cümlesi olarak ver.
 META YORUM YASAK: "bunu bilmen önemli", "sınavda işine yarar",
 "akılda tut" gibi cümleler yazma. Sadece bilgi.

 Format — her satır başında BİLGİ TÜRÜNE GÖRE ikon, sonra DOĞRUDAN bilgi:
   🔑 = anahtar tanım/kavram
   📐 = formül/sayısal değer
   📅 = tarih/kronoloji
   🧬 = bilimsel olgu/yasa
   ⚖️ = ilke/kural
   🎯 = sınav-kritik bilgi
   🌍 = bağlam/yer/coğrafya

 Örnekler (her madde tek cümle, 8-20 kelime):
   📐 **Pisagor:** \\( a^2 + b^2 = c^2 \\), dik üçgenin hipotenüs ilişkisi.
   🧬 **DNA** çift sarmal yapıdadır; iki zincir antiparalel uzanır.
   📅 **Lozan Antlaşması** 24 Temmuz 1923'te imzalandı, 18 maddedir.
   ⚖️ **Newton'un 3. Yasası:** her etkiye eşit ve zıt bir tepki vardır.
   🎯 **YKS Tuzağı:** Mol kavramında Avogadro sayısı 6,022×10²³ — bunu unutma.

 ${isNumeric ? 'Sayısal: formül / sayısal değer / sembol + birim; mümkünse LaTeX kutu.' : ''}
 ${isVerbal ? 'Sözel: yıl / yazar-eser / kavram-tanım / sebep-sonuç çekirdeği.' : ''}
 TAM 5 madde, ne eksik ne fazla. İkonlar ÇEŞİTLİ olsun — hepsi 🔑 olmasın.
 Sonrasına SADECE 📝 Konuyu Pekiştirme Soruları bölümü gelir; başka kapanış
 paragrafı, "Sonuç:", "📌 Özetle" YOK.
 KRİTİK: ⭐ Özet — 5 Bilgi bölümünün İÇİNE soru EKLEME. Sorular bu
 bölümden TAMAMEN AYRI, AŞAĞIDAKİ "📝 Konuyu Pekiştirme Soruları" başlığı
 altında yer alır.]

📝 Konuyu Pekiştirme Soruları
[Özetin EN SONUNDA, "⭐ Özet — 5 Bilgi" çerçevesinin TAMAMINDAN SONRA gelen
 AYRI bir bölüm. TAM 3 ÇOKTAN SEÇMELİ soru + her sorunun altında AÇIKLAMALI
 ÇÖZÜM ver.

 ŞIK SAYISI (öğrenci eğitim seviyesine göre — KESİN, TARTIŞMASIZ):
 ➤ Bu öğrenci için zorunlu şık sayısı: $choiceCount şık ($choiceLetters)
 ➤ Her sorunun TAM $choiceCount şıkkı olacak — eksik veya fazla şık YASAK.

 FORMAT — her soru için BU YAPI birebir uygulanır:

   **Soru 1:** [Soru metni — net ve tek anlamlı, $exam tarzında]
   A) [Şık 1]
   B) [Şık 2]
   C) [Şık 3]${choiceCount >= 4 ? '\n   D) [Şık 4]' : ''}${choiceCount >= 5 ? '\n   E) [Şık 5]' : ''}

   **Çözüm:** [2-4 cümlelik AÇIKLAMA — neden doğru cevap doğru, hangi
   kavram/formül/kural devrede, çeldiriciler neden yanlış. Sadece
   "Cevap: B" YAZMA — öğrenci anlamalı.]
   **Cevap:** [Doğru şık harfi]

   **Soru 2:** ...
   (aynı format, şık sayısı $choiceCount)

   **Soru 3:** ...
   (aynı format, şık sayısı $choiceCount)

 ÖRNEK (5 şıklı, lise+ için):
   **Soru 1:** Newton'un 2. yasasına göre, kütlesi 4 kg olan bir cisme
   12 N kuvvet uygulanırsa ivmesi kaç m/s² olur?
   A) 0,33   B) 2   C) 3   D) 4   E) 48

   **Çözüm:** \\( F = m \\cdot a \\) formülünden \\( a = F/m \\) çıkar.
   \\( a = 12\\,\\mathrm{N} / 4\\,\\mathrm{kg} = 3\\,\\mathrm{m/s^2} \\).
   Birim doğrulaması: N/kg = m/s² ✓. A şıkkı (0,33) m·F yerine F·m
   bölünmesi tuzağıdır; E (48) ise F·m hatasıdır.
   **Cevap:** C

 ÖRNEK (3 şıklı, ilkokul için):
   **Soru 1:** Aşağıdakilerden hangisi katı maddedir?
   A) Su   B) Buz   C) Hava

   **Çözüm:** Maddenin halleri: katı, sıvı, gaz. Su sıvıdır, hava gazdır.
   Buz ise donmuş su olduğu için katıdır — belirli şekli ve hacmi vardır.
   **Cevap:** B

 KURALLAR (BOZARSAN ÇIKTI GEÇERSİZDİR):
 • TAM 3 soru — ne eksik ne fazla.
 • Her soruda TAM $choiceCount şık ($choiceLetters) — atlamak veya fazla
   eklemek YASAK. Tüm sorular aynı şık sayısına sahip olmalı.
 • Sorular FARKLI kavramlardan — aynı bilgiyi 3 kez sorma.
 • Çeldiriciler MAKUL ve YAYGIN HATA tipinde — "Atatürk uzaylıdır" gibi
   absürt çeldirici YASAK.
 • Çözüm satırı ZORUNLU — sadece "Cevap: B" yazıp geçme. Çözüm 2-4
   cümle, NEDEN doğrunun doğru olduğunu açıkla; gerekirse formül/yıl/kural
   referansla. Sayısal sorularda HESAP ADIMINI göster.
 • LaTeX formüller \\( ... \\) ya da \\[ ... \\] içinde.
 • Bu bölüm "⭐ Özet — 5 Bilgi" çerçevesinin İÇİNDE DEĞİL, ONDAN SONRA
   ayrı bir başlık olarak gelir. Karıştırma.
 • Bu çıktının SON bölümüdür — sonrasına hiçbir şey yazma.]

═══════════════════════════════════════════════════════
KATI KURALLAR (bozarsan cevap geçersiz):
• ÇIKTI "📖 Tanım" satırıyla BAŞLAR. Öncesinde tek kelime selamlama,
  "Harika", "Tabii", "Hemen başlayalım", "Bu konuya bakalım" YASAK.
• "📚 Konu İşlenişi" bölümünde ana başlık → alt madde hiyerarşisi ZORUNLU.
• ⭐ Özet bölümünde "bunu bilmen önemli", "sınavda çıkar", "akılda tut" gibi
  meta yorum YASAK — sadece doğrudan bilgi cümleleri.
• Markdown bold (**metin**) SERBEST — UI bold render eder; sadece
  anahtar terimleri vurgulamak için kullan, paragraf süslemesi YOK.
• Markdown italic tek yıldız (*metin*) KULLANMA.
• Markdown başlık işareti (#) kullanma; tablo Markdown'u serbest.
• DOLAR işareti (\$) çıktıda HİÇ olmayacak.
  LaTeX için SADECE \\( ... \\) ve \\[ ... \\] kullan.
• Konu adını başlık olarak tekrar etme.
• "⚠️ KRİTİK UYARI / 🔬 QuAlsar Notu" diye AYRI BAŞLIK AÇMA — yasak.
  Tuzak/istisna/içgörü için sadece inline "💡 Önemli Bilgi: …" kullan.
• ⭐ Özet — 5 Bilgi bölümü ZORUNLU — tam 5 madde, 🔑 başlı.
  ÖNEMLİ: Bu bölümün İÇİNE SORU/ÇOKTAN SEÇMELİ test EKLEME — sadece
  bilgi cümleleri. Sorular AYRI ve SONRAKİ bölümdedir.
• 📝 Konuyu Pekiştirme Soruları bölümü ZORUNLU — ⭐ bölümünün hemen
  ardından AYRI bir başlık olarak; tam 3 çoktan seçmeli soru, her birinde
  $choiceCount şık ($choiceLetters), çözüm + cevap. Çıktının SON
  bölümüdür; sonrasına hiçbir şey yazma.
• "📌 Özetle" / kapanış paragrafı / "Sonuç:" YASAK — ekleme.
• Toplam uzunluk ${isVerbal ? '70-110' : '60-95'} satır — derinlikli Nihai Özet, dolgu yok.
• Türkçe yaz. $exam mantığına uygun, ders kitabı işlenişine sadık.
• YouTube/Web/kaynak önerisi EKLEME. [VIDEO:] ve [WEB:] yok.
${isNumeric ? '• Her sayısal tanımda sembol + BİRİM birlikte verilsin (boyut analizi).' : ''}
${isVerbal ? '• Tarihte yıl, edebiyatta yazar/eser/dönem, felsefede filozof/akım adı eksiksiz.' : ''}
''';
  }

  // Markdown yıldızlarını temizle + giriş paragrafını kırp
  String _stripMarkdown(String s) {
    // **bold** KORUNUR (UI inline bold render eder).
    // Sadece tek-yıldız italic ve markdown başlıkları temizlenir.
    var out = s.replaceAllMapped(
      RegExp(r'(?<![\\\w*])\*([^*\n]+)\*(?!\w|\*)'),
      (m) => m.group(1) ?? '',
    );
    out = out
        .replaceAll('###', '')
        .replaceAll('##', '')
        .replaceAll('# ', '');
    // AI giriş cümlesi yazmışsa "📖 Tanım" / "📚" gibi ilk başlık satırından
    // önceki giriş paragrafını kırp.
    final firstHeader = RegExp(
      r'(📖[^\n]*|📚[^\n]*|🎯[^\n]*|📐[^\n]*|🌊[^\n]*|⭐[^\n]*|📌[^\n]*)',
    );
    final m = firstHeader.firstMatch(out);
    if (m != null && m.start > 0) {
      out = out.substring(m.start);
    }
    return out.trimLeft();
  }

  Future<void> _deleteSubject(_Subject s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${s.name} — ${localeService.tr('delete_subject_confirm')}'),
        content: Text(localeService.tr('delete_subject_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localeService.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(localeService.tr('delete'), style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _subjects.removeWhere((x) => x.id == s.id));
      await _persistSubjects();
    }
  }

  void _openSummary(_Summary s, String subjectName) {
    // Summary mode → özet detayı. Questions mode burada çağrılmaz;
    // o akışta ya _openTestAttempt ya da _openCompletedAttempt kullanılır.
    if (widget.mode == LibraryMode.questions) {
      // Geriye dönük uyumluluk: eski kod yolu. İlk tamamlanmamış attempt'i aç.
      final attempt = s.tests.firstWhere(
        (t) => !t.completed,
        orElse: () => s.tests.isNotEmpty
            ? s.tests.first
            : _TestAttempt(
                id: s.id,
                content: s.content,
                answers: {},
                completed: false,
                createdAt: s.createdAt,
              ),
      );
      if (attempt.completed) {
        _openCompletedAttempt(s, attempt, subjectName);
      } else {
        _openTestAttempt(s, attempt, subjectName);
      }
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _SummaryDetailPage(
          summary: s,
          subjectName: subjectName,
        ),
      ));
    }
  }

  // Yeni ya da devam ettirilen bir test açar. Bitince answers + completed
  // alanlarını saklar.
  void _openTestAttempt(
      _Summary summary, _TestAttempt attempt, String subjectName) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TestPage(
        rawContent: attempt.content,
        subjectName: subjectName,
        topic: summary.topic,
        initialAnswers: attempt.answers,
        // Önceki oturumdan kalan timer state — çıkış-giriş cheese'i kapatır.
        initialPerQuestionRemaining: attempt.perQuestionRemaining.isEmpty
            ? null
            : Map<int, int>.from(attempt.perQuestionRemaining),
        timeLimit: attempt.timeLimit,
        // Cevap / timer değiştiğinde partial save — uygulama crash, çıkış,
        // arka plana atma senaryolarında son durum kaybolmasın.
        onAnswerChanged: (answers, remaining) async {
          attempt.answers = Map<int, String?>.from(answers);
          attempt.perQuestionRemaining = Map<int, int>.from(remaining);
          await _persistSubjects();
        },
        onFinish: (answers) async {
          attempt.answers = Map<int, String?>.from(answers);
          attempt.completed = true;
          // Tamamlandı → timer state'in artık önemi yok, temizle.
          attempt.perQuestionRemaining.clear();
          await _persistSubjects();
          if (mounted) setState(() {});
        },
      ),
    )).then((_) {
      if (mounted) setState(() {});
    });
  }

  // Tamamlanmış bir testin sonuç + çözüm ekranını açar.
  void _openCompletedAttempt(
      _Summary summary, _TestAttempt attempt, String subjectName) {
    final questions = parseTestQuestions(attempt.content);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TestResultPage(
        questions: questions,
        answers: attempt.answers,
        subjectName: subjectName,
        topic: summary.topic,
      ),
    ));
  }

  void _openSubject(_Subject s) {
    Navigator.of(context)
        .push<String>(MaterialPageRoute(
          builder: (_) => _SubjectDetailPage(
            subject: s,
            mode: widget.mode,
            // Planner'da bu ders kartı renklendirilmişse, açılan sayfa da
            // aynı zemin rengiyle başlasın — kayıtlı renk kalıcı kabul edilir.
            pageBg: _summaryCardColors[s.id],
            onAddTopic: (topic) =>
                _generateForExistingSubject(s, topic),
            onDelete: (sum) async {
              s.summaries.removeWhere((x) => x.id == sum.id);
              await _persistSubjects();
              if (mounted) setState(() {});
            },
            onAddAttempt: (summary, cfg) =>
                _generateAttemptForSummary(s, summary, config: cfg),
            onOpenAttempt: (summary, attempt) {
              if (attempt.completed) {
                _openCompletedAttempt(summary, attempt, s.name);
              } else {
                _openTestAttempt(summary, attempt, s.name);
              }
            },
          ),
        ))
        .then((result) {
      if (!mounted) return;
      setState(() {});
      // FAB'e basıldıysa `_openSubjectTopics` sinyali gelir → bu dersin
      // konular dialogunu aç (yeni konu seçmek için).
      if (result == '_openSubjectTopics') {
        final edu = _inlineEduSubjects.firstWhere(
          (e) => e.name.toLowerCase() == s.name.toLowerCase(),
          orElse: () => EduSubject(s.id, '📚', s.name, _blue),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openSubjectTopicsDialog(edu: edu);
        });
      }
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // Hata mesajı + Tekrar Dene aksiyonu olan snack — AI çağrıları için.
  // En fazla 5 saniye ekranda kalır, sonra otomatik kaybolur.
  void _showRetrySnack(String msg, VoidCallback onRetry) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 5),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(
        label: 'Tekrar Dene'.tr(),
        textColor: Color(0xFFFFB74D),
        onPressed: onRetry,
      ),
    ));
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Root Stack: loader çıkınca AppBar + sayfayı komple kapatsın.
    // Arka plan varsayılanı — kullanıcı palet üzerinden override edebilir.
    final pageBg = AppPalette.resolvePageBg(context, _pageBgOverride);
    return Stack(
      children: [
        Scaffold(
          backgroundColor: pageBg,
          appBar: AppBar(
            backgroundColor: pageBg,
            elevation: 0,
            foregroundColor: AppPalette.textPrimary(context),
            // Sayfa başlığı kaldırıldı; sadece sağdaki Renk Seç + (?) kalır.
            titleSpacing: 0,
            title: const SizedBox.shrink(),
            actions: [
              // Renkli "🎨 Renk Seç" pill — sağ üstte belirgin.
              Padding(
                padding: const EdgeInsets.only(
                    top: 8, bottom: 8, left: 12, right: 6),
                child: GestureDetector(
                  onTap: () => setState(
                      () => _showColorPicker = !_showColorPicker),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFF6A00), // turuncu
                          Color(0xFFDB2777), // pembe
                          Color(0xFF7C3AED), // mor
                          Color(0xFF2563EB), // mavi
                        ],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showColorPicker
                              ? Icons.close_rounded
                              : Icons.palette_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          _showColorPicker
                              ? 'Kapat'.tr()
                              : 'Renk Seç'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Aile/Ebeveyn butonu Profil sayfasına taşındı.
              // Sayfa rehberi (?) — Renk Seç pill'inin sağında, aynı hizada.
              Padding(
                padding: const EdgeInsets.only(
                    top: 8, bottom: 8, left: 0, right: 12),
                child: Center(child: _buildHelpButton()),
              ),
            ],
          ),
          body: Column(
            children: [
              if (_showColorPicker) _buildColorPickerPanel(),
              Expanded(
                child: DragTarget<Color>(
                  onAcceptWithDetails: (d) =>
                      setState(() => _pageBgOverride = d.data),
                  builder: (ctx, cand, rej) => SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: _buildInlineAddPanel(),
                ),
                if (_subjects.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildCardsRow(),
                  ),
                SizedBox(height: 22),
              ],
            ),
                  ),
                ),
              ),
              ],
            ),
          ),
        // "Diğer Dersler" overlay sheet — modal değil, üstteki ders
        // grid'i tıklanabilir kalır (sürükle-bırak için).
        if (_showOtherSheet) _buildOtherSheetOverlay(),
        // Loader her şeyin üstünde — AppBar + body'yi tamamen kaplar.
        // Sağ üstte "İptal" butonu: kullanıcı bekleme süresinden vazgeçerse
        // arka plan isteği devam eder ama sonuç yutulur + kota iade edilir.
        if (_generating)
          Positioned.fill(
            child: Material(
              color: AppPalette.card(context),
              child: Stack(
                children: [
                  QuAlsarLoadingWidget(
                    type: widget.mode == LibraryMode.questions
                        ? QuAlsarLoadingType.test
                        : QuAlsarLoadingType.summary,
                    topic: _generatingTopic,
                    domain: _generatingDomain,
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: GestureDetector(
                          onTap: _generatingCancelled
                              ? null
                              : () {
                                  setState(() {
                                    _generatingCancelled = true;
                                  });
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: _generatingCancelled
                                  ? Color(0x33808080)
                                  : Colors.black,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.close_rounded,
                                    size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  _generatingCancelled
                                      ? 'İptal ediliyor…'.tr()
                                      : 'İptal'.tr(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCardsRow() {
    // Her dersin kendi mini "sayfası" var — başlığın altında o dersin TÜM
    // konu özetleri/testleri listelenir. Sayfalar 3 sütunda Wrap ile dizilir;
    // 4+ ders olduğunda alt satıra (soldan başlayarak) sarar.
    final shown = _subjects.where((s) => s.summaries.isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        const cols = _cardSlots; // 3
        const spacing = 10.0;
        final cellWidth =
            (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final s in shown)
              SizedBox(
                width: cellWidth,
                child: _subjectPageTile(s),
              ),
          ],
        );
      },
    );
  }

  // Bir dersin "sayfası" — başlık + alt alta tüm konu özetleri (testler).
  // Çerçeve SABİT BOYUT: yatay 3 / dikey 5 oran (aspectRatio = 0.6) — kaç
  // konu olursa olsun tüm sayfalar aynı görünür; içerik fazlaysa konu
  // listesi tile içinde dikey kaydırılır.
  Widget _subjectPageTile(_Subject s) {
    final isQuestions = widget.mode == LibraryMode.questions;
    final custom = _summaryCardColors[s.id];
    final bg = AppPalette.resolveInnerBg(context, custom);
    final lum = (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b);
    final isDark = lum < 0.55;
    final ink = isDark ? Colors.white : Colors.black;
    final inkMute = isDark ? Colors.white70 : Colors.black54;
    final divider = isDark ? Colors.white24 : Colors.black12;
    return DragTarget<Color>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) =>
          _applyColorToSummaryCard(s.id, d.data),
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        return AspectRatio(
          aspectRatio: 3 / 5, // yatay 3 : dikey 5
          child: AnimatedContainer(
            duration: Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hovering ? _orange : Colors.black12,
                width: hovering ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            // TÜM tile tıklanabilir — header'a, divider'a, boş alana
            // basılınca dersin liste detay sayfası açılır. Konu satırları
            // kendi InkWell'lerini taşıdığı için inner tap onlara gider.
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openSubject(s),
                onLongPress: () => _deleteSubject(s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: ink,
                                height: 1.1,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 16,
                              color: ink.withValues(alpha: 0.55)),
                        ],
                      ),
                    ),
                    Container(height: 1, color: divider),
                    // ── Konu özetleri listesi — kalan alanı doldurur, fazla
                    //    içerik kaydırılabilir. Tile her zaman aynı boyut.
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        physics: ClampingScrollPhysics(),
                        children: [
                          for (final sum in s.summaries)
                            _topicSummaryRow(
                                s, sum, isQuestions, ink, inkMute),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Tek bir konu satırı — özet adına bas → o özet açılır
  // (test modunda son denemeyi açar). Uzun bas → o özeti sil.
  Widget _topicSummaryRow(
    _Subject s,
    _Summary sum,
    bool isQuestions,
    Color ink,
    Color inkMute,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (isQuestions) {
            // Son attempt'ı aç — _openSummary mantığı zaten bu fallback'i yapıyor
            _openSummary(sum, s.name);
          } else {
            _openSummary(sum, s.name);
          }
        },
        onLongPress: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(sum.topic,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
              content: Text(
                isQuestions
                    ? 'Bu test setini silmek ister misin?'.tr()
                    : 'Bu özeti silmek ister misin?'.tr(),
                style: GoogleFonts.poppins(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('İptal'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text('Sil'.tr(),
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (ok != true || !mounted) return;
          setState(() {
            s.summaries.removeWhere((x) => x.id == sum.id);
          });
          await _persistSubjects();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 4),
                child: Text(
                  '•',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  sum.topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: inkMute,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══ Ebeveyn Gelişim Raporu — basit matematik doğrulamasıyla açılır.
  //   "8 x 7 kaçtır?" gibi 4-9 arası iki sayının çarpımını sorar; doğru
  //   cevap girilirse ParentReportPage push edilir. Öğrencinin raporları
  //   manipüle etmesini engellemek için ufak bir engel.
  Future<void> _openParentReport() async {
    final ok = await askParentGate(context);
    if (!ok || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ParentReportPage(),
    ));
  }

  // ═══ Sayfa rehberi (?) — Renk Seç pill'inin altında küçük yuvarlak buton.
  //   Basınca sayfanın nasıl çalıştığını anlatan dialog açılır.
  Widget _buildHelpButton() {
    return Material(color: AppPalette.card(context),
      shape: CircleBorder(),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        customBorder: CircleBorder(),
        onTap: _showHelpDialog,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppPalette.textPrimary(context), width: 1),
          ),
          child: Icon(
            Icons.question_mark_rounded,
            size: 16,
            color: AppPalette.textPrimary(context),
          ),
        ),
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    final isQuestions = widget.mode == LibraryMode.questions;
    final pageLabel = isQuestions
        ? 'Sınav Soruları'.tr()
        : 'Konu Özetleri'.tr();
    final outputWord = isQuestions ? 'test sorularını' : 'özetini';
    final limitLine = isQuestions
        ? 'Her dersin her konusu için en fazla 3 test hakkın var. 3. denemen bittikten sonra aynı konudan yeni test üretemezsin; başka bir konu seçebilirsin.'
        : 'Bir ay içinde aynı dersten en fazla 4 konu özeti çıkarabilirsin. Limit dolduğunda bekle, yeni ay başında sayaç sıfırlanır. İstediğin kadar farklı dersle çalışabilirsin — toplam ders sayısı sınırsız.';
    final steps = <(String, String, String)>[
      (
        '1',
        'Ders seç'.tr(),
        'Üstteki çerçevede tüm derslerin listelenir. Bir derse basarak o dersin müfredat konuları açılır. İstediğin dersten ${outputWord.replaceAll('ını', 'ı')} çıkarabilirsin — ders sayısı limitsiz.'
            .tr(),
      ),
      (
        '2',
        'Dersleri sıralarken sürükle-bırak'.tr(),
        'Bir derse PARMAĞINI BASILI TUT, sürükleyip başka bir dersin üzerine bırak — iki dersin yeri yer değiştirir. Sıralaman cihazına kayıtlı kalır.'
            .tr(),
      ),
      (
        '3',
        'Konu seç veya kendin yaz'.tr(),
        'Açılan ekranda müfredat konuları listelenir. Bir konuya basınca AI o konunun ${isQuestions ? "test sorularını" : "özetini"} oluşturur. Konu listede yoksa, alttaki "Yeni Konu Ekle" alanına başlığı yazıp Kaydet\'e bas — kendi konunun $outputWord aynı kalitede üretilir.'
            .tr(),
      ),
      (
        '4',
        '${isQuestions ? "Test" : "Özet"} kütüphanen — her dersin kendi sayfası'.tr(),
        '${isQuestions ? "Test soruları" : "Özet"} oluşturduğun her ders, sayfanın altında KENDİ MİNİ SAYFASINI alır. Sayfalar 3\'lü grid hâlinde dizilir; 4. dersi eklediğinde yeni satıra (soldan başlayarak) sarar. Her sayfada ders adının altında o derse ait TÜM ${isQuestions ? "test denemeleri" : "konu özetleri"} alt alta listelenir. Bir konuya basınca doğrudan o ${isQuestions ? "test denemesine" : "özete"} gidersin; ders başlığına basarsan tüm liste detayını açan ders sayfasına ulaşırsın.'
            .tr(),
      ),
      (
        '5',
        'Aylık limit'.tr(),
        limitLine.tr(),
      ),
      (
        '6',
        'Renk Seç paleti — sayfayı kişiselleştir'.tr(),
        'Sağ üstteki renkli "Renk Seç" pill\'ine bas — palet açılır. 3 hedef arasından seç (Arka plan / Çerçeve / Ders alanı) ve modu belirle (Yazı rengi mi, Çerçeve/zemin rengi mi). Sonra paletten bir rengi PARMAĞINLA SÜRÜKLEYİP istediğin alana bırak — anında uygulanır. Tek bir ders sayfasına ya da manuel ders çerçevesine renk sürükleyerek özel renk de verebilirsin.'
            .tr(),
      ),
      (
        '7',
        'Uzun basma kısayolları'.tr(),
        'Bir ders sayfasının BAŞLIĞINA uzun bas → o dersi tamamen silebilirsin. Sayfa içindeki bir ${isQuestions ? "test" : "özet"} satırına uzun bas → o ${isQuestions ? "testi" : "özeti"} silme onayı çıkar. Kendi eklediğin özel bir derse (üstteki ders ızgarasında) uzun bas → dersi listeden kaldırabilirsin.'
            .tr(),
      ),
      if (!isQuestions)
        (
          '8',
          'Özet ekranını da renklendirebilirsin'.tr(),
          'Bir özete girince, içerideki ekran da kendi renk paletine sahip — başlık çerçevesi, kart zemini ve yazı rengini bağımsız değiştirebilirsin. Her özet kendi ayarlarını saklar.'
              .tr(),
        ),
    ];
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.card(context),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppPalette.textPrimary(context), width: 1),
                      ),
                      child: Icon(
                        Icons.question_mark_rounded,
                        size: 18,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$pageLabel — ${'Bu sayfa nasıl çalışır?'.tr()}',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ),
                    Material(color: AppPalette.card(context),
                      shape: CircleBorder(),
                      child: InkWell(
                        customBorder: CircleBorder(),
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded,
                              size: 18, color: Colors.black54),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Container(height: 1, color: Colors.black12),
                SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < steps.length; i++) ...[
                          if (i > 0) SizedBox(height: 12),
                          _helpStep(steps[i].$1, steps[i].$2, steps[i].$3),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppPalette.textPrimary(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Anladım'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _helpStep(String n, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppPalette.textPrimary(context),
          ),
          child: Text(
            n,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              SizedBox(height: 2),
              Text(
                body,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppPalette.textPrimary(context),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _unusedQuestionsSubjectSection(_Subject subject) {
    final customBg = _summaryCardColors[subject.id];
    final bg = AppPalette.resolveInnerBg(context, customBg);
    final lum = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    final ink = lum < 0.55 ? Colors.white : Colors.black;
    final allAttempts = <_AttemptRef>[];
    for (final sum in subject.summaries) {
      for (var i = 0; i < sum.tests.length; i++) {
        allAttempts.add(_AttemptRef(
          summary: sum,
          attempt: sum.tests[i],
          attemptIndex: i + 1,
        ));
      }
    }
    allAttempts.sort((a, b) =>
        b.attempt.createdAt.compareTo(a.attempt.createdAt));
    return DragTarget<Color>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) =>
          _applyColorToSummaryCard(subject.id, d.data),
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        return AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hovering ? _orange : Colors.black,
              width: hovering ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık — ders ismi
              Row(
                children: [
                  Expanded(
                    child: Text(
                      subject.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: ink,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                  Text(
                    '${allAttempts.length} ${'test'.tr()}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ink.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Container(height: 1, color: ink.withValues(alpha: 0.2)),
              SizedBox(height: 8),
              for (final ref in allAttempts)
                _unusedTestAttemptRow(subject, ref, ink),
            ],
          ),
        );
      },
    );
  }

  Widget _unusedTestAttemptRow(
      _Subject subject, _AttemptRef ref, Color ink) {
    final attempt = ref.attempt;
    final completed = attempt.completed;
    // Skor hesabı — tamamlandıysa parse et.
    String statusText;
    Color statusColor;
    if (completed) {
      try {
        final questions = parseTestQuestions(attempt.content);
        if (questions.isEmpty) {
          statusText = 'Tamamlandı'.tr();
          statusColor = Color(0xFF10B981);
        } else {
          var correct = 0;
          for (var i = 0; i < questions.length; i++) {
            final userAns = attempt.answers[i];
            if (userAns != null &&
                userAns.toUpperCase() == questions[i].ans) {
              correct++;
            }
          }
          final pct = (correct / questions.length * 100).round();
          statusText = '%$pct';
          statusColor = pct >= 70
              ? Color(0xFF10B981)
              : pct >= 40
                  ? Color(0xFFF59E0B)
                  : Color(0xFFDC2626);
        }
      } catch (_) {
        statusText = 'Tamamlandı'.tr();
        statusColor = Color(0xFF10B981);
      }
    } else {
      // Cevap var mı? Varsa "Devam et", yoksa "Başla"
      if (attempt.answers.isNotEmpty) {
        statusText = 'Devam et'.tr();
        statusColor = _orange;
      } else {
        statusText = 'Başla'.tr();
        statusColor = _blue;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: () {
          if (completed) {
            _openCompletedAttempt(ref.summary, attempt, subject.name);
          } else {
            _openTestAttempt(ref.summary, attempt, subject.name);
          }
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: ink.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ink.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.quiz_rounded,
                    size: 16, color: _orange),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.summary.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      '${ref.attemptIndex}. ${'Deneme'.tr()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: ink.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  statusText,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: ink.withValues(alpha: 0.55)),
            ],
          ),
        ),
      ),
    );
  }


  // Her kelimenin baş harfini büyütür. Türkçe "i" → "İ", "ı" → "I" özel
  // dönüşümü doğru çalışsın diye küçük "i"yi açıkça ele alır.
  String _toTitleCase(String s) {
    return s.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return w;
      final first = w[0];
      String upper;
      if (first == 'i') {
        upper = 'İ';
      } else if (first == 'ı') {
        upper = 'I';
      } else {
        upper = first.toUpperCase();
      }
      return '$upper${w.substring(1)}';
    }).join(' ');
  }

  Widget _buildInlineAddPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ═══ Çerçevenin ÜSTÜ — yalnız başlık pill'i (Title Case, siyah).
        //    Eğitim seviyesi ve hak sayacı kaldırıldı; başlık tam genişlikte
        //    görünür, kırpılmaz.
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
            color: AppPalette.card(context),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: AppPalette.textPrimary(context), width: 1.2),
            ),
            child: Text(
              _toTitleCase(_headline),
              maxLines: 2,
              softWrap: true,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
                height: 1.2,
              ),
            ),
          ),
        ),
        // ═══ Çerçeve — yalnız ders kareleri (iç başlık kaldırıldı) ═══
        DragTarget<Color>(
          onWillAcceptWithDetails: (_) =>
              _colorTarget == 'frame' || _showColorPicker,
          onAcceptWithDetails: (d) => _applyColorTo('frame', d.data),
          builder: (ctx, cand, _) {
            final hovering = cand.isNotEmpty;
            return Container(
              decoration: BoxDecoration(
                color: AppPalette.resolveBlackoutBg(context, _frameOverride),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: hovering ? _orange : AppPalette.border(context),
                  width: hovering ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: _buildInlineSubjectGrid(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildInlineSubjectGrid() {
    if (_inlineEduSubjects.isEmpty) {
      // Profile gate kaldırıldı — _subjectsForProfileAllTracks artık profil
      // null olsa bile varsayılan (TR Lise 11) ders listesini döndürür.
      // Bu blok sadece kısa async load anında görünür.
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text('Yükleniyor…'.tr(),
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade600)),
        ),
      );
    }
    // İlk 12 ders burada (3x4 ızgara); kalanlar alt "Diğer Dersler" sheet'inde
    final visible = _inlineEduSubjects.take(12).toList();
    // "Diğer Dersler" sheet'ine geçiş koşulu: ister müfredat 13+, ister
    // manuel ders 5+ olsun.
    final hasMore = _inlineEduSubjects.length > 12 || _customSubjects.length > 4;
    // Kullanıcının eklediği özel dersler her zaman görünür (en sonda).
    // Manuel ders çerçevesinde sadece ilk 4 görünür; fazlası "Diğer
    // Dersler" sheet'inde listelenir.
    final customVisible = _customSubjects.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Ders ızgarası — TAM 12 hücre (3 satır × 4) — son satırda yalnız
        //    1 hücre kalmasın diye "+ Yeni Ders Ekle" grid'in DIŞINA alındı.
        GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.0,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          children: [
            for (final s in visible) _subjectGridTile(s),
          ],
        ),
        // ── "Yeni Ders Ekle" — tam genişlikte buton, grid altında.
        SizedBox(height: 10),
        _wideAddSubjectButton(),
        if (customVisible.isNotEmpty) ...[
          SizedBox(height: 12),
          _customSubjectsFrame(customVisible),
        ],
        if (hasMore) ...[
          SizedBox(height: 10),
          GestureDetector(
            onTap: _openOtherSubjectsSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
            color: AppPalette.card(context),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppPalette.textPrimary(context), width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('📚', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 8),
                  Text(
                    'Diğer Dersler'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Tam genişlikte "+ Yeni Ders Ekle" butonu — grid'in altında.
  /// `_addSubjectTile()` (kare grid hücresi) kaldırıldı; yerine bu kullanılır.
  Widget _wideAddSubjectButton() {
    return GestureDetector(
      onTap: _openAddCustomSubjectDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: _orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _orange.withValues(alpha: 0.55), width: 1.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 16, color: _orange),
            SizedBox(width: 6),
            Text(
              'Yeni Ders Ekle'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subjectGridTile(EduSubject s) {
    final custom = _subjectTileColors[s.key];
    final bgColor = AppPalette.resolveBlackoutBg(context, custom);
    final lum = (0.299 * bgColor.r +
        0.587 * bgColor.g +
        0.114 * bgColor.b);
    final isDark = lum < 0.55;
    final customText = _subjectTileTextColors[s.key];
    final fg = customText ?? (isDark ? Colors.white : Colors.black);

    Widget tile(bool hovering) {
      return AnimatedContainer(
        duration: Duration(milliseconds: 150),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          // Çerçeve çizgisi yok — yalnızca hover/drag'de turuncu vurgu.
          // Normal durumda hafif gölgeyle zeminden ayrışır.
          border: hovering
              ? Border.all(color: _orange, width: 2.4)
              : null,
          boxShadow: hovering
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(s.emoji, style: TextStyle(fontSize: 22)),
            SizedBox(height: 3),
            // Uzun ders adlarında otomatik küçülerek kart içine sığar
            // (örn. "Elektrik-Elektronik Mühendisliği"). Kısa adlar 10pt'te kalır.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 90),
                  child: Text(
                    s.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Üç katmanlı: dış DragTarget<String> (ders swap), iç DragTarget<Color>
    // (renk uygula), en içte LongPressDraggable<String> (basılı tut sürükle).
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != s.key,
      onAcceptWithDetails: (d) => _swapSubjects(d.data, s.key),
      builder: (ctx, swapCand, _) {
        return DragTarget<Color>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (d) => _applyColorToTile(s.key, d.data),
          builder: (ctx2, colorCand, _) {
            final hovering = swapCand.isNotEmpty || colorCand.isNotEmpty;
            return LongPressDraggable<String>(
              data: s.key,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: tile(false),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: tile(false),
              ),
              child: GestureDetector(
                onTap: _showColorPicker
                    ? null
                    : () => _openSubjectTopicsDialog(edu: s),
                child: tile(hovering),
              ),
            );
          },
        );
      },
    );
  }

  /// Kullanıcının eklediği özel ders kartı.
  /// Tıklandığında o dersin konuları (statik/AI) gösterilir.
  /// Uzun basıldığında silinir.
  Widget _customSubjectGridTile(EduSubject s) {
    final custom = _subjectTileColors[s.key];
    final bgColor = AppPalette.resolveBlackoutBg(context, custom);
    final lum =
        (0.299 * bgColor.r + 0.587 * bgColor.g + 0.114 * bgColor.b);
    final isDark = lum < 0.55;
    final customText = _subjectTileTextColors[s.key];
    final fg = customText ?? (isDark ? Colors.white : Colors.black);
    return GestureDetector(
      onTap: _showColorPicker
          ? null
          : () => _openSubjectTopicsDialog(edu: s),
      onLongPress: () => _confirmDeleteCustomSubject(s),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(s.emoji, style: TextStyle(fontSize: 22)),
            SizedBox(height: 3),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 90),
                  child: Text(
                    s.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Manuel olarak eklenen ders kareleri için ayrı, fütüristik & renklendirilebilir
  /// çerçeve. `DragTarget<Color>` — kullanıcı paletten istediği rengi sürükleyip
  /// buraya bırakırsa çerçeve zemini o renge boyanır.
  Widget _customSubjectsFrame(List<EduSubject> customs) {
    return DragTarget<Color>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        setState(() => _customFrameOverride = d.data);
        _saveColorPrefs();
      },
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        final hasOverride = _customFrameOverride != null;
        // Override yoksa fütüristik gradient kenarlık; varsa düz ince siyah
        // kenarlık + override zemini.
        final innerBg = _customFrameOverride ?? Colors.white;
        final lum = 0.299 * innerBg.r + 0.587 * innerBg.g + 0.114 * innerBg.b;
        final isDark = lum < 0.55;
        final labelColor = isDark ? Colors.white : Colors.black87;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF7C3AED)
                    .withValues(alpha: hovering ? 0.30 : 0.14),
                blurRadius: hovering ? 18 : 12,
                offset: Offset(0, 4),
              ),
              BoxShadow(
                color: Color(0xFF22D3EE).withValues(alpha: 0.08),
                blurRadius: 18,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(1.3),
              decoration: BoxDecoration(
                gradient: hasOverride
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFF6A00),
                          Color(0xFFDB2777),
                          Color(0xFF7C3AED),
                          Color(0xFF22D3EE),
                        ],
                      ),
                color: hasOverride ? Colors.black : null,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: BoxDecoration(
                  color: innerBg,
                  borderRadius: BorderRadius.circular(14.7),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 6),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 12, color: labelColor),
                          SizedBox(width: 4),
                          Text(
                            'Eklediğin Dersler'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: labelColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GridView.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.0,
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      children: [
                        for (final s in customs) _customSubjectGridTile(s),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// "+ Yeni Ders Ekle" karesi — grid'in en sonunda durur.
  // _addSubjectTile() kaldırıldı — artık _wideAddSubjectButton tam genişlikte
  // grid altında gösteriliyor. Kullanıcı "+ Yeni Ders Ekle"'ye basınca aynı
  // _openAddCustomSubjectDialog akışı çalışır.

  Future<void> _openAddCustomSubjectDialog() async {
    final result = await showModalBottomSheet<_NewCustomSubjectResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddCustomSubjectSheet(
        existingNames: [
          ..._inlineEduSubjects.map((s) => s.name),
          ..._customSubjects.map((s) => s.name),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final exists = [
      ..._inlineEduSubjects,
      ..._customSubjects,
    ].any((s) => s.name.toLowerCase() == result.name.toLowerCase());
    if (exists) {
      _showSnack('Bu ders zaten listede.'.tr());
      return;
    }
    final key = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _customSubjects.add(EduSubject(key, result.emoji, result.name, _blue));
    });
    await _saveCustomSubjects();
  }

  Future<void> _confirmDeleteCustomSubject(EduSubject s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.emoji} ${s.name}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
        content: Text(
          'Bu dersi listeden kaldırmak ister misin?'.tr(),
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('İptal'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Sil'.tr(),
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _customSubjects.removeWhere((x) => x.key == s.key);
    });
    _saveCustomSubjects();
  }

  /// 8'in üstündeki müfredat dersleri + 4'ün üstündeki manuel dersleri
  /// listeleyen bottom sheet.
  Future<void> _openOtherSubjectsSheet() async {
    // Ana grid 12 ders gösteriyor (3×4); sheet sadece TAŞAN dersleri içerir.
    // Önceki bug: skip(8) → 9-12 arası dersler hem grid'te hem sheet'te
    // görünüyordu.
    final overflowCurr = _inlineEduSubjects.skip(12).toList();
    final overflowCustom = _customSubjects.skip(4).toList();
    if (overflowCurr.isEmpty && overflowCustom.isEmpty) return;
    setState(() => _showOtherSheet = true);
  }

  void _closeOtherSheet() {
    if (_showOtherSheet) {
      setState(() {
        _showOtherSheet = false;
        _draggingFromSheet = false;
      });
    }
  }

  // Overlay sheet — modal değil, arka plandaki top-8 grid tıklanabilir kalır.
  Widget _buildOtherSheetOverlay() {
    // Müfredat dersleri 13+ ve manuel dersler 5+ aynı sheet'te toplanır.
    // (Ana grid ilk 12 müfredat + ilk 4 manuel gösterir.)
    final overflowCurr = _inlineEduSubjects.skip(12).toList();
    final overflowCustom = _customSubjects.skip(4).toList();
    final overflow = [...overflowCurr, ...overflowCustom];
    if (overflow.isEmpty) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final sheetHeight = mq.size.height * 0.55;
    return Stack(
      children: [
        // Sürükleme aktifken hafif şeffaf — kullanıcı arkayı görsün.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedOpacity(
            opacity: _draggingFromSheet ? 0.30 : 1.0,
            duration: Duration(milliseconds: 180),
            // Material sarmalı: Text widget'larındaki sarı debug
            // alt çizgilerini önler (Material context sağlar).
            child: Material(
              type: MaterialType.transparency,
              child: Container(
              height: sheetHeight,
              decoration: BoxDecoration(
                color: AppPalette.bg(context),
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(width: 30),
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppPalette.textSecondary(context),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _closeOtherSheet,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppPalette.card(context),
                            border: Border.all(
                                color: AppPalette.border(context)),
                          ),
                          child: Icon(Icons.close_rounded,
                              size: 16,
                              color: AppPalette.textPrimary(context)),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  // Başlık + ipucu pill
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Diğer Dersler'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textPrimary(context),
                          ),
                        ),
                      ),
                      // Sağ üstte küçük, çerçevesiz, soluk (flu) ipucu —
                      // iki satıra sığacak kadar dar.
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: 130),
                        child: Opacity(
                          opacity: 0.85,
                          child: Text(
                            'Derslere basılı tut,\nsürükle, yerini değiştir'
                                .tr(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textPrimary(context),
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.0,
                      children: [
                        for (final s in overflow)
                          _OverflowSubjectTile(
                            subject: s,
                            bgColor: _subjectTileColors[s.key],
                            textColor: _subjectTileTextColors[s.key],
                            onTap: () {
                              _closeOtherSheet();
                              _openSubjectTopicsDialog(edu: s);
                            },
                            onDragStarted: () {
                              setState(() =>
                                  _draggingFromSheet = true);
                            },
                            onDragEnd: () {
                              setState(() =>
                                  _draggingFromSheet = false);
                            },
                            onAcceptSwap: (draggedKey) =>
                                _swapSubjects(draggedKey, s.key),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  Ders seçim modali — sol: konu sekmeleri, sağ: özet durumu, alt: yeni
  //  konu ekleme. `edu` ile seçilir (grid) veya `customName` (kendim yazayım).
  // ═════════════════════════════════════════════════════════════════════════
  /// Profil'in country+level+grade kombinasyonu için TÜM track'lerden
  /// subjectKey veya subjectName ile eşleşen dersin konularını UNION'la topla.
  /// Bu sayede kullanıcı hangi alanı seçmiş olursa olsun, hangi derse tıklarsa
  /// o dersin tüm konuları gösterilir.
  List<String> _topicsForSubjectAllTracks({
    required EduProfile? profile,
    String? subjectKey,
    required String subjectName,
  }) {
    bool matches(CurriculumSubject c) {
      final sName = subjectName.toLowerCase();
      final cName = c.displayName.toLowerCase();
      if (subjectKey != null && c.key == subjectKey) return true;
      if (cName == sName) return true;
      return cName.contains(sName) || sName.contains(cName);
    }

    final seen = <String>{};
    final collected = <String>[];

    void addFrom(EduProfile p) {
      for (final c in curriculumFor(p)) {
        if (!matches(c)) continue;
        for (final t in c.topics) {
          final k = t.trim().toLowerCase();
          if (k.isEmpty) continue;
          if (seen.add(k)) collected.add(t);
        }
      }
    }

    if (profile != null) {
      addFrom(profile);
      // Tüm bilinen track varyasyonlarını da tara
      const knownTracks = <String>[
        'sayisal', 'esit_agirlik', 'sozel', 'dil',
        'lixue', 'wenxue',
        'jayeon', 'insa',
        'ipa', 'ips',
        'science', 'commerce', 'arts',
        'stem', 'abm', 'humss',
        'sciences', 'humanities',
      ];
      for (final t in knownTracks) {
        if (profile.track == t) continue;
        addFrom(EduProfile(
          country: profile.country,
          level: profile.level,
          grade: profile.grade,
          track: t,
          faculty: profile.faculty,
        ));
      }
      // Track'siz genel fallback
      addFrom(EduProfile(
        country: profile.country,
        level: profile.level,
        grade: profile.grade,
        track: null,
        faculty: profile.faculty,
      ));
    } else {
      addFrom(EduProfile(
        country: 'international',
        level: 'high',
        grade: '11',
      ));
    }
    return collected;
  }

  Future<void> _openSubjectTopicsDialog({
    EduSubject? edu,
    String? customName,
    String? customEmoji,
  }) async {
    final subjectName = edu?.name ?? customName ?? '';
    final subjectEmoji = edu?.emoji ?? customEmoji ?? '📚';
    final subjectColor = edu?.color ?? _blue;
    if (subjectName.isEmpty) return;

    // Curriculum'dan bu dersin konuları (ülke+sınıf+alan'a göre)
    // Dersi ülke+sınıf için TÜM alan (track) varyasyonlarından topla,
    // böylece profil 'eşit ağırlık' seçili olsa bile matematik/fizik/
    // biyoloji vb. hangi ders tıklandıysa o dersin konuları çıkar.
    var topics = _topicsForSubjectAllTracks(
      profile: _inlineProfile,
      subjectKey: edu?.key,
      subjectName: subjectName,
    );

    // Statik müfredat bu ders için konu vermediyse (örn. AI-generated bir
    // bölüm dersi: Anatomi, Arkeoloji, Veri Bilimi vb.) → önce offline pack
    // cache'i, sonra AI'ya canlı sor; konuları doldur.
    if (topics.isEmpty && _inlineProfile != null && edu != null) {
      final cached = await OfflineDownloadController.readPack(
        profile: _inlineProfile!,
        subjectKey: edu.key,
      );
      if (cached != null && cached.topics.isNotEmpty) {
        topics = cached.topics.map((t) => t.name).toList();
      } else {
        // Yükleme overlay'i — dialog açıkken AI'dan getirebilirdik ama
        // dialog daha açılmadığından küçük bir snackbar yeterli.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Konular hazırlanıyor…'.tr()),
                ],
              ),
              duration: Duration(seconds: 30),
            ),
          );
        }
        try {
          final pairs = await GeminiService.fetchSubjectTopicPack(
            subjectName: subjectName,
            profile: _inlineProfile!,
          );
          topics = pairs
              .map((m) => m['name'] ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          // Pack'i cache'le → bir sonraki açılış anında olsun.
          if (pairs.isNotEmpty) {
            // OfflineDownloadController'ın savePack helper'ı yok; doğrudan
            // SharedPreferences üzerinden offline pack key'ine yaz.
            final pack = OfflineSubjectPack(
              subjectKey: edu.key,
              subjectName: subjectName,
              emoji: edu.emoji,
              topics: pairs
                  .map((p) => OfflineTopic(
                        name: p['name'] ?? '',
                        summary: p['summary'] ?? '',
                      ))
                  .toList(),
              cachedAt: DateTime.now(),
            );
            try {
              final prefs = await SharedPreferences.getInstance();
              final p = _inlineProfile!;
              final key = 'offline_pack_v1::'
                  '${p.country}_${p.level}_${p.grade}_'
                  '${p.faculty ?? ""}_${p.track ?? ""}::${edu.key}';
              await prefs.setString(key, pack.encode());
            } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
          }
        } catch (_) {
          // Sessizce başarısız → kullanıcı kendi konusunu yazabilir.
        }
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _SubjectTopicsDialog(
        subjectName: subjectName,
        subjectEmoji: subjectEmoji,
        subjectColor: subjectColor,
        profileLabel: _inlineProfile?.displayLabel() ?? '',
        curriculumTopics: topics,
        mode: widget.mode,
        getExistingSubject: () {
          final target = _normSubjectName(subjectName);
          return _subjects.firstWhere(
            (x) => _normSubjectName(x.name) == target,
            orElse: () => _Subject(
              id: '',
              name: subjectName,
              summaries: [],
            ),
          );
        },
        onGenerateTopic: (topic) async {
          Navigator.of(ctx).pop();
          await _runGenerateWithSetup(subjectName: subjectName, topic: topic);
        },
        onOpenExistingSummary: (summary) {
          Navigator.of(ctx).pop();
          _openSummary(summary, subjectName);
        },
        onAddCustomTopic: (topic) async {
          Navigator.of(ctx).pop();
          await _runGenerateWithSetup(subjectName: subjectName, topic: topic);
        },
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
//  _AddCustomSubjectSheet — "Yeni Ders Ekle" modal sheet'i.
//  Controller lifecycle bu sheet'in State'ine bağlı (parent rebuild olsa
//  da dialog güvenli kalır). Klavye safe-aware (viewInsets).
// ═══════════════════════════════════════════════════════════════════════════
class _NewCustomSubjectResult {
  final String name;
  final String emoji;
  const _NewCustomSubjectResult({required this.name, required this.emoji});
}

class _AddCustomSubjectSheet extends StatefulWidget {
  final List<String> existingNames;
  const _AddCustomSubjectSheet({required this.existingNames});

  @override
  State<_AddCustomSubjectSheet> createState() =>
      _AddCustomSubjectSheetState();
}

class _AddCustomSubjectSheetState extends State<_AddCustomSubjectSheet> {
  final _nameCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final emoji = _emojiCtrl.text.trim().isEmpty
        ? '📚'
        : _emojiCtrl.text.trim();
    Navigator.of(context).pop(
      _NewCustomSubjectResult(name: name, emoji: emoji),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Yeni Ders Ekle'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary(context),
                ),
                cursorColor: Colors.black,
                decoration: _inputDec('Ders adı'.tr()),
                onSubmitted: (_) => _submit(),
              ),
              SizedBox(height: 10),
              TextField(
                controller: _emojiCtrl,
                maxLength: 4,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary(context),
                ),
                cursorColor: Colors.black,
                decoration: _inputDec('Emoji (opsiyonel, örn. 🧠)'.tr())
                    .copyWith(counterText: ''),
                onSubmitted: (_) => _submit(),
              ),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'İptal'.tr(),
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textSecondary(context),
                      ),
                    ),
                  ),
                  SizedBox(width: 6),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _submit,
                    child: Text(
                      'Ekle'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Bottom Sheet: Yeni Ders (ders + ilk konu) — eski tasarım, geriye uyum.
// ═══════════════════════════════════════════════════════════════════════════
class _NewSubjectRequest {
  final String subject;
  final String topic;
  _NewSubjectRequest(this.subject, this.topic);
}

class _NewSubjectSheet extends StatefulWidget {
  const _NewSubjectSheet();
  @override
  State<_NewSubjectSheet> createState() => _NewSubjectSheetState();
}

class _NewSubjectSheetState extends State<_NewSubjectSheet> {
  final _topicCtrl = TextEditingController();
  final _topicFocus = FocusNode();
  EduProfile? _profile;
  List<EduSubject> _subjects = [];
  EduSubject? _selectedSubject;
  bool _customMode = false;
  final _customSubjectCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final p = await EduProfile.load();
    if (!mounted) return;
    setState(() {
      _profile = p;
      _subjects = subjectsForProfile(p);
    });
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    _topicFocus.dispose();
    _customSubjectCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Eğitim profili bandı
              if (_profile != null) _profileBanner(),
              if (_profile != null) SizedBox(height: 14),
              // Ders seçimi
              Row(
                children: [
                  Text('DERS SEÇ'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade700,
                        letterSpacing: 0.08,
                      )),
                  Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => _customMode = !_customMode),
                    icon: Icon(_customMode ? Icons.grid_view_rounded : Icons.edit_rounded,
                        size: 14, color: _orange),
                    label: Text(
                      _customMode ? 'Listeden seç'.tr() : 'Kendim yazayım'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _orange,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              if (_customMode)
                TextField(
                  controller: _customSubjectCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _topicFocus.requestFocus(),
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    color: AppPalette.textPrimary(context),
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: _blue,
                  decoration: _inputDec(localeService.tr('subject_title_hint')),
                )
              else
                _buildSubjectGrid(),
              SizedBox(height: 18),
              // Konu adı
              Text(localeService.tr('topic_name'),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                  )),
              SizedBox(height: 6),
              TextField(
                controller: _topicCtrl,
                focusNode: _topicFocus,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: AppPalette.textPrimary(context),
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: _blue,
                decoration: _inputDec(localeService.tr('topic_name_hint')),
              ),
              SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    localeService.tr('create_summary_btn'),
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Text('🎓'.tr(), style: TextStyle(fontSize: 16)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _profile!.displayLabel(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _blue,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectGrid() {
    if (_subjects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text('Yükleniyor…'.tr(),
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.0,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      children: [
        for (final s in _subjects)
          GestureDetector(
            onTap: () => setState(() => _selectedSubject = s),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 150),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _selectedSubject?.key == s.key
                    ? s.color.withValues(alpha: 0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedSubject?.key == s.key ? s.color : Colors.grey.shade300,
                  width: _selectedSubject?.key == s.key ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(s.emoji, style: TextStyle(fontSize: 24)),
                  SizedBox(height: 4),
                  // Uzun ders adı taşmasın — FittedBox ile auto-shrink.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 90),
                        child: Text(
                          s.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _selectedSubject?.key == s.key
                                ? s.color
                                : Colors.black87,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _submit() {
    final subject = _customMode
        ? _customSubjectCtrl.text.trim()
        : (_selectedSubject?.name ?? '');
    final topic = _topicCtrl.text.trim();
    if (subject.isEmpty || topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _customMode
              ? localeService.tr('subject_topic_required')
              : 'Lütfen bir ders seç ve konu adı yaz',
        ),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    Navigator.pop(context, _NewSubjectRequest(subject, topic));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Bottom Sheet: Mevcut derse yeni konu
// ═══════════════════════════════════════════════════════════════════════════
class _NewTopicSheet extends StatefulWidget {
  final String subjectName;
  const _NewTopicSheet({required this.subjectName});
  @override
  State<_NewTopicSheet> createState() => _NewTopicSheetState();
}

class _NewTopicSheetState extends State<_NewTopicSheet> {
  final _topicCtrl = TextEditingController();

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.menu_book_rounded, color: _blue, size: 20),
                SizedBox(width: 8),
                Text(widget.subjectName,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _blue,
                    )),
              ],
            ),
            SizedBox(height: 14),
            Text(localeService.tr('which_topic_summary'),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                )),
            SizedBox(height: 8),
            TextField(
              controller: _topicCtrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w500,
              ),
              cursorColor: _blue,
              decoration:
                  _inputDec(_topicHintForSubject(widget.subjectName)),
            ),
            SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(localeService.tr('create_summary_btn'),
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final t = _topicCtrl.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, t);
  }
}

InputDecoration _inputDec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(
        fontSize: 14,
        color: Colors.grey.shade400,
      ),
      filled: true,
      fillColor: Color(0xFFF3F4F6),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );

// ═══════════════════════════════════════════════════════════════════════════
//  Ders detay sayfası (içinde konu özetleri listesi + yeni konu ekle)
// ═══════════════════════════════════════════════════════════════════════════
class _SubjectDetailPage extends StatefulWidget {
  final _Subject subject;
  final LibraryMode mode;
  final Future<bool> Function(String topic) onAddTopic;
  final Future<void> Function(_Summary sum) onDelete;
  // Questions mode — boş slot: yeni attempt üret. Çağıran tarafta loader
  // durumu yok; burası kendi loader'ını gösterir. Config, önce setup page'de
  // seçilip buraya aktarılır.
  final Future<void> Function(_Summary summary, _TestConfig cfg)? onAddAttempt;
  // Questions mode — dolu slot: tamamlanmışsa sonuç, değilse devam.
  final void Function(_Summary summary, _TestAttempt attempt)? onOpenAttempt;
  // Planner'da ders kartına uygulanan renk — buradaki sayfanın da arka
  // planına yansır. null → varsayılan açık gri zemin.
  final Color? pageBg;
  const _SubjectDetailPage({
    required this.subject,
    required this.mode,
    required this.onAddTopic,
    required this.onDelete,
    this.onAddAttempt,
    this.onOpenAttempt,
    this.pageBg,
  });
  @override
  State<_SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends State<_SubjectDetailPage> {
  bool _generating = false;
  String _generatingTopic = '';
  // Loader sırasında kullanıcı "İptal"e basarsa true — onAddTopic/onAddAttempt
  // arka planda devam eder ama _SubjectDetailPage tarafı sonucu beklemeden
  // loader'ı kapatır. Parent (_AcademicPlannerState) zaten kendi
  // _generatingCancelled mantığıyla kotayı iade eder.
  bool _generatingCancelled = false;

  /// Konu satırına basılı tutunca: [Yeniden Oluştur] + [Sil] seçenekleri.
  Future<void> _showTopicActions(_Summary sum) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppPalette.textPrimary(context), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 14),
              Text(
                sum.topic,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              SizedBox(height: 14),
              Container(height: 1, color: Colors.black),
              InkWell(
                onTap: () => Navigator.of(ctx).pop('regen'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, size: 20,
                          color: Colors.black),
                      SizedBox(width: 10),
                      Text(
                        'Yeniden Oluştur'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(height: 1, color: Colors.black),
              InkWell(
                onTap: () => Navigator.of(ctx).pop('delete'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 20,
                          color: Color(0xFFDC2626)),
                      SizedBox(width: 10),
                      Text(
                        'Sil'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'delete') {
      await widget.onDelete(sum);
      if (mounted) setState(() {});
    } else if (action == 'regen') {
      final topic = sum.topic;
      // Önce mevcut özeti sil, sonra aynı konu için yeniden oluştur
      await widget.onDelete(sum);
      if (!mounted) return;
      setState(() {
        _generating = true;
        _generatingTopic = topic;
      });
      await widget.onAddTopic(topic);
      if (!mounted) return;
      setState(() => _generating = false);
    }
  }

  // Summary mode — eski düzen.
  Widget _summaryRow(_Subject s, _Summary sum) {
    final d = sum.createdAt;
    final dateText =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return Material(color: AppPalette.card(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _SummaryDetailPage(
              summary: sum,
              subjectName: s.name,
            ),
          ));
        },
        onLongPress: () => _showTopicActions(sum),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.textPrimary(context), width: 1),
          ),
          child: Row(
            children: [
              Text('📖', style: TextStyle(fontSize: 20)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sum.topic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.black)),
                    SizedBox(height: 2),
                    Text(dateText,
                        style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: Colors.black54)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }

  // Questions mode — konu + sağda 3 küçük test slot'u.
  // Dolu slot turuncu (tamamlanmışsa ✓ ikonlu), boş slot soluk.
  // Dolu slot → sonuç / devam. Boş slot → yeni test üret. 3 bitince kapalı.
  Widget _questionsRow(_Subject s, _Summary sum) {
    final slots = <Widget>[];
    for (int i = 0; i < 3; i++) {
      final attempt = i < sum.tests.length ? sum.tests[i] : null;
      slots.add(Expanded(child: _testSlot(s, sum, i, attempt)));
      if (i < 2) slots.add(SizedBox(width: 6));
    }
    return Material(color: AppPalette.card(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: () => _showTopicActions(sum),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.textPrimary(context), width: 1),
          ),
          child: Row(
            children: [
              Text('📖', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              // Sol: konu adı
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sum.topic,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context),
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    // Hak rozeti: kaç test hakkı kaldı, renkli vurgu.
                    //   3 hak → yeşil "Hazır"
                    //   2 hak → mavi  "2 hak kaldı"
                    //   1 hak → turuncu "Son hak"
                    //   0 hak → gri "Bitti"
                    _testQuotaBadge(sum.tests.length),
                  ],
                ),
              ),
              SizedBox(width: 8),
              // Sağ: 3 slot
              Expanded(
                flex: 5,
                child: Row(children: slots),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Kaç test hakkı kaldığını renkli rozetle göster.
  Widget _testQuotaBadge(int used) {
    final remaining = 3 - used;
    final Color bg;
    final Color fg;
    final String label;
    if (remaining == 3) {
      bg = Color(0x1410B981);
      fg = Color(0xFF059669);
      label = '3 ${'hak'.tr()}';
    } else if (remaining == 2) {
      bg = Color(0x142563EB);
      fg = Color(0xFF2563EB);
      label = '2 ${'hak kaldı'.tr()}';
    } else if (remaining == 1) {
      bg = Color(0x14FF6A00);
      fg = Color(0xFFFF6A00);
      label = 'Son hak'.tr();
    } else {
      bg = AppPalette.cardMuted(context);
      fg = AppPalette.textSecondary(context);
      label = 'Bitti'.tr();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.3), width: 0.7),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _testSlot(
      _Subject subject, _Summary summary, int index, _TestAttempt? attempt) {
    final filled = attempt != null;
    final completed = attempt?.completed ?? false;
    // Renkler: dolu=turuncu, boş=soluk.
    final bg = filled
        ? _orange.withValues(alpha: completed ? 1.0 : 0.75)
        : Color(0xFFEFF1F6);
    final fg = filled ? Colors.white : Colors.black38;
    final borderColor = filled
        ? _orange
        : Colors.black.withValues(alpha: 0.18);
    final label = '${index + 1}. ${'Test'.tr()}';
    return AspectRatio(
      aspectRatio: 1.0,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            if (filled) {
              widget.onOpenAttempt?.call(summary, attempt);
            } else {
              // Yalnızca sıradaki boş slot oluşturabilir;
              // ileri slotlar önceki boşsa pasif.
              if (index != summary.tests.length) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      'Önce ${summary.tests.length + 1}. testi oluştur.'.tr()),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
                return;
              }
              if (widget.onAddAttempt == null) return;
              // Önce kullanıcıya son ayarlar sayfası.
              final cfg = await Navigator.of(context).push<_TestConfig>(
                MaterialPageRoute(
                  builder: (_) => _TestSetupPage(
                    subjectName: subject.name,
                    topic: summary.topic,
                    attemptIndex: summary.tests.length,
                  ),
                ),
              );
              if (cfg == null) return;
              setState(() {
                _generating = true;
                _generatingTopic = summary.topic;
              });
              await widget.onAddAttempt!(summary, cfg);
              if (!mounted) return;
              setState(() => _generating = false);
            }
          },
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  filled
                      ? (completed
                          ? Icons.check_circle_rounded
                          : Icons.play_arrow_rounded)
                      : Icons.add_rounded,
                  size: 14,
                  color: fg,
                ),
                SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final isQuestions = widget.mode == LibraryMode.questions;
    final fabLabel = isQuestions
        ? 'Yeni Test Soruları'.tr()
        : 'Yeni Konu Özeti'.tr();
    // Sayfa zemini — planner'da ders kartına atanmış renk varsa onu kullan,
    // yoksa nötr açık gri. Kart arka planının koyu/açık olmasına göre
    // başlık ve geri ikonu rengi otomatik ayarlanır.
    final pageBg = AppPalette.resolvePageBg(context, widget.pageBg);
    final lum = (0.299 * pageBg.r + 0.587 * pageBg.g + 0.114 * pageBg.b);
    final isDark = lum < 0.55;
    final fg = isDark ? Colors.white : Colors.black;
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: fg,
        iconTheme: IconThemeData(color: fg),
        title: Text(
          s.name,
          style: GoogleFonts.poppins(
              fontSize: 17, fontWeight: FontWeight.w800, color: fg),
        ),
      ),
      // Sağ alt: yeni özet/soru için bu dersin konular sayfasını açan buton.
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () {
          // _LibraryPage'e sinyali gönder → o, konular dialogunu açar.
          Navigator.of(context).pop('_openSubjectTopics');
        },
        icon: Icon(Icons.add_rounded, size: 20),
        label: Text(
          fabLabel,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Stack(
        children: [
          s.summaries.isEmpty
              ? Center(
                  child: Text(localeService.tr('no_summary_yet'),
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade500)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: s.summaries.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final sum = s.summaries[i];
                    if (widget.mode == LibraryMode.questions) {
                      return _questionsRow(s, sum);
                    }
                    return _summaryRow(s, sum);
                  },
                ),
          if (_generating)
            Positioned.fill(
              child: Stack(
                children: [
                  QuAlsarLoadingWidget(
                    type: widget.mode == LibraryMode.questions
                        ? QuAlsarLoadingType.test
                        : QuAlsarLoadingType.summary,
                    topic: _generatingTopic,
                    domain: _AcademicPlannerState._subjectLayer(
                                widget.subject.name) ==
                            'verbal'
                        ? SubjectDomain.verbal
                        : SubjectDomain.numeric,
                  ),
                  // İptal pill — sağ üst. Loader'dan vazgeçilir, arka plan
                  // isteği devam etse de UI serbest kalır. Parent quota
                  // refund mantığı (_generate*) zaten yerinde.
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: GestureDetector(
                          onTap: _generatingCancelled
                              ? null
                              : () {
                                  setState(() {
                                    _generatingCancelled = true;
                                    _generating = false;
                                  });
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: _generatingCancelled
                                  ? Color(0x33808080)
                                  : Colors.black,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.close_rounded,
                                    size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'İptal'.tr(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Özet Detay Sayfası (çerçeveli, temiz, profesyonel)
// ═══════════════════════════════════════════════════════════════════════════
class _SummaryDetailPage extends StatefulWidget {
  final _Summary summary;
  final String subjectName;
  // Streaming desteği — null değilse sayfa boş açılır, AI yazdıkça
  // içerik gelir; stream bitince onStreamComplete çağrılır (persist için).
  final Stream<String>? stream;
  final Future<void> Function(String finalContent)? onStreamComplete;
  // Stream tek chunk üretemeden fail oldu → kullanıcı kotasını geri al.
  final Future<void> Function()? onEarlyFailure;
  // "Tekrar Dene" butonu — sayfa içinden stream restart. null değilse
  // banner'da retry butonu görünür. Yeni stream döndürür.
  final Stream<String> Function()? onRetry;
  const _SummaryDetailPage({
    required this.summary,
    required this.subjectName,
    this.stream,
    this.onStreamComplete,
    this.onEarlyFailure,
    this.onRetry,
  });

  @override
  State<_SummaryDetailPage> createState() => _SummaryDetailPageState();
}

class _SummaryDetailPageState extends State<_SummaryDetailPage> {
  // ── Renk özelleştirme state'i — Konu Özetleri / Bilgi Yarışı ile aynı ──
  // 3 hedef: 'bg' (sayfa arka planı) · 'title' (üst başlık çerçevesi) ·
  // 'cards' (alt başlık kartları + en önemli 5 bilgi kartı).
  // 2 mod: 'frame' (zemin) · 'text' (yazı rengi).
  bool _showColorPicker = false;
  String _colorMode = 'frame'; // 'frame' | 'text'
  String _colorTarget = 'bg'; // 'bg' | 'title' | 'cards'
  Color? _pageBgOverride;
  Color? _titleBgOverride;
  Color? _cardsBgOverride;
  Color? _titleTextOverride;
  Color? _cardsTextOverride;

  static const _palette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  // Her özet kendi renk setine sahip — SharedPreferences anahtarı özet id'si.
  String get _prefKey => 'summary_colors_${widget.summary.id}';

  // ── Streaming state ─────────────────────────────────────────────────────
  // _streamedContent: stream geldikçe büyür. Stream bittiğinde
  // widget.summary.content güncellenir + onStreamComplete persist eder.
  String? _streamedContent;
  bool _streaming = false;
  bool _streamFailed = false;
  /// Stream başarısız olunca kullanıcıya gösterilecek nedeni içerir.
  /// noInternet/serverTimeout/safety/etc spesifik mesajları üstlenir.
  String? _streamFailMessage;
  StreamSubscription<String>? _streamSub;
  // Parse debounce — stream sırasında her chunk full parse ediyordu (5KB
  // özette jank). 150ms throttle: chunk'lar üst üste binerse sonuncu
  // parse'i tetikler, intermediate'lerde eski cache görünür.
  Timer? _parseDebounce;
  // Auto-scroll DEVRE DIŞI — kullanıcı özet oluşturulurken ekranın
  // aşağı kaymasını istemiyor; özetin ilk sayfası ekranda kalsın,
  // okuyucu kendi kaydırdığı kadar görsün. Kullanıcı manuel olarak
  // aşağı inerse zaten yeni içerik orada bekliyor olacak.
  bool _autoFollowBottom = false;

  /// StudyToolbarOverlay sticky highlights için — ListView ile overlay
  /// Stack'te sibling olduğundan Scrollable.maybeOf(context) bulamıyor.
  /// Controller'ı parent'ta tutup overlay'e inject ediyoruz.
  final ScrollController _scrollController = ScrollController();

  // ── Parse cache — sayfa açılışını anında yapmak için ───────────────────
  // _clean() + _splitSections() pahalı; her build'de tekrar koşmasın.
  // Ham içerik değişmediyse cache kullan, sadece içerik değişince yenile.
  String? _cachedRaw;
  String _cachedCleaned = '';
  List<_Section> _cachedNormalSections = const [];
  _Section? _cachedKeyFacts;
  _Section? _cachedExamples;

  void _ensureParsed(String raw) {
    if (raw == _cachedRaw) return;
    _cachedRaw = raw;
    _cachedCleaned = _clean(raw);
    final sections = _splitSections(_cachedCleaned);
    final normal = <_Section>[];
    _Section? key;
    _Section? examples;
    for (final s in sections) {
      // "📌 Özetle" kapanış paragrafı kaldırıldı — geçmişte üretilmiş
      // özetlerde bu bölüm varsa render'da gizle.
      if (_isClosingHeader(s.header)) continue;
      if (_isKeyFactsHeader(s.header)) {
        key = s;
      } else if (_isExamplesHeader(s.header)) {
        examples = s;
      } else {
        normal.add(s);
      }
    }
    _cachedNormalSections = normal;
    _cachedKeyFacts = key;
    _cachedExamples = examples;
  }

  bool _isClosingHeader(String h) {
    final t = h.toLowerCase();
    return t.contains('📌') || t.contains('özetle');
  }

  bool _isExamplesHeader(String h) {
    final t = h.toLowerCase();
    return t.contains('📝') ||
        t.contains('örnek soru') ||
        t.contains('ornek soru') ||
        t.contains('konuyu pekiştir') ||
        t.contains('konuyu pekistir') ||
        t.contains('pekiştirme soru') ||
        t.contains('pekistirme soru') ||
        t.contains('uygulama soru') ||
        t.contains('example question') ||
        t.contains('sample question') ||
        t.contains('practice question');
  }

  @override
  void initState() {
    super.initState();
    // Çalışma süresi takibi — sayfa açıldığında session başlar, dispose'da
    // _ActivityStore'a yazılır.
    StudySessionTracker.instance.start(
      subject: widget.subjectName,
      topic: widget.summary.topic,
      type: 'özet',
    );
    _loadColors();
    _scrollController.addListener(_handleScroll);
    _attachStreamIfAny(widget.stream);
    // Heavy parse'ı ilk frame'den SONRA yap — sayfa transition'ı anında
    // açılsın, içerik bir tick sonra dolsun. Boş cache ile ilk build hızlı.
    if (widget.stream == null && widget.summary.content.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureParsed(widget.summary.content);
        setState(() {});
      });
    }
  }

  // Scroll dinleyici devre dışı — auto-follow kapalı, kullanıcı her zaman
  // kendi konumunda kalsın. Eski davranış: kullanıcı en alttayken stream
  // akarken yapışık tutuyordu; özet oluşturulurken ilk sayfa görünmüyordu.
  void _handleScroll() {
    // No-op; manuel scroll kullanıcıya bırakıldı.
  }

  void _scrollToBottomIfFollowing() {
    if (!_autoFollowBottom) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    _scrollController.jumpTo(pos.maxScrollExtent);
  }

  void _attachStreamIfAny(Stream<String>? s) {
    if (s == null) return;
    setState(() {
      _streaming = true;
      _streamFailed = false;
      _streamFailMessage = null;
      _streamedContent = '';
    });
    _streamSub = s.listen(
      (acc) {
        if (!mounted) return;
        // setState yapmıyoruz; her chunk full parse + rebuild jank yapıyor.
        // Sadece bayrakları güncelle, debounce timer parse + setState'i
        // 150ms sonra topluca çalıştırsın. Bu aralıkta ekranda eski cache
        // görünür — kabul edilebilir, kullanıcı zaten satırlar akarken bakıyor.
        _streamedContent = acc;
        _scheduleParse();
      },
      onError: (e) async {
        if (!mounted) return;
        // Stream hata verse bile o ana kadar gelmiş kısmi içeriği KAYDET —
        // kullanıcı yarıda kalmış özeti görsün, ileride uzun-bas → "Yeniden
        // Oluştur" ile tamamlayabilsin.
        final partial = _streamedContent ?? '';
        // Hata tipinden anlamlı kullanıcı mesajı çıkar.
        String msg;
        if (e is GeminiException) {
          msg = e.userMessage;
        } else {
          // Retry butonu yan tarafta görünüyorsa kullanıcı zaten görüyor.
          msg = 'AI yanıt veremedi.';
        }
        // Debounce'u iptal et + son parse'i ZORLA çalıştır.
        _parseDebounce?.cancel();
        _parseDebounce = null;
        setState(() {
          _streaming = false;
          _streamFailed = true;
          _streamFailMessage = msg;
          if (partial.isNotEmpty) {
            _ensureParsed(partial);
            widget.summary.content = partial;
          }
        });
        if (partial.isNotEmpty) {
          try {
            await widget.onStreamComplete?.call(partial);
          } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
        } else {
          // Hiç chunk gelmedi → kotayı iade et.
          try {
            await widget.onEarlyFailure?.call();
          } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
        }
      },
      onDone: () async {
        if (!mounted) return;
        final finalContent = _streamedContent ?? '';
        // Debounce'u iptal et + son parse'i ZORLA çalıştır.
        _parseDebounce?.cancel();
        _parseDebounce = null;
        setState(() {
          _streaming = false;
          if (finalContent.isNotEmpty) _ensureParsed(finalContent);
          widget.summary.content = finalContent;
        });
        // Son chunk'tan sonra alta yapışık kalmak isteyen kullanıcı için
        // bir frame sonrası finalize scroll.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottomIfFollowing();
        });
        if (finalContent.isNotEmpty) {
          try {
            await widget.onStreamComplete?.call(finalContent);
          } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
        } else {
          // Stream boş yanıt verdi → kotayı iade et.
          try {
            await widget.onEarlyFailure?.call();
          } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
        }
      },
      cancelOnError: true,
    );
  }

  // 150ms debounce — chunk arası setState + parse maliyetini düşürür.
  void _scheduleParse() {
    _parseDebounce?.cancel();
    _parseDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      final raw = _streamedContent ?? '';
      _ensureParsed(raw);
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottomIfFollowing();
      });
    });
  }

  Future<void> _retryStream() async {
    final cb = widget.onRetry;
    if (cb == null) return;
    // Eski sub'ı kapat + state'i sıfırla.
    await _streamSub?.cancel();
    _streamSub = null;
    _parseDebounce?.cancel();
    _parseDebounce = null;
    setState(() {
      _streamedContent = '';
      _streamFailed = false;
      _streamFailMessage = null;
      _streaming = true;
      // Cache'i de temizle ki loader yeniden görünsün.
      _cachedRaw = null;
      _cachedCleaned = '';
      _cachedNormalSections = const [];
      _cachedKeyFacts = null;
      _cachedExamples = null;
      widget.summary.content = '';
    });
    _attachStreamIfAny(cb());
  }

  @override
  void dispose() {
    // Çalışma session'ını kapat — geçen süre _ActivityStore'a yazılır.
    StudySessionTracker.instance.end();
    // Yarıda kalan stream → partial içerik varsa persist et, yoksa kotayı
    // iade et. dispose async olamadığı için fire-and-forget.
    if (_streaming) {
      final partial = _streamedContent ?? '';
      if (partial.isNotEmpty) {
        widget.summary.content = partial;
        // ignore: discarded_futures
        widget.onStreamComplete?.call(partial);
      } else {
        // ignore: discarded_futures
        widget.onEarlyFailure?.call();
      }
    }
    _parseDebounce?.cancel();
    _streamSub?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        Color? read(String k) {
          final v = m[k];
          return v is num ? Color(v.toInt()) : null;
        }

        _pageBgOverride = read('bg');
        _titleBgOverride = read('title');
        _cardsBgOverride = read('cards');
        _titleTextOverride = read('titleText');
        _cardsTextOverride = read('cardsText');
      });
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  Future<void> _saveColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = <String, int>{};
      void put(String k, Color? c) {
        if (c != null) m[k] = c.toARGB32();
      }

      put('bg', _pageBgOverride);
      put('title', _titleBgOverride);
      put('cards', _cardsBgOverride);
      put('titleText', _titleTextOverride);
      put('cardsText', _cardsTextOverride);
      if (m.isEmpty) {
        await prefs.remove(_prefKey);
      } else {
        await prefs.setString(_prefKey, jsonEncode(m));
      }
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
  }

  void _applyColorTo(String target, Color c) {
    setState(() {
      if (_colorMode == 'text') {
        if (target == 'title') {
          _titleTextOverride = c;
        } else if (target == 'cards') {
          _cardsTextOverride = c;
        } else {
          // 'bg' Yazı modunda — başlık + kart yazılarını birlikte ayarla.
          _titleTextOverride = c;
          _cardsTextOverride = c;
        }
      } else {
        if (target == 'bg') {
          _pageBgOverride = c;
        } else if (target == 'title') {
          _titleBgOverride = c;
        } else {
          _cardsBgOverride = c;
        }
      }
    });
    _saveColors();
  }

  void _resetColors() {
    setState(() {
      _pageBgOverride = null;
      _titleBgOverride = null;
      _cardsBgOverride = null;
      _titleTextOverride = null;
      _cardsTextOverride = null;
    });
    _saveColors();
  }

  bool _isDark(Color c) {
    final l = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
    return l < 0.55;
  }

  // Üst başlık kartı — ders adı + konu adı; renk paletinden 'title' hedefi.

  Widget _buildTitleCard() {
    return DragTarget<Color>(
      onAcceptWithDetails: (d) => _applyColorTo('title', d.data),
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        final bg = AppPalette.resolveCardBg(context, _titleBgOverride);
        final ink = _titleTextOverride ??
            (_isDark(bg) ? Colors.white : Colors.black);
        return AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering ? Color(0xFFFF6A00) : Colors.black,
              width: hovering ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF2563EB).withValues(alpha: 0.30),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  _subjectIcon(widget.subjectName),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: widget.subjectName,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: ink,
                          letterSpacing: 0.1,
                        ),
                      ),
                      TextSpan(
                        text: ' / ',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: ink.withValues(alpha: 0.5),
                        ),
                      ),
                      TextSpan(
                        text: widget.summary.topic,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: ink.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Sağ alt FAB — "Test Sorularını Çöz" ─────────────────────────────
  // Tıklanınca: questions kütüphanesinden bu konunun testi varsa direkt aç,
  // yoksa AcademicPlanner(questions, autoOpen) ile yönlendir.
  // `enabled=false` → gri disabled görünür (stream akarken kullanıcı FAB'ı
  // önceden görür ama tıklayamaz).
  Widget _testQuestionsFab({bool enabled = true}) {
    final bg = enabled ? Color(0xFFFF6A00) : Color(0x33808080);
    final ink = enabled ? Colors.white : Color(0xCCFFFFFF);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: Color(0xFFFF6A00).withValues(alpha: 0.40),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.quiz_rounded, color: ink, size: 16),
          SizedBox(width: 6),
          Text('Test Çöz'.tr(),
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: ink)),
        ],
      ),
    );
    if (!enabled) return IgnorePointer(child: pill);
    return GestureDetector(onTap: _onTestQuestionsTap, child: pill);
  }

  Future<void> _onTestQuestionsTap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('library_subjects_questions_v2') ?? const [];
    final subjects = raw
        .map((s) {
          try {
            return _Subject.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<_Subject>()
        .toList();
    final subjTarget = widget.subjectName.toLowerCase().trim();
    final topicTarget = widget.summary.topic.toLowerCase().trim();
    _Subject? subject;
    for (final s in subjects) {
      if (s.name.toLowerCase().trim() == subjTarget) {
        subject = s;
        break;
      }
    }
    if (!mounted) return;

    // Hiç ders/konu yoksa direkt yeni test oluşturma akışına yönlendir.
    if (subject == null || subject.summaries.isEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AcademicPlanner(
          mode: LibraryMode.questions,
          autoOpenSubject: widget.subjectName,
          autoOpenTopic: widget.summary.topic,
        ),
      ));
      return;
    }

    // ŞU ANKİ konuya ait test var mı?
    //   • VAR → "Testlerim" picker'ı aç, bu konunun satırına (3 test sekmeli)
    //     odaklan.
    //   • YOK → direkt test oluşturma akışı (AcademicPlanner autoOpen).
    final currentTopicSummary = subject.summaries.firstWhere(
      (s) => s.topic.toLowerCase().trim() == topicTarget,
      orElse: () => _Summary(
        id: '', topic: '', content: '', createdAt: DateTime.now(),
      ),
    );
    final hasTestForThisTopic = currentTopicSummary.id.isNotEmpty &&
        currentTopicSummary.tests.isNotEmpty;

    if (!hasTestForThisTopic) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AcademicPlanner(
          mode: LibraryMode.questions,
          autoOpenSubject: widget.subjectName,
          autoOpenTopic: widget.summary.topic,
        ),
      ));
      return;
    }

    // Testlerim picker — bu konunun satırına auto-scroll + highlight.
    final result = await showModalBottomSheet<_TopicPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TestTopicPicker(
        subject: subject!,
        activeTopicLower: topicTarget,
        mode: _TestPickerMode.testlerim,
      ),
    );
    if (result == null || !mounted) return;
    await _navigateToTestWithIntent(subject, result.summary, result.intent);
  }

  /// Picker'dan dönen sonuca göre yönlendirme — Devam Et veya Yeni Test.
  Future<void> _navigateToTestWithIntent(
      _Subject subject, _Summary summary, _TestPickerIntent intent) async {
    if (intent == _TestPickerIntent.continueLast && summary.tests.isNotEmpty) {
      final attempt = summary.tests.last;
      if (attempt.completed) {
        final qs = parseTestQuestions(attempt.content);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TestResultPage(
            questions: qs,
            answers: attempt.answers,
            subjectName: subject.name,
            topic: summary.topic,
          ),
        ));
      } else {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TestPage(
            rawContent: attempt.content,
            subjectName: subject.name,
            topic: summary.topic,
            initialAnswers: attempt.answers,
            timeLimit: attempt.timeLimit,
            onFinish: (answers) async {
              attempt.answers = Map<int, String?>.from(answers);
              attempt.completed = true;
            },
          ),
        ));
      }
      return;
    }
    // Yeni Test → AcademicPlanner üzerinden mevcut otomatik açılış akışı.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AcademicPlanner(
        mode: LibraryMode.questions,
        autoOpenSubject: subject.name,
        autoOpenTopic: summary.topic,
      ),
    ));
  }

  // Sayfa açılır açılmaz görünen ince şerit — AI yazıyor / başarısız oldu.
  Widget _buildStreamingBanner() {
    final isFail = _streamFailed;
    final color = isFail
        ? Color(0xFFEF4444)
        : Color(0xFF7C3AED);
    final canRetry = isFail && widget.onRetry != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        children: [
          if (!isFail)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF7C3AED),
              ),
            )
          else
            Icon(Icons.error_outline_rounded,
                size: 16, color: Color(0xFFEF4444)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              isFail
                  ? (_streamFailMessage ??
                      'AI yanıt veremedi. Tekrar dene.')
                  : 'AI özeti yazıyor… içerik geldikçe ekrana akacak.',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          if (canRetry) ...[
            SizedBox(width: 8),
            // Sayfa içinde restart — listeye dönüp uzun basmaya gerek yok.
            InkWell(
              onTap: _retryStream,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 13, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Tekrar Dene'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Streaming aktifse o anki birikmiş içeriği göster; bittiğinde
    // widget.summary.content nihai metni içeriyor.
    final raw = _streamedContent ?? widget.summary.content;
    // Streaming durumunda her chunk için parse et (cache'li, idempotent).
    // Non-streaming durumda parse zaten initState'in postFrameCallback'inde
    // arkaplanda yapılıyor; ilk build skeleton döner → sayfa anında açılır.
    if (widget.stream != null) {
      _ensureParsed(raw);
    }
    final cleaned = _cachedCleaned;
    final keyFactsSection = _cachedKeyFacts;
    final normalSections = _cachedNormalSections;
    final examplesSection = _cachedExamples;
    // Cache henüz dolmadıysa (postFrame öncesi) hafif skeleton döndür —
    // sayfa transition'ı pürüzsüz başlar, içerik bir tick sonra dolar.
    final notParsedYet =
        _cachedRaw == null && raw.isNotEmpty && widget.stream == null;

    final pageBg = AppPalette.resolvePageBg(context, _pageBgOverride);

    // Streaming başladığında ama henüz anlamlı içerik gelmediğinde —
    // QuAlsar küresi + 3 birikimli aşama (analiz / özetleniyor / hazır).
    // İlk gerçek tokenlar gelene kadar gösterilir; sonrası içeriğe geçer.
    if (widget.stream != null && _streaming && cleaned.trim().length < 40) {
      return Scaffold(
        backgroundColor: AppPalette.card(context),
        body: QuAlsarLoadingWidget(
          type: QuAlsarLoadingType.summary,
          topic: widget.summary.topic,
          domain: _AcademicPlannerState._subjectLayer(widget.subjectName) ==
                  'verbal'
              ? SubjectDomain.verbal
              : SubjectDomain.numeric,
        ),
      );
    }

    if (notParsedYet) {
      return Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          backgroundColor: pageBg,
          elevation: 0,
          foregroundColor: AppPalette.textPrimary(context),
          titleSpacing: 0,
          title: const SizedBox.shrink(),
        ),
        body: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      // ── Sağ alt FAB: "Test Sorularını Çöz" ─────────────────────────
      // • _streamFailed → tamamen gizli (boş özetten test mantıksız)
      // • _streaming    → gri/disabled (kullanıcı önceden görsün, tıklayamaz)
      // • aksi          → normal aktif
      floatingActionButton: _streamFailed
          ? null
          : _testQuestionsFab(enabled: !_streaming),
      appBar: AppBar(
        // Üst bar her zaman soluk beyaz — kullanıcı renk paletini değiştirse
        // bile sabit kalır. Yükseklik 44 (varsayılan 56'dan dar).
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        titleSpacing: 0,
        toolbarHeight: 44,
        title: const SizedBox.shrink(),
        actions: [
          // Renkli "Renk Seç" pill — diğer sayfalardaki ile aynı.
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            child: GestureDetector(
              onTap: () => setState(
                  () => _showColorPicker = !_showColorPicker),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFF6A00),
                      Color(0xFFDB2777),
                      Color(0xFF7C3AED),
                      Color(0xFF2563EB),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showColorPicker
                          ? Icons.close_rounded
                          : Icons.palette_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      _showColorPicker
                          ? 'Kapat'.tr()
                          : 'Renk Seç'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // Klavye açıldığında layout otomatik kaysın (TextField sheet için kritik).
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Asıl içerik (sayfa)
          Column(children: [
          if (_showColorPicker) _buildColorPickerPanel(),
          // Streaming şeridi sadece HATA durumunda gösterilir; üretim
          // sırasında "AI özeti yazıyor…" yazısı kaldırıldı.
          if (_streamFailed) _buildStreamingBanner(),
          Expanded(
            child: DragTarget<Color>(
              onAcceptWithDetails: (d) {
                if (_colorMode == 'text') return;
                setState(() => _pageBgOverride = d.data);
                _saveColors();
              },
              builder: (ctx, cand, _) {
                // Lazy section render — sadece ekrandaki kart inşa edilir.
                // LaTeX widget'ları off-screen kartlarda compile edilmediği
                // için sayfa anında açılır, scrollda parça parça dolar.
                final hasFallback = normalSections.isEmpty &&
                    keyFactsSection == null &&
                    examplesSection == null;
                final sectionCount = hasFallback ? 1 : normalSections.length;
                final keyOffset = keyFactsSection != null ? 1 : 0;
                final exOffset = examplesSection != null ? 1 : 0;
                // Layout: [title, spacer, sections..., (spacer+keyFacts)?,
                //         (spacer+examples)?, rating?]
                // Rating widget'ı sadece cache ID'leri varsa gösterilir
                // (topluluk cache'i aktif değilse — eski özetler için).
                final showRating = widget.summary.cacheDocId != null &&
                    widget.summary.candidateDocId != null &&
                    widget.stream == null; // streaming bittiğinde göster
                final ratingOffset = showRating ? 1 : 0;
                final total = 2 +
                    sectionCount +
                    (keyOffset == 0 ? 0 : 2) +
                    (exOffset == 0 ? 0 : 2) +
                    ratingOffset;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 32),
                  itemCount: total,
                  cacheExtent: 600,
                  itemBuilder: (ctx, i) {
                    if (i == 0) return _buildTitleCard();
                    if (i == 1) return SizedBox(height: 14);
                    final sIdx = i - 2;
                    if (sIdx < sectionCount) {
                      if (hasFallback) {
                        return RepaintBoundary(
                          child: _wrappedCard(
                            child: _card(
                                header: '',
                                headerColor: Colors.black,
                                body: cleaned),
                          ),
                        );
                      }
                      final s = normalSections[sIdx];
                      return RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _wrappedCard(
                            child: _card(
                              header: s.header,
                              headerColor: s.color,
                              body: s.body,
                            ),
                          ),
                        ),
                      );
                    }
                    // Sıralama: keyFacts → examples (her ikisi opsiyonel).
                    int cursor = sectionCount;
                    if (keyFactsSection != null) {
                      if (sIdx == cursor) return SizedBox(height: 6);
                      if (sIdx == cursor + 1) {
                        return RepaintBoundary(
                          child: _wrappedCard(
                            child: _keyFactsCard(keyFactsSection),
                          ),
                        );
                      }
                      cursor += 2;
                    }
                    if (examplesSection != null) {
                      if (sIdx == cursor) return SizedBox(height: 8);
                      if (sIdx == cursor + 1) {
                        return RepaintBoundary(
                          child: _wrappedCard(
                            child: _examplesCard(examplesSection),
                          ),
                        );
                      }
                      cursor += 2;
                    }
                    // En sonda rating widget'ı (topluluk değerlendirme)
                    if (showRating && sIdx == cursor) {
                      return SummaryRatingTable(
                        cacheDocId: widget.summary.cacheDocId!,
                        candidateDocId: widget.summary.candidateDocId!,
                        isCanonical: widget.summary.isCanonical,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                );
              },
            ),
          ),
          ]),
          // Çalışma araç çubuğu — sol kenar; not + vurgulayıcı + kalem +
          // silgi + kapat. Çizimler topicId bazlı kalıcı saklanır.
          StudyToolbarOverlay(
            topicId: 'note_${widget.summary.id}',
            topicName: widget.summary.topic,
            scrollController: _scrollController,
          ),
        ],
      ),
    );
  }

  // Kart'ı DragTarget<Color> ile sar — hedef 'cards'.
  Widget _wrappedCard({required Widget child}) {
    return DragTarget<Color>(
      onAcceptWithDetails: (d) => _applyColorTo('cards', d.data),
      builder: (ctx, cand, _) => child,
    );
  }

  // ═════ İçerik temizleyici ═════
  String _clean(String content) {
    var out = content;
    // İlk başlık satırından önceki giriş paragrafını ("Harika...", "Tabii ki",
    // "Hemen başlayalım" vb.) kırp — özet doğrudan başlıkla başlasın.
    final firstHeader = RegExp(
      r'(📖[^\n]*|📚[^\n]*|🎯[^\n]*|📐[^\n]*|🌊[^\n]*|⭐[^\n]*)',
    );
    final fm = firstHeader.firstMatch(out);
    if (fm != null && fm.start > 0) {
      out = out.substring(fm.start);
    }
    // YouTube / Web satırları
    out = out.replaceAll(
      RegExp(r'\[(VIDEO|WEB):\s*"[^"]+"\s*\|\s*[^\]]+\]\s*$',
          caseSensitive: false, multiLine: true),
      '',
    );
    // SECTION HEADER ** ** SARMALARI — AI bazen başlıkları markdown bold ile
    // sarıyor: "**📚 Konu İşlenişi**". Bu durumda section parser emoji'yi
    // göremiyor → başlık BODY'ye düşüyor + ekranda yıldız görünüyor. Tam
    // satır olarak sarılı bold/italic'leri sökerek temiz emoji başlığı bırak.
    out = out.replaceAllMapped(
      RegExp(r'^\s*\*\*([^*\n]+?)\*\*\s*$', multiLine: true),
      (m) => m.group(1)!.trim(),
    );
    out = out.replaceAllMapped(
      RegExp(r'^\s*\*([^*\n]+?)\*\s*$', multiLine: true),
      (m) => m.group(1)!.trim(),
    );
    // Emoji marker'ından ÖNCE veya SONRA kalan tek-taraflı yıldızları
    // çıkar: "**📚 Header" → "📚 Header" / "📚 Header**" → "📚 Header".
    out = out.replaceAll(
      RegExp(r'^\*+\s*(?=[📖📚🔑📐🌊🎯⚠💡⭐📌1-9])', multiLine: true),
      '',
    );
    out = out.replaceAllMapped(
      RegExp(r'^([📖📚🔑📐🌊🎯⚠💡⭐📌][^\n]*?)\s*\*+\s*$',
          multiLine: true),
      (m) => m.group(1)!.trimRight(),
    );
    // Markdown bold (**...**) KORUNUR — LatexText inline bold render eder.
    // Tek yıldızlı italik (*...*) → metin (UI italic'i render etmiyor).
    out = out.replaceAllMapped(
      RegExp(r'(?<![\\\w*])\*([^*\n]+)\*(?!\w|\*)'),
      (m) => m.group(1) ?? '',
    );
    // İçi boş **...** → tamamen sil (AI bazen "** **" gibi süs bırakıyor)
    out = out.replaceAll(RegExp(r'\*\*\s*\*\*'), '');
    // Satır sonunda kalan tek "*" / "**" artıkları
    out = out.replaceAll(RegExp(r'\s\*+\s*$', multiLine: true), '');
    // Markdown başlık işaretleri ### ## # (satır başı + satır içi setext)
    out = out.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    // Setext başlık altçizgileri (=== veya ---) — başlık değil normal metin sandı
    out = out.replaceAll(
        RegExp(r'^[=\-]{3,}\s*$', multiLine: true), '');
    // Tek başına yıldız artıkları ("* metin" → "• metin")
    out = out.replaceAllMapped(
      RegExp(r'^\s*\*\s+', multiLine: true),
      (_) => '• ',
    );
    // Çift dolar kullanımları → LaTeX \[ \]
    out = out.replaceAllMapped(
      RegExp(r'\$\$([^\$\n]+)\$\$'),
      (m) => '\\[${m.group(1)}\\]',
    );
    // Tekli $...$ → \( ... \)
    out = out.replaceAllMapped(
      RegExp(r'\$([^\$\n]+)\$'),
      (m) => '\\(${m.group(1)}\\)',
    );
    // Serbest kalan yalnız dolar işaretleri — temizle
    out = out.replaceAll(RegExp(r'\s*\$\s*'), ' ');
    // Alt başlık içinde "1." "2." vs numara başı geçerse → "▸"
    // (AI bazen kurala uymaz; UI tarafında güvenceye al)
    out = out.replaceAllMapped(
      RegExp(r'^\s*(\d+)[\.\)]\s+', multiLine: true),
      (_) => '▸ ',
    );
    // "Sonuç:", "Püf Nokta:", "İpucu:" — özet modunda yasaklı etiketler.
    // Yine de çıkarsa temizlenir (defansif).
    out = out.replaceAll(
      RegExp(r'^\s*(Sonuç|Sonuc|Püf Nokta|Puf Nokta|İpucu|Ipucu|Tip|Conclusion|Key Tip|Pro Tip)\s*[:：].*$',
          multiLine: true, caseSensitive: false),
      '',
    );
    // Triple newline → double
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  bool _isKeyFactsHeader(String h) {
    final t = h.toLowerCase();
    return t.contains('⭐') ||
        t.contains('en önemli 5') ||
        t.contains('en onemli 5') ||
        t.contains('top 5') ||
        t.contains('5 key') ||
        t.contains('5 temel');
  }

  /// Header metnindeki bilinen emoji marker'ları + Markdown süs karakterlerini
  /// (#, *, ~, `, baştaki noktalama) temizler. İkon ayrı yerde render edildiği
  /// için saf metin kalır.
  String _stripHeaderMarkers(String header) {
    var t = header;
    const markers = [
      '1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣',
      '📖', '📚', '🔑', '📐', '🌊', '🎯',
      '⚠️', '⚠', '💡', '⭐', '📌',
    ];
    bool changed = true;
    while (changed) {
      changed = false;
      final stripped = t.trimLeft();
      for (final m in markers) {
        if (stripped.startsWith(m)) {
          t = stripped.substring(m.length);
          changed = true;
          break;
        }
      }
    }
    // İçerideki ** ** süslemeleri ve baş/son noktalama → kaldır.
    t = t.replaceAll(RegExp(r'\*+'), '');
    t = t.replaceAll(RegExp(r'^#{1,6}\s*'), '');
    t = t.replaceAll(RegExp(r'^[\s#~`›▸•:\-—–]+'), '');
    t = t.replaceAll(RegExp(r'[\s#~`›:]+$'), '');
    return t.trim();
  }

  /// Ders adına göre ana başlık ikonu — Matematik=hesap, Tarih=müze vb.
  IconData _subjectIcon(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('mat') || s.contains('math')) {
      return Icons.functions_rounded;
    }
    if (s.contains('fizik') || s.contains('phys')) {
      return Icons.science_rounded;
    }
    if (s.contains('kimya') || s.contains('chem')) {
      return Icons.biotech_rounded;
    }
    if (s.contains('biyo') || s.contains('bio')) {
      return Icons.eco_rounded;
    }
    if (s.contains('tarih') || s.contains('history')) {
      return Icons.museum_rounded;
    }
    if (s.contains('coğraf') ||
        s.contains('cograf') ||
        s.contains('geo')) {
      return Icons.public_rounded;
    }
    if (s.contains('türk') ||
        s.contains('turk') ||
        s.contains('edebiyat') ||
        s.contains('literat')) {
      return Icons.menu_book_rounded;
    }
    if (s.contains('ingiliz') ||
        s.contains('english') ||
        s.contains('almanca') ||
        s.contains('frans') ||
        s.contains('german') ||
        s.contains('french')) {
      return Icons.translate_rounded;
    }
    if (s.contains('felsefe') || s.contains('philosoph')) {
      return Icons.psychology_rounded;
    }
    if (s.contains('din') || s.contains('religi')) {
      return Icons.auto_stories_rounded;
    }
    if (s.contains('müzik') || s.contains('muzik') || s.contains('music')) {
      return Icons.music_note_rounded;
    }
    if (s.contains('beden') ||
        s.contains('spor') ||
        s.contains('sport') ||
        s.contains('phys ed')) {
      return Icons.directions_run_rounded;
    }
    if (s.contains('bilgisayar') ||
        s.contains('inform') ||
        s.contains('computer') ||
        s.contains('kodlam')) {
      return Icons.computer_rounded;
    }
    if (s.contains('sanat') || s.contains('resim') || s.contains('art')) {
      return Icons.palette_rounded;
    }
    return Icons.school_rounded;
  }

  // ═════ Normal alt başlık kartı — bölüm rengiyle tonlanmış belirgin çerçeve ═
  //   • Kart kenarlığı: bölüm rengi (headerColor) ile vurgulu
  //   • Üst bant: aynı renkten yumuşak tinted zemin + sol şerit + accent metin
  //   • Hafif drop shadow → kartlar sayfadan ayrışır
  Widget _card({
    required String header,
    required Color headerColor,
    required String body,
  }) {
    final bg = AppPalette.resolveCardBg(context, _cardsBgOverride);
    final ink = _cardsTextOverride ??
        (_isDark(bg) ? Colors.white : Colors.black);
    // Üst bant arkaplanı: bölüm rengiyle tonlanmış soft tint. Kullanıcı renk
    // override yaptıysa bg'yi koru (tutarlılık).
    final headerBg = _cardsBgOverride == null
        ? Color.alphaBlend(
            headerColor.withValues(alpha: 0.13), Colors.white)
        : bg;
    final cleanedHeader = _stripHeaderMarkers(header);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: headerColor.withValues(alpha: 0.55), width: 1.6),
        boxShadow: [
          BoxShadow(
            color: headerColor.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cleanedHeader.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
              decoration: BoxDecoration(
                color: headerBg,
                border: Border(
                  bottom: BorderSide(
                    color: headerColor.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                  left: BorderSide(
                    color: headerColor,
                    width: 4,
                  ),
                ),
              ),
              child: Text(
                cleanedHeader,
                style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: _cardsTextOverride ?? headerColor,
                  letterSpacing: 0.15,
                  height: 1.25,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: ink),
              child: LatexText(body, fontSize: 14, lineHeight: 1.65),
            ),
          ),
        ],
      ),
    );
  }

  // ═════ 📝 Örnek Sorular — gri zeminli özel kart (özetin sonunda) ═══════
  //   3 kısa soru + kısa cevap; AI tarafından "📝 Örnek Sorular" başlığıyla
  //   üretilir, parser bu section'ı _cachedExamples'a yönlendirir.
  Widget _examplesCard(_Section s) {
    final bg = AppPalette.resolveInnerBg(context, _cardsBgOverride);
    final ink = _cardsTextOverride ??
        (_isDark(bg) ? Colors.white : Colors.black);
    const accent = Color(0xFF6B7280); // slate-500
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('📝', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Text(
                'Konuyu Pekiştirme Soruları'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: _cardsTextOverride ?? accent,
                  letterSpacing: 0.15,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Container(height: 1, color: accent.withValues(alpha: 0.30)),
          SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: TextStyle(color: ink),
            child: LatexText(s.body, fontSize: 13.5, lineHeight: 1.6),
          ),
        ],
      ),
    );
  }

  // ═════ ⭐ En Önemli 5 Bilgi — vurgulu, farklı renk kartı ═════
  Widget _keyFactsCard(_Section s) {
    final bg = AppPalette.resolveInnerBg(context, _cardsBgOverride);
    final ink = _cardsTextOverride ??
        (_isDark(bg) ? Colors.white : Colors.black);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.textPrimary(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'En Önemli 5 Bilgi'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ink,
              letterSpacing: 0.15,
            ),
          ),
          SizedBox(height: 6),
          Container(height: 1, color: ink.withValues(alpha: 0.25)),
          SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: TextStyle(color: ink),
            child: LatexText(s.body, fontSize: 14, lineHeight: 1.7),
          ),
        ],
      ),
    );
  }

  // ══════════════════ Renk seçim paneli — diğer sayfalar ile aynı ═══════════
  Widget _buildColorPickerPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.textPrimary(context), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded,
                  size: 16, color: Colors.black),
              SizedBox(width: 6),
              Text('Renk'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
              SizedBox(width: 10),
              Expanded(child: _modeToggle()),
              SizedBox(width: 8),
              GestureDetector(
                onTap: _resetColors,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppPalette.cardMuted(context),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text('Sıfırla'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.black54)),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          _targetToggle(),
          SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin yere bırak.'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
                height: 1.3),
          ),
          SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _palette.length,
              itemBuilder: (_, i) => _draggableColor(_palette[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeToggle() {
    Widget box(String id, IconData icon, String label) {
      final active = _colorMode == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorMode = id),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 140),
            padding:
                const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: active
                  ? _orange.withValues(alpha: 0.12)
                  : Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _orange : Colors.black,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 13,
                    color: active ? _orange : Colors.black),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active ? _orange : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        box('text', Icons.text_fields_rounded, 'Yazı'.tr()),
        SizedBox(width: 8),
        box('frame', Icons.crop_square_rounded, 'Çerçeve'.tr()),
      ],
    );
  }

  Widget _targetToggle() {
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = id),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? _orange.withValues(alpha: 0.12)
                  : Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _orange : Colors.black12,
                width: active ? 1.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: active ? _orange : Colors.black),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('bg', 'Arka plan'.tr()),
        SizedBox(width: 6),
        chip('title', 'Başlık'.tr()),
        SizedBox(width: 6),
        chip('cards', 'Kartlar'.tr()),
      ],
    );
  }

  Widget _draggableColor(Color c) {
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _dot(c)),
      child: GestureDetector(
        onTap: () => _applyColorTo(_colorTarget, c),
        child: _dot(c),
      ),
    );
  }

  Widget _dot(Color c) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border(context), width: 1),
      ),
    );
  }

  // Emoji başlıklarına göre böl: 📚 🔑 📐 🎯 ⚠️ ⭐
  List<_Section> _splitSections(String content) {
    const markers = {
      '📖': Color(0xFF0F766E), // Tanım — teal
      '📚': Color(0xFF2563EB),
      '🔑': Color(0xFF059669),
      '📐': Color(0xFF7C3AED),
      '🌊': Color(0xFF0EA5E9),
      '🎯': Color(0xFFEA580C),
      '⚠️': Color(0xFFDC2626),
      '💡': Color(0xFFCA8A04),
      '⭐': Color(0xFFCA8A04),
      '📌': Color(0xFF334155), // Özetle kapanış — slate
      '📝': Color(0xFF6B7280), // Örnek sorular — gri (özel kart)
      '1️⃣': Color(0xFF2563EB),
      '2️⃣': Color(0xFF059669),
      '3️⃣': Color(0xFF7C3AED),
      '4️⃣': Color(0xFFEA580C),
      '5️⃣': Color(0xFFDC2626),
      '6️⃣': Color(0xFF0891B2),
    };
    final lines = content.split('\n');
    final sections = <_Section>[];
    _Section? current;
    // ⭐ "EN ÖNEMLİ 5 BİLGİ" section'ı başlayınca — sonraki satırlar marker
    // (🔑 vs.) olsa bile yeni section açma; hepsi bu vurgulu kartın body'si.
    bool inKeyFactsBlock = false;
    for (final raw in lines) {
      final line = raw.trimRight();
      final trim = line.trimLeft();
      String? foundMarker;
      if (!inKeyFactsBlock) {
        for (final m in markers.keys) {
          if (trim.startsWith(m)) {
            foundMarker = m;
            break;
          }
        }
      }
      if (foundMarker != null) {
        if (current != null) {
          current.body = current.body.trim();
          if (current.body.isNotEmpty || current.header.isNotEmpty) {
            sections.add(current);
          }
        }
        current = _Section(
          header: trim,
          color: markers[foundMarker]!,
          body: '',
        );
        if (foundMarker == '⭐') inKeyFactsBlock = true;
      } else if (current != null) {
        current.body += '$line\n';
      } else if (line.trim().isNotEmpty) {
        current = _Section(
          header: '',
          color: AppPalette.textPrimary(context),
          body: '$line\n',
        );
      }
    }
    if (current != null) {
      current.body = current.body.trim();
      if (current.body.isNotEmpty || current.header.isNotEmpty) {
        sections.add(current);
      }
    }
    return sections;
  }
}

class _Section {
  String header;
  Color color;
  String body;
  _Section({required this.header, required this.color, required this.body});
}

// ══════════════════════════════════════════════════════════════════════════
//  Zorluk Seçici Dialog — Kolay · Orta · Zor. Kullanıcı bir kutuya basarak
//  seçer, sağ altta "Tamam" ile _TestConfig döner.
// ══════════════════════════════════════════════════════════════════════════
class _DifficultyPickerDialog extends StatefulWidget {
  const _DifficultyPickerDialog();

  @override
  State<_DifficultyPickerDialog> createState() =>
      _DifficultyPickerDialogState();
}

class _DifficultyPickerDialogState extends State<_DifficultyPickerDialog> {
  // Üç satırlı seçim — hepsi default olarak dolu (medium / 10 / relax),
  // kullanıcı istemezse dokunmadan "Tamam"a basabilir → eski davranış.
  String _difficulty = 'medium'; // 'easy' | 'medium' | 'hard'
  int _count = 10; // 5 | 10 | 15 | 20
  String _timeMode = 'relax'; // 'relax' | 'normal' | 'race'

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Dialog(
        backgroundColor: AppPalette.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Başlık
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Test Ayarları'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.textPrimary(context),
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppPalette.cardMuted(context),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Icon(Icons.close_rounded,
                            size: 15, color: Colors.black),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),

                // ── Satır 1: Zorluk ─────────────────────────────────────
                _sectionLabel('Zorluk'.tr()),
                SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _difficultyBox(
                        id: 'easy',
                        emoji: '🌱',
                        label: 'Kolay'.tr(),
                        accent: Color(0xFF10B981),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _difficultyBox(
                        id: 'medium',
                        emoji: '⚖️',
                        label: 'Orta'.tr(),
                        accent: Color(0xFFF59E0B),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _difficultyBox(
                        id: 'hard',
                        emoji: '🔥',
                        label: 'Zor'.tr(),
                        accent: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),

                // ── Satır 2: Soru sayısı ────────────────────────────────
                _sectionLabel('Soru Sayısı'.tr()),
                SizedBox(height: 6),
                Row(
                  children: [
                    for (final n in const [5, 10, 15, 20]) ...[
                      Expanded(child: _countPill(n)),
                      if (n != 20) SizedBox(width: 8),
                    ],
                  ],
                ),
                SizedBox(height: 14),

                // ── Satır 3: Süre modu ──────────────────────────────────
                _sectionLabel('Süre Modu'.tr()),
                SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _timeBox(
                        id: 'relax',
                        emoji: '🧘',
                        label: 'Rahat'.tr(),
                        sub: 'Süresiz'.tr(),
                        accent: Color(0xFF6B7280),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _timeBox(
                        id: 'normal',
                        emoji: '⏱️',
                        label: 'Normal'.tr(),
                        sub: '90s/soru'.tr(),
                        accent: Color(0xFF2563EB),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _timeBox(
                        id: 'race',
                        emoji: '⚡',
                        label: 'Hız'.tr(),
                        sub: '45s/soru'.tr(),
                        accent: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 16),
                // Tamam — her zaman aktif, default değerlerle de basılabilir.
                GestureDetector(
                  onTap: () {
                    final cfg = _TestConfig()
                      ..difficulty = _difficulty
                      ..count = _count
                      ..timeMode = _timeMode;
                    Navigator.of(context).pop(cfg);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Teste Başla'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String t) => Text(
        t,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppPalette.textSecondary(context),
          letterSpacing: 0.3,
        ),
      );

  Widget _difficultyBox({
    required String id,
    required String emoji,
    required String label,
    required Color accent,
  }) {
    final active = _difficulty == id;
    return GestureDetector(
      onTap: () => setState(() => _difficulty = id),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? accent : Colors.black,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: TextStyle(fontSize: 22)),
            SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: active ? accent : Colors.black,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countPill(int n) {
    final active = _count == n;
    return GestureDetector(
      onTap: () => setState(() => _count = n),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black,
            width: active ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '$n',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: active ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _timeBox({
    required String id,
    required String emoji,
    required String label,
    required String sub,
    required Color accent,
  }) {
    final active = _timeMode == id;
    return GestureDetector(
      onTap: () => setState(() => _timeMode = id),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? accent : Colors.black,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: TextStyle(fontSize: 20)),
            SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: active ? accent : Colors.black,
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Sınav Soruları sayfasında — bir dersin altındaki her test için
// özet + test denemesi + sırası (1./2./3. deneme) ikilisi.
class _AttemptRef {
  final _Summary summary;
  final _TestAttempt attempt;
  final int attemptIndex; // 1-based
  _AttemptRef({
    required this.summary,
    required this.attempt,
    required this.attemptIndex,
  });
}


// ═══════════════════════════════════════════════════════════════════════════════
//  _SubjectTopicsDialog — ders seçildiğinde açılan küçük modal.
//  Sol sütun: curriculum konuları (oval pill, ince siyah border)
//  Sağ sütun: "Konu Özeti" (varsa) / "Oluştur" rozeti
//  Alt: yeni konu ekle input + kaydet (eklenince ikon görünür)
// ═══════════════════════════════════════════════════════════════════════════════

class _SubjectTopicsDialog extends StatefulWidget {
  final String subjectName;
  final String subjectEmoji;
  final Color subjectColor;
  final String profileLabel;
  final List<String> curriculumTopics;
  final LibraryMode mode; // summary → "Konu Özeti", questions → "Soru Seti"
  final _Subject Function() getExistingSubject;
  final Future<void> Function(String topic) onGenerateTopic;
  final void Function(_Summary summary) onOpenExistingSummary;
  final Future<void> Function(String topic) onAddCustomTopic;

  const _SubjectTopicsDialog({
    required this.subjectName,
    required this.subjectEmoji,
    required this.subjectColor,
    required this.profileLabel,
    required this.curriculumTopics,
    required this.mode,
    required this.getExistingSubject,
    required this.onGenerateTopic,
    required this.onOpenExistingSummary,
    required this.onAddCustomTopic,
  });

  // Sağ sekme etiketleri — mod'a göre
  String get _existingLabel =>
      mode == LibraryMode.questions ? 'Test Soruları' : 'Konu Özeti';
  String get _createLabel =>
      mode == LibraryMode.questions ? 'Test Oluştur' : 'Özet Oluştur';

  @override
  State<_SubjectTopicsDialog> createState() => _SubjectTopicsDialogState();
}

class _SubjectTopicsDialogState extends State<_SubjectTopicsDialog> {
  final _newTopicCtrl = TextEditingController();
  final Set<String> _savedCustomTopics = {};

  @override
  void dispose() {
    _newTopicCtrl.dispose();
    super.dispose();
  }

  _Summary? _summaryForTopic(String topic) {
    final subj = widget.getExistingSubject();
    for (final s in subj.summaries) {
      if (s.topic.toLowerCase() == topic.toLowerCase()) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.getExistingSubject();
    final existingTopics = existing.summaries.map((s) => s.topic).toList();
    final extras = existingTopics
        .where((t) => !widget.curriculumTopics
            .any((c) => c.toLowerCase() == t.toLowerCase()))
        .toList();
    final allTopics = [...widget.curriculumTopics, ...extras];

    return Dialog(
      // Dialog iç zemini SOLUK beyaz — konu kartları (saf beyaz) öne çıksın
      backgroundColor: AppPalette.bg(context),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ═══ Ders başlığı — merkezde, büyük ═══
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.subjectEmoji,
                            style: TextStyle(fontSize: 28)),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.subjectName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimary(context),
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              SizedBox(height: 14),
              // Ders başlığı altında ince ayırıcı — yumuşak ton
              Container(height: 1, color: Colors.black.withValues(alpha: 0.08)),
              SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (allTopics.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Bu ders için henüz müfredat konuları yüklenmemiş. Aşağıdan kendi konunu ekleyebilirsin.'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                        )
                      else
                        for (final topic in allTopics) _topicRow(topic),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Yeni Konu Ekle'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textSecondary(context),
                  letterSpacing: 0.08,
                ),
              ),
              SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
            color: AppPalette.card(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          textSelectionTheme: TextSelectionThemeData(
                            cursorColor: Colors.black,
                            selectionColor:
                                Colors.black.withValues(alpha: 0.25),
                            selectionHandleColor: Colors.black,
                          ),
                        ),
                        child: TextField(
                          controller: _newTopicCtrl,
                          textCapitalization: TextCapitalization.sentences,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.textPrimary(context),
                          ),
                          cursorColor: Colors.black,
                          decoration: InputDecoration(
                            hintText: 'Konu başlığı…'.tr(),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppPalette.textSecondary(context),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      final t = _newTopicCtrl.text.trim();
                      if (t.isEmpty) return;
                      setState(() {
                        _savedCustomTopics.add(t);
                        _newTopicCtrl.clear();
                      });
                      await widget.onAddCustomTopic(t);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppPalette.textPrimary(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Kaydet'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
            // ═══ Kapat butonu — Dialog kartının SAĞ ÜSTÜNDE (çerçevesiz) ═══
            Positioned(
              right: 10,
              top: 10,
              child: Material(color: AppPalette.card(context),
                shape: CircleBorder(),
                child: InkWell(
                  customBorder: CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: Colors.black),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topicRow(String topic) {
    final existing = _summaryForTopic(topic);
    final hasSummary = existing != null;
    final hasIcon = hasSummary || _savedCustomTopics.contains(topic);
    final isQuestions = widget.mode == LibraryMode.questions;
    // Questions mode'da sağdaki butonun davranışı:
    //   • testCount < 3  → her tıklama yeni test üretir (eski sonuca gitmez)
    //   • testCount == 3 → buton kilitli, dokununca uyarı snackbar'ı
    final testCount =
        isQuestions && existing != null ? existing.tests.length : 0;
    final limitReached = isQuestions && testCount >= 3;

    final IconData actionIcon;
    final String actionLabel;
    final Color actionBg;
    final Color actionFg;
    if (isQuestions) {
      if (limitReached) {
        actionIcon = Icons.lock_rounded;
        actionLabel = '${'Limit'.tr()} · 3/3';
        actionBg = Color(0xFFE5E7EB);
        actionFg = Colors.black54;
      } else if (testCount > 0) {
        actionIcon = Icons.add_rounded;
        actionLabel = '${'Yeni Test'.tr()} · $testCount/3';
        actionBg = Color(0xFFEFF1F6);
        actionFg = Colors.black;
      } else {
        actionIcon = Icons.auto_awesome_rounded;
        actionLabel = widget._createLabel.tr();
        actionBg = Color(0xFFEFF1F6);
        actionFg = Colors.black;
      }
    } else {
      actionIcon = hasSummary
          ? Icons.auto_stories_rounded
          : Icons.auto_awesome_rounded;
      actionLabel =
          hasSummary ? widget._existingLabel.tr() : widget._createLabel.tr();
      actionBg = Color(0xFFEFF1F6);
      actionFg = Colors.black;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('•',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppPalette.textPrimary(context),
                      fontWeight: FontWeight.w800)),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                topic,
                maxLines: 3,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary(context),
                  height: 1.3,
                ),
              ),
            ),
            if (hasIcon) ...[
              SizedBox(width: 6),
              Icon(Icons.check_circle_rounded,
                  size: 14, color: Colors.black),
            ],
            SizedBox(width: 10),
            Material(
              color: actionBg,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  if (limitReached) {
                    // Limit dolu — diyaloğu kapat, planner sayfasında
                    // (3 slot'un göründüğü konu satırının olduğu sayfa)
                    // uyarı snackbar'ı göster.
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(context).pop();
                    messenger.showSnackBar(SnackBar(
                      content: Text(
                        'Bu konudan zaten 3 test oluşturdun. Aynı konu için en fazla 3 test oluşturabilirsin.'
                            .tr(),
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
                    return;
                  }
                  if (isQuestions) {
                    widget.onGenerateTopic(topic);
                  } else if (hasSummary) {
                    widget.onOpenExistingSummary(existing);
                  } else {
                    widget.onGenerateTopic(topic);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(actionIcon, size: 13, color: actionFg),
                      SizedBox(width: 5),
                      Text(
                        actionLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: actionFg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Test Setup Page — sınav için "Son Ayarlar" (QuAlsar Arena stilinde).
//  Soru sayısı · Zorluk · Süre Modu. Onaylayınca _TestConfig döner.
// ═══════════════════════════════════════════════════════════════════════════════

class _TestSetupPage extends StatefulWidget {
  final String subjectName;
  final String topic;
  final int attemptIndex; // 0..2 — 1./2./3. test
  const _TestSetupPage({
    required this.subjectName,
    required this.topic,
    required this.attemptIndex,
  });

  @override
  State<_TestSetupPage> createState() => _TestSetupPageState();
}

class _TestSetupPageState extends State<_TestSetupPage> {
  final _cfg = _TestConfig();

  @override
  Widget build(BuildContext context) {
    final pageBg = AppPalette.bg(context);
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        centerTitle: true,
        title: Text(
          '${widget.attemptIndex + 1}. ${'Test'.tr()}',
          style:
              GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Son Ayarlar'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimary(context),
                              height: 1.1,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${widget.subjectName} · ${widget.topic}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 18),
                    _TestPillGroup(
                      label: '📊 SORU SAYISI'.tr(),
                      options: const [
                        _TestPillOpt('5', '⚡', '5 Soru', '~5 dk'),
                        _TestPillOpt('10', '📝', '10 Soru', '~10 dk'),
                        _TestPillOpt('15', '📚', '15 Soru', '~15 dk'),
                        _TestPillOpt('20', '🎯', '20 Soru', '~20 dk'),
                      ],
                      selected: '${_cfg.count}',
                      onSelect: (v) =>
                          setState(() => _cfg.count = int.parse(v)),
                    ),
                    _TestPillGroup(
                      label: '⚡ ZORLUK SEVİYESİ'.tr(),
                      options: const [
                        _TestPillOpt('easy', '🟢', 'Kolay', 'Temel',
                            tone: Color(0xFF059669),
                            toneBg: Color(0xFFECFDF5)),
                        _TestPillOpt('medium', '🟡', 'Orta', 'Dengeli',
                            tone: Color(0xFFD97706),
                            toneBg: Color(0xFFFFFBEB)),
                        _TestPillOpt('hard', '🔴', 'Zor', 'Zorlayıcı',
                            tone: Color(0xFFDC2626),
                            toneBg: Color(0xFFFEF2F2)),
                      ],
                      selected: _cfg.difficulty,
                      onSelect: (v) =>
                          setState(() => _cfg.difficulty = v),
                    ),
                    _TestPillGroup(
                      label: '⏱️ SÜRE MODU'.tr(),
                      options: const [
                        _TestPillOpt('relax', '🧘', 'Rahat', 'Süre yok'),
                        _TestPillOpt(
                            'normal', '⏲️', 'Normal', '90 sn/soru'),
                        _TestPillOpt('race', '🔥', 'Yarış', '45 sn/soru'),
                      ],
                      selected: _cfg.timeMode,
                      onSelect: (v) =>
                          setState(() => _cfg.timeMode = v),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(_cfg),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _orange,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: _orange.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🚀', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 8),
                      Text(
                        'Testi Oluştur'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestPillOpt {
  final String value;
  final String emoji;
  final String title;
  final String hint;
  final Color? tone;
  final Color? toneBg;
  const _TestPillOpt(this.value, this.emoji, this.title, this.hint,
      {this.tone, this.toneBg});
}

class _TestPillGroup extends StatelessWidget {
  final String label;
  final List<_TestPillOpt> options;
  final String selected;
  final ValueChanged<String> onSelect;
  const _TestPillGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppPalette.textSecondary(context),
              letterSpacing: 0.8,
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              for (int i = 0; i < options.length; i++) ...[
                if (i > 0) SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onSelect(options[i].value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected == options[i].value
                            ? (options[i].toneBg ?? Colors.white)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected == options[i].value
                              ? (options[i].tone ?? Colors.black)
                              : Colors.black12,
                          width: selected == options[i].value ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(options[i].emoji,
                              style: TextStyle(fontSize: 22)),
                          SizedBox(height: 4),
                          Text(
                            options[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            options[i].hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Pomodoro Tekniği — iki alt başlığı barındıran kapsayıcı sayfa:
//    • Yeşil Koloni (mola zamanı mini oyun)
//    • QuAlsar · Mars Protokolü (derin odak pomodoro)
//  İlk tıklamada kısa açıklama modalı çıkar, "Tamam" ile kapanır; tekrar
//  girişlerde gösterilmez (SharedPreferences bayrağı).
// ═══════════════════════════════════════════════════════════════════════════════

// Diğer Dersler sheet'indeki ders tile'ı — uzun basışta drag başlar,
// onDragStarted ile parent sheet'i kapatır. Ayrıca DragTarget<String>
// olduğu için, sheet içindeki başka bir ders üstüne bırakılınca onAcceptSwap
// tetiklenir (sheet içi yer değiştirme).
class _OverflowSubjectTile extends StatelessWidget {
  final EduSubject subject;
  final Color? bgColor;
  final Color? textColor;
  final VoidCallback onTap;
  final VoidCallback onDragStarted;
  final VoidCallback? onDragEnd;
  final ValueChanged<String>? onAcceptSwap;
  const _OverflowSubjectTile({
    required this.subject,
    required this.onTap,
    required this.onDragStarted,
    this.bgColor,
    this.textColor,
    this.onDragEnd,
    this.onAcceptSwap,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != subject.key,
      onAcceptWithDetails: (d) => onAcceptSwap?.call(d.data),
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        final dark = AppPalette.isDark(ctx);
        final bg = bgColor ?? (dark ? Colors.black : Colors.white);
        final lum = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
        final autoFg = lum < 0.55 ? Colors.white : Colors.black;
        final fg = textColor ?? autoFg;
        final defaultBorder = dark ? const Color(0xFF2E2E2E) : Colors.black;
        final tile = AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering ? Color(0xFFFF6A00) : defaultBorder,
              width: hovering ? 2.4 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(subject.emoji, style: TextStyle(fontSize: 22)),
              SizedBox(height: 3),
              Text(
                subject.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  height: 1.15,
                ),
              ),
            ],
          ),
        );
        return LongPressDraggable<String>(
          data: subject.key,
          onDragStarted: onDragStarted,
          onDragEnd: (_) => onDragEnd?.call(),
          onDraggableCanceled: (_, __) => onDragEnd?.call(),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: 72, height: 72, child: tile),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: tile),
          child: GestureDetector(onTap: onTap, child: tile),
        );
      },
    );
  }
}

class _PomodoroTechniquePage extends StatefulWidget {
  const _PomodoroTechniquePage();

  @override
  State<_PomodoroTechniquePage> createState() => _PomodoroTechniquePageState();
}

class _PomodoroTechniquePageState extends State<_PomodoroTechniquePage>
    with WidgetsBindingObserver {
  static const _colonyPrefKey = 'pomodoro_intro_colony_seen_v1';
  static const _marsPrefKey = 'pomodoro_intro_mars_seen_v1';

  PomodoroStatsSnapshot _stats = PomodoroStatsSnapshot.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Alt sayfadan dönüş veya app foreground'a gelince istatistik yenile.
    if (state == AppLifecycleState.resumed) _refreshStats();
  }

  Future<void> _refreshStats() async {
    final s = await PomodoroStats.read();
    if (!mounted) return;
    setState(() {
      _stats = s;
      _loading = false;
    });
  }

  Future<void> _openWithIntro(
    BuildContext context, {
    required String prefKey,
    required String title,
    required String emoji,
    required String intro,
    required Widget Function() pageBuilder,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(prefKey) ?? false;
    if (!context.mounted) return;
    if (!seen) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (ctx) => _IntroDialog(
          title: title,
          emoji: emoji,
          body: intro,
        ),
      );
      await prefs.setBool(prefKey, true);
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => pageBuilder()),
    );
    // Geri dönüşte istatistik yenile.
    _refreshStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_rounded,
                color: Color(0xFFE11D48), size: 22),
            SizedBox(width: 8),
            Text(
              'Pomodoro Tekniği'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.emoji_events_rounded,
                color: AppPalette.textPrimary(context)),
            tooltip: 'Rozetler'.tr(),
            onPressed: _stats.marsBadges.isEmpty
                ? null
                : () => _openBadgesSheet(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Odaklanmış çalışma ritmi — 25 dk çalış, 5 dk dinlen. Aşağıdan iki farklı pomodoro modunu seçebilirsin.'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
            SizedBox(height: 14),
            if (!_loading) _buildStatsCard(context),
            SizedBox(height: 14),
            _LandingCard(
              icon: Icons.eco_rounded,
              title: 'Yeşil Koloni'.tr(),
              color: Color(0xFF00B070),
              onTap: () => _openWithIntro(
                context,
                prefKey: _colonyPrefKey,
                title: 'Yeşil Koloni'.tr(),
                emoji: '🌱',
                intro: 'Pomodoro boyunca küçük bir koloni geliştiriyorsun. '
                        'Her tamamlanan 25 dakikalık odak seansı için '
                        'bir kapsül ekilir ve oksijen yenilenir. '
                        'Kesintisiz odaklanmak kolonini büyütür; '
                        'çalışma takvimine de otomatik yazılır. '
                        'Hedef: haftalar içinde kapsülleri çoğaltıp '
                        'koloniyi büyütmek.'
                    .tr(),
                pageBuilder: () => GreenColonyScreen(),
              ),
            ),
            SizedBox(height: 12),
            _LandingCard(
              icon: Icons.rocket_launch_rounded,
              title: 'QuAlsar · Mars Protokolü'.tr(),
              color: Color(0xFFFF6A3C),
              onTap: () => _openWithIntro(
                context,
                prefKey: _marsPrefKey,
                title: 'QuAlsar · Mars Protokolü'.tr(),
                emoji: '🚀',
                intro: 'Bu mod derin odak için tasarlandı. Her aşama bir '
                        '"görev fazı"dır; görev boyunca koloni Mars\'ta '
                        'kurulur. Uygulamadan çıkarsan sinyal kaybı alarmı '
                        'başlar; geri dönmezsen aşama biter. Her tamamlanan '
                        'faz çalışma takvimine yazılır ve rozet açar. '
                        '4 fazı tamamlayınca "Koloni Kurucusu" rozetini alırsın.'
                    .tr(),
                pageBuilder: () => QuAlsarMarsScreen(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ink.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 18, color: ink),
              SizedBox(width: 6),
              Text(
                'Odak İstatistiğin'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  emoji: '🎯',
                  label: 'Toplam'.tr(),
                  value: '${_stats.totalPhases}',
                  ink: ink,
                  muted: muted,
                ),
              ),
              Expanded(
                child: _statTile(
                  emoji: '☀️',
                  label: 'Bugün'.tr(),
                  value: '${_stats.todayPhases}',
                  ink: ink,
                  muted: muted,
                ),
              ),
              Expanded(
                child: _statTile(
                  emoji: '🔥',
                  label: 'Streak'.tr(),
                  value: '${_stats.streakDays} ${'gün'.tr()}',
                  ink: ink,
                  muted: muted,
                ),
              ),
            ],
          ),
          if (_stats.marsBadges.isNotEmpty) ...[
            SizedBox(height: 8),
            Divider(height: 1, color: ink.withValues(alpha: 0.10)),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.emoji_events_rounded,
                    size: 16, color: Colors.amber.shade700),
                SizedBox(width: 4),
                Text(
                  '${_stats.marsBadges.length} ${'rozet'.tr()}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _stats.marsBadges
                        .take(5)
                        .map((id) => findPomodoroBadge(id)?.emoji ?? '🏅')
                        .join('  '),
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statTile({
    required String emoji,
    required String label,
    required String value,
    required Color ink,
    required Color muted,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: TextStyle(fontSize: 22)),
        SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: ink,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: muted,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  void _openBadgesSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final earned = _stats.marsBadges.toSet();
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scroll) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppPalette.border(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Rozetler'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${earned.length} / ${pomodoroBadgeCatalog.length}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppPalette.textSecondary(context),
                    ),
                  ),
                  SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      controller: scroll,
                      itemCount: pomodoroBadgeCatalog.length,
                      separatorBuilder: (_, __) => SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final b = pomodoroBadgeCatalog[i];
                        final got = earned.contains(b.id);
                        return Opacity(
                          opacity: got ? 1 : 0.4,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppPalette.bg(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: got
                                    ? Colors.amber.shade700
                                    : AppPalette.border(context),
                                width: got ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(b.emoji,
                                    style: TextStyle(fontSize: 26)),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b.title.tr(),
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: AppPalette.textPrimary(
                                              context),
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        b.desc.tr(),
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color:
                                              AppPalette.textSecondary(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (got)
                                  Icon(Icons.check_circle_rounded,
                                      color: Colors.green.shade600,
                                      size: 20),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _IntroDialog extends StatelessWidget {
  final String title;
  final String emoji;
  final String body;
  const _IntroDialog({
    required this.title,
    required this.emoji,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppPalette.card(context),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: AppPalette.textPrimary(context), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(emoji, style: TextStyle(fontSize: 28)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Container(height: 1, color: Colors.black),
            SizedBox(height: 14),
            Text(
              body,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppPalette.textPrimary(context),
                height: 1.5,
              ),
            ),
            SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
            color: AppPalette.card(context),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppPalette.textPrimary(context), width: 1),
                  ),
                  child: Text(
                    'Tamam'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Test Topic Picker — Test FAB tıklanınca açılan sheet
//  Aktif konu turuncu border + dolgu ile vurgulanır (active_topic_color).
// ═════════════════════════════════════════════════════════════════════════
enum _TestPickerMode { testlerim, pick }
enum _TestPickerIntent { continueLast, newTest }

class _TopicPickerResult {
  final _Summary summary;
  final _TestPickerIntent intent;
  const _TopicPickerResult(this.summary, this.intent);
}

class _TestTopicPicker extends StatelessWidget {
  final _Subject subject;
  final String activeTopicLower;
  final _TestPickerMode mode;
  const _TestTopicPicker({
    required this.subject,
    required this.activeTopicLower,
    required this.mode,
  });

  static const _activeColor = Color(0xFFFF6A00);

  @override
  Widget build(BuildContext context) {
    final summaries = subject.summaries;
    final isTestlerim = mode == _TestPickerMode.testlerim;
    return DraggableScrollableSheet(
      initialChildSize: isTestlerim ? 0.62 : 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Icon(Icons.quiz_rounded,
                        color: _activeColor, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isTestlerim
                            ? '${subject.name} — Testlerim'
                            : '${subject.name} — Test Konuları',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ),
                    Text('${summaries.length}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.textSecondary(context),
                        )),
                  ],
                ),
              ),
              Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  itemCount: summaries.length,
                  separatorBuilder: (_, __) =>
                      SizedBox(height: isTestlerim ? 10 : 8),
                  itemBuilder: (_, i) {
                    final s = summaries[i];
                    final isActive =
                        s.topic.toLowerCase().trim() == activeTopicLower;
                    if (isTestlerim) {
                      return _TestlerimRow(
                        topic: s.topic,
                        isActive: isActive,
                        testCount: s.tests.length,
                        onContinue: s.tests.isNotEmpty
                            ? () => Navigator.of(ctx).pop(
                                _TopicPickerResult(
                                    s, _TestPickerIntent.continueLast))
                            : null,
                        onNewTest: s.tests.length >= 3
                            ? null
                            : () => Navigator.of(ctx).pop(_TopicPickerResult(
                                s, _TestPickerIntent.newTest)),
                      );
                    }
                    return _PickRow(
                      topic: s.topic,
                      isActive: isActive,
                      onTap: () => Navigator.of(ctx).pop(
                          _TopicPickerResult(s, _TestPickerIntent.newTest)),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Testlerim modu satırı: konu adı + test sayısı (space-between),
/// altında "Devam Et" + "Yeni Test Oluştur" butonları.
class _TestlerimRow extends StatelessWidget {
  final String topic;
  final bool isActive;
  final int testCount;
  final VoidCallback? onContinue;
  final VoidCallback? onNewTest;
  const _TestlerimRow({
    required this.topic,
    required this.isActive,
    required this.testCount,
    required this.onContinue,
    required this.onNewTest,
  });

  static const _activeColor = Color(0xFFFF6A00);

  @override
  Widget build(BuildContext context) {
    final hasTest = testCount > 0;
    final atLimit = testCount >= 3;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isActive
            ? _activeColor.withValues(alpha: 0.10)
            : AppPalette.bg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? _activeColor : Colors.transparent,
          width: isActive ? 2 : 0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: _activeColor.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (isActive) ...[
                Icon(Icons.location_on_rounded,
                    color: _activeColor, size: 16),
                SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: isActive ? _activeColor : Colors.black87,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: hasTest
                      ? _activeColor.withValues(alpha: 0.16)
                      : Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  hasTest ? '$testCount Test' : 'Test yok',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: hasTest ? _activeColor : Colors.black54,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              if (onContinue != null) ...[
                Expanded(
                  child: _SmallActionBtn(
                    icon: Icons.play_arrow_rounded,
                    label: 'Devam Et',
                    color: _activeColor,
                    filled: false,
                    onTap: onContinue!,
                  ),
                ),
                SizedBox(width: 8),
              ],
              Expanded(
                child: _SmallActionBtn(
                  icon: atLimit ? Icons.lock_rounded : Icons.add_rounded,
                  label: atLimit ? 'Limit · 3/3' : 'Yeni Test Oluştur',
                  color: atLimit ? Colors.black54 : _activeColor,
                  filled: !atLimit,
                  onTap: onNewTest ?? () {},
                  disabled: onNewTest == null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pick modu satırı: hiç test yokken — tıkla → o konu için yeni test akışı.
class _PickRow extends StatelessWidget {
  final String topic;
  final bool isActive;
  final VoidCallback onTap;
  const _PickRow({
    required this.topic,
    required this.isActive,
    required this.onTap,
  });

  static const _activeColor = Color(0xFFFF6A00);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? _activeColor.withValues(alpha: 0.12)
                : AppPalette.bg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? _activeColor : Colors.transparent,
              width: isActive ? 2 : 0,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: _activeColor.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? _activeColor : Colors.black12,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isActive
                      ? Icons.location_on_rounded
                      : Icons.add_rounded,
                  color: isActive ? Colors.white : Colors.black54,
                  size: 16,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w800 : FontWeight.w700,
                        color: isActive ? _activeColor : Colors.black87,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      isActive
                          ? 'Şu anki konu — test oluştur'
                          : 'Test oluştur',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? _activeColor.withValues(alpha: 0.85)
                            : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: isActive ? _activeColor : Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final bool disabled;
  final VoidCallback onTap;
  const _SmallActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = disabled
        ? Colors.black38
        : (filled ? Colors.white : color);
    final bg = disabled
        ? Color(0xFFE5E7EB)
        : (filled ? color : Colors.transparent);
    final borderColor = disabled
        ? Color(0xFFE5E7EB)
        : color;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: disabled ? null : onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: filled || disabled ? 0 : 1.4,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: fg),
              SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: fg,
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

// ═══════════════════════════════════════════════════════════════════════════
//  Ebeveyn Doğrulaması — basit matematik sorusu (4-9 arası iki rakam çarpımı)
//  Öğrencinin raporları manipüle etmesini önlemek için ufak bir engel.
//  Ana fikir: pratik koruma, mutlak güvenlik değil. Doğru → true döner.
// ═══════════════════════════════════════════════════════════════════════════
Future<bool> askParentGate(BuildContext context) async {
  final rng = math.Random();
  final a = 4 + rng.nextInt(6); // 4..9
  final b = 4 + rng.nextInt(6); // 4..9
  final answer = a * b;
  final controller = TextEditingController();
  bool wrong = false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        backgroundColor: AppPalette.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.family_restroom_rounded,
                    size: 36, color: Color(0xFF1E3A8A)),
                SizedBox(height: 8),
                Text(
                  'Ebeveyn Doğrulaması'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Bu kısım ebeveynler içindir. Lütfen aşağıdaki işlemi çöz.'
                      .tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppPalette.textSecondary(context),
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$a × $b = ?',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E3A8A),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Cevap'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    errorText: wrong ? 'Yanlış cevap. Tekrar dene.'.tr() : null,
                  ),
                  onSubmitted: (_) {
                    if (int.tryParse(controller.text.trim()) == answer) {
                      Navigator.of(ctx).pop(true);
                    } else {
                      setSt(() => wrong = true);
                    }
                  },
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(
                          'İptal'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textSecondary(context),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          if (int.tryParse(controller.text.trim()) ==
                              answer) {
                            Navigator.of(ctx).pop(true);
                          } else {
                            setSt(() => wrong = true);
                          }
                        },
                        child: Text(
                          'Doğrula'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return result == true;
}

// ═══════════════════════════════════════════════════════════════════════════
//  _ParentLink — öğrenci tarafında ebeveyn bağlantısı için yerel state.
//  Şu an sadece local persist; cloud senkronizasyonu sonraki fazda eklenir.
//   • studentId: öğrencinin benzersiz ID'si ("stu_xxxxxxxx")
//   • pairCode: ebeveyne paylaşılacak 6 haneli kod
//   • linked: ebeveyn bu cihaza bağlanmış mı (manuel toggle ile simüle)
// ═══════════════════════════════════════════════════════════════════════════
class _ParentLink {
  static const _kStudentId = 'parent_link_student_id_v1';
  static const _kPairCode = 'parent_link_pair_code_v1';
  static const _kLinked = 'parent_link_active_v1';

  static String _genStudentId() {
    final r = math.Random.secure();
    const alpha = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final buf = StringBuffer('stu_');
    for (int i = 0; i < 8; i++) {
      buf.write(alpha[r.nextInt(alpha.length)]);
    }
    return buf.toString();
  }

  static String _genPairCode() {
    final r = math.Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  static Future<String> getOrCreateStudentId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kStudentId);
    if (id == null || id.isEmpty) {
      id = _genStudentId();
      await prefs.setString(_kStudentId, id);
    }
    return id;
  }

  static Future<String> getOrCreatePairCode() async {
    final prefs = await SharedPreferences.getInstance();
    var code = prefs.getString(_kPairCode);
    if (code == null || code.length != 6) {
      code = _genPairCode();
      await prefs.setString(_kPairCode, code);
    }
    return code;
  }

  static Future<String> refreshPairCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = _genPairCode();
    await prefs.setString(_kPairCode, code);
    return code;
  }

  static Future<bool> isLinked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kLinked) ?? false;
  }

  static Future<void> setLinked(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLinked, v);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Ebeveyn Gelişim Raporu — son 7 günün verisini görselleştirir.
//   • Cihazda ebeveyn bağlı DEĞİLSE → davet ekranı (büyük "Ebeveynine
//     Davet Gönder" butonu + öğrenci ID'si + 6 haneli pairing kodu).
//   • Bağlıysa → Aktiflik Skoru / Odaklanma Analizi / Haftalık Özet Notu.
//  Tasarım dili: Lacivert (#1E3A8A) + beyaz; öğrenci sayfasına göre daha
//  durağan ve kurumsal.
// ═══════════════════════════════════════════════════════════════════════════
class ParentReportPage extends StatefulWidget {
  const ParentReportPage({super.key});

  @override
  State<ParentReportPage> createState() => ParentReportPageState();
}

class ParentReportPageState extends State<ParentReportPage> {
  static const _navy = Color(0xFF1E3A8A);
  static const _navySoft = Color(0xFFEFF4FF);
  static const _activeColor = Color(0xFF1E3A8A);
  static const _passiveColor = Color(0xFFF59E0B);

  bool _loading = true;
  // Ebeveyn bu cihaza bağlanmış mı; bağlı değilse rapor yerine davet ekranı.
  bool _linked = false;
  String _studentId = '';
  String _pairCode = '';
  // Son 7 günde derslere göre toplam aktif ve pasif saniyeler.
  // Anahtar: ders adı (orijinal). Toplam değerler kart + chart için.
  Map<String, int> _activeBySubject = const {};
  Map<String, int> _passiveBySubject = const {};
  int _totalActive = 0;
  int _totalPassive = 0;
  String _summaryText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final linked = await _ParentLink.isLinked();
    final id = await _ParentLink.getOrCreateStudentId();
    final code = await _ParentLink.getOrCreatePairCode();
    final all = await _ActivityStore.readAll();
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: 7));
    final active = <String, int>{};
    final passive = <String, int>{};
    int totA = 0;
    int totP = 0;
    for (final e in all) {
      if (e.when.isBefore(cutoff)) continue;
      active[e.subject] = (active[e.subject] ?? 0) + e.durationSec;
      passive[e.subject] = (passive[e.subject] ?? 0) + e.idleSec;
      totA += e.durationSec;
      totP += e.idleSec;
    }
    if (!mounted) return;
    setState(() {
      _linked = linked;
      _studentId = id;
      _pairCode = code;
      _activeBySubject = active;
      _passiveBySubject = passive;
      _totalActive = totA;
      _totalPassive = totP;
      _summaryText = _generateSummary(
        activeBySubject: active,
        passiveBySubject: passive,
        totalActive: totA,
        totalPassive: totP,
      );
      _loading = false;
    });
  }

  /// Daveti paylaşma — fire-and-forget pattern (`unawaited`) ile her basışta
  /// bağımsız bir paylaşım request'i yapılır. Buton onPressed'i Share.share
  /// future'ını beklemez, böylece ikinci/üçüncü tıklamalar Activity context
  /// kilidi nedeniyle takılmaz. Pre-share snack YOK (Scaffold rebuild
  /// paylaşım sheet'ini dismiss ediyordu).
  Future<void> _shareInvite() async {
    final msg = 'QuAlsar Ebeveyn Paneli daveti\n\n'
        'Çocuğunun çalışma istatistiklerini izlemek için QuAlsar '
        'uygulamasını yükle ve aşağıdaki kodla bağlan:\n\n'
        'Eşleşme kodu: $_pairCode\n'
        'Öğrenci ID: $_studentId\n\n'
        'Uygulamayı indir: https://qualsar.app';

    unawaited(_doShareInvite(msg));
  }

  Future<void> _doShareInvite(String msg) async {
    try {
      await Share.share(msg);
    } catch (e) {
      // Yalnızca hata olduğunda snack — başarılı paylaşımda sessiz kal.
      try {
        await Clipboard.setData(ClipboardData(text: msg));
      } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'academic_planner'); }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${'Paylaşım hatası:'.tr()} $e — ${'davet panoya kopyalandı'.tr()}.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _refreshCode() async {
    final c = await _ParentLink.refreshPairCode();
    if (!mounted) return;
    setState(() => _pairCode = c);
  }

  /// Sadece test akışı için — gerçek çoklu cihaz pairing yokken simülasyon.
  /// Kullanıcı "Bağlandı say" derse rapor görünür hale gelir.
  Future<void> _simulateLink() async {
    await _ParentLink.setLinked(true);
    if (!mounted) return;
    setState(() => _linked = true);
  }

  /// Toplanan istatistiklere göre 1-2 cümlelik kural tabanlı yorum.
  /// Gemini gerektirmez; offline çalışır, anlık döner.
  String _generateSummary({
    required Map<String, int> activeBySubject,
    required Map<String, int> passiveBySubject,
    required int totalActive,
    required int totalPassive,
  }) {
    final total = totalActive + totalPassive;
    if (total < 60) {
      return 'Bu hafta henüz yeterli veri yok. Birkaç çalışma oturumundan sonra '
          'ayrıntılı bir gelişim yorumu hazırlanabilir.';
    }
    final activePct = total == 0 ? 0 : ((totalActive / total) * 100).round();
    // En çok çalışılan ders (aktif süre).
    String? topSubject;
    int topActive = 0;
    activeBySubject.forEach((s, sec) {
      if (sec > topActive) {
        topActive = sec;
        topSubject = s;
      }
    });
    // Pasif/aktif oranı en yüksek ders → odaklanmasında zorlanılan.
    String? laggingSubject;
    double worstRatio = 0;
    activeBySubject.forEach((s, a) {
      final p = passiveBySubject[s] ?? 0;
      final t = a + p;
      if (t < 600) return; // 10 dk altı kararı saptırır
      final ratio = p / t;
      if (ratio > worstRatio) {
        worstRatio = ratio;
        laggingSubject = s;
      }
    });
    final buf = StringBuffer();
    if (activePct >= 80) {
      buf.write('Bu hafta odaklanma yüksek — toplam sürenin %$activePct\'i '
          'gerçek etkileşimle geçti. ');
    } else if (activePct >= 60) {
      buf.write('Bu hafta dengeli bir tablo var; sürenin %$activePct\'i '
          'aktif çalışma. ');
    } else {
      buf.write('Bu hafta ekran süresi aktif çalışmadan fazla görünüyor '
          '(%$activePct aktif). ');
    }
    if (topSubject != null) {
      buf.write('En çok çalışılan ders: $topSubject. ');
    }
    if (laggingSubject != null && worstRatio > 0.35) {
      final pct = (worstRatio * 100).round();
      buf.write('$laggingSubject\'da pasif zaman %$pct civarında — '
          'bu derste ekran açık kalmış olabilir.');
    } else if (activePct >= 75) {
      buf.write('Genel ritim sağlıklı görünüyor.');
    }
    return buf.toString();
  }

  String _fmt(int sec) {
    if (sec <= 0) return '0 dk';
    final m = sec ~/ 60;
    if (m < 60) return '$m dk';
    final h = m ~/ 60;
    final mm = m % 60;
    return mm == 0 ? '$h sa' : '$h sa $mm dk';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          _linked
              ? 'Ebeveyn Gelişim Raporu'.tr()
              : 'Ebeveyn Paneli'.tr(),
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _navy))
          // YAPIM AŞAMASI: Bağlantı durumundan bağımsız olarak hem davet
          // ekranı (kod + paylaş) hem de rapor aşağıya birlikte gösterilir.
          // Cloud sync sonrası `_linked` flag'iyle ikiye ayrılacak.
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInviteSection(),
                  SizedBox(height: 22),
                  _buildSectionDivider(),
                  SizedBox(height: 18),
                  _buildScoreCard(),
                  SizedBox(height: 14),
                  _buildFocusCard(),
                  SizedBox(height: 14),
                  _buildSummaryCard(),
                ],
              ),
            ),
    );
  }

  /// İki bölüm arası ayraç — "Haftalık Rapor Önizlemesi" bandı.
  Widget _buildSectionDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: _navy.withValues(alpha: 0.20),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'Haftalık Rapor Önizlemesi'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: _navy,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: _navy.withValues(alpha: 0.20),
          ),
        ),
      ],
    );
  }

  // ── Davet bölümü — ebeveyn bağlanma kodu, ID ve paylaş butonu ─────────
  // Büyük "Ebeveynine Davet Gönder" butonu + 6 haneli pairing kodu +
  // öğrenci ID'si + kısa açıklama. Yapım aşamasında her açılışta gösterilir.
  Widget _buildInviteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          // Üst görsel — aileyi temsil eden büyük renkli ikon.
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 14),
            alignment: Alignment.center,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
            color: AppPalette.card(context),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _navy.withValues(alpha: 0.20),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFFEF4444),
                    Color(0xFFFBBF24),
                    Color(0xFF10B981),
                    Color(0xFF2563EB),
                  ],
                ).createShader(rect),
                child: Icon(
                  Icons.family_restroom_rounded,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          // Başlık + açıklama
          Text(
            'Ebeveynine Bağlan'.tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: _navy,
              letterSpacing: 0.1,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Ebeveynine bir davet gönder; o da QuAlsar uygulamasını yüklediğinde aşağıdaki kodla seni takip etmeye başlayabilir.'
                .tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppPalette.textSecondary(context),
              height: 1.45,
            ),
          ),
          SizedBox(height: 20),
          // Eşleşme kodu kartı
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            decoration: BoxDecoration(
              color: _navySoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _navy.withValues(alpha: 0.20)),
            ),
            child: Column(
              children: [
                Text(
                  'Eşleşme Kodu'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context),
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < _pairCode.length; i++) ...[
                      Container(
                        width: 36,
                        height: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
            color: AppPalette.card(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _navy.withValues(alpha: 0.30)),
                        ),
                        child: Text(
                          _pairCode[i],
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: _navy,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: _pairCode));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Kod kopyalandı'.tr()),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: Icon(Icons.copy_rounded,
                          size: 14, color: _navy),
                      label: Text(
                        'Kopyala'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _navy,
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: _refreshCode,
                      icon: Icon(Icons.refresh_rounded,
                          size: 14, color: _navy),
                      label: Text(
                        'Yeni Kod'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _navy,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          // Öğrenci ID
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
            color: AppPalette.card(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                Icon(Icons.badge_rounded,
                    size: 16, color: _navy),
                SizedBox(width: 8),
                Text(
                  'Öğrenci ID:'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _studentId,
                    style: GoogleFonts.firaCode(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 22),
          // Ana CTA — Ebeveynine Davet Gönder. Sade çağrı; share_plus
          // platforma göre kendi default'larını kullanır.
          ElevatedButton.icon(
            onPressed: _shareInvite,
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
            ),
            icon: Icon(Icons.ios_share_rounded, size: 18),
            label: Text(
              'Ebeveynine Davet Gönder'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(height: 14),
          // Bilgi kutusu — bağlantı simülasyonu (cloud sync gelene kadar)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Color(0xFFFB923C).withValues(alpha: 0.40),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: Color(0xFFB45309)),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Geliştirme aşamasında'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB45309),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Çoklu cihaz bağlantısı (Firebase) sonraki güncellemeyle gelecek. Şimdilik raporu görmek için aşağıdaki düğmeyi kullanabilirsin.'
                            .tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF7C2D12),
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _simulateLink,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Color(0xFFB45309),
                          side: BorderSide(
                              color: Color(0xFFFB923C)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                        child: Text(
                          'Bu cihazda raporu göster (test)'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
    );
  }

  // ── Aktiflik Skoru — dairesel grafik + büyük yüzde ────────────────────
  Widget _buildScoreCard() {
    final total = _totalActive + _totalPassive;
    final activePct = total == 0 ? 0 : ((_totalActive / total) * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _navy.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aktiflik Skoru'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Son 7 günün gerçek etkileşim oranı'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppPalette.textSecondary(context),
            ),
          ),
          SizedBox(height: 14),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Bu hafta henüz veri yok.'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 0,
                          centerSpaceRadius: 42,
                          startDegreeOffset: -90,
                          sections: [
                            PieChartSectionData(
                              value: _totalActive.toDouble(),
                              color: _activeColor,
                              radius: 18,
                              showTitle: false,
                            ),
                            PieChartSectionData(
                              value: _totalPassive.toDouble(),
                              color: _passiveColor,
                              radius: 18,
                              showTitle: false,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '%$activePct',
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: _navy,
                              height: 1.0,
                            ),
                          ),
                          SizedBox(height: 1),
                          Text(
                            'aktif',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _legendRow(_activeColor, 'Aktif Çalışma'.tr(),
                          _fmt(_totalActive)),
                      SizedBox(height: 8),
                      _legendRow(_passiveColor, 'Pasif Zaman'.tr(),
                          _fmt(_totalPassive)),
                      SizedBox(height: 8),
                      Container(height: 1, color: Colors.black12),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'Ekran Süresi'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                          Spacer(),
                          Text(
                            _fmt(total),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label, String value) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppPalette.textPrimary(context),
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  // ── Odaklanma Analizi — ders bazlı aktif/pasif yan yana bar grafik ────
  Widget _buildFocusCard() {
    // En aktif 5 dersi al (toplam aktif süreye göre).
    final entries = _activeBySubject.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _navy.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Odaklanma Analizi'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Ders bazında aktif çalışma ve pasif zaman'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppPalette.textSecondary(context),
            ),
          ),
          SizedBox(height: 14),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Henüz ders verisi yok.'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= top.length) {
                            return const SizedBox.shrink();
                          }
                          final s = top[i].key;
                          final short = s.length > 7
                              ? '${s.substring(0, 7)}…'
                              : s;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              short,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.textPrimary(context),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (int i = 0; i < top.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 4,
                        barRods: [
                          BarChartRodData(
                            toY: (top[i].value / 60).toDouble(),
                            color: _activeColor,
                            width: 12,
                            borderRadius:
                                const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                          BarChartRodData(
                            toY: ((_passiveBySubject[top[i].key] ?? 0) /
                                    60)
                                .toDouble(),
                            color: _passiveColor,
                            width: 12,
                            borderRadius:
                                const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 10),
            Row(
              children: [
                _legendDot(_activeColor, 'Aktif (dk)'.tr()),
                SizedBox(width: 14),
                _legendDot(_passiveColor, 'Pasif (dk)'.tr()),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppPalette.textPrimary(context),
          ),
        ),
      ],
    );
  }

  // ── Haftalık Özet Notu — kural tabanlı kısa AI-style yorum ────────────
  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: _navySoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _navy.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 18, color: _navy),
              SizedBox(width: 8),
              Text(
                'Haftalık Özet Notu'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            _summaryText,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppPalette.textPrimary(context),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
