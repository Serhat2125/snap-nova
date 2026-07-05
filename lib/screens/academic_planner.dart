// ignore_for_file: unused_element, unused_element_parameter

import '../services/app_settings_service.dart';
import '../services/push_service.dart';
import '../services/runtime_translator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show localeService;
import '../services/analytics.dart';
import '../services/parent_preview.dart';
import '../services/error_logger.dart';
import '../services/summary_cache_service.dart';
import '../services/question_pool_service.dart';
import '../widgets/summary_rating_table.dart';
import '../services/usage_quota.dart';
import '../features/offline/domain/offline_subject_pack.dart';
import '../features/offline/providers/offline_pack_provider.dart';
import '../services/curriculum_catalog.dart';
import '../services/education_profile.dart';
import '../services/exam_catalog.dart' show examGroupsFor;
import '../services/gemini_service.dart';
import '../services/tts_service.dart';
import '../services/rag_service.dart';
import '../widgets/latex_text.dart';
import '../widgets/qualsar_loading_widget.dart';
import 'test_page.dart';
import 'green_colony_screen.dart';
import 'ai_coach_screen.dart';
import 'student_homeworks_screen.dart';
import 'student_materials_screen.dart';
import 'history_screen.dart';
import 'qualsar_arena_screen.dart';
import 'bilgi_ligi_screen.dart';
import '../widgets/exam_mode_widgets.dart';
import '../widgets/study_toolbar.dart';
import 'qualsar_mars_screen.dart';
import 'edu_3d_screen.dart';
import '../services/pomodoro_stats.dart';
import '../services/activity_writer_service.dart';
import '../services/ai_quota_service.dart';
import 'premium_screen.dart';

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

  /// Day key — kullanıcının LOKAL gününe göre normalize edilir.
  /// Cloud restore'dan gelen UTC DateTime'lar için `.toLocal()` zorlanır;
  /// böylece "23:00'da çalıştım ama yarın gösteriyor" bug'ı oluşmaz.
  static String dayKey(DateTime d) {
    final l = d.isUtc ? d.toLocal() : d;
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

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

  // In-memory cache — 1000+ entry'de readAll() çok sayfa scroll'da yavaş.
  // log/logSession/restoreFromCloudIfEmpty çağrıldığında invalidate edilir.
  static Map<String, List<_ActivityEntry>>? _weekGroupedCache;
  static DateTime? _weekGroupedCacheAt;
  static const Duration _cacheTtl = Duration(seconds: 30);

  static void _invalidateWeekCache() {
    _weekGroupedCache = null;
    _weekGroupedCacheAt = null;
  }

  // Mevcut hafta için günlere göre gruplayarak döner
  static Future<Map<String, List<_ActivityEntry>>> readWeekGrouped() async {
    // Cache hit — 30sn TTL içinde tekrar okuma yapma.
    final cached = _weekGroupedCache;
    final cachedAt = _weekGroupedCacheAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }
    final all = await readAll();
    final out = <String, List<_ActivityEntry>>{};
    for (final e in all) {
      final k = dayKey(e.when);
      out.putIfAbsent(k, () => []).add(e);
    }
    for (final v in out.values) {
      v.sort((a, b) => b.when.compareTo(a.when));
    }
    _weekGroupedCache = out;
    _weekGroupedCacheAt = DateTime.now();
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
      _ActivityEntry? entry;
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = List<String>.from(prefs.getStringList(_key) ?? []);
        entry = _ActivityEntry(
          when: DateTime.now(),
          subject: subject,
          topic: topic,
          type: type,
        );
        list.add(jsonEncode(entry.toJson()));
        final trimmed = await _trimAndArchive(list);
        await prefs.setStringList(_key, trimmed);
        _invalidateWeekCache();
      } catch (e) {
        debugPrint('[ActivityStore] log fail: $e');
      }
      if (entry != null) unawaited(_cloudAppend(entry));
      // Ebeveyn paneli / Gelişimim verisi — özet üretimi sayacı.
      if (type == 'özet') {
        unawaited(ActivityWriterService.recordSummaryCreated(subject));
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
      _ActivityEntry? entry;
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = List<String>.from(prefs.getStringList(_key) ?? []);
        entry = _ActivityEntry(
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
        _invalidateWeekCache();
      } catch (e) {
        debugPrint('[ActivityStore] logSession fail: $e');
      }
      if (entry != null) unawaited(_cloudAppend(entry));
      // Ebeveyn paneli / Gelişimim verisi — çalışma süresi (özet + soru).
      unawaited(ActivityWriterService.recordFocus(durationSec, subject));
      StudySessionTracker.instance._notifyDataChanged();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  CLOUD SYNC — users/{uid}/study_activities/{auto}
  //
  //  Her log/logSession sonrası fire-and-forget Firestore yazımı. Yerel
  //  her zaman kaynak; cloud yedek. Auth yoksa veya offline ise sessiz
  //  no-op. Yerel boşsa restoreFromCloudIfEmpty() son 500 entry'yi geri
  //  yükler.
  // ═══════════════════════════════════════════════════════════════════════

  static Future<void> _cloudAppend(_ActivityEntry e) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('study_activities')
          .add({
        ...e.toJson(),
        'whenTs': Timestamp.fromDate(e.when),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (err) {
      debugPrint('[ActivityStore] cloud append fail: $err');
    }
  }

  /// Yerel boşsa cloud'dan son 500 entry'yi yükle. Bootstrap'ta çağrılır.
  /// Yeni telefonda / uygulama yeniden yüklendiğinde aktivite geçmişi geri gelir.
  /// Döner: restore edilen entry sayısı (0 = restore yapılmadı).
  static Future<int> restoreFromCloudIfEmpty() async {
    return _serialize(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final localList = prefs.getStringList(_key) ?? const [];
        if (localList.isNotEmpty) return 0;
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return 0;
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('study_activities')
            .orderBy('whenTs', descending: true)
            .limit(_activeCap)
            .get();
        if (snap.docs.isEmpty) return 0;
        final list = <String>[];
        for (final d in snap.docs) {
          final m = d.data();
          // whenTs Timestamp olarak gelir — _ActivityEntry'nin beklediği
          // ISO string format'a normalize et.
          final ts = m['whenTs'];
          if (ts is Timestamp) {
            m['when'] = ts.toDate().toIso8601String();
          }
          m.remove('whenTs');
          m.remove('createdAt');
          try {
            final entry = _ActivityEntry.fromJson(
                Map<String, dynamic>.from(m));
            list.add(jsonEncode(entry.toJson()));
          } catch (e) {
            debugPrint('[ActivityStore] cloud parse fail: $e');
          }
        }
        if (list.isEmpty) return 0;
        // En eski en başta olacak şekilde sırala (yerel format böyle)
        list.sort();
        await prefs.setStringList(_key, list);
        _invalidateWeekCache();
        debugPrint(
            '[ActivityStore] cloud restore: ${list.length} entry');
        return list.length;
      } catch (e) {
        debugPrint('[ActivityStore] cloud restore fail: $e');
        return 0;
      }
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

/// Ebeveyn paneli / Gelişimim — son 7 günün LOKAL aktivite verisini
/// StudentActivityModel.fromJson uyumlu JSON listesi olarak döndürür
/// (focusSeconds + subjectDurations). Firestore `activity` dökümanı yeni
/// olduğu için eski/birikmiş veri yalnızca lokal `_ActivityStore`'dadır;
/// panel boş görünmesin diye buradan beslenir.
Future<List<Map<String, dynamic>>> readLocalActivityLast7Days() async {
  String keyFor(DateTime d) {
    final l = d.isUtc ? d.toLocal() : d;
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  final now = DateTime.now();
  final byDay = <String, Map<String, dynamic>>{};
  for (int d = 6; d >= 0; d--) {
    final day = DateTime(now.year, now.month, now.day - d);
    final key = keyFor(day);
    byDay[key] = {
      'dateKey': key,
      'focusSeconds': 0,
      'subjectDurations': <String, int>{},
    };
  }
  try {
    final all = await _ActivityStore.readAll();
    for (final e in all) {
      if (e.durationSec <= 0) continue;
      final m = byDay[keyFor(e.when)];
      if (m == null) continue; // 7 günden eski
      m['focusSeconds'] = (m['focusSeconds'] as int) + e.durationSec;
      if (e.subject.isNotEmpty) {
        final subs = m['subjectDurations'] as Map<String, int>;
        subs[e.subject] = (subs[e.subject] ?? 0) + e.durationSec;
      }
    }
  } catch (_) {}
  return byDay.values.toList();
}

/// Gelişim Paneli kategori sekmeleri — bu HAFTANIN (Pazartesi→Pazar) ham
/// aktivite kayıtlarını döndürür. Her kayıt:
///   {dateKey, weekday (1=Pzt..7=Paz), type, subject, topic, sec}
/// Kaynak: lokal `_ActivityStore` (özet/soru/pomodoro/3d/yarisma/foto tipleri).
Future<List<Map<String, dynamic>>> readLocalWeekEntries() async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: now.weekday - 1));
  String keyFor(DateTime d) {
    final l = d.isUtc ? d.toLocal() : d;
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  final out = <Map<String, dynamic>>[];
  try {
    final all = await _ActivityStore.readAll();
    for (final e in all) {
      final w = e.when.isUtc ? e.when.toLocal() : e.when;
      final day = DateTime(w.year, w.month, w.day);
      if (day.isBefore(monday)) continue; // bu haftadan önce
      out.add({
        'dateKey': keyFor(w),
        'weekday': w.weekday, // 1=Pzt .. 7=Paz
        'type': e.type,
        'subject': e.subject,
        'topic': e.topic,
        'sec': e.durationSec,
      });
    }
  } catch (_) {}
  return out;
}

/// Aylık rapor — son N günün LOKAL günlük aktivite verisi (focus + ders süresi).
Future<List<Map<String, dynamic>>> readLocalActivityLastNDays(int n) async {
  String keyFor(DateTime d) {
    final l = d.isUtc ? d.toLocal() : d;
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  final now = DateTime.now();
  final byDay = <String, Map<String, dynamic>>{};
  for (int d = n - 1; d >= 0; d--) {
    final day = DateTime(now.year, now.month, now.day - d);
    byDay[keyFor(day)] = {
      'dateKey': keyFor(day),
      'focusSeconds': 0,
      'subjectDurations': <String, int>{},
    };
  }
  try {
    final all = await _ActivityStore.readAll();
    for (final e in all) {
      if (e.durationSec <= 0) continue;
      final m = byDay[keyFor(e.when)];
      if (m == null) continue;
      m['focusSeconds'] = (m['focusSeconds'] as int) + e.durationSec;
      if (e.subject.isNotEmpty) {
        final subs = m['subjectDurations'] as Map<String, int>;
        subs[e.subject] = (subs[e.subject] ?? 0) + e.durationSec;
      }
    }
  } catch (_) {}
  return byDay.values.toList();
}

/// Aylık rapor — son N günün LOKAL ham aktivite kayıtları (type/ders/süre).
Future<List<Map<String, dynamic>>> readLocalEntriesLastNDays(int n) async {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day - (n - 1));
  String keyFor(DateTime d) {
    final l = d.isUtc ? d.toLocal() : d;
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  final out = <Map<String, dynamic>>[];
  try {
    final all = await _ActivityStore.readAll();
    for (final e in all) {
      final w = e.when.isUtc ? e.when.toLocal() : e.when;
      final day = DateTime(w.year, w.month, w.day);
      if (day.isBefore(from)) continue;
      out.add({
        'dateKey': keyFor(w),
        'type': e.type,
        'subject': e.subject,
        'topic': e.topic,
        'sec': e.durationSec,
      });
    }
  } catch (_) {}
  return out;
}

/// 3D ders / yarışma gibi süre tabanlı aktiviteleri lokal mağazaya yazar
/// (Gelişim Paneli kategori kırılımı için). Public sarmalayıcı.
Future<void> logActivitySession({
  required String subject,
  required String topic,
  required String type,
  required int durationSec,
}) =>
    _ActivityStore.logSession(
      subject: subject, topic: topic, type: type, durationSec: durationSec);

/// Foto-soru gibi anlık (süresiz) aktiviteleri lokal mağazaya yazar.
Future<void> logActivityEvent({
  required String subject,
  required String topic,
  required String type,
}) =>
    _ActivityStore.log(subject: subject, topic: topic, type: type);

/// Aktivite geçmişini buluttan geri yükle (yalnız yerel boşsa). main.dart
/// bootstrap'ında çağrılır → yeni cihazda Gelişim Paneli/haftalık özet,
/// kullanıcı takvim sayfasını açmadan da dolu gelir.
Future<int> restoreActivityFromCloudIfEmpty() =>
    _ActivityStore.restoreFromCloudIfEmpty();

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
      // İdle pause olunca local notification ile kullanıcıyı bilgilendir —
      // sayfa görünür değilse (arka planda telefonda başka şey yapıyorsa)
      // bu uyarı sistem tepsisinde görünür. PushService.init() main'de zaten
      // bağlı; izin verilmediyse sessiz no-op.
      unawaited(PushService.showLocal(
        title: 'Hâlâ burada mısın?',
        body: 'Çalışma süresi 2 dakikadır dondu. Devam etmek için uygulamaya dön.',
        id: 0xFA002,
      ));
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
    var g = await _ActivityStore.readWeekGrouped();
    // Yerel boşsa cloud'dan restore — telefon değişti / yeniden yükleme
    // sonrası kullanıcı eski çalışma geçmişini geri görsün.
    if (g.isEmpty) {
      final restored = await _ActivityStore.restoreFromCloudIfEmpty();
      if (restored > 0) {
        g = await _ActivityStore.readWeekGrouped();
      }
    }
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
      } else if (i == 0) {
        // Bugün HENÜZ boş → seriyi bozma, düne bak (kullanıcı günü kaybetmesin).
        continue;
      } else {
        // Geçmiş bir gün boş → seri bitti.
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
    'edu3d': '3D Eğitim Modelleri',
    'league': 'Dünya Sıralaması',
    'contest': 'Düello Arenası',
    'calendar': 'Çalışma Takvimi',
    'ai_coach': 'AI Koç',
    'pomodoro': 'Pomodoro Tekniği',
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
        // Sayfa zeminine yumuşak geçiş — altta küçük radius ile "sarkan"
        // header + hafif gölge.
        elevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
        centerTitle: false,
        titleSpacing: 8,
        // Kütüphanem uygulama açılış ekranı olarak (root, geri gidilecek
        // sayfa yok) VEYA başka bir sayfadan push edilerek açılabiliyor.
        // automaticallyImplyLeading (varsayılan true) bunu Navigator.canPop
        // ile otomatik ayırt eder: root'ta ok gizli kalır, push edildiğinde
        // solda geri oku belirir.
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
                            : 'Renk Seç'.tr(),
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
      body: SingleChildScrollView(
        // Alt nav bar (_NavShell) sayfanın üstüne overlay olarak çizildiği için
        // en alttaki kart/sekme onun arkasında kalıyordu; nav bar yüksekliği +
        // sistem çubuğu kadar boşluk bırakarak tam görünmesini sağla.
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 16 + 112 + MediaQuery.of(context).padding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showColorPicker) _buildLibraryColorPanel(),
            if (_showColorPicker) SizedBox(height: 10),
            // (Ebeveyn Paneli banner'ı kaldırıldı — ebeveyn önizlemesi
            //  artık öğrencinin gerçek ana sayfasını açıyor ve dönüş
            //  alttaki "Ebeveyn Paneli" çipiyle yapılıyor.)
            // ── ÜRET: Konu Özeti + Sınav Soruları — hero kartlar ─────
            _sectionLabel('Üret'),
            _HeroCard(
              icon: Icons.summarize_rounded,
              imageAsset: 'assets/library_icons/summary.png',
              title: localeService.tr('create_topic_summary'),
              subtitle: 'Fotoğraftan akıllı konu özeti çıkar'.tr(),
              gradient: const [Color(0xFF2563EB), Color(0xFF7C3AED)],
              customBg: _cardBgs['summary'],
              customTextColor: _cardInks['summary'],
              onColorAccept: (c) => _applyLibraryColor('summary', c),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AcademicPlanner(
                      mode: LibraryMode.summary),
                ),
              ),
            ),
            SizedBox(height: 10),
            _HeroCard(
              icon: Icons.fact_check_rounded,
              imageAsset: 'assets/library_icons/questions.png',
              title: localeService.tr('create_exam_questions'),
              subtitle: 'AI ile deneme soruları üret ve çöz'.tr(),
              gradient: const [Color(0xFFFF6A00), Color(0xFFDB2777)],
              customBg: _cardBgs['questions'],
              customTextColor: _cardInks['questions'],
              onColorAccept: (c) => _applyLibraryColor('questions', c),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AcademicPlanner(
                      mode: LibraryMode.questions),
                ),
              ),
            ),
            SizedBox(height: 16),
            // ── KİTAPLIĞIM: Çözümlerim | 3D Eğitim Modelleri ─────────
            _sectionLabel('Kitaplığım'),
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.history_rounded,
                    imageAsset: 'assets/library_icons/history.png',
                    title: 'Çözümlerim'.tr(),
                    subtitle: 'Geçmiş çözümlerini incele'.tr(),
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
                    icon: Icons.view_in_ar_rounded,
                    imageAsset: 'assets/library_icons/edu3d.png',
                    title: '3D Eğitim Modelleri'.tr(),
                    subtitle: 'Konuları 3D sahnede keşfet'.tr(),
                    color: Color(0xFF06B6D4),
                    customBg: _cardBgs['edu3d'],
                    customTextColor: _cardInks['edu3d'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('edu3d', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const Edu3DSubjectsScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            // ── YARIŞ: Dünya Sıralaması | Bilgi Yarışı ───────────────
            _sectionLabel('Yarış'),
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.public_rounded,
                    // Gerçek Dünya fotoğrafı (NASA Apollo 17 "Blue Marble") —
                    // kıtalar, konumlar ve renkler orijinal.
                    imageAsset: 'assets/library_icons/earth.png',
                    title: 'Dünya Sıralaması'.tr(),
                    subtitle: 'Dünyadaki yerini gör'.tr(),
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
                SizedBox(width: 10),
                Expanded(
                  child: _LandingCard(
                    icon: Icons.sports_esports_rounded,
                    imageAsset: 'assets/library_icons/contest.png',
                    title: 'Düello Arenası'.tr(),
                    subtitle: 'Arkadaşlarınla düello yap'.tr(),
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
            SizedBox(height: 16),
            // ── ÇALIŞ: Takvim | Pomodoro + AI Koç ────────────────────
            _sectionLabel('Çalış'),
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.edit_calendar_rounded,
                    imageAsset: 'assets/library_icons/calendar.png',
                    title: localeService.tr('my_study_calendar'),
                    subtitle: 'Programını planla, takip et'.tr(),
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
                    icon: Icons.timer_rounded,
                    imageAsset: 'assets/library_icons/pomodoro.png',
                    title: 'Pomodoro Tekniği'.tr(),
                    subtitle: 'Odaklan, mola ver, tekrarla'.tr(),
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
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.psychology_rounded,
                    title: 'AI Koç'.tr(),
                    subtitle: 'Kişisel çalışma tavsiyeleri'.tr(),
                    color: Color(0xFF7C3AED),
                    customBg: _cardBgs['ai_coach'],
                    customTextColor: _cardInks['ai_coach'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('ai_coach', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AICoachScreen(),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(child: SizedBox()),
              ],
            ),
            SizedBox(height: 16),
            // ── SINIFIM: Ödevler | Kaynaklar ─────────────────────────
            _sectionLabel('Sınıfım'),
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.assignment_turned_in_rounded,
                    title: 'Sınıf Ödevlerim'.tr(),
                    subtitle: 'Öğretmeninin verdiği ödevler'.tr(),
                    color: Color(0xFF7C3AED),
                    customBg: _cardBgs['homeworks'],
                    customTextColor: _cardInks['homeworks'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('homeworks', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StudentHomeworksScreen(),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _LandingCard(
                    icon: Icons.folder_shared_rounded,
                    title: 'Sınıf Kaynaklarım'.tr(),
                    subtitle: 'Öğretmenin paylaştığı dosyalar'.tr(),
                    color: Color(0xFF0EA5E9),
                    customBg: _cardBgs['materials'],
                    customTextColor: _cardInks['materials'],
                    onColorAccept: (c) =>
                        _applyLibraryColor('materials', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StudentMaterialsScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Küçük gri kategori başlığı — kart grupları arasını ayırır.
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(
        text.tr().toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppPalette.textSecondary(context),
          letterSpacing: 1.1,
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

class _LandingCard extends StatefulWidget {
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
  /// 3D görsel ikon (assets/library_icons/*). Verilirse altıgen rozet yerine
  /// bu görsel gösterilir; null → eski _HexBadge davranışı.
  final String? imageAsset;
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
    this.imageAsset,
  });

  @override
  State<_LandingCard> createState() => _LandingCardState();
}

class _LandingCardState extends State<_LandingCard> {
  // Basılıyken hafif küçülme (0.97) — dokunma hissi.
  bool _pressed = false;

  IconData get icon => widget.icon;
  String get title => widget.title;
  String? get subtitle => widget.subtitle;
  Color get color => widget.color;
  VoidCallback get onTap => widget.onTap;
  Color? get customBg => widget.customBg;
  Color? get customTextColor => widget.customTextColor;
  ValueChanged<Color>? get onColorAccept => widget.onColorAccept;
  bool get compact => widget.compact;

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

    final cardHeight = compact ? 102.0 : 122.0;
    final iconBox = compact ? 34.0 : 40.0;
    final titleFs = compact ? 11.0 : 12.5;

    return DragTarget<Color>(
      onAcceptWithDetails: (d) => onColorAccept?.call(d.data),
      builder: (ctx, cand, _) => GestureDetector(
        onTap: onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: AnimatedContainer(
          duration: Duration(milliseconds: 160),
          height: cardHeight,
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 11),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            // İnce çerçeve çizgisi — solution_screen kartlarıyla aynı dil.
            // Koyu kart zemininde beyaz tonlu, açıkta %8 siyah.
            border: cand.isNotEmpty
                ? Border.all(color: Color(0xFFFF6A00), width: 2)
                : Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
            boxShadow: [
              // Çerçeve çizgisinin hemen bittiği yerde ince, sıkı gölge —
              // kart kenarını zeminden ayırır.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.09),
                blurRadius: 3,
                spreadRadius: 0.6,
                offset: Offset(0, 1),
              ),
              // Yumuşak derinlik gölgesi.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          // Sol hizalı kompakt düzen: rozet sol üstte, sağ üstte ok,
          // başlık + alt metin altta sola yaslı.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 3D görsel ikon varsa onu göster (referans tasarım seti);
                  // yoksa fütüristik altıgen HUD rozetine düş.
                  if (widget.imageAsset != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset(
                        widget.imageAsset!,
                        width: iconBox + 16,
                        height: iconBox + 16,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _HexBadge(
                            icon: icon, color: color, size: iconBox + 2),
                      ),
                    )
                  else
                    _HexBadge(icon: icon, color: color, size: iconBox + 2),
                  Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: titleColor.withValues(alpha: 0.30),
                    size: 20,
                  ),
                ],
              ),
              Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: titleFs,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                  height: 1.15,
                ),
              ),
              if (hasSub) ...[
                SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
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
      ),
    );
  }
}

// ── Fütüristik altıgen rozet — Kütüphanem kart logoları ─────────────────────
// Koyu "derin uzay" zeminli altıgen + neon degrade çerçeve + dış parıltı +
// degrade ikon. Sci-fi/HUD dili: başlığın rengini neon olarak taşır.
class _HexBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  /// Hero kartlarda (renkli degrade zemin) çerçeve/ikon beyaz neon olur.
  final bool onGradient;
  const _HexBadge({
    required this.icon,
    required this.color,
    this.size = 42,
    this.onGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = onGradient ? Colors.white : color;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _HexBadgePainter(accent, onGradient: onGradient),
          ),
          // Neon degrade ikon — düz beyaz yerine renkten beyaza akan ışık.
          ShaderMask(
            shaderCallback: (b) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Color.lerp(accent, Colors.white, 0.25)!,
              ],
            ).createShader(b),
            child: Icon(icon, color: Colors.white, size: size * 0.46),
          ),
        ],
      ),
    );
  }
}

class _HexBadgePainter extends CustomPainter {
  final Color accent;
  final bool onGradient;
  const _HexBadgePainter(this.accent, {this.onGradient = false});

  Path _hex(Size s, double inset) {
    // Düz-tepe (flat-top) altıgen — teknolojik/HUD görünüm.
    final w = s.width - inset * 2;
    final h = s.height - inset * 2;
    final cx = s.width / 2, cy = s.height / 2;
    final rx = w / 2, ry = h / 2;
    final p = Path();
    for (int i = 0; i < 6; i++) {
      final a = (60.0 * i - 30.0) * math.pi / 180.0;
      final x = cx + rx * math.cos(a);
      final y = cy + ry * math.sin(a);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final hex = _hex(size, 2.5);
    // 1) Dış neon parıltı — rozet zeminden "yüzüyor" hissi.
    canvas.drawPath(
      hex,
      Paint()
        ..color = accent.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    // 2) Derin uzay zemini (hero'da yarı saydam siyah — degradeyi ezmesin).
    canvas.drawPath(
      hex,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(size.width, size.height),
          onGradient
              ? [const Color(0x59000000), const Color(0x40000000)]
              : [const Color(0xFF0B1220), const Color(0xFF1E2A44)],
        ),
    );
    // 3) Neon degrade çerçeve.
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(size.width, size.height),
          [
            Color.lerp(accent, Colors.white, 0.35)!,
            accent,
          ],
        ),
    );
    // 4) Sağ üst köşede minik HUD kıvılcımı.
    final spark = Offset(size.width * 0.80, size.height * 0.16);
    canvas.drawCircle(
        spark,
        1.8,
        Paint()
          ..color = Color.lerp(accent, Colors.white, 0.4)!
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
  }

  @override
  bool shouldRepaint(covariant _HexBadgePainter old) =>
      old.accent != accent || old.onGradient != onGradient;
}

// ── Hero kart — en çok kullanılan özellikler için boydan boya degrade kart ──
// Kütüphanem "Üret" bölümünde kullanılır: soldan sağa marka degradesi,
// beyaz başlık + alt metin, sağda yarı saydam büyük ikon rozeti + ok.
// Renk sürükle-bırak (DragTarget) ve basma animasyonu _LandingCard ile aynı.
class _HeroCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;
  final Color? customBg;
  final Color? customTextColor;
  final ValueChanged<Color>? onColorAccept;
  /// 3D görsel ikon (assets/library_icons/*). Verilirse altıgen rozet yerine
  /// bu görsel gösterilir.
  final String? imageAsset;
  const _HeroCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.customBg,
    this.customTextColor,
    this.onColorAccept,
    this.imageAsset,
  });

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Kullanıcı Renk Seç ile kart rengi atadıysa düz renk; yoksa degrade.
    final custom = widget.customBg;
    Color inkBase;
    if (custom != null) {
      final lum =
          0.299 * custom.r + 0.587 * custom.g + 0.114 * custom.b;
      inkBase = lum < 0.55 ? Colors.white : Colors.black;
    } else {
      inkBase = Colors.white;
    }
    final ink = widget.customTextColor ?? inkBase;
    final glow = widget.gradient.first;

    return DragTarget<Color>(
      onAcceptWithDetails: (d) => widget.onColorAccept?.call(d.data),
      builder: (ctx, cand, _) => GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: Duration(milliseconds: 160),
            height: 88,
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: custom,
              gradient: custom == null
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: widget.gradient,
                    )
                  : null,
              borderRadius: BorderRadius.circular(18),
              border: cand.isNotEmpty
                  ? Border.all(color: Color(0xFFFF6A00), width: 2)
                  : Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                      width: 1.0,
                    ),
              boxShadow: [
                // Kenarda sıkı gölge + markanın renkli derinlik gölgesi.
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.09),
                  blurRadius: 3,
                  spreadRadius: 0.6,
                  offset: Offset(0, 1),
                ),
                BoxShadow(
                  color: glow.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: ink,
                          height: 1.15,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: ink.withValues(alpha: 0.75),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                // 3D görsel ikon varsa onu göster; yoksa altıgen HUD rozeti
                // (hero degradesi üstünde yarı saydam koyu zemin).
                if (widget.imageAsset != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      widget.imageAsset!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _HexBadge(
                        icon: widget.icon,
                        color: widget.gradient.first,
                        size: 50,
                        onGradient: true,
                      ),
                    ),
                  )
                else
                  _HexBadge(
                    icon: widget.icon,
                    color: widget.gradient.first,
                    size: 50,
                    onGradient: true,
                  ),
                SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  color: ink.withValues(alpha: 0.55),
                  size: 22,
                ),
              ],
            ),
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
  String timeMode = 'relax'; // 'relax' | 'normal' | 'race' | 'custom'
  /// timeMode=='custom' iken soru başına saniye (30–120 clamp).
  int customSecondsPerQuestion = 60;
  /// Soru tipi: 'mc' (çoktan seçmeli) · 'tf' (doğru/yanlış) ·
  /// 'fill' (boşluk doldurma) · 'mixed' (karışık)
  String questionType = 'mc';
  /// Yanlışlardan Tekrar Testi modu — true ise AI çağrısı yapılmaz,
  /// `wrongsToReuse`'daki sorular ile attempt oluşturulur.
  bool fromWrongs = false;
  List<dynamic> wrongsToReuse = const [];
  /// Karışık konu modunda eklenen yan konular (current topic'e ek).
  List<String> extraTopics = const [];

  int get timeLimitSeconds {
    switch (timeMode) {
      case 'normal':
        return 90;
      case 'race':
        return 45;
      case 'custom':
        return customSecondsPerQuestion.clamp(15, 300);
      default:
        return 0;
    }
  }

  // SharedPreferences için JSON sürümü — sadece kalıcı (UI) ayarlar.
  // fromWrongs / wrongsToReuse / extraTopics geçici, kalıcılaştırılmaz.
  Map<String, dynamic> toPrefsJson() => {
        'count': count,
        'difficulty': difficulty,
        'timeMode': timeMode,
        'customSecondsPerQuestion': customSecondsPerQuestion,
        'questionType': questionType,
      };

  void applyFromPrefsJson(Map<String, dynamic> m) {
    final c = m['count'];
    if (c is int) count = c.clamp(5, 40);
    final d = m['difficulty'];
    if (d is String && {'easy', 'medium', 'hard'}.contains(d)) difficulty = d;
    final t = m['timeMode'];
    if (t is String && {'relax', 'normal', 'race', 'custom'}.contains(t)) {
      timeMode = t;
    }
    final cs = m['customSecondsPerQuestion'];
    if (cs is int) customSecondsPerQuestion = cs.clamp(15, 300);
    final qt = m['questionType'];
    if (qt is String && {'mc', 'tf', 'fill', 'mixed'}.contains(qt)) {
      questionType = qt;
    }
  }

  static const String _prefsKey = 'test_config_last_v2';

  static Future<_TestConfig> loadFromPrefs() async {
    final cfg = _TestConfig();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return cfg;
      cfg.applyFromPrefsJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    return cfg;
  }

  Future<void> persistToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(toPrefsJson()));
    } catch (_) {}
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

// ─── Home aggregate'ları için yardımcı veri yapıları ────────────────────
// AcademicPlanner üst panellerinde (Devam Et, Bugün Tekrar Et, mini stats,
// kart-altı progress) kullanılır. Hepsi prefs'ten async hesaplanır.

class _DueItem {
  final String subjectName;
  final _Summary summary;
  final DateTime lastReview;
  final int currentIntervalDays;
  _DueItem({
    required this.subjectName,
    required this.summary,
    required this.lastReview,
    required this.currentIntervalDays,
  });
  int get daysSince => DateTime.now().difference(lastReview).inDays;
}

class _RecentItem {
  final String subjectName;
  final _Summary summary;
  final DateTime openedAt;
  _RecentItem({
    required this.subjectName,
    required this.summary,
    required this.openedAt,
  });
}


// TOC sheet'inde ana başlık ve alt başlıkları aynı düz listede taşır.
class _TocEntry {
  final int sectionIdx;
  final bool isSub;
  final String label;
  _TocEntry({
    required this.sectionIdx,
    required this.isSub,
    required this.label,
  });
}

class _SearchHit {
  final String subjectName;
  final _Summary summary;
  final bool topicMatch; // true: konu adı eşleşti, false: ders adı
  _SearchHit({
    required this.subjectName,
    required this.summary,
    required this.topicMatch,
  });
}

// Seviye → kısaltma (sınav tipi)
String _examShort(String grade) {
  switch (grade) {
    case 'LGS Hazırlık': return 'LGS';
    case 'TYT Hazırlık': return 'TYT';
    case 'AYT Hazırlık': return 'AYT';
    case 'KPSS Hazırlık': return 'KPSS';
    case 'Lise 9-10':    return 'TYT';
  }
  // Diğer ülkeler: EduProfile ülkesinin sınav kataloğundan YEREL sınav adı
  // (SAT, Abitur, Gaokao, JEE, A-Level, ENEM…). Böylece özet/soru üretimi
  // "jenerik sınav" değil, o ülkenin gerçek sınav stiline hizalanır.
  final p = EduProfile.current;
  final country = p?.country ?? '';
  if (country.isNotEmpty && country != 'tr') {
    try {
      final groups = examGroupsFor(country);
      if (groups != null && groups.isNotEmpty) {
        // İlk grup ülkenin ana (üniversiteye giriş / bitirme) sınavıdır.
        final name = groups.first.displayName.trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {/* katalog hatası → jenerik */}
  }
  return 'Sınav';
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
      : 'Hangi dersten test oluşturmak istersin?'.tr();

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

  // ── Home aggregate state — üst panellerin verisi ───────────────────────
  // Hepsi async _loadHomeAggregates ile doldurulur; UI null-safe render eder.
  // Sayfa her açılışta (initState + ekrana geri dönüldüğünde) yenilenir.
  List<_DueItem> _dueToday = [];
  _RecentItem? _continueItem;
  int _statsWeeklyMinutes = 0;
  int _statsTotalSummaries = 0;
  int _statsCompletedTopics = 0;

  // ── Arama state ────────────────────────────────────────────────────────
  bool _showSearch = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

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

  // ─── Home aggregate yükleyici ─────────────────────────────────────────
  // Tek SharedPreferences instance'ında: subjects + tüm SRS key'leri +
  // last_opened_summary + summary_completed_* + activity log → 4 panele
  // veri üretir. Subject sayısı * ortalama 5 özet pek çoğunlukla < 100
  // anahtar; getKeys() filter yeterince hızlı.
  Future<void> _loadHomeAggregates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // 1) Subjects + summary index
      final raw = prefs.getStringList(_subjectsKey) ?? const [];
      final subjects = <_Subject>[];
      for (final s in raw) {
        try {
          subjects
              .add(_Subject.fromJson(jsonDecode(s) as Map<String, dynamic>));
        } catch (_) {}
      }
      // summary id → (subject, summary) lookup
      final byId = <String, ({String name, _Summary summary})>{};
      int totalSummaries = 0;
      for (final sub in subjects) {
        for (final sum in sub.summaries) {
          byId[sum.id] = (name: sub.name, summary: sum);
          totalSummaries++;
        }
      }

      // 2) SRS due topics + completed count
      final due = <_DueItem>[];
      int completedTopics = 0;
      final now = DateTime.now();
      for (final k in keys) {
        if (!k.startsWith('srs_')) continue;
        final id = k.substring(4);
        final hit = byId[id];
        if (hit == null) continue;
        try {
          final m = jsonDecode(prefs.getString(k) ?? '{}')
              as Map<String, dynamic>;
          final lastStr = m['last'] as String?;
          final step = (m['step'] as int?) ?? 0;
          final done = (m['done'] as bool?) ?? false;
          if (lastStr == null) continue;
          final last = DateTime.tryParse(lastStr);
          if (last == null) continue;
          completedTopics++;
          if (done) continue;
          final stepClamp =
              step.clamp(0, _SummaryDetailPageState._kSrsIntervalsDays.length - 1);
          final intervalDays =
              _SummaryDetailPageState._kSrsIntervalsDays[stepClamp];
          final dueDate = last.add(Duration(days: intervalDays));
          if (now.isBefore(dueDate)) continue;
          due.add(_DueItem(
            subjectName: hit.name,
            summary: hit.summary,
            lastReview: last,
            currentIntervalDays: intervalDays,
          ));
        } catch (_) {}
      }
      // En çok bekleyen önce
      due.sort(
          (a, b) => b.lastReview.compareTo(a.lastReview) * -1);

      // 3) Continue: last_opened_summary
      _RecentItem? recent;
      try {
        final lastRaw = prefs.getString('last_opened_summary');
        if (lastRaw != null && lastRaw.isNotEmpty) {
          final m = jsonDecode(lastRaw) as Map<String, dynamic>;
          final id = m['summaryId'] as String?;
          final atStr = m['at'] as String?;
          final at = atStr != null ? DateTime.tryParse(atStr) : null;
          if (id != null && at != null) {
            final hit = byId[id];
            if (hit != null) {
              recent = _RecentItem(
                subjectName: hit.name,
                summary: hit.summary,
                openedAt: at,
              );
            }
          }
        }
      } catch (_) {}

      // 4) Haftalık dakikalar — son 7 gün durationSec toplamı
      final weekAgo = now.subtract(const Duration(days: 7));
      int weeklySec = 0;
      try {
        final all = await _ActivityStore.readAll();
        for (final e in all) {
          if (e.when.isAfter(weekAgo)) weeklySec += e.durationSec;
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _dueToday = due;
        _continueItem = recent;
        _statsWeeklyMinutes = weeklySec ~/ 60;
        _statsTotalSummaries = totalSummaries;
        _statsCompletedTopics = completedTopics;
      });
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'load_home_aggregates');
    }
  }

  // ─── Arama: ders adı + konu adı içinde fuzzy filter ──────────────────
  // Diakritik insensitive değil, basit lowercase contains — TR'de yeterli.
  // En fazla 30 sonuç döner.
  List<_SearchHit> _runSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <_SearchHit>[];
    for (final sub in _subjects) {
      final subjLower = sub.name.toLowerCase();
      final subjectMatch = subjLower.contains(q);
      for (final sum in sub.summaries) {
        final topicLower = sum.topic.toLowerCase();
        final topicMatch = topicLower.contains(q);
        if (!topicMatch && !subjectMatch) continue;
        out.add(_SearchHit(
          subjectName: sub.name,
          summary: sum,
          topicMatch: topicMatch,
        ));
        if (out.length >= 30) return out;
      }
    }
    return out;
  }

  void _toggleSearchBar() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchQuery = '';
        _searchCtrl.clear();
      }
    });
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
    _loadHomeAggregates();
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
    _searchCtrl.dispose();
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
    // Yerel boşsa cloud'dan restore — telefon değiştiyse veya yeniden
    // yüklendiyse kullanıcı eski özet/test'lerini geri alır.
    if (list.isEmpty) {
      unawaited(_restoreLibraryFromCloudIfEmpty());
    }
    // Subjects yüklendi → home aggregate (SRS due, progress, stats) yenile.
    // Async, fire-and-forget; build daha önce çalışırsa null-safe render eder.
    unawaited(_loadHomeAggregates());
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
    // Cloud sync — telefon değişimi/yeniden yükleme durumunda kullanıcının
    // kendi özetleri kaybolmasın. Yerel her zaman kaynak; cloud yedek.
    unawaited(_syncLibraryToCloud());
  }

  /// Kütüphaneyi (özet + test attempts) Firestore'a yedekler.
  /// Yerel yazımdan SONRA arka planda çalışır; başarısızlık yerel kaydı
  /// etkilemez. Auth yoksa sessiz no-op.
  Future<void> _syncLibraryToCloud() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      // Tek doc — listenin tamamı (özet+test attempts dahil). Subject sayısı
      // tipik 8-15, her birinin altında <50 summary/test → toplam <1MB.
      // Firestore doc limit 1MB; aşılırsa parça parça yazıma geçeriz.
      final payload = {
        'mode': widget.mode == LibraryMode.questions ? 'questions' : 'summary',
        'subjects':
            _subjects.map((s) => s.toJson()).toList(growable: false),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('library')
          .doc(widget.mode == LibraryMode.questions ? 'questions' : 'summary')
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Library] cloud sync fail: $e');
    }
  }

  /// Yerel boşsa cloud'dan geri yükle — bootstrap sırasında çağrılır.
  /// Cloud verisi varsa yerelin üstüne yazar (telefon değişti senaryosu).
  /// Cloud da boşsa hiçbir şey yapmaz.
  Future<bool> _restoreLibraryFromCloudIfEmpty() async {
    if (_subjects.isNotEmpty) return false; // yerel dolu
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return false;
      final docId =
          widget.mode == LibraryMode.questions ? 'questions' : 'summary';
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('library')
          .doc(docId)
          .get();
      if (!doc.exists) return false;
      final m = doc.data() ?? const <String, dynamic>{};
      final raw = m['subjects'];
      if (raw is! List) return false;
      final restored = <_Subject>[];
      for (final item in raw) {
        if (item is Map) {
          try {
            restored.add(_Subject.fromJson(
                Map<String, dynamic>.from(item)));
          } catch (e) {
            debugPrint('[Library] subject parse fail: $e');
          }
        }
      }
      if (restored.isEmpty) return false;
      if (!mounted) return false;
      setState(() => _subjects = restored);
      // Yerele de yaz — bir sonraki açılışta cloud'a tekrar gitmesin
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _subjectsKey,
        _subjects.map((s) => jsonEncode(s.toJson())).toList(),
      );
      debugPrint('[Library] cloud\'tan ${restored.length} ders restore edildi');
      return true;
    } catch (e) {
      debugPrint('[Library] cloud restore fail: $e');
      return false;
    }
  }





  // Public: detail page'in çağırdığı "yeni konu ekle" akışı (page açık kalır)
  // [forcedLength] — özet modunda kullanıcı UI'da "Kısa" veya "Kapsamlı"
  // slot'una bastıysa diyalog atlanır, bu uzunlukla üretilir.
  void _showSummaryPremiumGate() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF161B2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0xFF9D7FE6), width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Premium Özellik',
              style: TextStyle(
                color: Color(0xFFFFD166), fontSize: 20, fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '7 günlük ücretsiz deneme süren sona erdi. Konu özetleri oluşturmaya devam etmek için Premium\'a geç.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB9C2EE), fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PremiumScreen()),
                  );
                },
                child: const Text(
                  'Premium\'a Geç',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Geri Dön', style: TextStyle(color: Color(0xFF8A93B0))),
            ),
          ],
        ),
      ),
    );
  }

  void _showTestPremiumGate() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF161B2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0xFF9D7FE6), width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Premium Özellik',
              style: TextStyle(
                color: Color(0xFFFFD166), fontSize: 20, fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Her konudan 1 test ücretsiz oluşturabilirsin. Sınırsız test için Premium\'a geç.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB9C2EE), fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PremiumScreen()),
                  );
                },
                child: const Text(
                  'Premium\'a Geç',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Geri Dön', style: TextStyle(color: Color(0xFF8A93B0))),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _generateForExistingSubject(
      _Subject subject, String topic,
      {_TestConfig? config, _SummaryLength? forcedLength}) async {
    final isQuestions = widget.mode == LibraryMode.questions;
    final cfg = config ?? _TestConfig();

    // Deneme süresi (7 gün) bittiyse özet üretimi premium gerektirir.
    if (!isQuestions && !AiQuotaService.instance.isPremium) {
      _showSummaryPremiumGate();
      return false;
    }

    // ── ÖZET UZUNLUK ROUTING (kısa vs kapsamlı) ─────────────────────────
    // Aynı konuda max 2 özet: 1 kısa + 1 kapsamlı.
    //   • forcedLength verildi: o uzunluk var mı kontrol et; varsa engelle.
    //   • forcedLength null + ikisi de var: snack ile engelle.
    //   • forcedLength null + biri var: diğerini otomatik üret.
    //   • forcedLength null + hiçbiri yok: kullanıcıya sor.
    _SummaryLength? chosenLength;
    if (!isQuestions) {
      bool hasShort = false;
      bool hasComp = false;
      for (final s in subject.summaries) {
        if (s.topic.toLowerCase() == topic.toLowerCase()) {
          if (s.length == _SummaryLength.short) hasShort = true;
          if (s.length == _SummaryLength.comprehensive) hasComp = true;
        }
      }
      if (forcedLength != null) {
        final exists = forcedLength == _SummaryLength.short ? hasShort : hasComp;
        if (exists) {
          _showSnack(
              'Bu uzunlukta özet zaten var. Aynı konuda 3. özet üretilemez.'
                  .tr());
          return false;
        }
        chosenLength = forcedLength;
      } else if (hasShort && hasComp) {
        _showSnack(
            'Bu konunun hem kısa hem kapsamlı özeti zaten var. Tekrar oluşturulamaz.'
                .tr());
        return false;
      } else if (hasShort && !hasComp) {
        chosenLength = _SummaryLength.comprehensive;
      } else if (hasComp && !hasShort) {
        chosenLength = _SummaryLength.short;
      } else {
        chosenLength = await _askSummaryLength(context);
        if (chosenLength == null) return false;
      }
    }

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
      // Ücretsiz kullanıcı (deneme bitti): konudan sadece 1 test.
      if (existingSummary != null &&
          existingSummary.tests.isNotEmpty &&
          !AiQuotaService.instance.isPremium) {
        _showTestPremiumGate();
        return false;
      }
      if (existingSummary != null && existingSummary.tests.length >= 6) {
        _showSnack(
            'Bu konu için 6 test hakkın da bitti. Başka bir konu dene.'.tr());
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
        length: chosenLength ?? _SummaryLength.short,
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
          length: chosenLength ?? _SummaryLength.short,
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
    // Ebeveyn önizlemesi: test üretimi kapalı (salt-izleme).
    if (ParentPreview.guard(context)) return;
    final cfg = config ?? _TestConfig();
    if (summary.tests.length >= 6) {
      _showSnack(
          'Bu konu için 6 test hakkın da bitti. Başka bir konu dene.'.tr());
      return;
    }
    // Ücretsiz kullanıcı (deneme bitti): konudan yalnızca 1 YENİ test. Premium
    // gate — diğer test üretim yollarıyla tutarlı. fromWrongs (yanlış tekrarı,
    // AI'sız, kota harcamaz) muaf — yeni içerik üretmiyor.
    if (!cfg.fromWrongs &&
        summary.tests.isNotEmpty &&
        !AiQuotaService.instance.isPremium) {
      _showTestPremiumGate();
      return;
    }
    // ── YANLIŞLARDAN TEKRAR YOLU — AI çağrısı yok, kota tüketilmez ───
    if (cfg.fromWrongs) {
      final wrongs = cfg.wrongsToReuse.whereType<TestQuestion>().toList();
      if (wrongs.isEmpty) {
        _showSnack('Tekrar edilecek yanlış soru bulunamadı.'.tr());
        return;
      }
      // JSON array string olarak yeniden serileştir — TestPage parse eder.
      final rebuilt = jsonEncode(wrongs
          .map((q) => {
                'q': q.q,
                'opts': q.opts,
                'ans': q.ans,
                'hint': q.hint,
                'sol': q.sol,
                'd': q.d,
              })
          .toList());
      final attempt = _TestAttempt(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: rebuilt,
        answers: {},
        completed: false,
        createdAt: DateTime.now(),
        timeLimit: cfg.timeLimitSeconds,
        difficulty: 'mixed',
      );
      summary.tests.add(attempt);
      await _persistSubjects();
      await _ActivityStore.log(
        subject: subject.name,
        topic: summary.topic,
        type: 'soru',
      );
      if (!mounted) return;
      setState(() {});
      _openTestAttempt(summary, attempt, subject.name);
      return;
    }
    // ── HAVUZDAN ÇEKME YOLU — aynı ülke/seviye/sınıf öğrencileri için ──
    // Topluluk soru havuzu (QuestionPoolService) yeterli soru biriktiyse,
    // AI çağrısı yapmadan oradan çek. Karışık konu modunda atla (havuz
    // tek konuluk). drawQuestions accepted<10 ise null döner → AI fallback.
    if (cfg.extraTopics.isEmpty) {
      try {
        final profile = await EduProfile.load();
        // "Topluluk önerileri" kapalıysa havuzu kullanma → doğrudan AI üretir.
        if (profile != null && AppSettingsService.instance.communityData) {
          // 'medium' tüm havuz dahil; 'easy'/'hard' filtreli çek.
          final filterDifficulty =
              (cfg.difficulty == 'easy' || cfg.difficulty == 'hard')
                  ? cfg.difficulty
                  : null;
          final pool = await QuestionPoolService.drawQuestions(
            profile: profile,
            subject: subject.name,
            topic: summary.topic,
            count: cfg.count,
            difficulty: filterDifficulty,
          );
          if (pool != null && pool.length >= cfg.count ~/ 2) {
            // PoolQuestion → TestQuestion JSON formatına dönüştür
            const letters = ['A', 'B', 'C', 'D', 'E'];
            final json = jsonEncode(pool.map((p) {
              final opts = <String, String>{};
              for (var i = 0; i < p.options.length && i < 5; i++) {
                opts[letters[i]] = p.options[i];
              }
              final ansIdx = p.correctIndex.clamp(0, opts.length - 1);
              return {
                'q': p.stem,
                'opts': opts,
                'ans': letters[ansIdx],
                'hint': '',
                'sol': p.explanation ?? '',
                'd': p.difficulty,
              };
            }).toList());
            if (parseTestQuestions(json).isNotEmpty) {
              final attempt = _TestAttempt(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                content: json,
                answers: {},
                completed: false,
                createdAt: DateTime.now(),
                timeLimit: cfg.timeLimitSeconds,
                difficulty: cfg.difficulty,
              );
              summary.tests.add(attempt);
              await _persistSubjects();
              await _ActivityStore.log(
                subject: subject.name,
                topic: summary.topic,
                type: 'soru',
              );
              if (!mounted) return;
              setState(() {});
              _showSnack(
                  '📦 ${pool.length} soru havuzdan getirildi — kotan dokunulmadı.'
                      .tr());
              _openTestAttempt(summary, attempt, subject.name);
              return;
            }
          }
        }
      } catch (e, st) {
        ErrorLogger.instance.capture(e, st, context: 'question_pool_draw');
        // Sessizce AI fallback'e geç
      }
    }
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
        questionType: cfg.questionType,
        extraTopics: cfg.extraTopics,
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
      // ── HAVUZA ORGANIK YAZIM (fire-and-forget) ──────────────────────────
      // AI'ın ürettiği soruları topluluk havuzuna ekle → sonraki öğrenciler
      // aynı (country|level|grade|subject|topic) için havuzdan çekecek.
      // Hata olursa kullanıcı akışı etkilenmez (sessizce log'a düşer).
      try {
        final profileForPool = await EduProfile.load();
        if (profileForPool != null) {
          final parsed = parseTestQuestions(content);
          if (parsed.isNotEmpty) {
            const letters = ['A', 'B', 'C', 'D', 'E'];
            final qList = <Map<String, dynamic>>[];
            for (final q in parsed) {
              final options = <String>[];
              for (final l in letters) {
                final v = q.opts[l];
                if (v != null) options.add(v);
              }
              final ansIdx = letters.indexOf(q.ans.toUpperCase());
              if (ansIdx < 0 || ansIdx >= options.length) continue;
              qList.add({
                'stem': q.q,
                'options': options,
                'correctIndex': ansIdx,
                'explanation': q.sol,
                'difficulty': q.d,
              });
            }
            // "Topluluk önerileri" kapalıysa kullanıcının soruları havuza
            // YAZILMAZ (veri toplanmaz).
            if (qList.isNotEmpty &&
                AppSettingsService.instance.communityData) {
              unawaited(QuestionPoolService.insertQuestions(
                profile: profileForPool,
                subject: subject.name,
                topic: summary.topic,
                questions: qList,
              ));
            }
          }
        }
      } catch (e, st) {
        ErrorLogger.instance.capture(e, st,
            context: 'pool_insert_after_ai_test');
      }
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
    // Ücretsiz kullanıcı (deneme bitti): bir konudan yalnızca 1 test. Premium
    // gate — _generateForExistingSubject (5641) ile aynı kural, iki test üretim
    // yolu artık tutarlı. (isPremium deneme süresince true → deneme serbest.)
    if (nextIdx >= 1 && !AiQuotaService.instance.isPremium) {
      _showTestPremiumGate();
      return;
    }
    if (nextIdx >= 6) {
      _showSnack(
          'Bu konu için 6 test hakkın da bitti. Başka bir konu dene.'.tr());
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
    // Ebeveyn önizlemesi: özet/soru ÜRETİMİ kapalı (salt-izleme).
    if (ParentPreview.guard(context)) return;
    final isQuestions = widget.mode == LibraryMode.questions;
    final cfg = config ?? _TestConfig();

    // 7 günlük ücretsiz deneme bittiyse YENİ özet üretimi Premium gerektirir.
    // (_generateForExistingSubject ile aynı kural — iki üretim yolu tutarlı.)
    // NOT: Bu yalnız ÜRETİMİ engeller; deneme süresince üretilmiş eski özetler
    // her zaman görüntülenebilir kalır.
    if (!isQuestions && !AiQuotaService.instance.isPremium) {
      _showSummaryPremiumGate();
      return;
    }

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
        existingSummary.tests.length >= 6) {
      _showSnack(
          'Bu konu için 6 test hakkın da bitti. Başka bir konu dene.'.tr());
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
        // CACHE HIT — anında göster, stream'siz. AI çağrısı YAPILMADIĞI için
        // 6280'de erkenden artırılan kotayı geri ver (topluluk cache'inin
        // amacı kullanıcıya bedava içerik + kota tasarrufu sağlamak).
        await UsageQuota.decrement(kind);
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
    _SummaryLength length = _SummaryLength.short,
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
        length: length,
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
    String questionType = 'mc',
    List<String> extraTopics = const [],
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
    // ── Soru tipi direktifi ───────────────────────────────────────────
    // Parser tüm tipleri opts/ans formatında bekliyor; "tf" 2 şık (Doğru/
    // Yanlış), "fill" boşluk doldurma stilinde soru + 5 şık, "mixed" karışım.
    final qTypeLine = () {
      switch (questionType) {
        case 'tf':
          return '• SORU TİPİ: Hepsi DOĞRU/YANLIŞ. "opts" SADECE 2 şık olsun '
              '({"A": "Doğru", "B": "Yanlış"}). Soru metni bir önerme '
              'cümlesi (bildirim cümlesi) olmalı, soru cümlesi değil. '
              'Önermeyi doğrulamak/yalanlamak öğrencinin işi.';
        case 'fill':
          return '• SORU TİPİ: Hepsi BOŞLUK DOLDURMA. Soru metninde anahtar '
              'kavramı "_____" (5 alt çizgi) ile gizle. "opts" 5 şık olsun '
              've sadece bir tanesi boşluğa doğru tamamlamayı yapsın. '
              'Çeldirici şıklar yakın kavramlar/kelimeler olsun.';
        case 'mixed':
          return '• SORU TİPİ: KARIŞIK — sorular arası dağılım yaklaşık şöyle '
              'olsun: %50 çoktan seçmeli klasik, %25 doğru/yanlış (2 şık), '
              '%25 boşluk doldurma (5 şık + soruda "_____"). Tek bir test '
              'farklı tipleri görür.';
        case 'mc':
        default:
          return '• SORU TİPİ: Hepsi ÇOKTAN SEÇMELİ (klasik). 5 şık, 1 doğru.';
      }
    }();
    final extraTopicsLine = extraTopics.isEmpty
        ? ''
        : '\nEK KONULAR (karışık konu testi): ${extraTopics.join(", ")}\n'
            '• KARIŞIK KONU MODU: Sorular toplam $count tane ve şu konular '
            'arasında dağıtılmış: $topic + ${extraTopics.join(", ")}. '
            'Her konudan dengeli pay (yaklaşık eşit sayıda soru).\n';

    // ── GÖRSEL SORU PROTOKOLÜ — bazı sorular diyagram/şekil üzerinden ──────
    // Gerçek sınavlarda (ÖSYM/LGS) soruların bir kısmı şekil/grafik/devre
    // okumaya dayanır. UI, "q" içindeki [ŞEMA: ...] ... [/ŞEMA] bloğunu
    // monospace diyagram kartı olarak render eder → soru görsel olur.
    const visualBlock = r'''
[GÖRSEL SORU PROTOKOLÜ — DİYAGRAM ÜZERİNDEN SORMA]
Bu konu ŞEKİLLE anlatılabiliyorsa, soruların YAKLAŞIK %25'ini (her 4 sorudan
~1'i) bir DİYAGRAM üzerine kur. Diyagramı "q" alanının İÇİNE, aşağıdaki blokla
göm (UI bunu şekil kartı olarak çizer):

  [ŞEMA: <kısa şekil adı>]
  <Unicode/ASCII çizim — 4-9 satır, 28-46 karakter genişlik>
  ─────────
  <1: ... , 2: ... gibi kısa lejant satırları>
  [/ŞEMA]

ve şekilden SONRA tek cümlelik soruyu yaz. Örnek "q" değeri (JSON'da \n ile):
  "[ŞEMA: Basit Devre]\n ┌── R₁ ──┬── R₂ ──┐\n │        │        │\n ⎓ V      ⊗ L1     ⊗ L2\n └────────┴────────┘\n─────────\nV=Pil, R=Direnç, L=Lamba\n[/ŞEMA]\nŞekildeki devrede L1 lambasının parlaklığı L2'ye göre nasıldır?"

GÖRSEL-UYGUN KONULAR (bunlarda ~%25 şekilli soru ZORUNLU):
• Geometri (şekil + ölçü), fonksiyon/parabol grafiği, koordinat düzlemi
• Fizik: devre (seri/paralel), kuvvet/vektör diyagramı, optik ışın yolu,
  dalga formu, hareket grafiği (konum-zaman, hız-zaman)
• Kimya: atom/Bohr modeli, molekül yapısı, deney düzeneği, periyodik kesit
• Biyoloji: hücre/organel, sistem (dolaşım/sindirim), besin zinciri, genetik
  çaprazlama (Punnett karesi tablo da olabilir)
• Coğrafya: yer şekli kesiti, izohips/harita okuma, iklim grafiği, levha
• Matematik (ilk/ortaokul): kesir pastası, geometrik cisim, saat, sayı doğrusu

KURALLAR:
• Şekil çizimi MONOSPACE hizalı olsun; kutu/ok/geometri sembolleri serbest:
  ┌─┐│└┘╭╮╰╯ → ← ↑ ↓ ○●◇◆□■△▲ ⊕⊖⊗ ⎓ ∡ ° · x y.
• Şekil olmadan cevaplanabilen soruyu ŞEMA'ya SOKMA — diyagram soruya GERÇEKTEN
  gerekli olsun (şekilden veri/ilişki okunmalı). Süs diyagram YASAK.
• Görsel soruda da "opts/ans/hint/sol" kuralları aynen geçerli; çözüm şekle atıf
  yapsın ("R₁ ile R₂ seri → ...").
• KONU görsel-uygun DEĞİLSE (ör. tarih tarihleri, kelime bilgisi, felsefe
  kavramı) şekil ZORLAMA — o testte 0 diyagram normaldir.
• Şekilli soru "q" çok satırlıdır; "en fazla 15 kelime" kuralı yalnız ŞEKİL
  DIŞINDAKİ soru cümlesi için geçerli (diyagram satırları sayılmaz).
''';
    return '''
${_strategyBlock(strategy, exam)}
$ragSection
[TEST — $count SORU · JSON]
Ders: $subject
Konu: $topic$extraTopicsLine
Bağlam: $ctx
Zorluk: $difficulty
Katman: ${isNumeric ? 'SAYISAL (formül + sembol + birim)' : isVerbal ? 'SÖZEL (anlatı + kronoloji + bağlam)' : 'KARMA'}

GÖREVİN: Bu konu için $exam stiline uygun TAM OLARAK $count soru üret.
Tüm sorular $difficulty zorluk seviyesinde olsun.
QuAlsar Akademik İçerik Protokolü'nü uygula:
$layerLine
$qTypeLine
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

[SORU YAZIM STANDARDI — ÖSYM/ULUSLARARASI SINAV KALİTESİ]
Gerçek sınav sorusu yazan bir SORU YAZARI gibi çalış; her madde zorunlu:
• KÖK TEK ANLAMLI: Soru kökü tek yorumla okunur; gereksiz bilgi, süs,
  hikâye YOK. Olumsuz kökte olumsuzluk vurgulu yazılır
  ("hangisi YANLIŞTIR?", "hangisi DEĞİLDİR?").
• ŞIK PARALELLİĞİ: Tüm şıklar aynı dilbilgisi yapısında ve BENZER
  uzunlukta. Doğru cevap sistematik olarak en uzun/en detaylı şık OLMASIN
  (öğrenci uzun şıkkı işaretleyerek bilmeden doğru yapmasın).
• YASAK ŞIKLAR: "Hepsi", "Hiçbiri", "A ve B", "Yukarıdakilerin tümü" YOK.
• CEVAP DAĞILIMI: $count soruda doğru cevap harfleri DENGELİ dağılsın —
  aynı harf art arda en fazla 2 kez; tek harf toplamın %40'ını geçmesin
  (doğru/yanlış tipinde: iki harf yaklaşık yarı yarıya).
• KAZANIM ÇEŞİTLİLİĞİ: Her soru konunun FARKLI bir alt kavramını/kazanımını
  ölçer — aynı bilgiyi iki kez sorma. Bir sorunun kökü, başka bir sorunun
  cevabını ele vermesin (bilgi sızıntısı yasak).
• BİLİŞSEL DAĞILIM: Yalnız ezber sorma — yaklaşık %30 tanım/hatırlama,
  %40 uygulama/hesap, %30 analiz/yorum sorusu (zorluk seviyesi içinde).
• ÇIKMIŞ SORU HİZASI: $exam sınavının GERÇEK çıkmış soru kalıplarını taklit
  et — soru uzunluğu, şık kurgusu ve çeldirici mantığı o sınavın
  istatistiklerine benzesin; ders kitabı sonu alıştırması gibi durmasın.

[ÜRETİM ÖNCESİ DOĞRULAMA — HER SORUYU YAZDIKTAN SONRA KENDİN ÇÖZ]
JSON'a koymadan önce her soru için içinden şu 4 kontrolü yap (çıktıya
YAZMA, sadece uygula); geçemeyen soruyu düzelt ya da yenisiyle değiştir:
1. Soruyu bağımsız çöz → bulduğun sonuç "ans" harfindeki şıkla BİREBİR
   aynı mı? Sayısalda hesabı yap; "sol"daki adımlar ve sonuç tutarlı mı?
2. Diğer 4 şıktan HİÇBİRİ hiçbir yorumla doğru olamaz mı? Çift doğru
   ihtimali olan soru GEÇERSİZ — şıkkı değiştir.
3. Sorudaki her bilgi (tarih, isim, formül, sabit, birim) ders kitabı
   değeriyle uyumlu mu? Emin olmadığın bilgiyi soruya SOKMA.
4. Doğru/yanlış tipinde önerme KESİN doğru ya da KESİN yanlış mı?
   Tartışmalı, göreceli, "genelde" gerektiren önerme yasak.

[KOMPAKTLIK — HIZ KURALI]
Çıktı ne kadar öz, üretim o kadar hızlı; şu sınırların ÜSTÜNE ÇIKMA:
• Şık metni ≤ 8 kelime; sayısal şıklarda sadece değer + birim ("3 m/s²").
• "hint" ≤ 15 kelime. "sol" ≤ 45 kelime (2-3 cümle, → oklu zincir).
• İçsel akıl yürütmeni ve doğrulama notlarını çıktıya DÖKME — çıktı
  yalnızca istenen JSON array.

ZORUNLU KURALLAR:
• TAM $count soru, ne eksik ne fazla.
• "opts" her zaman 5 şık: A, B, C, D, E.
• "ans" şık harfi: "A" | "B" | "C" | "D" | "E".
• Soru metni (q) ÇOK KISA — ideal 1 kısa cümle, maksimum 15 kelime.
  Uzun anlatım, hikâye, gereksiz detay EKLEME. (İSTİSNA: görsel soruda "q"
  bir [ŞEMA: ...] diyagram bloğu + kısa soru cümlesi içerir; 15 kelime sınırı
  yalnız soru cümlesine uygulanır — bkz. GÖRSEL SORU PROTOKOLÜ.)
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
$visualBlock
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
• ÇIKTI DİLİ: ${localeService.localeCode == 'tr' ? 'Türkçe' : 'TÜM içerik (soru, şık, çözüm) "${localeService.localeCode}" dil kodundaki dilde — Türkçe/İngilizce DEĞİL'}. $exam stiline uygun, tek doğru cevaplı.
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
  • LaTeX KULLANMA — düz, akıcı paragraf/maddeler (yukarıdaki [ÇIKTI DİLİ] kuralındaki dilde).
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

    // ── PEDAGOJİK ÖĞE PROTOKOLÜ — özeti "okunan" değil "öğreten" yapan öğeler
    // Referans: Cornell (ipucu+özet), aktif hatırlama (test etkisi), charting.
    // UI bu 3 bloğu ÖZEL kart olarak render eder → işaretleri BİREBİR kullan.
    const pedagogyBlock = '''
[PEDAGOJİK ÖĞELER — ÖĞRENMEYİ MÜHÜRLEYEN KAPANIŞ (İŞARETLER BİREBİR)]
Konu anlatımı bittikten SONRA, özetin SONUNA aşağıdaki öğeleri EKLE. UI
bunları özel renkli kart olarak gösterir; başlık işaretlerini AYNEN yaz.

1) ⭐ Aklında Kalsın   ← ZORUNLU (her özette, en sonda)
   Konunun EN KRİTİK 3-6 maddesi — sınavdan önce son bakışta okunacak öz.
   Her madde tek satır, "•" ile başlar, kısa ve keskin (ezberlenecek çekirdek).
   Biçim:
     ⭐ Aklında Kalsın
     • <en kritik nokta 1>
     • <en kritik nokta 2>
     • …

2) 🎯 Kendini Sına   ← KAPSAMLI özette ZORUNLU, KISA özette 1-2 soruyla opsiyonel
   Aktif hatırlama: konuyu ölçen 3-5 kısa soru + hemen altında cevabı.
   Öğrenci önce cevabı kapatıp kendini test eder. Sayısalsa 1-2 mini hesap
   sorusu da olsun. Biçim:
     🎯 Kendini Sına
     • S1: <soru> → C: <kısa cevap>
     • S2: <soru> → C: <kısa cevap>
     • …

3) 🧠 Hafıza Tekniği   ← Ezberlenmesi gereken bir SIRA/LİSTE varsa EKLE (opsiyonel)
   Akronim, baş harf cümlesi veya çağrışım ver. Tek satır:
     🧠 Hafıza Tekniği: <akronim/çağrışım ve neyi hatırlattığı>

KURALLAR:
• Bu 3 blok özetin ANLATIM gövdesinin İÇİNE serpiştirilmez — hepsi en SONA gelir.
• "⭐ Aklında Kalsın" HER özette bulunur (kısa modda bile). Diğer ikisi konuya göre.
• Cevaplar/maddeler öğrencinin dilinde; gereksiz LaTeX/kod artığı olmadan düz metin.
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
    // KRİTİK: Bu iki mod CIDDI ÖLÇÜDE farklı çıktı vermeli. Kısa = sadece öz;
    // Kapsamlı = mümkün olan en detaylı, hiçbir alt başlık eksik kalmadan.
    final lengthDirective = length == _SummaryLength.short
        ? '''
[ÖZET UZUNLUĞU — KISA · MUTLAK ÖNCELİK]
KULLANICI KISA ÖZET istedi. SADECE EN ÖNEMLİ NOKTALAR.
HEDEF: 300-550 KELİME ARASI. Bu sınırı AŞMA. Saymadan önce yaz, sonra fazlasını kes.

ZORUNLU İÇERİK (yalnızca bunlar):
• Konunun 1-2 cümlelik TANIMI.
• EN KRİTİK 3-5 ANA NOKTA (her biri en fazla 2-3 cümle).
• Sınav için MUTLAKA bilinmesi gereken 1-3 FORMÜL veya KAVRAM
  (matematik/fizik/kimya ise; sözel ise 1-3 anahtar tarih/kural/tanım).
• Konuya özel 1 KRİTİK TUZAK/YAYGIN HATA (varsa).

KESİNLİKLE YAPMA:
✗ Uzun türetme / ispat
✗ Birden fazla çözümlü örnek soru (en fazla 1 mini örnek)
✗ Tarihsel arka plan / detaylı dönem analizi
✓ 1-2 küçük tablo serbest (karşılaştırma/sınıflandırma için)
✓ ŞEMA: görsel-zorunlu konularda (hücre, anatomi, atom, dalga, devre,
  harita, kesir pastası, ilkokul/ortaokul konuları) EN AZ 1, EN FAZLA 2.
  Diğer konularda kısa modda şema YOK.
✗ "Bonus", "ileri seviye not", "ek bilgi" gibi opsiyonel kısımlar

ZORUNLU KAPANIŞ (kelime hedefine EK, kısa tut):
✓ "⭐ Aklında Kalsın" — 3-5 kritik madde (her biri tek satır).
✓ "🎯 Kendini Sına" — 1-2 kısa soru + cevap (öğrenci kendini yoklasın).

TON: YOĞUN, KESKİN, FİLTRELİ. Bir öğrenci sınav öncesi son 5 dakikada
okusa, konuyu kafasında tazelemeli. Genişletme YOK; özünü ver, geç.
'''
        : '''
[ÖZET UZUNLUĞU — KAPSAMLI · MAKSIMUM DERİNLİK]
KULLANICI KAPSAMLI ÖZET istedi. KONUYU EN İNCE DETAYINA KADAR İŞLE.
HEDEF: 2200-4000 KELİME. Aşağı düşme — eksik kalmasından bol olması iyidir.

ZORUNLU İÇERİK (HEPSİ EKSİKSİZ):
• Konunun TARİHÇESİ / BAĞLAMI (nereden geldi, neden önemli).
• TÜM ALT BAŞLIKLAR — biri bile atlanmasın. Müfredatta geçen her kavram
  ayrı kart/bölüm olarak işlenir.
• Her formül için TAM TÜRETİM (1-3 adımda) + sembol tablosu + birim
  analizi + tipik değerler.
• Her alt başlık için EN AZ 1 ÇÖZÜMLÜ ÖRNEK ("🧪 Uygulama Örneği" hücresi)
  — sayısal derste 3-5 örnek; sözel derste 2-3 vaka analizi.
• İSTİSNALAR, UÇ DURUMLAR, SINIR HÂLLERİ (0!, n=0, payda=0, kararsız izotop,
  istisna kelime grubu vb.) tek tek listele, neden istisna olduğunu açıkla.
• Konuyla İLİŞKİLİ DİĞER KONULAR (bağlantı haritası): hangi konuyla nasıl
  bağlanır, prerequisite hangileri, ileri seviye nereye götürür.
• YAYGIN HATALAR / TUZAKLAR — sınavda en çok hangi noktada öğrenci yanılır,
  doğru yaklaşım nedir.
• TABLOLAR bol miktarda (EN AZ 4-6 tane) — karşılaştırma, sınıflandırma,
  formül listesi, kronoloji, kavram sözlüğü, sebep-sonuç hep tablo.
• GÖRSELLER (ŞEMA): konuya göre 1-5 arası. Görsel-zorunlu konularda
  (hücre, anatomi, atom modeli, dalga, devre, harita, eser kapağı,
  ilkokul/ortaokul müfredatı) MUTLAKA görsel ekle — eksik kalmasın.
• İLERİ SEVİYE NOTLAR / BONUS — meraklı öğrenci için ekstra derinlik.
• ZORUNLU KAPANIŞ ÜÇLÜSÜ (en sonda): "⭐ Aklında Kalsın" (5-6 çekirdek madde),
  "🎯 Kendini Sına" (3-5 soru + cevap; sayısalda 1-2 mini hesap dahil) ve
  ezberlenecek liste varsa "🧠 Hafıza Tekniği" (akronim/çağrışım).

TON: BİR DERSHANE KİTABININ EN AYRINTILI BÖLÜMÜ + akademik makale arası.
Konuyu hiç bilmeyen biri okuyup sıfırdan uzmanlaşabilmeli. Tekrar etmekten
kaçınma — pekiştirme için aynı kavramı farklı açıdan tekrar tekrar göstermek
KAPSAMLI özetin imzasıdır. Eksik bırakmak HATA, fazla yazmak ERDEMDİR.
''';

    final lang = localeService.localeCode;
    final langDirective = lang == 'tr'
        ? '[ÇIKTI DİLİ] Tüm metin, başlık, tablo hücreleri, şema lejantları, '
            'parça etiketleri ve numaralı açıklamalar TÜRKÇE yazılacak. '
            'Yabancı kavramların Türkçe karşılığı varsa onu kullan '
            '(örn. "Nucleus" değil "Çekirdek"). Karışık dil YOK.'
        : '[OUTPUT LANGUAGE] All text, headings, table cells, schema legends, '
            'part labels and numbered explanations MUST be in the language '
            'with code "$lang". Use native vocabulary; no mixing with other '
            'languages (e.g. don\'t write English term alongside translation).';

    return '''
$langDirective

$lengthDirective
${_strategyBlock(strategy, exam)}
$ragSection
[KONU ÖZETİ — DERSHANE KİTABI TARZI]
Ders: $subject
Konu: $topic
Bağlam: $ctx

[REFERANS DERS KİTABI HİZASI — İÇERİK OTORİTESİ]
Bu özeti yazarken zihninde o ülkenin RESMÎ DERS KİTABI + alanının dünyaca
kabul görmüş referans kitapları açık dursun; içerik onlarla HİZALI olsun:
• Türkiye müfredatı → MEB onaylı ders kitabı ünite işlenişi ve kazanım
  listesi; diğer ülkeler → kendi resmî müfredat kitabı.
• Disiplin referansları (doğruluk ve anlatım sırası çıpası):
  Biyoloji → Campbell Biology · Fizik → Halliday-Resnick-Walker ·
  Kimya → Zumdahl/Atkins · Matematik → Stewart Calculus / ulusal kaynak ·
  Tarih-Coğrafya-Edebiyat → ulusal akademik ders kitapları ·
  Açık kaynak yapı örneği → OpenStax bölüm mimarisi.
• KONU SIRASI: Kitaplardaki pedagojik sırayı izle — önce ön koşul kavram,
  sonra ana kavram, sonra uygulama. Kitapta önce gelen kavramı sona atma.
• TERMİNOLOJİ: Öğrencinin ülkesindeki ders kitabında hangi terim
  kullanılıyorsa AYNEN onu kullan (sınavda o terim sorulur).
• SAYISAL DOĞRULUK: Sabitler, tarihler, formüller ders kitabı konsensüs
  değerleriyle birebir (örn. Avogadro 6,022×10²³; g = 9,81 m/s²).
  Emin olmadığın spesifik değeri YAZMA — yanlış bilgi en büyük hatadır.
• KAZANIM KAPSAMI: Bu konunun müfredat kazanımlarında geçen HER alt
  kavram özette karşılık bulmalı; kitapta işlenen alt başlığı atlama.
• KAVRAM YANILGISI: Ders kitaplarının "sık yapılan yanlış" kutuları gibi,
  bu konuda öğrencilerin bilimsel olarak YANLIŞ kurduğu ezberleri
  ("ağır cisim hızlı düşer", "mitoz sadece vücut hücresinde olur" tarzı)
  tespit et ve 🔴 rozetli başlık veya 💡 satırıyla düzelt.

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

📊 İÇERİK ANLATIM KURALI — DOĞRU FORMAT, DOĞRU YERDE (KRİTİK):
Her bilgi tipinin ideal sunum biçimi farklıdır. Hedef: ÖĞRENCİ KAFASINDA
RESIM OLUŞSUN. Tablo verisi tablo, görsel bilgisi GÖRSEL olarak ver.

🟦 TABLO KULLAN — şu durumlarda:
• Karşılaştırma (X vs Y): kavram/yıl/temsilci/özellik → TABLO
• Sınıflandırma (türler, alt türler, kategoriler) → TABLO
• Süreç adımları metinsel ise (1, 2, 3 → sonuç) → TABLO
• Formül listesi (formül, ne için, birim) → TABLO
• Zaman çizgisi / kronoloji → TABLO (yıl | olay | etki)
• Dilbilgisi kuralı + istisnası → TABLO (kural | örnek | istisna)
• Periyodik özellikler → TABLO
• Kavram sözlüğü → TABLO (terim | tanım | örnek)

🟪 GÖRSEL (ŞEMA) ZORUNLU — şu konularda öğrenci görmeden öğrenemez:
✅ FEN BİLİMLERİ
• Hücre yapısı (bitki/hayvan hücresi, organeller numaralı) → ŞEMA ŞART
• Fotosentez → yaprak kesiti + hücredeki kloroplast + reaksiyon akışı
• Solunum sistemi / sindirim sistemi / dolaşım sistemi / boşaltım sistemi
  → organların yerleşimi + akış oklarıyla
• İnsan anatomisi (kalp, beyin, göz, kulak, böbrek, akciğer) → kesit + numara
• Atom modelleri (Bohr, Rutherford, Dalton, Thomson, Modern) → her birinin
  ŞEMASI ayrı ayrı
• Periyodik tablo kesiti (gruplar/periyotlar arası ilişki) → grid ŞEMA
• Dalga şekilleri (enine, boyuna, su, ses, ışık) → dalga formları
• Elektrik devreleri → seri/paralel ŞEMA
• Optik (mercek, ayna, ışık yolu, kırılma) → ışık yolu ŞEMASI
• Coğrafya: yer şekli kesiti, levha hareketi, atmosfer katmanları,
  iklim haritası → ŞEMA + harita basit gösterim
• Geometrik şekil, vektör → ŞEMA

✅ SOSYAL / EDEBİYAT
• Tarih: önemli savaş haritası, sınır değişimi, antlaşma kesiti → ŞEMA
• Edebiyat: eserin (örn. "Çalıkuşu", "Saatleri Ayarlama Enstitüsü") kapak
  ASCII çizimi, dönem-akım ağacı, karakterler arası ilişki şeması → ŞEMA
• Felsefe: düşünce akımları arasındaki etki şeması → ŞEMA

✅ İLKOKUL (1-4) ve ORTAOKUL (5-8) — GÖRSEL EN KRİTİK
Bu yaş aralığında öğrenci SOMUT düşünür. Her ana kavram için MUTLAKA görsel:
• Matematik: kesirler (pasta dilimi ŞEMA), dört işlem (somut nesne ŞEMA),
  geometri (şekiller + ölçüler ŞEMA), saat okuma (saat yüzü ŞEMA)
• Fen: canlılar, mevsimler, su döngüsü, kuvvet/hareket → HER BİRİ ŞEMA
• Türkçe: noktalama (cümle örneği + işaret konumu ŞEMA), öyküleyici metin
  yapısı (giriş-gelişme-sonuç akış ŞEMASI)
• Sosyal: harita, mahalle krokisi, milli bayramlar zaman çizgisi → ŞEMA
• Müzik: nota değerleri, porte → ŞEMA
• Hayat bilgisi: trafik kuralları, beslenme piramidi → ŞEMA

🟧 ALTIN KURAL: "Bir öğrenci bu konuyu okuyup KAFASINDA RESIM OLUŞTURABİLİYOR MU?"
• EVET (sebep-sonuç metni, tarih listesi, kural-istisna) → TABLO/METİN
• HAYIR (anatomik yapı, devre, dalga, hücre, model, harita) → ŞEMA ZORUNLU

🟧 KİTAP KURALI (ŞEMA YERLEŞİMİ TESTİ): Her ana başlığı yazmadan önce
kendine sor: "Basılı bir ders kitabında bu paragrafın YANINDA şekil olur
muydu?" Cevap EVET ise o paragrafın hemen altına [ŞEMA] koy — kitapta
şekilli anlatılan konuyu şemasız anlatmak eksik anlatımdır. Görsel-zorunlu
bir konuda tek şema bile yoksa çıktı GEÇERSİZDİR.

DİL: Tüm şema etiketleri, lejant, başlık, parça isimleri öğrencinin
DİLİNDE yazılır. Sistem dili Türkçe ise Türkçe; İngilizce ise İngilizce.
Kesinlikle karışık dil kullanma (örn. "Nucleus / Çekirdek" YOK, sadece
hangi dilse o).

ŞEMA PROTOKOLÜ (KENDİ ÇİZ — dış bağımlılık YOK):
Eskiden Wikipedia'dan görsel çekiliyordu; çoğunlukla yüklenmiyordu.
ARTIK görselleri SEN kendin Unicode/ASCII sanatıyla çiziyorsun.
UI bu blokları monospace çerçeveli kart olarak render edecek.

Format (BLOK ETIKETI — başlangıç ve bitiş zorunlu):
   [ŞEMA: <Konu Adı>]
   <ÇİZİM>
   ─────────
   <LEJANT / AÇIKLAMA SATIRLARI>
   [/ŞEMA]

Kurallar:
• Çizim satırları MONOSPACE çıkacağı için Unicode kutu karakterleri,
  oklar ve semboller serbestçe kullanılır:
    Kutu/çerçeve : ┌ ─ ┐ │ └ ┘ ╔ ═ ╗ ║ ╚ ╝ ╭ ╮ ╰ ╯
    Oklar         : → ← ↑ ↓ ↔ ↕ ⟶ ⟵ ⇒ ⇐
    Geometri      : ○ ● ◯ ◉ ◇ ◆ □ ■ △ ▲ ▽ ▼ ⬡ ⬢
    Bilim         : ⊕ ⊖ ⊗ ⊘ ∇ ∆ ∑ ∫ √ ∞ ° ± ·
    Bağlantı      : ━ ┃ ╋ ╂ ┳ ┻ ┣ ┫
• Çizim satırları SOLDAN HİZALI başlar; ortalamak için boşlukla
  doldurursun. Aralıklı kalmasın — kompakt çiz.
• Her şemanın altında, "─" çizgisinden sonra LEJANT satırları:
   ⊕ = Çekirdek (proton + nötron)
   ● = Elektron (kabuk üzerinde)
   ↑ = Pozitif yön
  Numaralı parçalar varsa "1: …, 2: …" gibi listele.
• Şemanın YÜKSEKLİĞİ 4-10 satır, GENİŞLİĞİ 30-50 karakter aralığında
  olsun — telefon ekranına sığsın. Çok büyük olanları parçalara böl.

YERLEŞİM:
Şema bloğu, ilgili kavramın ANLATILDIĞI metin bloğunun HEMEN ALTINA
yerleştirilir. Asla başlığın hemen altına toplu liste olarak yazma.

DERS BAZLI ŞEMA POLİTİKASI (konu görsel-zorunlu mu?):
• Biyoloji / Anatomi / Tıp → 2-4 ŞEMA serbest (hücre, organ, sistem,
  döngü). Karşılaştırma için TABLO da ekle. Görsel öğrenmenin omurgası.
• Kimya → 1-3 ŞEMA (atom modelleri ZORUNLU; molekül yapısı, periyodik
  kesit). Reaksiyon listesi/özellik karşılaştırma TABLO.
• Fizik → 1-3 ŞEMA (dalga şekli, devre, optik ışık yolu, vektör, kuvvet
  diyagramı). Formül listesi TABLO.
• Coğrafya → 2-4 ŞEMA (yer şekli kesiti, levha, atmosfer, iklim haritası).
  Veri karşılaştırması TABLO.
• Tarih → 1-2 ŞEMA (savaş haritası, sınır değişimi, antlaşma kesiti).
  Kronoloji ve neden-sonuç TABLO.
• Edebiyat → 1-2 ŞEMA (eserin ASCII kapak çizimi, dönem-akım ağacı,
  karakter ilişki şeması). Akım-temsilci-eser TABLO.
• Felsefe / Sosyal → 0-1 ŞEMA (etki şeması zorunlu ise).
• Matematik → 1-2 ŞEMA (geometri, fonksiyon grafiği, kesir pastası,
  küme şeması). Formül TABLO.
• Türkçe → 0-1 ŞEMA (metin yapısı akış oku zorunlu ise).
• Yabancı dil → 0 ŞEMA; kural-örnek-istisna TABLO.

⚠️ İLKOKUL (1-4) ve ORTAOKUL (5-8) MÜFREDATI İSE:
Bu yaş gruplarında HER kavram için görsel kritik. Yukarıdaki üst sınırları
%50 ARTIR (örn. Fizik 1-3 → 2-5; Türkçe 0-1 → 1-2). Çocuk metni okurken
zihninde RESMI oluşturamazsa öğrenemez. Görsel ZORUNLU.

ÖRNEK 1 — Bohr atom modeli (basit/kompakt):
[ŞEMA: Bohr Atom Modeli]
        ●  ●
      ●  ⊕  ●          K kabuğu (2e⁻)
        ●  ●
      ● ● ● ● ●          L kabuğu (8e⁻)
─────────────
⊕ = Çekirdek (proton + nötron)
● = Elektron
[/ŞEMA]

ÖRNEK 2 — Hayvan hücresi (numaralı parça):
[ŞEMA: Hayvan Hücresi]
   ╭───────────────────────╮
   │  ⑤  ╭───────╮         │
   │    │   ①   │  ②      │
   │    ╰───────╯    ⑥    │
   │  ③            ④       │
   ╰───────────────────────╯
─────────────
① = Çekirdek         ② = Mitokondri
③ = Golgi aygıtı     ④ = Ribozom
⑤ = Hücre zarı       ⑥ = Endoplazmik retikulum
[/ŞEMA]

ÖRNEK 3 — Sebep-sonuç akış (tarih/sosyal):
[ŞEMA: Tanzimat Süreci]
Mali Buhran (1838)
       │
       ▼
Avrupa Baskısı  ─→  Gülhane Hattı (1839)
                          │
                          ▼
                  Kanun Önünde Eşitlik
─────────────
→ : Tetikleyen ilişki
▼ : Doğrudan sonuç
[/ŞEMA]

ÖRNEK 4 — Devre şeması (fizik):
[ŞEMA: Basit Elektrik Devresi]
    ┌───── R ─────┐
    │             │
    ┴ V           ⊗ L (lamba)
    │             │
    └─────────────┘
─────────────
V = Pil (gerilim kaynağı)   R = Direnç
⊗ = Lamba (yük)             ┴ = Topraklama / negatif uç
[/ŞEMA]

NOT: Eski formattaki [Görsel Betimlemesi: ...] etiketini ARTIK kullanma.
Sadece yukarıdaki [ŞEMA: ...] ... [/ŞEMA] bloğunu kullan.

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
$pedagogyBlock
GÖREVİN: Konuyu standart bir DERSHANE KİTABINDAKİ gibi işle. Önce kısa
tanım, ardından konuyu mantıksal ana başlıklara böl ve her ana başlığın
altında alt başlıkları/maddeleri ver — tıpkı bir ders kitabının
"konu işlenişi" sayfası gibi. Hedef: "Nihai Özet" kalitesi.

⚠️ ÇIKTI ZORUNLU OLARAK ŞU BÖLÜMLERİ İÇERİR (sırayla):
   1) 📖 Tanım
   2) ANA BAŞLIKLAR (▸ 1. 📍 Başlık Adı formatında, doğrudan, "Konu
      İşlenişi" wrapper başlığı YOK) — ana başlıklar + alt maddeler
   3) ${isNumeric ? '📐 Formül Galerisi + 🧪 Uygulama Örneği' : isVerbal ? '(Ana başlıklar içine yedirilen detaylı sebep-sonuç akışı yeterli)' : '📐 Formül / Akış (varsa)'}
   4) ⭐ Aklında Kalsın (3-6 kritik madde — konunun çekirdeği)
   5) 🎯 Kendini Sına (aktif hatırlama — kapsamlıda 3-5 soru+cevap; kısada 1-2)
HERHANGİ BİR BÖLÜM EKSİK OLURSA cevap GEÇERSİZDİR.
NOT: "⭐ Aklında Kalsın" ve "🎯 Kendini Sına" başlıklarını AYNEN bu işaretle
yaz — UI bunları özel renkli kart olarak gösterir.

KRİTİK — "📚 Konu İşlenişi" WRAPPER BAŞLIĞI ARTIK YOK:
Tanım'dan sonra DOĞRUDAN ilk ana başlık (▸ 1. {emoji} Başlık Adı) ile
başla. "📚 Konu İşlenişi", "📚 Konu Anlatımı", "📚 Topic Processing"
gibi wrapper başlıkları KESİNLİKLE YAZMA — sadece ana başlıklar olsun.
UI tarafı bu wrapper'ı zaten gizliyor; yazarsan boşa harcanmış olur.

İlk satır "📖 Tanım" başlığı olmalıdır; öncesinde HİÇBİR selamlama
("Harika!", "Tabii ki", "Hemen başlayalım", "Bu konuyu inceleyelim") YOK.
Tanım satırından sonra DOĞRUDAN ilk ana başlık (▸ 1. {emoji} ...) gelir,
ardından diğer ana başlıklar — TÜM bölümler tamamlanana dek bitirme.

ÖZEL ÇERÇEVE YOK — "⚠️ KRİTİK UYARI / 🔬 QuAlsar Notu" diye AYRI bir bölüm
açma. Tuzak/istisna/uzman içgörüsü gerekiyorsa ana başlık içinde
"💡 Önemli Bilgi: ..." satırı olarak inline yedir (UI bunu kutuda gösterir).

YAPI (aşağıdaki başlıkları BİREBİR kullan — sırayla):

📖 Tanım
[TEK kısa cümle. Süsleme YOK, dolambaç YOK.]

[ANA BAŞLIKLAR — wrapper başlığı YAZMA, doğrudan ▸ 1. ile başla]
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
• Ana başlıklar (▸ N. {emoji}...) için ana başlık → alt madde hiyerarşisi
  ZORUNLU. "📚 Konu İşlenişi" wrapper başlığı YAZMA (UI gizliyor).
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
• $exam mantığına uygun, ders kitabı işlenişine sadık. (Çıktı dili: yukarıdaki [ÇIKTI DİLİ] kuralına UY.)
• YouTube/Web/kaynak önerisi EKLEME. [VIDEO:] ve [WEB:] yok.
${isNumeric ? '• Her sayısal tanımda sembol + BİRİM birlikte verilsin (boyut analizi).' : ''}
${isVerbal ? '• Tarihte yıl, edebiyatta yazar/eser/dönem, felsefede filozof/akım adı eksiksiz.' : ''}

═══════════════════════════════════════════════════════
[YAYIN ÖNCESİ SON KONTROL — YAZDIKTAN SONRA, GÖNDERMEDEN ÖNCE UYGULA]
Çıktıyı bitirdikten sonra aşağıdaki 8 maddeyi ZİHNİNDE tek tek işaretle;
EKSİK çıkan maddeyi düzeltmeden cevabı sonlandırma:
1. GÖRSEL: Konu görsel-zorunlu sınıfta mı (hücre/anatomi/atom/dalga/devre/
   optik/harita/geometri/kesir veya ilkokul-ortaokul)? → Ders bazlı minimum
   [ŞEMA] sayısına ulaşıldı mı? Şemalar ilgili paragrafın ALTINDA mı?
2. FORMÜL: Her formülün altında "Burada:" sembol+birim listesi var mı?
   Sayısal konuda en az 1 "🧪 Uygulama Örneği" çözüldü mü?
3. TABLO: Karşılaştırma/sınıflandırma/kronoloji içeren her bilgi bloğu
   tabloya döküldü mü?
4. KAPSAM: Ders kitabında bu ünitede işlenen alt başlıklardan atlanan
   var mı? Varsa ekle.
5. YANILGI: En az 1 yaygın kavram yanılgısı/tuzak düzeltildi mi
   (🔴 başlık veya 💡 satır)?
6. YAPI: 📖 Tanım → ▸ ana başlıklar → ⭐ Özet — 5 Bilgi → 📝 Pekiştirme
   Soruları sırası tam mı? Selamlama/kapanış paragrafı sızmadı mı?
7. DİL: Tüm metin, tablo hücreleri ve şema lejantları TEK dilde mi?
   Dolar işareti (\$), çıplak "#", tek yıldız italik kalmadı mı?
8. DOĞRULUK: Verdiğin her sayı/tarih/formül ders kitabı değerleriyle
   uyumlu mu? Şüpheli olanı sil veya genelle.
Bu listeyi çıktıya YAZMA — sadece uygula.
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
            onAddTopic: (topic, {length}) =>
                _generateForExistingSubject(s, topic, forcedLength: length),
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
      // Subject detay sayfasından dönüldüğünde home aggregate'leri yenile —
      // kullanıcı orada özet açtıysa "Devam Et" + due strip + stats güncellensin.
      unawaited(_loadHomeAggregates());
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
              // Arama ikonu — kütüphane büyüdükçe ders/konu hızlı bulmak için.
              Padding(
                padding: const EdgeInsets.only(
                    top: 8, bottom: 8, left: 0, right: 4),
                child: GestureDetector(
                  onTap: _toggleSearchBar,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _showSearch
                          ? AppPalette.textPrimary(context)
                              .withValues(alpha: 0.08)
                          : Colors.transparent,
                      border: Border.all(
                        color: AppPalette.textPrimary(context)
                            .withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _showSearch
                          ? Icons.close_rounded
                          : Icons.search_rounded,
                      size: 17,
                      color: AppPalette.textPrimary(context),
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
                // Arama çubuğu — aktifse query'ye göre tüm panelleri yutar.
                if (_showSearch) _buildSearchBar(),
                if (_showSearch && _searchQuery.trim().isNotEmpty) ...[
                  _buildSearchResults(),
                ] else ...[
                  // Üst paneller: Bugün Tekrar Et
                  _buildDueTodayStrip(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _buildInlineAddPanel(),
                  ),
                  if (_subjects.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildCardsRow(),
                    ),
                ],
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

  // ─── Arama çubuğu — AppBar'daki ikon ile toggle'lanır ─────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search_rounded,
                size: 18, color: AppPalette.textSecondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary(context),
                ),
                decoration: InputDecoration(
                  hintText: 'Ders veya konu ara…'.tr(),
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppPalette.textSecondary(context),
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: AppPalette.textSecondary(context),
              onPressed: _toggleSearchBar,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final hits = _runSearch(_searchQuery);
    if (_searchQuery.trim().isEmpty) return const SizedBox.shrink();
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Row(
            children: [
              Icon(Icons.search_off_rounded,
                  color: AppPalette.textSecondary(context), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Eşleşen ders veya konu yok'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Column(
          children: [
            for (int i = 0; i < hits.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    color: AppPalette.border(context).withValues(alpha: 0.5)),
              _searchHitRow(hits[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchHitRow(_SearchHit h) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        // Aramayı kapat → kullanıcı listeye geri dönerse temiz.
        FocusScope.of(context).unfocus();
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _SummaryDetailPage(
            summary: h.summary,
            subjectName: h.subjectName,
          ),
        ));
        if (mounted) _loadHomeAggregates();
      },
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                h.topicMatch
                    ? Icons.menu_book_rounded
                    : Icons.school_rounded,
                size: 15,
                color: const Color(0xFF7C3AED),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    h.summary.topic,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                  Text(
                    h.subjectName,
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
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppPalette.textSecondary(context)),
          ],
        ),
      ),
    );
  }

  // ─── Mini istatistik bandı (3-chip yatay) ─────────────────────────────
  Widget _buildStatsBand() {
    if (_statsTotalSummaries == 0 && _statsWeeklyMinutes == 0) {
      return const SizedBox.shrink();
    }
    Widget chip(IconData icon, String value, String label, Color tint) {
      return Expanded(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tint.withValues(alpha: 0.35), width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: tint,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textSecondary(context),
                        letterSpacing: 0.2,
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

    final hours = (_statsWeeklyMinutes / 60).floor();
    final mins = _statsWeeklyMinutes % 60;
    final timeStr = hours > 0
        ? (mins > 0 ? '${hours}sa ${mins}dk' : '${hours}sa')
        : '${_statsWeeklyMinutes}dk';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          chip(Icons.timer_rounded, timeStr, 'BU HAFTA'.tr(),
              const Color(0xFF2563EB)),
          const SizedBox(width: 8),
          chip(Icons.menu_book_rounded, '$_statsTotalSummaries',
              'TOPLAM ÖZET'.tr(), const Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          chip(Icons.task_alt_rounded, '$_statsCompletedTopics',
              'TAMAMLANAN'.tr(), const Color(0xFF10B981)),
        ],
      ),
    );
  }

  // ─── "Devam Et" kartı — en son açılan özet ─────────────────────────────
  // İnce profil: yatay padding 10/8, dikey 6 — kart yüksekliği ~46px.
  Widget _buildContinueCard() {
    final r = _continueItem;
    if (r == null) return const SizedBox.shrink();
    final ago = _humanAgo(DateTime.now().difference(r.openedAt));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _SummaryDetailPage(
              summary: r.summary,
              subjectName: r.subjectName,
            ),
          ));
          if (mounted) _loadHomeAggregates();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      r.summary.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      '${r.subjectName}  ·  $ago',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.80),
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  String _humanAgo(Duration d) {
    if (d.inMinutes < 1) return 'az önce';
    if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
    if (d.inHours < 24) return '${d.inHours} sa önce';
    if (d.inDays < 7) return '${d.inDays} gün önce';
    return '${(d.inDays / 7).floor()} hafta önce';
  }

  // ─── "Bugün Tekrar Et" yatay kuşağı ──────────────────────────────────
  Widget _buildDueTodayStrip() {
    if (_dueToday.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.event_repeat_rounded,
                    size: 16, color: Color(0xFFFF6A00)),
                const SizedBox(width: 6),
                Text(
                  'BUGÜN TEKRAR ET'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFFF6A00),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFFFF6A00).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_dueToday.length} ${'konu'.tr()}',
                    style: GoogleFonts.poppins(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFFF6A00),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _dueToday.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _dueCard(_dueToday[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dueCard(_DueItem d) {
    final days = d.daysSince;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _SummaryDetailPage(
            summary: d.summary,
            subjectName: d.subjectName,
          ),
        ));
        if (mounted) _loadHomeAggregates();
      },
      child: Container(
        width: 200,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFBBF24), Color(0xFFFF6A00)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6A00).withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    days <= 0
                        ? 'bugün'.tr()
                        : '$days ${'gün'.tr()}',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.refresh_rounded,
                    size: 14, color: Colors.white),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  d.summary.topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  d.subjectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
        // Tek konu satırına bas → DOĞRUDAN o özeti açma; önce dersin TÜM
        // konuları listesini aç. Kullanıcı oradan hangisini istiyorsa seçer
        // (kısa/kapsamlı slot ile birlikte). Karta neresine basılırsa basılsın
        // davranış aynı: konu seçim sayfası gelir.
        onTap: () => _openSubject(s),
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
        ? 'Her konu için en fazla 6 test üretebilirsin; 6. testten sonra o konudan yeni test üretilemez. 7 günlük ücretsiz deneme bittikten sonra bir konudan yalnızca 1 test ücretsizdir, fazlası Premium gerektirir. "Yanlışlardan Tekrar" her zaman ücretsizdir. Farklı ders/konu sayısı sınırsız.'
        : 'Her konu için 1 kısa + 1 kapsamlı özet üretebilirsin. 7 günlük ücretsiz deneme bittikten sonra yeni özet oluşturmak Premium gerektirir; deneme süresince ürettiğin özetler her zaman açık kalmaya devam eder. Farklı ders ve konu sayısı sınırsız.';
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

  // Sınav Modu → seçilen (sınav × ders × konu, kaydedilmiş sınav kısayolu
  // dahil) ile bu ekranın KENDİ test üretim akışını (_runGenerateWithSetup:
  // zorluk seçimi + kota + AI üretimi) tetikler — Bilgi Ligi/Arena'dan farklı
  // olarak burada üretilen test bu ekranda kalır (yeni sayfaya gitmez).
  Future<void> _startExamModeQuiz(ExamModeSelection picked) async {
    final synthetic = examSyntheticSubject(picked.exam, picked.subject);
    await _runGenerateWithSetup(
      subjectName: synthetic.displayName,
      topic: picked.topic ?? 'Genel Tekrar'.tr(),
    );
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
        // "Sınav modu açmak ister misin?" — Bilgi Ligi/Bilgi Yarışı'ndaki
        // AYNI bölüm (lib/widgets/exam_mode_widgets.dart, kaydedilmiş sınav
        // kısayolu dahil). Sadece "Sınav Soruları Oluştur" (questions)
        // modunda; özet modunda gösterilmez.
        if (widget.mode == LibraryMode.questions) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ExamModeSection(
              countryCode: EduProfile.current?.country,
              onSelected: _startExamModeQuiz,
            ),
          ),
        ],
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
  /// Sağında kalan hak rozeti (n/4). Dolu olduğunda görünüm "kilitli"
  /// olarak gri tonlarına döner; tıklayınca sınır uyarısı snackbar.
  Widget _wideAddSubjectButton() {
    final used = _customSubjects.length;
    final remaining = _customSubjectMaxCount - used;
    final full = remaining <= 0;
    final Color tint = full ? Colors.grey : _orange;
    return GestureDetector(
      onTap: _openAddCustomSubjectDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint.withValues(alpha: 0.55), width: 1.4),
        ),
        child: Row(
          children: [
            // Spacer için sol tarafa boş alan: rozet sağdayken metin ortalı görünsün.
            // Estetik için sağdaki rozetle simetrik 56px sol boşluk.
            const SizedBox(width: 56),
            // Sol+orta: ikon + metin (ortalı)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    full ? Icons.lock_rounded : Icons.add_rounded,
                    size: 16,
                    color: tint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Yeni Ders Ekle'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: tint,
                    ),
                  ),
                ],
              ),
            ),
            // Sağ: kalan hak rozeti. "n/4" formatı, içerik renkli kapsül.
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: tint.withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: Text(
                '$used/$_customSubjectMaxCount',
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: tint,
                  letterSpacing: 0.2,
                ),
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

  // En fazla bu kadar özel ders eklenebilir. Kullanıcı kütüphanesinin
  // dağılmasını önlemek için sınırlı tutuldu.
  static const int _customSubjectMaxCount = 4;

  Future<void> _openAddCustomSubjectDialog() async {
    // Limit ön-kontrol: dialog'u açmadan önce bilgilendir.
    if (_customSubjects.length >= _customSubjectMaxCount) {
      _showSnack(
          'En fazla $_customSubjectMaxCount yeni ders ekleyebilirsin. '
                  'Daha fazla eklemek için mevcut bir dersi sil.'
              .tr());
      return;
    }
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
    // Yarışma koşulu: dialog açıkken başka yerden eklenebilir. Tekrar kontrol.
    if (_customSubjects.length >= _customSubjectMaxCount) {
      _showSnack(
          'En fazla $_customSubjectMaxCount yeni ders eklenebilir.'.tr());
      return;
    }
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
                      // Sağ üstte vurgulu ipucu — gradient zemin + ikon,
                      // basılı tut + sürükle akışını net anlatır.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 160),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFF6A3C),
                                Color(0xFFFF8A5C),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF6A3C)
                                    .withValues(alpha: 0.30),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.swap_horiz_rounded,
                                  size: 14, color: Colors.white),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Bir derse basılı tut, sürükle —\nana derslerle yer değiştir'
                                      .tr(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                            ],
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
  /// Summary modunda [length] verildiyse o uzunlukla üretir (slot tap'i).
  /// Verilmediyse parent kendi rutin akışı: mevcut özetlere göre otomatik
  /// veya kullanıcıya sorarak.
  final Future<bool> Function(String topic, {_SummaryLength? length}) onAddTopic;
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
      final regenLength = sum.length;
      // Önce mevcut özeti sil, sonra aynı konu+uzunlukta yeniden oluştur
      await widget.onDelete(sum);
      if (!mounted) return;
      setState(() {
        _generating = true;
        _generatingTopic = topic;
      });
      await widget.onAddTopic(topic, length: regenLength);
      if (!mounted) return;
      setState(() => _generating = false);
    }
  }

  // Summary mode — konu + sağda 2 slot (Kısa / Kapsamlı).
  // Dolu slot → o özeti aç. Boş slot → onAddTopic(topic, length:…)
  // ile ilgili türde özet üret. İki slot da dolduktan sonra ekstra üretim
  // _generateForExistingSubject içinde engellenir.
  Widget _summarySlotsRow(
      _Subject s, String topic, _Summary? shortSum, _Summary? compSum) {
    final (icon, iconColor) = _topicIcon(topic);
    return Material(
      color: AppPalette.card(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: () {
          // Uzun bas: hangi özet varsa onun action menüsü açılır.
          // İki varsa kullanıcıya kısa olanı göster (daha yaygın seçim).
          final target = shortSum ?? compSum;
          if (target != null) _showTopicActions(target);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppPalette.textPrimary(context), width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Sol: konuya özel ikon (üstte, ortalı) + konu adı (altta).
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: iconColor, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      topic,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Sağ: 2 slot — Kısa / Kapsamlı (mevcut düzen aynı kalıyor).
              Expanded(
                flex: 5,
                child: Row(children: [
                  Expanded(
                    child: _summarySlot(
                      s,
                      topic,
                      _SummaryLength.short,
                      shortSum,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _summarySlot(
                      s,
                      topic,
                      _SummaryLength.comprehensive,
                      compSum,
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Konu adına göre uygun ikon + renk döndürür. Anahtar kelime tabanlı
  // hızlı eşleştirme: fotosentez → yaprak, atom → atom, türev → fonksiyon vb.
  // Eşleşme yoksa varsayılan kitap ikonu.
  (IconData, Color) _topicIcon(String topic) {
    final t = topic.toLowerCase();
    // — Biyoloji / Botanik —
    if (t.contains('fotosentez') ||
        t.contains('bitki') ||
        t.contains('yaprak') ||
        t.contains('çiçek') ||
        t.contains('orman') ||
        t.contains('ekosistem')) {
      return (Icons.eco_rounded, const Color(0xFF22C55E));
    }
    if (t.contains('hücre') ||
        t.contains('mikrobiy') ||
        t.contains('bakteri') ||
        t.contains('virüs') ||
        t.contains('dna') ||
        t.contains('rna') ||
        t.contains('gen')) {
      return (Icons.biotech_rounded, const Color(0xFF14B8A6));
    }
    if (t.contains('insan') ||
        t.contains('anatomi') ||
        t.contains('iskelet') ||
        t.contains('kas') ||
        t.contains('sindirim') ||
        t.contains('dolaşım') ||
        t.contains('sinir')) {
      return (Icons.accessibility_new_rounded, const Color(0xFFEF4444));
    }
    if (t.contains('kalp') || t.contains('damar') || t.contains('kan')) {
      return (Icons.favorite_rounded, const Color(0xFFEF4444));
    }
    // — Kimya —
    if (t.contains('atom') ||
        t.contains('molekül') ||
        t.contains('element') ||
        t.contains('periyodik') ||
        t.contains('izotop')) {
      return (Icons.bubble_chart_rounded, const Color(0xFF8B5CF6));
    }
    if (t.contains('asit') ||
        t.contains('baz') ||
        t.contains('ph') ||
        t.contains('tepkime') ||
        t.contains('reaksiyon') ||
        t.contains('kimya')) {
      return (Icons.science_rounded, const Color(0xFF06B6D4));
    }
    // — Fizik —
    if (t.contains('elektrik') ||
        t.contains('akım') ||
        t.contains('voltaj') ||
        t.contains('manyet')) {
      return (Icons.bolt_rounded, const Color(0xFFFBBF24));
    }
    if (t.contains('ışık') ||
        t.contains('optik') ||
        t.contains('mercek') ||
        t.contains('renk') ||
        t.contains('dalga')) {
      return (Icons.wb_sunny_rounded, const Color(0xFFF59E0B));
    }
    if (t.contains('kuvvet') ||
        t.contains('hareket') ||
        t.contains('hız') ||
        t.contains('ivme') ||
        t.contains('newton') ||
        t.contains('momentum')) {
      return (Icons.speed_rounded, const Color(0xFFEF4444));
    }
    if (t.contains('uzay') ||
        t.contains('gezegen') ||
        t.contains('güneş sistem') ||
        t.contains('yıldız') ||
        t.contains('evren') ||
        t.contains('astronomi')) {
      return (Icons.rocket_launch_rounded, const Color(0xFF6366F1));
    }
    if (t.contains('enerji') || t.contains('iş güç') || t.contains('termodin')) {
      return (Icons.flash_on_rounded, const Color(0xFFFBBF24));
    }
    // — Matematik —
    if (t.contains('türev') ||
        t.contains('integral') ||
        t.contains('limit') ||
        t.contains('fonksiyon')) {
      return (Icons.functions_rounded, const Color(0xFF2563EB));
    }
    if (t.contains('geometri') ||
        t.contains('üçgen') ||
        t.contains('daire') ||
        t.contains('çember') ||
        t.contains('kare') ||
        t.contains('dikdörtgen') ||
        t.contains('polig')) {
      return (Icons.category_rounded, const Color(0xFF2563EB));
    }
    if (t.contains('denklem') ||
        t.contains('eşitsizlik') ||
        t.contains('cebir') ||
        t.contains('polinom')) {
      return (Icons.calculate_rounded, const Color(0xFF2563EB));
    }
    if (t.contains('olasılık') ||
        t.contains('istatistik') ||
        t.contains('permüt') ||
        t.contains('kombin')) {
      return (Icons.casino_rounded, const Color(0xFF2563EB));
    }
    if (t.contains('mantık') || t.contains('küme')) {
      return (Icons.account_tree_rounded, const Color(0xFF2563EB));
    }
    // — Tarih / Sosyal —
    if (t.contains('tarih') ||
        t.contains('osman') ||
        t.contains('selçuk') ||
        t.contains('cumhuriyet') ||
        t.contains('savaş') ||
        t.contains('antlaş') ||
        t.contains('inkılap') ||
        t.contains('atatürk')) {
      return (Icons.history_edu_rounded, const Color(0xFF92400E));
    }
    if (t.contains('coğraf') ||
        t.contains('iklim') ||
        t.contains('harita') ||
        t.contains('kıta') ||
        t.contains('nehir') ||
        t.contains('dağ')) {
      return (Icons.public_rounded, const Color(0xFF0EA5E9));
    }
    // — Edebiyat / Dil —
    if (t.contains('şiir') ||
        t.contains('roman') ||
        t.contains('öykü') ||
        t.contains('edebiyat') ||
        t.contains('destan')) {
      return (Icons.menu_book_rounded, const Color(0xFFA855F7));
    }
    if (t.contains('dilbilgisi') ||
        t.contains('gramer') ||
        t.contains('sözcük') ||
        t.contains('yazım') ||
        t.contains('noktal') ||
        t.contains('cümle')) {
      return (Icons.abc_rounded, const Color(0xFFA855F7));
    }
    if (t.contains('ingilizce') ||
        t.contains('almanca') ||
        t.contains('fransızca') ||
        t.contains('yabancı dil')) {
      return (Icons.translate_rounded, const Color(0xFF7C3AED));
    }
    // — Felsefe / Din —
    if (t.contains('felsefe') ||
        t.contains('mantık') ||
        t.contains('etik') ||
        t.contains('ahlak')) {
      return (Icons.psychology_rounded, const Color(0xFF6366F1));
    }
    if (t.contains('din') ||
        t.contains('kuran') ||
        t.contains('peygamb') ||
        t.contains('ibadet')) {
      return (Icons.mosque_rounded, const Color(0xFF059669));
    }
    // — Ekonomi / Sosyal —
    if (t.contains('ekonomi') ||
        t.contains('para') ||
        t.contains('enflasyon') ||
        t.contains('ticaret')) {
      return (Icons.attach_money_rounded, const Color(0xFF10B981));
    }
    // — Bilişim —
    if (t.contains('kod') ||
        t.contains('programlama') ||
        t.contains('algoritma') ||
        t.contains('yazılım')) {
      return (Icons.code_rounded, const Color(0xFF2563EB));
    }
    // — Su / Çevre —
    if (t.contains('su') || t.contains('okyanus') || t.contains('deniz')) {
      return (Icons.water_drop_rounded, const Color(0xFF0EA5E9));
    }
    // Varsayılan
    return (Icons.menu_book_rounded, AppPalette.textSecondary(context));
  }

  Widget _summarySlot(_Subject subject, String topic, _SummaryLength length,
      _Summary? existing) {
    final filled = existing != null;
    // Renkler: kısa=yeşil tonu, kapsamlı=mor tonu; boş=soluk gri.
    final Color accent = length == _SummaryLength.short
        ? const Color(0xFF10B981)
        : const Color(0xFF7C3AED);
    final bg = filled ? accent : const Color(0xFFEFF1F6);
    final fg = filled ? Colors.white : Colors.black38;
    final borderColor =
        filled ? accent : Colors.black.withValues(alpha: 0.18);
    final label = length == _SummaryLength.short
        ? 'Kısa Özet'.tr()
        : 'Kapsamlı Özet'.tr();
    return AspectRatio(
      aspectRatio: 1.0,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            if (filled) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _SummaryDetailPage(
                  summary: existing,
                  subjectName: subject.name,
                ),
              ));
              return;
            }
            // Boş slot — bu uzunlukta üret.
            setState(() {
              _generating = true;
              _generatingTopic = topic;
            });
            await widget.onAddTopic(topic, length: length);
            if (!mounted) return;
            setState(() => _generating = false);
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
                      ? Icons.check_circle_rounded
                      : Icons.add_rounded,
                  size: 14,
                  color: fg,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Questions mode — konu + sağda 3 küçük test slot'u.
  // Dolu slot turuncu (tamamlanmışsa ✓ ikonlu), boş slot soluk.
  // Dolu slot → sonuç / devam. Boş slot → yeni test üret. 3 bitince kapalı.
  // Konu kartı — üstte konu adı + ikon, altında yatay 6 test slotu.
  // Eski "yan yana 3 slot" düzeni 6 slota geçince yatayda sığmadığı için
  // altta tek satıra alındı.
  Widget _questionsRow(_Subject s, _Summary sum) {
    final slots = <Widget>[];
    for (int i = 0; i < 6; i++) {
      final attempt = i < sum.tests.length ? sum.tests[i] : null;
      slots.add(Expanded(child: _testSlot(s, sum, i, attempt)));
      if (i < 5) slots.add(const SizedBox(width: 5));
    }
    return Material(
      color: AppPalette.card(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: () => _showTopicActions(sum),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppPalette.textPrimary(context), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Üst satır: ikon + konu adı + hak rozeti ─────────────
              Row(
                children: [
                  const Text('📖', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
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
                  ),
                  const SizedBox(width: 8),
                  _testQuotaBadge(sum.tests.length),
                ],
              ),
              const SizedBox(height: 10),
              // ── Alt satır: 6 test slotu yatayda eşit dağılmış ──────
              Row(children: slots),
            ],
          ),
        ),
      ),
    );
  }

  // Kaç test hakkı kaldığını renkli rozetle göster — toplam 6 hak.
  Widget _testQuotaBadge(int used) {
    const total = 6;
    final remaining = total - used;
    final Color bg;
    final Color fg;
    final String label;
    if (remaining == total) {
      bg = const Color(0x1410B981);
      fg = const Color(0xFF059669);
      label = '$total ${'hak'.tr()}';
    } else if (remaining >= 3) {
      bg = const Color(0x142563EB);
      fg = const Color(0xFF2563EB);
      label = '$remaining ${'hak kaldı'.tr()}';
    } else if (remaining >= 2) {
      bg = const Color(0x14D97706);
      fg = const Color(0xFFD97706);
      label = '$remaining ${'hak kaldı'.tr()}';
    } else if (remaining == 1) {
      bg = const Color(0x14FF6A00);
      fg = const Color(0xFFFF6A00);
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
    // Renkler: tamamlandı → yeşil, başladı (yarım) → turuncu, boş → soluk.
    const green = Color(0xFF10B981);
    final bg = filled
        ? (completed ? green : _orange.withValues(alpha: 0.75))
        : const Color(0xFFEFF1F6);
    final fg = filled ? Colors.white : Colors.black38;
    final borderColor = filled
        ? (completed ? green : _orange)
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
              // Önce kullanıcıya son ayarlar sayfası. Konu özetini ve
              // önceki denemeleri ile birlikte aynı dersin diğer konularını
              // setup'a iletiyoruz — özeti hatırlat / yanlışlardan tekrar /
              // karışık konular özellikleri için.
              _Summary? thisSummary;
              try {
                thisSummary = subject.summaries.firstWhere(
                    (s) => s.id == summary.id);
              } catch (_) {
                thisSummary = null;
              }
              final summaryContent = thisSummary?.content ?? '';
              final prevAttempts = thisSummary?.tests ?? const <_TestAttempt>[];
              // showGeneralDialog → arka plan buğulu (BackdropFilter), kart
              // ortada animasyonla açılır. MaterialPageRoute tam ekran
              // açıyordu; "ilk test oluştur" akışındaki narin görünüm.
              final cfg = await showGeneralDialog<_TestConfig>(
                context: context,
                barrierDismissible: true,
                barrierLabel: 'TestSetup',
                barrierColor: Colors.black.withValues(alpha: 0.35),
                transitionDuration: const Duration(milliseconds: 240),
                pageBuilder: (_, __, ___) => _TestSetupPage(
                  subjectName: subject.name,
                  topic: summary.topic,
                  attemptIndex: summary.tests.length,
                  summaryContent: summaryContent,
                  previousAttempts: prevAttempts,
                  sameSubjectSummaries: subject.summaries,
                ),
                transitionBuilder: (ctx, anim, _, child) {
                  final t = Curves.easeOutCubic.transform(anim.value);
                  return BackdropFilter(
                    filter: ui.ImageFilter.blur(
                        sigmaX: 6 * t, sigmaY: 6 * t),
                    child: Opacity(
                      opacity: anim.value,
                      child: Transform.scale(
                        scale: 0.96 + 0.04 * t,
                        child: child,
                      ),
                    ),
                  );
                },
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
        ? 'Yeni Test Oluştur'.tr()
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
      // Questions mode → yeşil (Test Oluştur), Summary mode → siyah (orijinal).
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor:
            isQuestions ? const Color(0xFF10B981) : Colors.black,
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
              : Builder(
                  builder: (_) {
                    // Summary modunda aynı konuya ait kısa + kapsamlı özetleri
                    // tek bir satırda 2 slot olarak göster. Questions modu eski
                    // 1-satır-1-test akışını korur.
                    if (widget.mode == LibraryMode.questions) {
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: s.summaries.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _questionsRow(s, s.summaries[i]),
                      );
                    }
                    // Konuya göre grupla (case-insensitive). LinkedHashMap
                    // ekleme sırasını korur → en son eklenen konu üstte
                    // (s.summaries zaten insert(0, …) ile en güncel başta).
                    final groups = <String, List<_Summary>>{};
                    for (final sum in s.summaries) {
                      final key = sum.topic.toLowerCase();
                      groups.putIfAbsent(key, () => []).add(sum);
                    }
                    final entries = groups.entries.toList();
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final group = entries[i].value;
                        _Summary? shortSum;
                        _Summary? compSum;
                        for (final sum in group) {
                          if (sum.length == _SummaryLength.short) {
                            shortSum ??= sum;
                          } else {
                            compSum ??= sum;
                          }
                        }
                        // Konu adı için ilk öğeden al (orijinal harf düzeni).
                        return _summarySlotsRow(
                            s, group.first.topic, shortSum, compSum);
                      },
                    );
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

  // ── Formül paneli state'i (sadece sayısal dersler için) ────────────────
  bool _showFormulasPanel = false;
  String? _formulasContent;
  bool _loadingFormulas = false;
  String? _formulasError;

  /// EduProfile level/grade kodlarını Türkçe okunabilir etikete çevirir.
  /// Formül üreteci ve AI Koç bu etiketi kullanarak içeriği seviyeye uyarlar.
  String _gradeHuman(String level, String grade, String? faculty) {
    final lvl = level.toLowerCase();
    final g = grade.trim();
    switch (lvl) {
      case 'primary':
        return 'İlkokul $g. sınıf';
      case 'middle':
        return 'Ortaokul $g. sınıf';
      case 'high':
        return 'Lise $g. sınıf';
      case 'exam_prep':
        return 'Sınav hazırlığı: $g';
      case 'university':
        final fac = (faculty ?? '').isEmpty ? '' : ', $faculty';
        return 'Üniversite $g. sınıf$fac';
      case 'masters':
        return 'Yüksek lisans${(faculty ?? '').isEmpty ? '' : ' ($faculty)'}';
      case 'doctorate':
        return 'Doktora${(faculty ?? '').isEmpty ? '' : ' ($faculty)'}';
      case 'other':
        return 'Yetişkin / kişisel öğrenme';
      default:
        return '$level $g';
    }
  }

  Future<void> _toggleFormulasPanel() async {
    // Açıkken → kapat
    if (_showFormulasPanel) {
      setState(() => _showFormulasPanel = false);
      return;
    }
    setState(() => _showFormulasPanel = true);
    // İlk açılışta içeriği yükle (cache'lenir, ikinci açılışta hızlı gelir)
    if (_formulasContent == null && !_loadingFormulas) {
      setState(() {
        _loadingFormulas = true;
        _formulasError = null;
      });
      try {
        // Öğrenci seviyesini al — formülün karmaşıklığı + dil seviyesi buna
        // göre otomatik ayarlanır (ilkokul ≠ lise ≠ üniversite).
        String? gradeLabel;
        try {
          final p = await EduProfile.load();
          if (p != null) {
            gradeLabel = _gradeHuman(p.level, p.grade, p.faculty);
          }
        } catch (_) {}
        final content = await GeminiService.generateFormulas(
          subject: widget.subjectName,
          topic: widget.summary.topic,
          gradeLabel: gradeLabel,
          langCode: localeService.localeCode,
        );
        if (!mounted) return;
        setState(() {
          _formulasContent = content;
          _loadingFormulas = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _formulasError = 'Formüller yüklenemedi — internet/sunucu sorunu.'
              .tr();
          _loadingFormulas = false;
        });
      }
    }
  }

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
  // Loader watchdog — stream 45 sn boyunca anlamlı içerik üretmezse
  // loader ekranına "Bağlantı yavaş — Yeniden Dene" butonu ekleriz.
  // Önceden hiç timeout yoktu → kullanıcı sonsuza dek "özetin neredeyse
  // hazır" loader'ında takılıp kalıyordu.
  Timer? _loaderSlowTimer;
  bool _loaderSlow = false;
  // Auto-scroll DEVRE DIŞI — kullanıcı özet oluşturulurken ekranın
  // aşağı kaymasını istemiyor; özetin ilk sayfası ekranda kalsın,
  // okuyucu kendi kaydırdığı kadar görsün. Kullanıcı manuel olarak
  // aşağı inerse zaten yeni içerik orada bekliyor olacak.
  bool _autoFollowBottom = false;

  /// StudyToolbarOverlay sticky highlights için — ListView ile overlay
  /// Stack'te sibling olduğundan Scrollable.maybeOf(context) bulamıyor.
  /// Controller'ı parent'ta tutup overlay'e inject ediyoruz.
  final ScrollController _scrollController = ScrollController();

  // ── Yeni özet sayfası özellikleri (font / TOC / bookmark / arama / vs) ──
  /// Yazı boyutu — kullanıcı A−/A+ ile değiştirir. 12-22 arası clamp.
  double _bodyFontSize = 15;
  static const String _fontSizePrefKey = 'summary_body_font_size';

  /// Yer imi (scroll offset) — bu özete özel.
  double? _bookmarkOffset;
  String get _bookmarkPrefKey => 'summary_bookmark_${widget.summary.id}';

  /// Çizimleri/vurguları görsel olarak gizle — sınava hazırlıkta "boş özet".
  bool _hideStrokes = false;

  /// Arama state'i: search bar görünür mü, sorgu nedir.
  bool _showSearch = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  /// Scroll ilerleme yüzdesi (0..1) — üst ince çubuk için.
  final ValueNotifier<double> _readProgress = ValueNotifier<double>(0);

  /// Sayfanın başına dön FAB görünürlüğü — scroll > 600 ise true.
  final ValueNotifier<bool> _showBackToTop = ValueNotifier<bool>(false);

  /// TTS state'i.
  bool _ttsPlaying = false;

  /// Bölüm tamamlama — kullanıcı bir bölümü "öğrendim ✓" işaretler.
  Set<int> _completedSections = {};
  String get _completedPrefKey =>
      'summary_completed_${widget.summary.id}';

  /// Sticky header — şu an görünen bölümün başlığı (0..n).
  /// -1 = title card görünüyor (başlığı title card sağlıyor).
  final ValueNotifier<int> _currentSectionIdx = ValueNotifier<int>(-1);

  // ── Spaced repetition (tekrar planı) state ───────────────────────────────
  // Bilim "spaced repetition" intervals: 1, 3, 7, 14, 30 gün. Bölüm
  // tamamlama %100'e ulaşınca otomatik başlar; overflow menüsünden
  // manuel başlatılabilir. Her özet kendi planına sahip (key: srs_<id>).
  static const _kSrsIntervalsDays = [1, 3, 7, 14, 30];
  DateTime? _srsLastReview;
  int _srsStep = 0;
  bool _srsCompleted = false;
  String get _srsPrefKey => 'srs_${widget.summary.id}';
  bool get _srsScheduled => _srsLastReview != null && !_srsCompleted;
  DateTime? get _srsNextDue {
    if (_srsLastReview == null || _srsCompleted) return null;
    final step = _srsStep.clamp(0, _kSrsIntervalsDays.length - 1);
    return _srsLastReview!.add(Duration(days: _kSrsIntervalsDays[step]));
  }
  bool get _srsIsDue {
    final due = _srsNextDue;
    return due != null && !DateTime.now().isBefore(due);
  }

  // ── TTS hız kontrolü ─────────────────────────────────────────────────
  // 1.0x → TtsService default rate (0.58). Çarpan SharedPrefs'te kalıcı.
  static const String _ttsSpeedPrefKey = 'summary_tts_speed_x';
  double _ttsSpeedX = 1.0;

  // ── Parse cache — sayfa açılışını anında yapmak için ───────────────────
  // _clean() + _splitSections() pahalı; her build'de tekrar koşmasın.
  // Ham içerik değişmediyse cache kullan, sadece içerik değişince yenile.
  String? _cachedRaw;
  String _cachedCleaned = '';
  List<_Section> _cachedNormalSections = const [];
  _Section? _cachedKeyFacts;
  _Section? _cachedExamples;
  // Her normal section için GlobalKey — sticky header için gerçek scroll
  // konumunu ölçmekte kullanılır. Section sayısı değişince yenilenir.
  List<GlobalKey> _sectionKeys = const [];

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
      // "📚 Konu İşlenişi" sekmesi de gizlenir — ana içeriği zaten
      // başlık + 5 bilgi + sorular toplulukla aynı bilgiyi veriyor.
      if (_isTopicProcessHeader(s.header)) continue;
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
    if (_sectionKeys.length != normal.length) {
      _sectionKeys = List.generate(normal.length, (_) => GlobalKey());
    }
  }

  bool _isClosingHeader(String h) {
    final t = h.toLowerCase();
    return t.contains('📌') || t.contains('özetle');
  }

  /// "📚 Konu İşlenişi" / "topic processing" sekmesi — render'da gizlenir.
  /// Eski özetlerde bu bölüm varsa kart olarak gösterilmez (içerik korunur,
  /// silinmez — sadece UI'da çıkartılır).
  bool _isTopicProcessHeader(String h) {
    final t = h.toLowerCase();
    return t.contains('konu işlen') ||
        t.contains('konu islen') ||
        t.contains('topic processing') ||
        t.contains('topic process') ||
        t.contains('konu anlatımı') ||
        t.contains('konu anlatimi');
  }

  bool _isExamplesHeader(String h) {
    final t = h.toLowerCase();
    return t.contains('📝') ||
        // 🎯 "Kendini Sına" (aktif hatırlama öz-testi) — pekiştirme
        // kartına düşer; _ExamplesToggleList soru+cevabı çöz-göster toggle'ıyla
        // gösterir (öğrenci cevabı kapatıp kendini yoklar).
        t.contains('🎯') ||
        t.contains('kendini sına') ||
        t.contains('kendini sina') ||
        t.contains('örnek soru') ||
        t.contains('ornek soru') ||
        t.contains('konuyu pekiştir') ||
        t.contains('konuyu pekistir') ||
        t.contains('pekiştirme soru') ||
        t.contains('pekistirme soru') ||
        t.contains('uygulama soru') ||
        t.contains('example question') ||
        t.contains('sample question') ||
        t.contains('practice question') ||
        t.contains('self-test') ||
        t.contains('quiz yourself');
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
    _loadUserPrefs();
    _loadSrs();
    _incrementVisitCount();
    _scrollController.addListener(_handleScroll);
    _scrollController.addListener(_updateReadProgress);
    _attachStreamIfAny(widget.stream);
    // Heavy parse'ı ilk frame'den SONRA yap — sayfa transition'ı anında
    // açılsın, içerik bir tick sonra dolsun. Boş cache ile ilk build hızlı.
    if (widget.stream == null && widget.summary.content.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureParsed(widget.summary.content);
        setState(() {});
        // Bookmark varsa kullanıcıya "kaldığın yerden devam?" snackbar.
        _maybeShowBookmarkResume();
      });
    }
  }

  Future<void> _incrementVisitCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'topic_visits_${widget.summary.id}';
      final cur = prefs.getInt(key) ?? 0;
      await prefs.setInt(key, cur + 1);
      // AcademicPlanner home'daki "Kaldığın yerden devam et" kartı için —
      // son açılan özetin id+ders adı+zamanı global anahtara yazılır.
      await prefs.setString('last_opened_summary', jsonEncode({
        'summaryId': widget.summary.id,
        'subjectName': widget.subjectName,
        'topic': widget.summary.topic,
        'at': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }

  Future<void> _loadUserPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final fs = prefs.getDouble(_fontSizePrefKey);
    final bm = prefs.getDouble(_bookmarkPrefKey);
    final hs = prefs.getBool('summary_hide_strokes') ?? false;
    final completed = prefs.getStringList(_completedPrefKey) ?? const [];
    final tx = prefs.getDouble(_ttsSpeedPrefKey);
    if (!mounted) return;
    setState(() {
      if (fs != null) _bodyFontSize = fs.clamp(12, 22);
      _bookmarkOffset = bm;
      _hideStrokes = hs;
      _completedSections = completed
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet();
      if (tx != null) _ttsSpeedX = tx.clamp(0.25, 2.5);
    });
  }

  // ── Spaced repetition: load / save / control ───────────────────────────
  Future<void> _loadSrs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_srsPrefKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final last = m['last'] as String?;
      final step = (m['step'] as int?) ?? 0;
      final done = (m['done'] as bool?) ?? false;
      if (!mounted) return;
      setState(() {
        _srsLastReview = last != null ? DateTime.tryParse(last) : null;
        _srsStep = step.clamp(0, _kSrsIntervalsDays.length - 1);
        _srsCompleted = done;
      });
    } catch (_) {}
  }

  Future<void> _saveSrs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_srsLastReview == null) {
        await prefs.remove(_srsPrefKey);
        return;
      }
      await prefs.setString(_srsPrefKey, jsonEncode({
        'last': _srsLastReview!.toIso8601String(),
        'step': _srsStep,
        'done': _srsCompleted,
      }));
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'srs_save');
    }
  }

  Future<void> _startSrs({bool silent = false}) async {
    if (_srsScheduled) return;
    setState(() {
      _srsLastReview = DateTime.now();
      _srsStep = 0;
      _srsCompleted = false;
    });
    await _saveSrs();
    if (!silent && mounted) {
      _toast('📚 Tekrar planı başladı — 1 gün sonra hatırlatacağım.');
    }
  }

  Future<void> _confirmSrsReview() async {
    if (!_srsScheduled) return;
    setState(() {
      _srsLastReview = DateTime.now();
      _srsStep++;
      if (_srsStep >= _kSrsIntervalsDays.length) {
        _srsCompleted = true;
        _srsStep = _kSrsIntervalsDays.length - 1;
      }
    });
    await _saveSrs();
    if (mounted) {
      _toast(_srsCompleted
          ? '🎉 Tekrar planı tamamlandı — konu uzun süreli belleğe geçti.'
          : '✓ Sonraki tekrar ${_kSrsIntervalsDays[_srsStep]} gün sonra.');
    }
  }

  Future<void> _resetSrs() async {
    setState(() {
      _srsLastReview = null;
      _srsStep = 0;
      _srsCompleted = false;
    });
    await _saveSrs();
  }

  // ── TTS hız ayarı: çarpan → gerçek rate, kalıcı + canlı uygula ────────
  double get _ttsRateActual => (0.58 * _ttsSpeedX).clamp(0.15, 1.50);

  Future<void> _setTtsSpeed(double x) async {
    setState(() => _ttsSpeedX = x);
    await TtsService.setRate(_ttsRateActual);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_ttsSpeedPrefKey, x);
    } catch (_) {}
  }

  String _ttsSpeedLabel() {
    if (_ttsSpeedX <= 0.6) return '0.5x';
    if (_ttsSpeedX <= 1.1) return '1x';
    if (_ttsSpeedX <= 1.6) return '1.5x';
    return '2x';
  }

  Future<void> _saveCompletedSections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _completedPrefKey,
      _completedSections.map((i) => i.toString()).toList(),
    );
  }

  void _toggleSectionCompleted(int idx) {
    setState(() {
      if (_completedSections.contains(idx)) {
        _completedSections.remove(idx);
      } else {
        _completedSections.add(idx);
      }
    });
    _saveCompletedSections();
    // SRS otomatik tetik: tüm bölümler tamamlandığında ve henüz plan yoksa
    // 1/3/7/14/30 gün aralıklı tekrar planı kendiliğinden başlar.
    if (_cachedNormalSections.isNotEmpty &&
        _completedSections.length >= _cachedNormalSections.length &&
        !_srsScheduled && !_srsCompleted) {
      _startSrs();
    }
  }

  Future<void> _saveFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizePrefKey, _bodyFontSize);
  }

  Future<void> _saveHideStrokes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('summary_hide_strokes', _hideStrokes);
  }

  void _updateReadProgress() {
    if (!_scrollController.hasClients) return;
    final p = _scrollController.position;
    if (p.maxScrollExtent <= 0) {
      _readProgress.value = 0;
      _showBackToTop.value = false;
      return;
    }
    _readProgress.value =
        (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
    _showBackToTop.value = p.pixels > 600;
    // Sticky header: her section'ın GlobalKey'inden gerçek konumu ölç.
    // AppBar (44) + progress bar (2.5) + sticky pill yüksekliği (~30) +
    // küçük buffer = 80. Bu eşiğin altına geçen son section aktif kabul
    // edilir. Önceki yaklaşım: her section ~380px sabit varsayıyordu;
    // farklı uzunluktaki section'larda başlık yanlış konumda kalıyordu.
    if (_cachedNormalSections.isNotEmpty && _sectionKeys.isNotEmpty) {
      const threshold = 80.0;
      int activeIdx = -1;
      for (int i = _sectionKeys.length - 1; i >= 0; i--) {
        final ctx = _sectionKeys[i].currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject();
        if (box is! RenderBox || !box.attached) continue;
        final dy = box.localToGlobal(Offset.zero).dy;
        if (dy <= threshold) {
          activeIdx = i;
          break;
        }
      }
      _currentSectionIdx.value = activeIdx;
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  // ── TTS — Sesli Okuma ──────────────────────────────────────────────────
  /// TTS engine'in "yıldız", "yumruk emoji" gibi okuyacağı sembol/emoji/
  /// dingbat karakterlerini içerikten süzer. Rune bazında çalışır — Dart
  /// regex'in surrogate pair zafiyetlerinden bağımsız. Korur: harf, rakam,
  /// noktalama, boşluk, TR aksanlı karakterler, matematik temel sembolleri
  /// (=, +, −, ×, ÷, %, ‰), parantezler.
  String _stripSymbolsForTts(String s) {
    bool isSkippable(int r) {
      // Emoji blokları
      if (r >= 0x1F300 && r <= 0x1FAFF) return true; // misc symbols & pictographs, emoticons, transport
      if (r >= 0x1F000 && r <= 0x1F2FF) return true; // mahjong, domino, playing cards, enclosed
      if (r >= 0x2600 && r <= 0x27BF) return true; // misc symbols, dingbats
      if (r >= 0x2300 && r <= 0x23FF) return true; // misc technical
      if (r >= 0x2B00 && r <= 0x2BFF) return true; // misc symbols and arrows
      if (r >= 0x2190 && r <= 0x21FF) return true; // arrows
      if (r >= 0x25A0 && r <= 0x25FF) return true; // geometric shapes
      // Box drawing & block elements — bazen şema satırlarında kalır
      if (r >= 0x2500 && r <= 0x259F) return true;
      // Bullets ve seçilmiş işaretler
      const skip = <int>{
        0x2022, // •
        0x00B7, // ·
        0x2023, // ‣
        0x25CF, // ●
        0x25CB, // ○
        0x2605, // ★
        0x2606, // ☆
        0x2713, // ✓
        0x2714, // ✔
        0x2717, // ✗
        0x2718, // ✘
        0x27A4, // ➤
        0x27A1, // ➡
        0x2192, // → (zaten arrows içinde ama explicit)
        0xFE0F, // variation selector
        0x200D, // ZWJ
        0x2060, // word joiner
        0x00AD, // soft hyphen
      };
      if (skip.contains(r)) return true;
      // Yan-yana yıldız işaretleri (zaten regex'le siliniyor; rune kontrolünde de tut)
      if (r == 0x002A) return true; // *
      // Hash
      if (r == 0x0023) return true; // #
      return false;
    }

    final buf = StringBuffer();
    for (final r in s.runes) {
      if (isSkippable(r)) {
        buf.write(' ');
      } else {
        buf.writeCharCode(r);
      }
    }
    // Çoklu boşlukları tek boşluk yap.
    return buf.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  Future<void> _toggleTts() async {
    if (_ttsPlaying) {
      await TtsService.stop();
      setState(() => _ttsPlaying = false);
      return;
    }
    final raw = _streamedContent ?? widget.summary.content;
    final cleaned = _clean(raw);
    // İçeriği TTS için temizle: latex blokları, ŞEMA blokları, markdown
    // markerları çıkar; ardından rune bazında emoji/sembol/dingbat süz.
    String spoken = cleaned
        .replaceAll(RegExp(r'\\\([^\)]+\\\)'), '')
        .replaceAll(RegExp(r'\\\[[^\]]+\\\]'), '')
        .replaceAll(RegExp(r'\[ŞEMA:[^\]]*\][^\[]*\[/ŞEMA\]', dotAll: true), '')
        .replaceAll(RegExp(r'\[VIDEO:[^\]]*\]', dotAll: true), '')
        .replaceAll(RegExp(r'\[WEB:[^\]]*\]', dotAll: true), '');
    spoken = _stripSymbolsForTts(spoken);
    // Boş satır fazlalığını sadeleştir — TTS doğal nefes verir.
    spoken = spoken.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
    if (spoken.isEmpty) {
      _toast('Okunacak içerik yok.');
      return;
    }
    setState(() => _ttsPlaying = true);
    // Kullanıcının seçtiği hızı her oynatma öncesi yeniden uygula —
    // başka ekran (canlı analiz vb.) rate'i değiştirmiş olabilir.
    await TtsService.setRate(_ttsRateActual);
    try {
      await TtsService.speak(spoken);
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'summary_tts');
    } finally {
      if (mounted) setState(() => _ttsPlaying = false);
    }
  }

  // ── "Bu kısmı farklı anlat" — AI ile yeniden anlatım ────────────────
  Future<void> _rewriteSectionWithAi(String header, String body) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Text('Bu bölümü farklı anlattırıyorum…'.tr()),
        ],
      ),
      duration: const Duration(seconds: 12),
    ));
    try {
      final prompt =
          'Aşağıdaki ders konusu açıklamasını 12-15 yaşındaki bir öğrenciye '
          'günlük dilden örneklerle ve daha kısa olarak yeniden anlat. '
          'Akademik terimleri kullan ama hemen yanında gündelik karşılığını '
          'belirt. Maksimum 200 kelime.\n\n'
          'BAŞLIK: $header\n\nMETİN:\n$body';
      final content = await GeminiService.solveHomework(
        question: prompt,
        solutionType: 'KonuÖzeti',
        subject: widget.subjectName,
      );
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      // Yeniden anlatımı bottom sheet'te göster
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppPalette.card(context),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return DraggableScrollableSheet(
            initialChildSize: 0.62,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            expand: false,
            builder: (_, ctrl) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.textSecondary(context)
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: Color(0xFF7C3AED), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Farklı Anlatım — $header'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textPrimary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: ctrl,
                      child: SelectableText(
                        content,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          height: 1.55,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'rewrite_section');
      if (mounted) _toast('AI cevap veremedi.');
    }
  }

  // ── Konuya özel istatistikler ────────────────────────────────────────
  Future<void> _showTopicStats() async {
    int totalMinutes = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      totalMinutes =
          prefs.getInt('topic_minutes_${widget.summary.id}') ?? 0;
    } catch (_) {}
    final completedCount = _completedSections.length;
    final totalSections = _cachedNormalSections.length;

    // Oluşturma tarihi (createdAt) TR formatı: "8 Mayıs 2026"
    final created = widget.summary.createdAt;
    const trMonths = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    final createdStr =
        '${created.day} ${trMonths[created.month - 1]} ${created.year}';

    // Tekrar planı durumu
    String srsValue;
    String srsLabel;
    if (_srsCompleted) {
      srsValue = 'Tamamlandı 🎉';
      srsLabel = '5/5 tekrar — uzun süreli bellek';
    } else if (_srsScheduled) {
      final due = _srsNextDue;
      final daysToDue = due?.difference(DateTime.now()).inDays;
      final stepText = '${_srsStep + 1}/${_kSrsIntervalsDays.length}';
      final nextText = daysToDue == null
          ? ''
          : (daysToDue <= 0
              ? 'bugün'
              : '$daysToDue gün sonra');
      srsValue = nextText.isEmpty ? 'Plan aktif · $stepText' : 'Sonraki: $nextText';
      srsLabel = nextText.isEmpty
          ? 'Tekrar planı'
          : 'Tekrar planı · $stepText';
    } else {
      srsValue = 'Henüz başlamadı';
      srsLabel = 'Tüm bölümleri tamamla → plan başlasın';
    }

    // Test denemeleri — varsa say + tamamlanan deneme % ortalamasını hesapla.
    final attempts = widget.summary.tests;
    final completedAttempts = attempts.where((a) => a.completed).toList();
    int? avgPct;
    if (completedAttempts.isNotEmpty) {
      double sum = 0;
      int counted = 0;
      for (final a in completedAttempts) {
        try {
          final qs = parseTestQuestions(a.content);
          if (qs.isEmpty) continue;
          int correct = 0;
          for (int i = 0; i < qs.length; i++) {
            final ua = a.answers[i];
            if (ua != null && ua.toUpperCase() == qs[i].ans) correct++;
          }
          sum += (correct / qs.length) * 100;
          counted++;
        } catch (_) {}
      }
      if (counted > 0) avgPct = (sum / counted).round();
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.textSecondary(context)
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.insights_rounded,
                      color: Color(0xFF2563EB), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Konu İstatistikleri'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _statRow(
                Icons.timer_rounded,
                totalMinutes > 0 ? '$totalMinutes dk' : 'Henüz çalışmadın',
                'Toplam çalışma süresi'.tr(),
                const Color(0xFF2563EB),
              ),
              _statRow(
                Icons.check_circle_rounded,
                totalSections > 0
                    ? '$completedCount / $totalSections'
                    : 'Henüz bölüm yok',
                'Tamamlanan bölüm'.tr(),
                const Color(0xFF10B981),
              ),
              _statRow(
                Icons.calendar_today_rounded,
                createdStr,
                'Çalışmaya başladığın gün'.tr(),
                const Color(0xFF7C3AED),
              ),
              _statRow(
                Icons.event_repeat_rounded,
                srsValue,
                srsLabel.tr(),
                const Color(0xFFFF6A00),
              ),
              if (attempts.isNotEmpty)
                _statRow(
                  Icons.quiz_rounded,
                  avgPct != null
                      ? '${completedAttempts.length} ${'deneme'.tr()} · %$avgPct'
                      : '${attempts.length} ${'deneme'.tr()}',
                  avgPct != null
                      ? 'Test denemeleri · ortalama'.tr()
                      : 'Test denemeleri'.tr(),
                  const Color(0xFFEC4899),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(IconData icon, String value, String label,
      [Color tint = const Color(0xFF2563EB)]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppPalette.textSecondary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _maybeShowBookmarkResume() {
    final bm = _bookmarkOffset;
    if (bm == null || bm < 100) return;
    // Sayfa az scroll edildiyse veya bookmark başlangıçtaysa gösterme.
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('📍 Kaldığın yerden devam edebilirsin'.tr()),
        action: SnackBarAction(
          label: 'Git'.tr(),
          onPressed: () {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                bm,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
              );
            }
          },
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
    });
  }

  // Scroll dinleyici devre dışı — auto-follow kapalı, kullanıcı her zaman
  // kendi konumunda kalsın. Eski davranış: kullanıcı en alttayken stream
  // akarken yapışık tutuyordu; özet oluşturulurken ilk sayfa görünmüyordu.
  void _handleScroll() {
    // Scroll = kullanıcı etkileşimi → idle sayacını sıfırla (uzun özet okurken
    // 2 dk hareketsiz sayılıp süre yanlışlıkla duraklatılmasın; idle yüzünden
    // duraklamışsa otomatik devam etsin). notifyInteraction aktif değilse no-op.
    StudySessionTracker.instance.notifyInteraction();
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
      _loaderSlow = false;
    });
    // 45 sn sonra hâlâ anlamlı içerik yoksa loader'a retry butonu ekle.
    _loaderSlowTimer?.cancel();
    _loaderSlowTimer = Timer(const Duration(seconds: 45), () {
      if (!mounted) return;
      final accLen = (_streamedContent ?? '').trim().length;
      if (_streaming && accLen < 40) {
        setState(() => _loaderSlow = true);
      }
    });
    _streamSub = s.listen(
      (acc) {
        if (!mounted) return;
        // setState yapmıyoruz; her chunk full parse + rebuild jank yapıyor.
        // Sadece bayrakları güncelle, debounce timer parse + setState'i
        // 150ms sonra topluca çalıştırsın. Bu aralıkta ekranda eski cache
        // görünür — kabul edilebilir, kullanıcı zaten satırlar akarken bakıyor.
        _streamedContent = acc;
        // İlk anlamlı chunk geldi → "yavaş" uyarısı gerekmiyor, timer iptal.
        if (acc.trim().length >= 40 && _loaderSlowTimer != null) {
          _loaderSlowTimer?.cancel();
          _loaderSlowTimer = null;
        }
        _scheduleParse();
      },
      onError: (e) async {
        if (!mounted) return;
        // Loader yavaşlama timer'ını iptal — hata zaten geldi.
        _loaderSlowTimer?.cancel();
        _loaderSlowTimer = null;
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
        // Loader yavaşlama timer'ını iptal — stream başarıyla bitti.
        _loaderSlowTimer?.cancel();
        _loaderSlowTimer = null;
        final finalContent = _streamedContent ?? '';
        // Debounce'u iptal et + son parse'i ZORLA çalıştır.
        _parseDebounce?.cancel();
        _parseDebounce = null;
        setState(() {
          _streaming = false;
          if (finalContent.isNotEmpty) {
            _ensureParsed(finalContent);
          } else {
            // Boş ama "başarılı" biten stream → hata gibi davran. Aksi halde
            // ekran boş fallback kartında kalır, banner/"Tekrar Dene" çıkmaz.
            _streamFailed = true;
            _streamFailMessage = 'AI yanıt veremedi.';
          }
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
    _loaderSlowTimer?.cancel();
    _loaderSlowTimer = null;
    setState(() {
      _streamedContent = '';
      _streamFailed = false;
      _streamFailMessage = null;
      _streaming = true;
      _loaderSlow = false;
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
    _loaderSlowTimer?.cancel();
    _streamSub?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.removeListener(_updateReadProgress);
    _scrollController.dispose();
    _searchCtrl.dispose();
    _readProgress.dispose();
    _showBackToTop.dispose();
    _currentSectionIdx.dispose();
    // TTS aktifse durdur — sayfa kapanırken arkaplanda çalmasın.
    if (_ttsPlaying) TtsService.stop();
    super.dispose();
  }

  // ── Yeni özet sayfası action'ları ────────────────────────────────────
  void _adjustFontSize(double delta) {
    setState(() {
      _bodyFontSize = (_bodyFontSize + delta).clamp(12, 22);
    });
    _saveFontSize();
  }

  /// Section body içinden alt başlıkları çıkarır.
  /// AI prompt'ta tanımlı format: "▸ N. {emoji} Başlık Adı" — satır başında
  /// ▸ karakteri + numara + nokta + emoji + başlık. Başında 0–2 boşluk olabilir.
  List<String> _extractSubHeaders(String body) {
    final out = <String>[];
    final re = RegExp(r'^\s{0,3}▸\s*\d+\.\s+(.+?)\s*$', multiLine: true);
    for (final m in re.allMatches(body)) {
      final g = m.group(1)?.trim();
      if (g != null && g.isNotEmpty) out.add(g);
    }
    return out;
  }

  Future<void> _openSectionTOC() async {
    if (_cachedNormalSections.isEmpty) {
      _toast('Bu özette atlanacak başlık bulunamadı.');
      return;
    }
    // Düz liste: her section için bir başlık satırı + altında çıkarılan
    // alt başlık satırları. _TocEntry tuple: (sectionIdx, sub başlık metni
    // veya null, indent). null = ana başlık.
    final entries = <_TocEntry>[];
    for (int i = 0; i < _cachedNormalSections.length; i++) {
      final s = _cachedNormalSections[i];
      entries.add(_TocEntry(sectionIdx: i, isSub: false, label: s.header));
      for (final sub in _extractSubHeaders(s.body)) {
        entries.add(_TocEntry(sectionIdx: i, isSub: true, label: sub));
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, ctrl) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppPalette.textSecondary(context)
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.list_alt_rounded,
                          color: Color(0xFF7C3AED), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Bölümler'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      controller: ctrl,
                      shrinkWrap: true,
                      itemCount: entries.length,
                      separatorBuilder: (_, i) {
                        // Bir alt başlığın altında ince ayraç; ana başlıklar
                        // arasında biraz daha belirgin.
                        final cur = entries[i];
                        final next = i + 1 < entries.length
                            ? entries[i + 1]
                            : null;
                        if (next == null) return const SizedBox.shrink();
                        final isSectionBoundary =
                            cur.isSub != next.isSub || !next.isSub;
                        return Divider(
                          height: 1,
                          thickness: isSectionBoundary ? 0.8 : 0.4,
                          color: AppPalette.border(context).withValues(
                              alpha: isSectionBoundary ? 0.9 : 0.4),
                        );
                      },
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        final s = _cachedNormalSections[e.sectionIdx];
                        if (!e.isSub) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: s.color.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${e.sectionIdx + 1}',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: s.color,
                                ),
                              ),
                            ),
                            title: Text(
                              e.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.textPrimary(context),
                              ),
                            ),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _scrollToSection(e.sectionIdx);
                            },
                          );
                        }
                        // Alt başlık satırı — soldan girintili, narin görünüm.
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.only(left: 36, right: 0),
                          dense: true,
                          visualDensity: const VisualDensity(
                              horizontal: -3, vertical: -3),
                          leading: Container(
                            width: 5,
                            height: 18,
                            decoration: BoxDecoration(
                              color: s.color.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          title: Text(
                            e.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textSecondary(context),
                              height: 1.25,
                            ),
                          ),
                          onTap: () {
                            // Alt başlıkların kendi key'i yok — parent section'a
                            // kaydır, kullanıcı listede ilgili maddeyi görür.
                            Navigator.of(ctx).pop();
                            _scrollToSection(e.sectionIdx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _scrollToSection(int idx) {
    if (!_scrollController.hasClients) return;
    // Önce GlobalKey ile gerçek konuma git — Scrollable.ensureVisible
    // section'ı viewport top'a hizalar (alignment 0.0). RenderBox in-tree
    // değilse (cache extent dışı), kaba estimate ile yaklaş.
    if (idx >= 0 && idx < _sectionKeys.length) {
      final ctx = _sectionKeys[idx].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          alignment: 0.0,
        );
        return;
      }
    }
    final approxOffset = (idx * 380 + 100).toDouble();
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      approxOffset.clamp(0.0, max),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _toggleBookmark() async {
    if (!_scrollController.hasClients) return;
    final prefs = await SharedPreferences.getInstance();
    if (_bookmarkOffset != null) {
      await prefs.remove(_bookmarkPrefKey);
      if (!mounted) return;
      setState(() => _bookmarkOffset = null);
      _toast('Yer imi silindi.');
    } else {
      final pos = _scrollController.offset;
      await prefs.setDouble(_bookmarkPrefKey, pos);
      if (!mounted) return;
      setState(() => _bookmarkOffset = pos);
      _toast('📍 Yer imi konuldu.');
    }
  }

  void _toggleHideStrokes() {
    setState(() => _hideStrokes = !_hideStrokes);
    _saveHideStrokes();
    _toast(_hideStrokes ? 'Çizimler gizlendi.' : 'Çizimler gösteriliyor.');
  }

  /// Diğer versiyona geç (Kısa↔Kapsamlı).
  Future<void> _switchLengthVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('library_subjects_v2') ?? const [];
    for (final s in raw) {
      try {
        final j = jsonDecode(s) as Map<String, dynamic>;
        if ((j['name'] as String).toLowerCase() !=
            widget.subjectName.toLowerCase()) continue;
        final summaries = (j['summaries'] as List?) ?? [];
        for (final em in summaries) {
          final m = em as Map<String, dynamic>;
          if ((m['topic'] as String).toLowerCase() ==
              widget.summary.topic.toLowerCase()) {
            final otherSum = _Summary.fromJson(m);
            if (otherSum.id == widget.summary.id) continue;
            if (otherSum.length == widget.summary.length) continue;
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => _SummaryDetailPage(
                  summary: otherSum,
                  subjectName: widget.subjectName,
                ),
              ),
            );
            return;
          }
        }
      } catch (_) {}
    }
    // Diğer uzunluk henüz üretilmemiş — geçilecek versiyon yok. Üretim AI
    // hattı ana sayfada olduğundan buradan tetiklenemez; kullanıcıyı net
    // şekilde yönlendir (etiket "geç" dese de oluşturma orada yapılır).
    final otherLabel = widget.summary.length == _SummaryLength.short
        ? 'kapsamlı'
        : 'kısa';
    _toast('Bu konunun $otherLabel özeti henüz yok. '
        'Ana sayfadan aynı konuyu seçip "$otherLabel" üretebilirsin.');
  }

  Future<void> _shareSummary() async {
    final raw = _streamedContent ?? widget.summary.content;
    final cleaned = _clean(raw);
    final header = '${widget.subjectName} / ${widget.summary.topic}\n';
    final body = cleaned.length > 4000
        ? '${cleaned.substring(0, 4000)}…'
        : cleaned;
    final text = '$header\n$body';
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'summary_share');
    }
    if (!mounted) return;
    // Kopyalama bittikten sonra paylaşım sheet'i — WhatsApp/Telegram/SMS
    // gibi uygulamalara doğrudan yönlendirme için Share.share() kullanılır.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.textSecondary(context)
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFEC4899), Color(0xFF7C3AED)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Arkadaşına göndermek ister misin?'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimary(context),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Özet panoya kopyalandı'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: Text(
                      'Paylaş'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEC4899),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      try {
                        await Share.share(
                          text,
                          subject:
                              '${widget.subjectName} — ${widget.summary.topic}',
                        );
                      } catch (e, st) {
                        ErrorLogger.instance.capture(e, st,
                            context: 'summary_share_send');
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Şimdilik sadece kopyala'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textSecondary(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchQuery = '';
        _searchCtrl.clear();
      }
    });
  }

  void _toast(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      content: Text(msg.tr()),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, Color color,
      {bool enabled = true}) {
    // Her item kendi yuvarlatılmış kart kapsülünde — kapsayıcı menü içinde
    // satırlar zeminden ayrışsın, daha narin görünsün. Yükseklik default
    // 48 → 36; padding default 16 yatay → 4 yatay 2 dikey.
    final tint = enabled ? color : AppPalette.textSecondary(context);
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: tint.withValues(alpha: 0.20),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: tint.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 13, color: tint),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                label.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? AppPalette.textPrimary(context)
                      : AppPalette.textSecondary(context),
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onOverflowMenu(String action) {
    switch (action) {
      case 'toc':
        _openSectionTOC();
        break;
      case 'bookmark':
        _toggleBookmark();
        break;
      case 'search':
        _toggleSearch();
        break;
      case 'switchLength':
        _switchLengthVersion();
        break;
      case 'hideStrokes':
        _toggleHideStrokes();
        break;
      case 'share':
        _shareSummary();
        break;
      case 'tts':
        _toggleTts();
        break;
      case 'ttsSpeed':
        _showTtsSpeedSheet();
        break;
      case 'srs':
        _showSrsPlanSheet();
        break;
      case 'stats':
        _showTopicStats();
        break;
      case 'testCoz':
        _onTestQuestionsTap();
        break;
    }
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
              const SizedBox(width: 8),
              // Kısa/Kapsamlı rozeti — kullanıcı hangi versiyonu okuduğunu
              // her zaman görsün. Kısa=yeşil, Kapsamlı=mor (liste slot'larıyla
              // aynı renkler).
              _lengthBadge(),
            ],
              ),
              if (_cachedNormalSections.isNotEmpty) ...[
                const SizedBox(height: 8),
                // Sadece tamamlama oranı — okuma süresi tahmini kaldırıldı.
                ValueListenableBuilder<double>(
                  valueListenable: _readProgress,
                  builder: (_, __, ___) {
                    final completedRatio =
                        _completedSections.length /
                            _cachedNormalSections.length;
                    return Row(
                      children: [
                        const Spacer(),
                        Icon(Icons.check_circle_rounded,
                            size: 13, color: const Color(0xFF10B981)),
                        const SizedBox(width: 3),
                        Text(
                          '${(completedRatio * 100).toInt()}%',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _lengthBadge() {
    final isShort = widget.summary.length == _SummaryLength.short;
    final Color accent =
        isShort ? const Color(0xFF10B981) : const Color(0xFF7C3AED);
    final String label = isShort ? 'Kısa'.tr() : 'Kapsamlı'.tr();
    final IconData icon = isShort
        ? Icons.flash_on_rounded
        : Icons.menu_book_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // Test Sorularını Çöz aksiyonu — üst-sağ overflow menüsünden (testCoz)
  // tetiklenir. (Eski turuncu "Test Çöz" FAB pill'i kaldırıldı.)
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
              // KALICILAŞTIR: bu kısayol AcademicPlanner state'inde olmadığı
              // için _persistSubjects yok. questions store'unu yeniden oku,
              // eşleşen konunun son denemesini güncelle, geri yaz — aksi halde
              // çözülen test "tamamlanmamış" görünmeye devam ederdi.
              await _persistQuestionsAttempt(subject, summary, answers);
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

  /// Özet ekranı kısayolundan çözülen testin sonucunu kalıcılaştırır.
  /// questions store'unu yeniden okur, eşleşen ders+konunun SON denemesini
  /// günceller, geri yazar (instance kimliğine güvenmeden ada/konuya göre).
  Future<void> _persistQuestionsAttempt(
      _Subject subject, _Summary summary, Map<int, String?> answers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getStringList('library_subjects_questions_v2') ?? const [];
      final list = raw
          .map((s) {
            try {
              return _Subject.fromJson(jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<_Subject>()
          .toList();
      final subjName = subject.name.toLowerCase().trim();
      final topicName = summary.topic.toLowerCase().trim();
      for (final s in list) {
        if (s.name.toLowerCase().trim() != subjName) continue;
        for (final sum in s.summaries) {
          if (sum.topic.toLowerCase().trim() != topicName) continue;
          if (sum.tests.isEmpty) break;
          final t = sum.tests.last;
          t.answers = Map<int, String?>.from(answers);
          t.completed = true;
          break;
        }
      }
      await prefs.setStringList('library_subjects_questions_v2',
          list.map((s) => jsonEncode(s.toJson())).toList());
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'summary_test_persist');
    }
  }

  // ── Spaced repetition due banner ─────────────────────────────────────
  // Plan aktif + son tekrardan bu yana kontrol aralığı dolmuşsa görünür.
  // Üst kenardan ListView'ın üstüne yerleşir; "Tekrarladım ✓" → bir
  // sonraki interval'a geçer (1→3→7→14→30 gün).
  Widget _buildSrsDueBanner() {
    final due = _srsNextDue;
    if (!_srsIsDue || due == null) return const SizedBox.shrink();
    final daysSince = DateTime.now().difference(_srsLastReview!).inDays;
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFBBF24), Color(0xFFFF6A00)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6A00).withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.event_repeat_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              daysSince <= 0
                  ? 'Tekrar zamanı — bugün gözden geçirme günü.'.tr()
                  : '${'Tekrar zamanı — son okumadan'.tr()} $daysSince ${'gün geçti'.tr()}.',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _confirmSrsReview,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_rounded,
                      size: 13, color: Color(0xFFFF6A00)),
                  const SizedBox(width: 4),
                  Text(
                    'Tekrarladım'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFFF6A00),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── SRS plan bottom sheet (overflow menüsünden açılır) ───────────────
  Future<void> _showSrsPlanSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppPalette.textSecondary(context)
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.event_repeat_rounded,
                            color: Color(0xFFFF6A00), size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Tekrar Planı'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bilimsel "aralıklı tekrar" yöntemi: konuyu 1, 3, 7, 14 ve 30. günlerde tekrar edersen uzun süreli belleğe yerleşir.'
                          .tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        height: 1.45,
                        color: AppPalette.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (!_srsScheduled && !_srsCompleted) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text('Planı Başlat'.tr()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6A00),
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            await _startSrs(silent: true);
                            setSheet(() {});
                          },
                        ),
                      ),
                    ] else ...[
                      for (int i = 0; i < _kSrsIntervalsDays.length; i++)
                        _srsTimelineRow(i),
                      const SizedBox(height: 10),
                      if (_srsCompleted)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.emoji_events_rounded,
                                  color: Color(0xFF10B981), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '🎉 Plan tamamlandı — uzun süreli belleğe geçti.'
                                      .tr(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.refresh_rounded,
                                    size: 16),
                                label: Text('Sıfırla'.tr(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    )),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                      AppPalette.textSecondary(context),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10),
                                ),
                                onPressed: () async {
                                  await _resetSrs();
                                  setSheet(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.check_rounded,
                                    size: 16),
                                label: Text('Tekrarladım'.tr(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    )),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF6A00),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () async {
                                  await _confirmSrsReview();
                                  setSheet(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                      if (_srsCompleted) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            icon: const Icon(Icons.restart_alt_rounded,
                                size: 16),
                            label: Text('Planı Sıfırla'.tr()),
                            onPressed: () async {
                              await _resetSrs();
                              setSheet(() {});
                            },
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _srsTimelineRow(int idx) {
    final days = _kSrsIntervalsDays[idx];
    final isDone = idx < _srsStep || _srsCompleted;
    final isCurrent = idx == _srsStep && !_srsCompleted;
    final scheduledDate = isCurrent && _srsLastReview != null
        ? _srsLastReview!.add(Duration(days: days))
        : null;
    String dateStr = '';
    if (scheduledDate != null) {
      final d = scheduledDate;
      dateStr = '${d.day}/${d.month}/${d.year}';
    }
    final accent = isDone
        ? const Color(0xFF10B981)
        : isCurrent
            ? const Color(0xFFFF6A00)
            : AppPalette.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDone || isCurrent ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              isDone
                  ? Icons.check_rounded
                  : isCurrent
                      ? Icons.schedule_rounded
                      : Icons.circle_outlined,
              size: 16,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$days. ${'gün'.tr()}',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                color: AppPalette.textPrimary(context),
              ),
            ),
          ),
          if (dateStr.isNotEmpty)
            Text(
              dateStr,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
        ],
      ),
    );
  }

  // ── TTS hız seçici (overflow → "Sesli okuma hızı") ───────────────────
  Future<void> _showTtsSpeedSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Widget option(double x, String label, String hint) {
              final selected = _ttsSpeedX == x;
              return InkWell(
                onTap: () async {
                  await _setTtsSpeed(x);
                  setSheet(() {});
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF06B6D4).withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF06B6D4)
                          : AppPalette.border(context),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: selected
                            ? const Color(0xFF06B6D4)
                            : AppPalette.textSecondary(context),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hint,
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.textSecondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppPalette.textSecondary(context)
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.speed_rounded,
                            color: Color(0xFF06B6D4), size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Sesli Okuma Hızı'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    option(0.5, '0.5x', '— ${'yavaş, öğrenme'.tr()}'),
                    option(1.0, '1x', '— ${'normal'.tr()}'),
                    option(1.5, '1.5x', '— ${'hızlı'.tr()}'),
                    option(2.0, '2x', '— ${'çok hızlı, tekrar'.tr()}'),
                    const SizedBox(height: 8),
                    Text(
                      'Tercihin kaydedilir; sonraki seansta da aynı hız uygulanır.'
                          .tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: AppPalette.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
        body: Stack(
          children: [
            QuAlsarLoadingWidget(
              type: QuAlsarLoadingType.summary,
              topic: widget.summary.topic,
              domain:
                  _AcademicPlannerState._subjectLayer(widget.subjectName) ==
                          'verbal'
                      ? SubjectDomain.verbal
                      : SubjectDomain.numeric,
            ),
            // 45 sn'den uzun süredir içerik gelmediyse "yeniden dene" /
            // "geri dön" seçenekleri sunan alt panel. Loader devam ediyor
            // ama kullanıcı artık sıkışmış değil — eylem alabilir.
            if (_loaderSlow)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bağlantı yavaş görünüyor'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'AI hâlâ üretiyor — biraz bekle veya yeniden dene.'
                              .tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.black54,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10),
                                  side: BorderSide(
                                      color: Colors.black26, width: 1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'Geri'.tr(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: widget.onRetry == null
                                    ? null
                                    : () => _retryStream(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7C3AED),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'Yeniden Dene'.tr(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
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
          ],
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
      // ── Sağ alt FAB sütunu: "başa dön" + "sesli okumayı durdur" ────
      // (Test Sorularını Çöz aksiyonu üst-sağ overflow menüsünde —
      //  testCoz → _onTestQuestionsTap.) _streamFailed iken tüm FAB'lar
      // gizli (boş/başarısız özetten test/scroll mantıksız).
      floatingActionButton: _streamFailed
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Sayfanın başına dön — scroll > 600px iken görünür.
                ValueListenableBuilder<bool>(
                  valueListenable: _showBackToTop,
                  builder: (_, show, __) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: show
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: FloatingActionButton.small(
                              heroTag: 'backToTop',
                              backgroundColor: AppPalette.card(context),
                              foregroundColor:
                                  AppPalette.textPrimary(context),
                              onPressed: _scrollToTop,
                              child: const Icon(
                                Icons.keyboard_arrow_up_rounded,
                                size: 24,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                // TTS Stop — sesli okuma aktifken kırmızı durdur FAB'ı.
                // Kullanıcı dilediği anda kesebilsin; durunca FAB kaybolur.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _ttsPlaying
                      ? FloatingActionButton.small(
                          key: const ValueKey('ttsStop'),
                          heroTag: 'ttsStop',
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          onPressed: _toggleTts,
                          tooltip: 'Sesli okumayı durdur'.tr(),
                          child: const Icon(
                            Icons.stop_rounded,
                            size: 22,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
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
          // A− / A+ yazı boyutu pill — iki ufak buton birleşik kapsülde.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.card(context),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppPalette.textPrimary(context).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => _adjustFontSize(-1),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      child: Text(
                        'A−',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 16,
                    color: AppPalette.textPrimary(context)
                        .withValues(alpha: 0.2),
                  ),
                  InkWell(
                    onTap: () => _adjustFontSize(1),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      child: Text(
                        'A+',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Yardım butonu (?) — sayfanın nasıl çalıştığını açıklayan ekran.
          Padding(
            padding: const EdgeInsets.only(right: 4, top: 5, bottom: 5),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _SummaryHelpPage(),
                ),
              ),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                      color: AppPalette.textPrimary(context)
                          .withValues(alpha: 0.4),
                      width: 1.2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '?',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(context),
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
          // ─ Overflow ⋮ menüsü — tüm gelişmiş özellikler burada ─
          // Oval kenarlı, narin tasarım: dış kapsam radius 22, padding küçük,
          // arka plan AppPalette.bg → item beyaz kartlarıyla kontrast.
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                color: AppPalette.textPrimary(context)),
            tooltip: 'Daha fazla',
            color: AppPalette.bg(context),
            elevation: 10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: AppPalette.border(context),
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            menuPadding: const EdgeInsets.symmetric(vertical: 4),
            constraints: const BoxConstraints(
              minWidth: 200,
              maxWidth: 240,
            ),
            onSelected: _onOverflowMenu,
            itemBuilder: (ctx) => [
              // Test Çöz — en üstte ve vurgulu, ana aksiyon olduğu için.
              _menuItem('testCoz', Icons.quiz_rounded, 'Test Çöz',
                  _orange, enabled: !_streaming),
              _menuItem('toc', Icons.list_alt_rounded, 'Bölümler',
                  const Color(0xFF7C3AED)),
              _menuItem(
                  'bookmark',
                  _bookmarkOffset != null
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  _bookmarkOffset != null
                      ? 'Yer imini kaldır'
                      : 'Yer imi koy',
                  const Color(0xFFFF6A00)),
              _menuItem('search', Icons.search_rounded, 'Konuda ara',
                  const Color(0xFF2563EB)),
              _menuItem(
                  'switchLength',
                  Icons.swap_horiz_rounded,
                  widget.summary.length == _SummaryLength.short
                      ? 'Kapsamlıya geç'
                      : 'Kısaya geç',
                  const Color(0xFF10B981)),
              _menuItem(
                  'hideStrokes',
                  _hideStrokes
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  _hideStrokes
                      ? 'Çizimleri göster'
                      : 'Çizimleri gizle',
                  const Color(0xFF06B6D4)),
              _menuItem(
                'tts',
                _ttsPlaying
                    ? Icons.stop_circle_rounded
                    : Icons.volume_up_rounded,
                _ttsPlaying ? 'Sesli okumayı durdur' : 'Sesli oku',
                const Color(0xFFFBBF24),
              ),
              _menuItem(
                'ttsSpeed',
                Icons.speed_rounded,
                'Sesli okuma hızı (${_ttsSpeedLabel()})',
                const Color(0xFF06B6D4),
              ),
              _menuItem(
                'srs',
                _srsScheduled
                    ? Icons.event_available_rounded
                    : Icons.event_repeat_rounded,
                _srsCompleted
                    ? 'Tekrar planı (tamamlandı)'
                    : _srsScheduled
                        ? 'Tekrar planı (aktif)'
                        : 'Tekrar planına ekle',
                const Color(0xFFFF6A00),
              ),
              _menuItem('stats', Icons.insights_rounded,
                  'Konu istatistikleri', const Color(0xFF2563EB)),
              _menuItem('share', Icons.copy_rounded, 'Özeti kopyala',
                  const Color(0xFFEC4899)),
            ],
          ),
        ],
      ),
      // Klavye açıldığında layout otomatik kaysın (TextField sheet için kritik).
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Asıl içerik (sayfa)
          Column(children: [
          // Üst ince ilerleme çubuğu — kullanıcı özetin neresinde okuduğunu görür.
          ValueListenableBuilder<double>(
            valueListenable: _readProgress,
            builder: (_, p, __) => Container(
              height: 2.5,
              alignment: Alignment.centerLeft,
              color: AppPalette.border(context).withValues(alpha: 0.4),
              child: FractionallySizedBox(
                widthFactor: p,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Arama çubuğu — overflow menüsünden "Konuda ara" ile açılır.
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Konuda kelime ara…'.tr(),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: _toggleSearch,
                  ),
                ],
              ),
            ),
          if (_showColorPicker) _buildColorPickerPanel(),
          // Streaming şeridi sadece HATA durumunda gösterilir; üretim
          // sırasında "AI özeti yazıyor…" yazısı kaldırıldı.
          if (_streamFailed) _buildStreamingBanner(),
          // Tekrar planı zamanı geldiyse turuncu banner — "Tekrarladım ✓".
          // Streaming aktifken gösterme; kafası karışmasın.
          if (!_streaming && _srsIsDue) _buildSrsDueBanner(),
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
                        key: sIdx < _sectionKeys.length
                            ? _sectionKeys[sIdx]
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _wrappedCard(
                            child: _card(
                              header: s.header,
                              headerColor: s.color,
                              body: s.body,
                              sectionIdx: sIdx,
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
          // silgi + kapat. _hideStrokes=true iken tamamen gizlenir.
          if (!_hideStrokes)
            StudyToolbarOverlay(
              topicId: 'note_${widget.summary.id}',
              topicName: widget.summary.topic,
              scrollController: _scrollController,
            ),
          // Sticky section header — scroll edilince üstte mevcut bölüm
          // başlığını gösterir.
          ValueListenableBuilder<int>(
            valueListenable: _currentSectionIdx,
            builder: (_, idx, __) {
              if (idx < 0 || idx >= _cachedNormalSections.length) {
                return const SizedBox.shrink();
              }
              final s = _cachedNormalSections[idx];
              final header = _stripHeaderMarkers(s.header);
              return Positioned(
                top: 4, // progress bar altında
                left: 12,
                right: 12,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: 0.95,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppPalette.card(context)
                            .withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: s.color.withValues(alpha: 0.55),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 14,
                            decoration: BoxDecoration(
                              color: s.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              header,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: s.color,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                          Text(
                            '${idx + 1}/${_cachedNormalSections.length}',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // ── Sayısal ders → sol alt formül butonu + açılır panel ──────
          // Açıkken panel butonun ÜSTÜNDE belirir, içeride scroll vardır.
          // Buton sabit kalır (özet kaydırılırken bile pozisyonunu korur).
          if (_AcademicPlannerState._subjectLayer(widget.subjectName) ==
              'numeric') ...[
            if (_showFormulasPanel) _buildFormulasPanel(context),
            Positioned(
              left: 16,
              bottom: 16,
              child: _buildFormulasFab(),
            ),
          ],
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

  // ═════ FORMÜL PANELİ (sadece sayısal dersler) ═════════════════════════
  /// Sol alt köşede sabit duran küçük "Tüm formülleri oluştur" butonu.
  Widget _buildFormulasFab() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleFormulasPanel,
        borderRadius: BorderRadius.circular(28),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _showFormulasPanel
                  ? const [Color(0xFFEF4444), Color(0xFFDC2626)]
                  : const [Color(0xFF7C3AED), Color(0xFF2563EB)],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: (_showFormulasPanel
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF7C3AED))
                    .withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _showFormulasPanel
                    ? Icons.close_rounded
                    : Icons.functions_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _showFormulasPanel
                    ? 'Kapat'.tr()
                    : 'Tüm formülleri oluştur'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Butonun ÜZERİNDE açılan kart — tam ekran değil, max 60% yükseklik,
  /// içi scroll'lanabilir. AI tarafından üretilen formüller markdown render.
  Widget _buildFormulasPanel(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.62;
    final ink = AppPalette.textPrimary(context);
    return Positioned(
      left: 12,
      right: 12,
      bottom: 68, // butonun hemen üstünde
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                width: 1.4),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık çubuğu
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    const Icon(Icons.functions_rounded,
                        color: Color(0xFF7C3AED), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.summary.topic} — Formüller'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                  height: 1, color: AppPalette.border(context)),
              Flexible(
                child: _loadingFormulas
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : _formulasError != null
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                _formulasError!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: const Color(0xFFEF4444),
                                ),
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                                14, 10, 14, 14),
                            child: MarkdownBody(
                              data: _formulasContent ?? '',
                              shrinkWrap: true,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                p: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: ink,
                                    height: 1.5),
                                strong: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: ink),
                                h3: GoogleFonts.poppins(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF7C3AED),
                                  height: 1.3,
                                ),
                                listBullet: GoogleFonts.poppins(
                                    fontSize: 13, color: ink),
                                listIndent: 18,
                                code: GoogleFonts.firaCode(
                                  fontSize: 12.5,
                                  color: ink,
                                  backgroundColor: AppPalette.border(context)
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
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
    int? sectionIdx,
  }) {
    final bg = AppPalette.resolveCardBg(context, _cardsBgOverride);
    final ink = _cardsTextOverride ??
        (_isDark(bg) ? Colors.white : Colors.black);
    final isCompleted =
        sectionIdx != null && _completedSections.contains(sectionIdx);
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
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      cleanedHeader,
                      style: GoogleFonts.poppins(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: _cardsTextOverride ?? headerColor,
                        letterSpacing: 0.15,
                        height: 1.25,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: headerColor.withValues(alpha: 0.45),
                        decorationThickness: 1.5,
                      ),
                    ),
                  ),
                  if (sectionIdx != null)
                    InkWell(
                      onTap: () => _toggleSectionCompleted(sectionIdx),
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isCompleted
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 22,
                          color: isCompleted
                              ? const Color(0xFF10B981)
                              : headerColor.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // Section uzun bas → Kopyala (#7 Bölüm Bazlı Eylem).
          GestureDetector(
            onLongPress: () => _showSectionActions(cleanedHeader, body),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: ink),
                child: LatexText(
                  // Arama eşleşmesi varsa ★ ile vurgulanır (basit highlight).
                  _searchQuery.isNotEmpty &&
                          body.toLowerCase()
                              .contains(_searchQuery.toLowerCase())
                      ? body.replaceAllMapped(
                          RegExp(RegExp.escape(_searchQuery),
                              caseSensitive: false),
                          (m) => '★${m.group(0)}★')
                      : body,
                  fontSize: _bodyFontSize,
                  lineHeight: 1.65,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bölüm uzun bas → bottom sheet: Kopyala / Paylaş.
  Future<void> _showSectionActions(String header, String body) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  header,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded,
                    color: Color(0xFF7C3AED)),
                title: Text('Bölümü kopyala'.tr()),
                onTap: () => Navigator.of(ctx).pop('copy'),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded,
                    color: Color(0xFF7C3AED)),
                title: Text('Bu bölümü farklı anlat (AI)'.tr()),
                subtitle: Text(
                  'Daha basit, gündelik dilden örneklerle'.tr(),
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.of(ctx).pop('rewrite'),
              ),
              ListTile(
                leading: const Icon(Icons.thumb_up_rounded,
                    color: Color(0xFF10B981)),
                title: Text('İyi anlatılmış'.tr()),
                onTap: () => Navigator.of(ctx).pop('like'),
              ),
              ListTile(
                leading: const Icon(Icons.thumb_down_rounded,
                    color: Color(0xFFEF4444)),
                title: Text('Eksik / yanlış'.tr()),
                onTap: () => Navigator.of(ctx).pop('dislike'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: '$header\n\n$body'));
        if (mounted) _toast('📋 Bölüm kopyalandı.');
        break;
      case 'rewrite':
        _rewriteSectionWithAi(header, body);
        break;
      case 'like':
        _toast('👍 Geri bildirimin alındı.');
        break;
      case 'dislike':
        _toast('👎 Geri bildirimin alındı.');
        break;
    }
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
          // Toggle widget — her soru altında "Çözümü Göster" butonu.
          // Parse başarısız olursa düz LaTeX'e düşer (eski özetler korunur).
          _ExamplesToggleList(body: s.body, ink: ink),
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
      for (final m in markers.keys) {
        if (trim.startsWith(m)) {
          foundMarker = m;
          break;
        }
      }
      // ⭐ "Aklında Kalsın" bloğu artık en son bölüm DEĞİL — ardından
      // 🎯 Kendini Sına / 📝 Örnek Sorular / 📌 Özetle gelebiliyor. Bu bloktayken
      // yalnız bu "kapanış" markerları yeni bölüm açar; diğerleri (🔑, 1️⃣ vb.)
      // ⭐ kartının gövdesinde kalır (eski davranış korunur).
      if (foundMarker != null && inKeyFactsBlock) {
        const closers = {'🎯', '📝', '📌', '⭐'};
        if (!closers.contains(foundMarker)) foundMarker = null;
      }
      if (foundMarker != null) {
        if (foundMarker != '⭐') inKeyFactsBlock = false;
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

// ═══════════════════════════════════════════════════════════════════════════
//  _ExamplesToggleList — Pekiştirme sorularını parse eder; her sorunun
//  altında "Çözümü Göster" butonu, basınca çözüm + cevap açılır/kapanır.
//
//  AI çıktı formatı (academic_planner prompt'tan):
//    **Soru 1:** [metin]
//    A) ...  B) ...  C) ...
//
//    **Çözüm:** [açıklama]
//    **Cevap:** [şık]
//
//  Parser tolerant — markdown bold işaretleri, ekstra boşluk, eksik kısımları
//  graceful handle eder. Parse başarısız (örn. format değişmiş eski özet)
//  → tek bir bütün LaTeX bloğu olarak fallback gösterilir.
// ═══════════════════════════════════════════════════════════════════════════
class _ExamplesToggleList extends StatefulWidget {
  final String body;
  final Color ink;
  const _ExamplesToggleList({required this.body, required this.ink});

  @override
  State<_ExamplesToggleList> createState() => _ExamplesToggleListState();
}

class _ExamplesToggleListState extends State<_ExamplesToggleList> {
  late final List<_ParsedExample> _items = _parseExamples(widget.body);
  final Set<int> _open = <int>{};

  /// "**Soru N:**" ile başlayan blokları yakalar, içinden Çözüm/Cevap çıkarır.
  /// Bold işaretlerini (** **) temizler.
  static List<_ParsedExample> _parseExamples(String raw) {
    final out = <_ParsedExample>[];
    // "**Soru" ya da "Soru" başlığı ile satır başında olan yerlerde böl
    final pattern = RegExp(
        r'(?:^|\n)\s*\*{0,2}\s*Soru\s*\d+\s*[:\.\)]\s*',
        caseSensitive: false);
    final matches = pattern.allMatches(raw).toList();
    if (matches.isEmpty) return const [];
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : raw.length;
      final chunk = raw.substring(start, end).trim();
      // Çözüm ve Cevap satırlarını ayır
      final solIdx = RegExp(r'\*{0,2}\s*(?:Çözüm|Cozum|Solution)\s*[:\.]',
              caseSensitive: false)
          .firstMatch(chunk);
      String questionPart;
      String solutionPart = '';
      String answerPart = '';
      if (solIdx == null) {
        questionPart = chunk;
      } else {
        questionPart = chunk.substring(0, solIdx.start).trim();
        var rest = chunk.substring(solIdx.end).trim();
        // Cevap satırını ayır
        final ansIdx = RegExp(
                r'\*{0,2}\s*(?:Cevap|Answer)\s*[:\.]',
                caseSensitive: false)
            .firstMatch(rest);
        if (ansIdx == null) {
          solutionPart = rest;
        } else {
          solutionPart = rest.substring(0, ansIdx.start).trim();
          answerPart = rest.substring(ansIdx.end).trim();
        }
      }
      // Bold markdown temizliği (** çevresi)
      String clean(String s) =>
          s.replaceAll(RegExp(r'\*{2,}'), '').trim();
      out.add(_ParsedExample(
        index: i + 1,
        questionWithOptions: clean(questionPart),
        solution: clean(solutionPart),
        answer: clean(answerPart),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      // Parser hata — fallback olarak ham içerik
      return DefaultTextStyle.merge(
        style: TextStyle(color: widget.ink),
        child: LatexText(widget.body, fontSize: 13.5, lineHeight: 1.6),
      );
    }
    return DefaultTextStyle.merge(
      style: TextStyle(color: widget.ink),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _buildQuestion(_items[i], i),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestion(_ParsedExample ex, int i) {
    final isOpen = _open.contains(i);
    final hasSolution =
        ex.solution.isNotEmpty || ex.answer.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Soru numarası başlığı
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Soru ${ex.index}',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: widget.ink,
              letterSpacing: 0.15,
            ),
          ),
        ),
        // Soru + şıklar
        LatexText(
          ex.questionWithOptions,
          fontSize: 13.5,
          lineHeight: 1.6,
        ),
        if (hasSolution) ...[
          const SizedBox(height: 10),
          // "Çözümü Göster / Gizle" toggle butonu
          GestureDetector(
            onTap: () {
              setState(() {
                if (isOpen) {
                  _open.remove(i);
                } else {
                  _open.add(i);
                }
              });
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isOpen
                    ? const Color(0xFF7C3AED).withValues(alpha: 0.12)
                    : const Color(0xFF7C3AED).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.40),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: const Color(0xFF7C3AED),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOpen
                        ? 'Çözümü Gizle'.tr()
                        : 'Çözümü Göster'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF7C3AED),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Açıklama bloğu — animasyonlu açılış
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: isOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED)
                            .withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF7C3AED)
                              .withValues(alpha: 0.20),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (ex.solution.isNotEmpty) ...[
                            Row(
                              children: [
                                const Text('🧠',
                                    style: TextStyle(fontSize: 14)),
                                const SizedBox(width: 6),
                                Text(
                                  'Çözüm'.tr(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF6D28D9),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LatexText(
                              ex.solution,
                              fontSize: 13,
                              lineHeight: 1.55,
                            ),
                          ],
                          if (ex.answer.isNotEmpty) ...[
                            if (ex.solution.isNotEmpty)
                              const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('✅',
                                    style: TextStyle(fontSize: 14)),
                                const SizedBox(width: 6),
                                Text(
                                  '${"Cevap".tr()}: ${ex.answer}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF16A34A),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}

class _ParsedExample {
  final int index;
  final String questionWithOptions;
  final String solution;
  final String answer;
  const _ParsedExample({
    required this.index,
    required this.questionWithOptions,
    required this.solution,
    required this.answer,
  });
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
  final _searchCtrl = TextEditingController();
  final Set<String> _savedCustomTopics = {};
  String _searchQuery = '';

  @override
  void dispose() {
    _newTopicCtrl.dispose();
    _searchCtrl.dispose();
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
    // Arama filtresi — case-insensitive contains, boşken hepsini göster.
    final q = _searchQuery.trim().toLowerCase();
    final filteredTopics = q.isEmpty
        ? allTopics
        : allTopics.where((t) => t.toLowerCase().contains(q)).toList();

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
              SizedBox(height: 6),
              // Alt başlık — kullanıcıya bir konu seçmesini iste.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  widget.mode == LibraryMode.questions
                      ? 'Hangi konudan başlamak istersin?'.tr()
                      : 'Hangi konunun özetini görmek istersin?'.tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(context),
                    height: 1.25,
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Ders başlığı altında ince ayırıcı — yumuşak ton
              Container(height: 1, color: Colors.black.withValues(alpha: 0.08)),
              SizedBox(height: 12),
              // ── Konu arama çubuğu — 4+ konu varsa görünür ──────────────
              // Liste 30-50 konuya çıkabiliyor; arama olmadan scroll yorucu.
              if (allTopics.length > 4) ...[
                Container(
                  decoration: BoxDecoration(
                    color: AppPalette.card(context),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppPalette.border(context),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.search_rounded,
                          size: 16,
                          color: AppPalette.textSecondary(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.textPrimary(context),
                          ),
                          cursorColor: AppPalette.textPrimary(context),
                          decoration: InputDecoration(
                            hintText: 'Konu ara…'.tr(),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppPalette.textSecondary(context),
                            ),
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close_rounded,
                              size: 16,
                              color: AppPalette.textSecondary(context)),
                          onPressed: () => setState(() {
                            _searchQuery = '';
                            _searchCtrl.clear();
                          }),
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
                      else if (filteredTopics.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'Eşleşen konu yok'.tr(),
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppPalette.textSecondary(context),
                              ),
                            ),
                          ),
                        )
                      else
                        for (final topic in filteredTopics) _topicRow(topic),
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
    final isQuestions = widget.mode == LibraryMode.questions;
    // Konuya ait kısa/kapsamlı özetleri AYRI say. Aynı konuda max 2 özet var:
    // 1 kısa + 1 kapsamlı. Bu sayıma göre button davranışı:
    //   • 0/2 → "Özet Oluştur" (kullanıcıya kısa/kapsamlı sorulur)
    //   • 1/2 → "Özet Oluştur" (eksik olanı OTOMATIK üretir, sormaz)
    //   • 2/2 → "Tamamlandı" — buton kilitli, dokununca bilgilendirme.
    final subj = widget.getExistingSubject();
    _Summary? shortSum;
    _Summary? compSum;
    for (final s in subj.summaries) {
      if (s.topic.toLowerCase() == topic.toLowerCase()) {
        if (s.length == _SummaryLength.short) {
          shortSum ??= s;
        } else {
          compSum ??= s;
        }
      }
    }
    final summaryCount =
        (shortSum != null ? 1 : 0) + (compSum != null ? 1 : 0);
    final existing = shortSum ?? compSum; // questions mode için ilk varolan
    final hasSummary = existing != null;
    final hasIcon = hasSummary || _savedCustomTopics.contains(topic);
    final summaryFull = !isQuestions && summaryCount >= 2;
    // Questions mode'da sağdaki butonun davranışı:
    //   • testCount < 6  → her tıklama yeni test üretir (eski sonuca gitmez)
    //   • testCount == 6 → buton kilitli, dokununca uyarı snackbar'ı
    final testCount =
        isQuestions && existing != null ? existing.tests.length : 0;
    final limitReached = isQuestions && testCount >= 6;

    final IconData actionIcon;
    final String actionLabel;
    final Color actionBg;
    final Color actionFg;
    if (isQuestions) {
      if (limitReached) {
        actionIcon = Icons.lock_rounded;
        actionLabel = '${'Limit'.tr()} · 6/6';
        actionBg = Color(0xFFE5E7EB);
        actionFg = Colors.black54;
      } else if (testCount > 0) {
        actionIcon = Icons.add_rounded;
        actionLabel = '${'Yeni Test'.tr()} · $testCount/6';
        actionBg = Color(0xFFEFF1F6);
        actionFg = Colors.black;
      } else {
        actionIcon = Icons.auto_awesome_rounded;
        actionLabel = widget._createLabel.tr();
        actionBg = Color(0xFFEFF1F6);
        actionFg = Colors.black;
      }
    } else if (summaryFull) {
      // İki özet de tamamlandı — kilitli görünüm.
      actionIcon = Icons.lock_rounded;
      actionLabel = '${'Tamamlandı'.tr()} · 2/2';
      actionBg = const Color(0xFFE5E7EB);
      actionFg = Colors.black54;
    } else if (summaryCount == 1) {
      // 1 özet var, diğerini otomatik üret.
      actionIcon = Icons.add_rounded;
      actionLabel = widget._createLabel.tr();
      actionBg = const Color(0xFFEFF1F6);
      actionFg = Colors.black;
    } else {
      // Henüz hiç özet yok.
      actionIcon = Icons.auto_awesome_rounded;
      actionLabel = widget._createLabel.tr();
      actionBg = const Color(0xFFEFF1F6);
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
                        'Bu konudan zaten 6 test oluşturdun. Aynı konu için en fazla 6 test oluşturabilirsin.'
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
                    return;
                  }
                  // Summary mode — KISA/KAPSAMLI 2'li sistem:
                  //   • 2/2 dolu: dialog kapatıp bilgi snack'i göster.
                  //   • 1/2 veya 0/2: onGenerateTopic'a aktar; backend
                  //     (_generateForExistingSubject) eksik olanı otomatik
                  //     seçer veya hiçbiri yoksa kullanıcıya sorar.
                  if (summaryFull) {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(context).pop();
                    messenger.showSnackBar(SnackBar(
                      content: Text(
                          'Bu konunun hem kısa hem kapsamlı özeti zaten var.'
                              .tr()),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
                    return;
                  }
                  widget.onGenerateTopic(topic);
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
  /// Mevcut konunun özet içeriği — "Bu konunun özetini hatırlat" sheet'inde
  /// kullanılır. Boşsa buton görünmez.
  final String summaryContent;
  /// Önceki test denemeleri — "Yanlışlardan Tekrar Testi" için.
  /// Tamamlanmış denemelerdeki yanlış cevaplı sorular toplanır.
  final List<_TestAttempt> previousAttempts;
  /// Aynı dersin diğer konuları — "Karışık konular" modunda seçilebilir.
  /// Current topic listede yer almaz.
  final List<_Summary> sameSubjectSummaries;

  const _TestSetupPage({
    required this.subjectName,
    required this.topic,
    required this.attemptIndex,
    this.summaryContent = '',
    this.previousAttempts = const [],
    this.sameSubjectSummaries = const [],
  });

  @override
  State<_TestSetupPage> createState() => _TestSetupPageState();
}

class _TestSetupPageState extends State<_TestSetupPage> {
  _TestConfig _cfg = _TestConfig();
  bool _loaded = false;
  // Karışık konular toggle + seçili konu adları.
  bool _mixTopics = false;
  final Set<String> _selectedExtraTopics = {};

  // Önceki denemelerden yanlışlar — once hesaplanır, cached tutulur.
  late final List<TestQuestion> _wrongs = _collectWrongs();

  @override
  void initState() {
    super.initState();
    _loadCfg();
  }

  Future<void> _loadCfg() async {
    final loaded = await _TestConfig.loadFromPrefs();
    if (!mounted) return;
    setState(() {
      _cfg = loaded;
      _loaded = true;
    });
  }

  // Bütün tamamlanmış denemelerden yanlış cevaplı soruları topla — soru
  // metnine göre dedupe.
  List<TestQuestion> _collectWrongs() {
    final out = <TestQuestion>[];
    final seen = <String>{};
    for (final att in widget.previousAttempts) {
      if (!att.completed) continue;
      try {
        final qs = parseTestQuestions(att.content);
        for (int i = 0; i < qs.length; i++) {
          final ua = att.answers[i];
          if (ua == null) continue; // boş bırakılan → yanlış sayılmasın
          if (ua.toUpperCase() == qs[i].ans) continue; // doğru
          final key =
              qs[i].q.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
          if (seen.add(key)) out.add(qs[i]);
        }
      } catch (_) {}
    }
    return out;
  }

  void _applyPreset(int count, String difficulty, String timeMode,
      {String questionType = 'mc'}) {
    setState(() {
      _cfg.count = count;
      _cfg.difficulty = difficulty;
      _cfg.timeMode = timeMode;
      _cfg.questionType = questionType;
    });
  }

  String _estimatedDurationLabel() {
    final perQ = _cfg.timeMode == 'relax' ? 30 : _cfg.timeLimitSeconds;
    final totalSec = _cfg.count * perQ;
    if (totalSec < 60) return '~${totalSec}s';
    final m = (totalSec / 60).ceil();
    return '~$m dk';
  }

  Future<void> _onSubmit() async {
    // Onay dialog'u kaldırıldı — kullanıcı "Teste Başla" diyince direkt
    // pop edip arka planda test üretimini başlatır.
    // Karışık konular: seçili extra konuları cfg'ye yedir.
    if (_mixTopics && _selectedExtraTopics.isNotEmpty) {
      _cfg.extraTopics = _selectedExtraTopics.toList();
    }
    await _cfg.persistToPrefs();
    if (!mounted) return;
    Navigator.of(context).pop(_cfg);
  }

  String _difficultyLabel(String d) {
    switch (d) {
      case 'easy':
        return 'Kolay';
      case 'hard':
        return 'Zor';
      default:
        return 'Orta';
    }
  }

  String _timeModeLabel() {
    switch (_cfg.timeMode) {
      case 'normal':
        return '90s/soru';
      case 'race':
        return '45s/soru';
      case 'custom':
        return '${_cfg.customSecondsPerQuestion}s/soru';
      default:
        return 'süresiz';
    }
  }

  void _openSummarySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, ctrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.textSecondary(context)
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.menu_book_rounded,
                      color: Color(0xFF7C3AED), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.topic} — ${'Konu Özeti'.tr()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  controller: ctrl,
                  child: SelectableText(
                    widget.summaryContent,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      height: 1.55,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Yanlışlardan Tekrar Testi'ne geç → cfg.fromWrongs=true + count=wrongs.length
  // Onay dialog'undan geçmesin (AI çağrısı yok, kota tüketilmiyor).
  void _replayWrongs() {
    if (_wrongs.isEmpty) return;
    _cfg.fromWrongs = true;
    _cfg.wrongsToReuse = _wrongs;
    _cfg.count = _wrongs.length.clamp(1, 40);
    Navigator.of(context).pop(_cfg);
  }

  @override
  Widget build(BuildContext context) {
    // Dialog zemini beyaz — resimde de beyaz, pill'ler çevresinde net çıkar.
    const pageBg = Colors.white;
    if (!_loaded) {
      return Dialog(
        backgroundColor: pageBg,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22)),
        child: const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Dialog(
      backgroundColor: pageBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Üst başlık — "Test Ayarları" (her iki akış için aynı) ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 56, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Test Ayarları'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF6B7B95),
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── HIZLI YOLLAR ─────────────────────────────────────
                    // Yanlışlardan tekrar (tamamlanmış denemede yanlış varsa,
                    // AI'sız + kota harcamaz) ve özeti hatırlat (özet varsa).
                    if (_wrongs.isNotEmpty) ...[
                      _quickActionTile(
                        icon: Icons.replay_rounded,
                        tint: const Color(0xFFFF6A00),
                        title: 'Yanlışlardan Tekrar',
                        subtitle:
                            '${_wrongs.length} yanlış soruyu yeniden çöz · ücretsiz',
                        onTap: _replayWrongs,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (widget.summaryContent.trim().isNotEmpty) ...[
                      _quickActionTile(
                        icon: Icons.menu_book_rounded,
                        tint: const Color(0xFF7C3AED),
                        title: 'Özeti Hatırlat',
                        subtitle: 'Teste başlamadan konuyu hızlıca gözden geçir',
                        onTap: _openSummarySheet,
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Hazır şablonlar — tek dokunuşla ayar (Hızlı Tekrar /
                    // TYT Provası / Sınav Simülasyonu).
                    _quickTemplatesRow(),
                    const SizedBox(height: 14),
                    // Sıralama: Soru Tipi → Soru Sayısı → Zorluk → Süre Modu
                    // Soru Tipi — her label 2 kelime, alt alta satırlar (\n).
                    _TestPillGroup(
                      label: 'Soru Tipi'.tr(),
                      options: const [
                        _TestPillOpt('mc', '', 'Çoktan\nSeçmeli', ''),
                        _TestPillOpt('tf', '', 'Doğru\nYanlış', ''),
                        _TestPillOpt('fill', '', 'Boşluk\nDoldurma', ''),
                      ],
                      selected: _cfg.questionType,
                      titleFontSize: 12,
                      verticalPadding: 12,
                      onSelect: (v) =>
                          setState(() => _cfg.questionType = v),
                    ),
                    // Soru Sayısı — büyük rakamlar, daha uzun kutular.
                    _TestPillGroup(
                      label: 'Soru Sayısı'.tr(),
                      options: const [
                        _TestPillOpt('5', '', '5', ''),
                        _TestPillOpt('10', '', '10', ''),
                        _TestPillOpt('15', '', '15', ''),
                        _TestPillOpt('20', '', '20', ''),
                      ],
                      selected: '${_cfg.count}',
                      titleFontSize: 20,
                      verticalPadding: 18,
                      onSelect: (v) =>
                          setState(() => _cfg.count = int.parse(v)),
                    ),
                    // Zorluk Seviyesi — incelmiş Y.
                    _TestPillGroup(
                      label: 'Zorluk Seviyesi'.tr(),
                      options: const [
                        _TestPillOpt('easy', '🌱', 'Kolay', ''),
                        _TestPillOpt('medium', '⚖️', 'Orta', '',
                            tone: Color(0xFFD97706),
                            toneBg: Color(0xFFFEF3C7)),
                        _TestPillOpt('hard', '🔥', 'Zor', ''),
                      ],
                      selected: _cfg.difficulty,
                      titleFontSize: 13,
                      verticalPadding: 6,
                      onSelect: (v) => setState(() => _cfg.difficulty = v),
                    ),
                    // Süre Modu — incelmiş Y.
                    _TestPillGroup(
                      label: 'Süre Modu'.tr(),
                      options: const [
                        _TestPillOpt('relax', '🧘', 'Rahat', 'Süresiz',
                            tone: Color(0xFF374151),
                            toneBg: Color(0xFFE5E7EB)),
                        _TestPillOpt(
                            'normal', '⏱️', 'Normal', '90s/soru'),
                        _TestPillOpt('race', '⚡', 'Hız', '45s/soru'),
                      ],
                      selected: _cfg.timeMode,
                      titleFontSize: 13,
                      verticalPadding: 6,
                      onSelect: (v) => setState(() => _cfg.timeMode = v),
                    ),
                    // ── KARIŞIK KONULAR ─────────────────────────────────
                    if (widget.sameSubjectSummaries.isNotEmpty)
                      _mixTopicsSection(),
                  ],
                ),
              ),
            ),
            // ── ALT: "Teste Başla" (turuncu oval) ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: GestureDetector(
                onTap: _onSubmit,
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
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Teste Başla'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Sağ üstte kapat butonu — çerçevesiz daire
        Positioned(
          right: 8,
          top: 8,
          child: Material(
            color: AppPalette.card(context),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded,
                    size: 16, color: AppPalette.textPrimary(context)),
              ),
            ),
          ),
        ),
          ],
        ),
      ),
    );
  }

  // ── Hazır şablonlar — 3 chip yan yana ────────────────────────────────
  Widget _quickTemplatesRow() {
    Widget chip({
      required String emoji,
      required String label,
      required String hint,
      required Color tint,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint.withValues(alpha: 0.16), tint.withValues(alpha: 0.04)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tint.withValues(alpha: 0.45), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: tint,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(context),
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
        chip(
          emoji: '⚡',
          label: 'Hızlı Tekrar',
          hint: '5 · Kolay · Rahat',
          tint: const Color(0xFF10B981),
          onTap: () => _applyPreset(5, 'easy', 'relax'),
        ),
        const SizedBox(width: 8),
        chip(
          emoji: '🎯',
          label: 'TYT Provası',
          hint: '20 · Orta · 45s',
          tint: const Color(0xFFFF6A00),
          onTap: () => _applyPreset(20, 'medium', 'race'),
        ),
        const SizedBox(width: 8),
        chip(
          emoji: '🏆',
          label: 'Sınav Simülasyonu',
          hint: '20 · Zor · 90s',
          tint: const Color(0xFF7C3AED),
          onTap: () => _applyPreset(20, 'hard', 'normal',
              questionType: 'mixed'),
        ),
      ],
    );
  }

  // ── Tek tıklık aksiyon kartı (özet hatırlat / yanlışlardan tekrar) ───
  Widget _quickActionTile({
    required IconData icon,
    required Color tint,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tint.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 19, color: tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                  Text(
                    subtitle.tr(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: AppPalette.textSecondary(context),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: Color(0xFF6B7280)),
          ],
        ),
      ),
    );
  }

  // ── Özel süre slider'ı (30–120s soru başına) ─────────────────────────
  Widget _customTimeSlider() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18, top: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border(context), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Soru başına süre'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_cfg.customSecondsPerQuestion} sn',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: _orange,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: _cfg.customSecondsPerQuestion.toDouble(),
              min: 30,
              max: 120,
              divisions: 18, // 5s'lik adım
              activeColor: _orange,
              onChanged: (v) {
                setState(() {
                  _cfg.customSecondsPerQuestion = v.round();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Karışık konular: toggle + multi-select chip listesi ──────────────
  Widget _mixTopicsSection() {
    final others = widget.sameSubjectSummaries
        .where((s) => s.topic.toLowerCase().trim() !=
            widget.topic.toLowerCase().trim())
        .toList();
    if (others.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18, top: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border(context), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shuffle_rounded,
                    size: 16, color: Color(0xFFEC4899)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'KARIŞIK KONULAR'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.textSecondary(context),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: _mixTopics,
                  activeThumbColor: const Color(0xFFEC4899),
                  onChanged: (v) => setState(() {
                    _mixTopics = v;
                    if (!v) _selectedExtraTopics.clear();
                  }),
                ),
              ],
            ),
            if (_mixTopics) ...[
              const SizedBox(height: 4),
              Text(
                'Birden fazla konudan karışık soru üret'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppPalette.textSecondary(context),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in others)
                    GestureDetector(
                      onTap: () => setState(() {
                        if (_selectedExtraTopics.contains(s.topic)) {
                          _selectedExtraTopics.remove(s.topic);
                        } else {
                          _selectedExtraTopics.add(s.topic);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _selectedExtraTopics.contains(s.topic)
                              ? const Color(0xFFEC4899)
                                  .withValues(alpha: 0.15)
                              : AppPalette.bg(context),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _selectedExtraTopics.contains(s.topic)
                                ? const Color(0xFFEC4899)
                                : AppPalette.border(context),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          s.topic,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _selectedExtraTopics.contains(s.topic)
                                ? const Color(0xFFEC4899)
                                : AppPalette.textPrimary(context),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
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
  // Pill yüksekliği ve title font boyutu — gruptan gruba değişebilsin
  // (Soru Sayısı büyük, Zorluk/Süre Modu ince).
  final double verticalPadding;
  final double titleFontSize;
  const _TestPillGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.verticalPadding = 12,
    this.titleFontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bölüm başlığı — gri-mavi, normal weight (resimdeki gibi).
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF6B7B95),
                letterSpacing: 0.2,
                height: 1.1,
              ),
            ),
          ),
          // Pill satırı — her pill bağımsız kare-rounded kart.
          Row(
            children: [
              for (int i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onSelect(options[i].value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: EdgeInsets.symmetric(
                          horizontal: 4, vertical: verticalPadding),
                      decoration: BoxDecoration(
                        // Seçili → yeşil arka plan, beyaz yazı.
                        // Seçilmemiş → beyaz arka plan, siyah yazı.
                        color: selected == options[i].value
                            ? const Color(0xFF10B981)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected == options[i].value
                              ? const Color(0xFF10B981)
                              : Colors.black.withValues(alpha: 0.18),
                          width: selected == options[i].value ? 2 : 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (options[i].emoji.isNotEmpty) ...[
                            Text(options[i].emoji,
                                style: const TextStyle(fontSize: 28)),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            options[i].title,
                            // 2 kelimelik başlıklarda \n ile alt satıra düşer.
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w800,
                              color: selected == options[i].value
                                  ? Colors.white
                                  : Colors.black,
                              height: 1.15,
                            ),
                          ),
                          if (options[i].hint.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              options[i].hint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: selected == options[i].value
                                    ? Colors.white.withValues(alpha: 0.85)
                                    : const Color(0xFF6B7B95),
                                height: 1.1,
                              ),
                            ),
                          ],
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
enum _TestPickerMode { testlerim }
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
                        onNewTest: s.tests.length >= 6
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
    final atLimit = testCount >= 6;
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
                  label: atLimit ? 'Limit · 6/6' : 'Yeni Test Oluştur',
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

// ═══════════════════════════════════════════════════════════════════════════
//  _SummaryHelpPage — Özet detay sayfasının "Nasıl Çalışır?" rehberi.
//  Sağ üstteki (?) butonundan açılır; tüm UI öğelerini ve hareketli araç
//  çubuğunu net bir şekilde anlatır.
// ═══════════════════════════════════════════════════════════════════════════
class _SummaryHelpPage extends StatelessWidget {
  const _SummaryHelpPage();

  @override
  Widget build(BuildContext context) {
    final bg = AppPalette.bg(context);
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        foregroundColor: ink,
        title: Text(
          'Sayfa Nasıl Çalışır?'.tr(),
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          // ── Üst tanıtım (kısa) ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF7C3AED).withValues(alpha: 0.12),
                  const Color(0xFF2563EB).withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.30),
                  width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_stories_rounded,
                    size: 22, color: Color(0xFF7C3AED)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Konuyu oku, üstüne not al, sesli dinle, planla, tekrar et — her şey burada.'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: ink,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ════════ ÜST BAR ════════
          _groupHeader(context, '📌 ÜST BAR'),
          _section(
            context,
            icon: Icons.palette_rounded,
            iconColor: const Color(0xFFDB2777),
            title: 'Renk Seç',
            body: 'Sağ üstteki renkli kapsül → sayfanın arka planını, '
                'başlık ve kart renklerini değiştir. Seçimin bu konuya '
                'özel kaydedilir.',
          ),
          _section(
            context,
            icon: Icons.text_fields_rounded,
            iconColor: const Color(0xFF2563EB),
            title: 'Yazı Boyutu (A− / A+)',
            body: 'Yazı boyutunu küçült veya büyüt (12–22 punto). Tercihin '
                'tüm özetlerde geçerli olur.',
          ),
          _section(
            context,
            icon: Icons.help_outline_rounded,
            iconColor: const Color(0xFF7C3AED),
            title: 'Yardım (?)',
            body: 'Bu sayfa — her özelliğin nasıl çalıştığını anlatır.',
          ),
          _section(
            context,
            icon: Icons.more_vert_rounded,
            iconColor: const Color(0xFF06B6D4),
            title: '⋮ Menü',
            body: 'Sayfanın tüm gelişmiş özellikleri burada — her satır '
                'kendi mini kartında. Aşağıda tek tek anlattım.',
          ),

          // ════════ MENÜ İÇERİĞİ ════════
          _groupHeader(context, '🎛️ ⋮ MENÜ İÇERİĞİ'),
          _subItem(context,
              icon: Icons.quiz_rounded,
              color: const Color(0xFFFF6A00),
              title: 'Test Çöz',
              body: 'Bu konunun testini başlatır. Yarım kalan varsa '
                  'kaldığın yerden devam edersin, yoksa yeni test üretilir.'),
          _subItem(context,
              icon: Icons.list_alt_rounded,
              color: const Color(0xFF7C3AED),
              title: 'Bölümler',
              body: 'Tüm ana başlıkları VE alt başlıkları sırayla gösterir. '
                  'Bir satıra dokunarak doğrudan o bölüme atlarsın.'),
          _subItem(context,
              icon: Icons.bookmark_rounded,
              color: const Color(0xFFFF6A00),
              title: 'Yer İmi',
              body: 'O anki konumunu kaydeder. Bir sonraki açılışta '
                  '"Kaldığın yerden devam?" snackbar\'ı çıkar.'),
          _subItem(context,
              icon: Icons.search_rounded,
              color: const Color(0xFF2563EB),
              title: 'Konuda Ara',
              body: 'Özetin içinde kelime ara — eşleşen yerler ★ ile '
                  'vurgulanır.'),
          _subItem(context,
              icon: Icons.swap_horiz_rounded,
              color: const Color(0xFF10B981),
              title: 'Kısa ↔ Kapsamlı',
              body: 'Aynı konunun diğer versiyonuna geç. Her konu için '
                  'en fazla 1 Kısa + 1 Kapsamlı özet vardır.'),
          _subItem(context,
              icon: Icons.visibility_off_rounded,
              color: const Color(0xFF06B6D4),
              title: 'Çizimleri Gizle / Göster',
              body: 'Kalemle yaptığın çizimleri ve vurguları geçici '
                  'gizler — sınava hazırlanırken "boş özet" görünümü.'),
          _subItem(context,
              icon: Icons.volume_up_rounded,
              color: const Color(0xFFFBBF24),
              title: 'Sesli Oku',
              body: 'Özeti baştan sona sesli oku. Sembol, emoji ve '
                  'formülleri ATLAR — insansı akış. Konuşma başlayınca '
                  'sağ altta KIRMIZI durdur butonu çıkar.'),
          _subItem(context,
              icon: Icons.speed_rounded,
              color: const Color(0xFF06B6D4),
              title: 'Sesli Okuma Hızı',
              body: '0.5x (yavaş, öğrenme) · 1x (normal) · 1.5x (hızlı) · '
                  '2x (çok hızlı, tekrar). Tercihin kaydedilir.'),
          _subItem(context,
              icon: Icons.event_repeat_rounded,
              color: const Color(0xFFFF6A00),
              title: 'Tekrar Planı (Aralıklı Tekrar)',
              body: 'Bilimsel "spaced repetition": konuyu 1, 3, 7, 14, 30. '
                  'günlerde tekrar et → uzun süreli belleğe geç. Tüm '
                  'bölümleri tamamlayınca plan otomatik başlar; menüden de '
                  'manuel başlatabilirsin.'),
          _subItem(context,
              icon: Icons.insights_rounded,
              color: const Color(0xFF2563EB),
              title: 'Konu İstatistikleri',
              body: 'Toplam çalışma süren, tamamladığın bölümler, '
                  'başladığın gün, tekrar planı durumu ve test denemeleri '
                  '(ortalama doğru %).'),
          _subItem(context,
              icon: Icons.copy_rounded,
              color: const Color(0xFFEC4899),
              title: 'Özeti Kopyala',
              body: 'Özet panoya kopyalanır + arkadaşına göndermek '
                  'istersen Paylaş sheet\'i açılır (WhatsApp, Telegram, '
                  'SMS, e-posta, vs.).'),

          // ════════ SAYFA İÇİ ÖZELLİKLER ════════
          _groupHeader(context, '📖 SAYFA İÇİ'),
          _section(
            context,
            icon: Icons.title_rounded,
            iconColor: const Color(0xFF2563EB),
            title: 'Başlık Kartı',
            body: 'Üstteki kart ders + konu adını, ⚡ Kısa / 📖 Kapsamlı '
                'rozetini, tahmini okuma süresini ve % tamamlanma oranını '
                'gösterir.',
          ),
          _section(
            context,
            icon: Icons.linear_scale_rounded,
            iconColor: const Color(0xFF7C3AED),
            title: 'Üst İlerleme Çubuğu',
            body: 'AppBar\'ın altındaki ince mor-mavi şerit, özetin '
                'neresini okuduğunu gösterir.',
          ),
          _section(
            context,
            icon: Icons.push_pin_rounded,
            iconColor: const Color(0xFF06B6D4),
            title: 'Yapışan Bölüm Başlığı',
            body: 'Aşağı kaydırdıkça hangi bölümde olduğunu üstte küçük '
                'bir kapsülde görürsün — sağda "3/7" ile kaçıncı bölüm '
                'olduğunu söyler.',
          ),
          _section(
            context,
            icon: Icons.check_circle_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'Bölüm Tamamla (✓)',
            body: 'Her bölüm başlığının sağındaki yuvarlak işaret. '
                'Tıkladığında bölüm "öğrendim" olarak işaretlenir, '
                'başlık üzerinde çizgi belirir. Tüm bölümler tamamlanınca '
                'TEKRAR PLANI otomatik başlar.',
          ),
          _section(
            context,
            icon: Icons.notifications_active_rounded,
            iconColor: const Color(0xFFFF6A00),
            title: 'Tekrar Zamanı Banner\'ı',
            body: 'Aktif tekrar planında bir kontrol günü geldiyse üstte '
                'turuncu bir bant çıkar. "Tekrarladım ✓" → bir sonraki '
                'aralığa geçer (1 → 3 → 7 → 14 → 30 gün).',
          ),
          _section(
            context,
            icon: Icons.touch_app_rounded,
            iconColor: const Color(0xFFA855F7),
            title: 'Bölüme Uzun Bas',
            body: 'Herhangi bir bölümü UZUN BAS → "Kopyala", "Bu bölümü '
                'farklı anlat (AI)" veya "İyi / Eksik" geri bildirim '
                'seçenekleri.',
          ),

          // ════════ SAĞ ALT FAB ════════
          _groupHeader(context, '🎯 SAĞ ALT BUTONLAR'),
          _section(
            context,
            icon: Icons.keyboard_arrow_up_rounded,
            iconColor: const Color(0xFF2563EB),
            title: 'Başa Dön',
            body: 'Aşağı 600px\'den fazla kaydırınca beyaz yuvarlak FAB '
                'belirir — tıkla, sayfanın başına süzülerek döner.',
          ),
          _section(
            context,
            icon: Icons.stop_rounded,
            iconColor: const Color(0xFFEF4444),
            title: 'Sesli Okuma Durdur',
            body: 'TTS aktifken kırmızı durdur FAB\'ı çıkar — istediğin '
                'anda kes. Durduğunda FAB kaybolur, yeniden okutursan '
                'tekrar çıkar.',
          ),

          // ════════ ARAÇ ÇUBUĞU ════════
          _groupHeader(context, '✏️ HAREKETLİ ARAÇ ÇUBUĞU'),
          _section(
            context,
            icon: Icons.menu_book_rounded,
            iconColor: const Color(0xFF7C3AED),
            title: 'Sol Kenardaki Yuvarlak Buton',
            body: 'Sürüklenebilir. Tıkla, 3 araç açılır:',
          ),
          _subItem(context,
              icon: Icons.palette_rounded,
              color: const Color(0xFFEC4899),
              title: 'Renk Paleti (Vurgulayıcı)',
              body: '16 renkle metni vurgula — yatay parmak ile Serbest '
                  'veya Düz Çizgi.'),
          _subItem(context,
              icon: Icons.create_rounded,
              color: const Color(0xFFEF4444),
              title: 'Kalem',
              body: '16 renk + 3 kalınlık. Çizmeye Başla → Yuvarlak / '
                  'Dikdörtgen / Serbest seçeneklerinden biriyle çiz.'),
          _subItem(context,
              icon: Icons.close_rounded,
              color: Colors.white,
              title: 'Kapat',
              body: 'Aracı kapatır. Çizimlerin saklanır.'),

          const SizedBox(height: 8),
          _tipBox(
            context,
            'Tüm çizimlerin bu konuya kayıt edilir. Sayfayı kapatıp açsan '
                'da aynı yerde durur. Çizimi UZUN BASIP başka yere '
                'taşıyabilirsin. Renk/Kalem panelleri yapışan başlığın '
                'altında açılır — üst üste binmez.',
          ),

          // ════════ İPUÇLARI ════════
          _groupHeader(context, '💡 İPUÇLARI'),
          _section(
            context,
            icon: Icons.lightbulb_rounded,
            iconColor: const Color(0xFFFBBF24),
            title: 'Püf Noktalar',
            body: '• Tablonun sağ üstündeki "Tabloyu Tam Ekran Yap" → '
                'yatay geniş ekran.\n'
                '• Konu kartına UZUN BAS → Yeniden Oluştur veya Sil.\n'
                '• AI yazarken sayfa kaymaz; bağlantı koparsa "Tekrar Dene".\n'
                '• Tekrar planını overflow menüsünden "Sıfırla" ile '
                'baştan başlatabilirsin.\n'
                '• Sesli okuma sembolleri okumaz — ⚡, 📖, ▸, • gibi '
                'işaretler atlanır, insansı akış kalır.',
          ),

          const SizedBox(height: 12),
          Center(
            child: Text(
              'İyi çalışmalar! 📚',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppPalette.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // — Yardımcı: grup başlığı (Üst Bar, Menü İçeriği, vb.) —
  Widget _groupHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: AppPalette.textSecondary(context),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // — Yardımcı: tam başlıklı bölüm kartı —
  Widget _section(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    final ink = AppPalette.textPrimary(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppPalette.border(context).withValues(alpha: 0.6),
            width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body.tr(),
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: ink.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // — Yardımcı: alt madde (toolbar buton açıklaması) —
  Widget _subItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    final ink = AppPalette.textPrimary(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: ink.withValues(alpha: 0.80),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // — Yardımcı: bilgi kutusu —
  Widget _tipBox(BuildContext context, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFFBBF24).withValues(alpha: 0.45),
            width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_rounded,
              size: 18, color: Color(0xFFFBBF24)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.tr(),
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppPalette.textPrimary(context).withValues(alpha: 0.85),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
