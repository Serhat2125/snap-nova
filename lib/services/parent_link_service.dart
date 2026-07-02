// ═══════════════════════════════════════════════════════════════════════════
//  ParentLinkService — Ebeveyn-çocuk hesap bağlantı yönetimi.
//
//  Firestore yapısı:
//    parent_links/{parentUid}/children/{childUid}    → bağlı çocuklar
//        {childUsername, childDisplayName, linkedAt, status: 'pending'|'active'|'revoked'}
//    child_invites/{childUid}/from/{parentUid}        → çocuğun gelen istekleri
//        {parentUsername, parentDisplayName, requestedAt, status}
//
//  Akış:
//    1) Ebeveyn çocuğun username veya davet kodunu girer
//    2) requestLink() → her iki tarafa "pending" doc yazar
//    3) Çocuk uygulamada bildirim görür → kabul/red eder
//    4) Çocuk kabul edince her iki taraf "active" olur
//    5) Ebeveyn child_invites'tan stats okur
//
//  Anti-fraud: Çocuk kendisi onaylamadıkça ebeveyn veri göremez.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'class_service.dart';
import 'homework_service.dart';

enum LinkRequestResult {
  success,        // İstek oluşturuldu
  alreadyLinked,  // Zaten bağlı
  pending,        // İstek zaten beklemede
  childNotFound,  // Username'de çocuk yok
  selfLink,       // Kendi hesabına bağlanmaya çalıştı
  notAuthed,      // Giriş yapılmamış
  invalidCode,    // Kod formatı hatalı
  codeExpired,    // Kodun süresi dolmuş ya da bulunamadı
  error,
}

/// Çocuk profilinde üretilen kısa-ömürlü ebeveyn bağlantı kodu.
/// Firestore: `parent_link_codes/{code}` → {childUid, createdAt, expiresAt}
class ChildLinkCode {
  final String code;            // örn "EBEV-K7M3Q9"
  final DateTime expiresAt;
  const ChildLinkCode({required this.code, required this.expiresAt});
}

class LinkedChild {
  final String uid;
  final String username;
  final String displayName;
  final String avatar;
  final DateTime linkedAt;
  final String status; // 'pending' | 'active' | 'revoked'

  const LinkedChild({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.avatar,
    required this.linkedAt,
    required this.status,
  });

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';

  factory LinkedChild.fromMap(String uid, Map<String, dynamic> m) {
    DateTime when = DateTime.now();
    final ts = m['linkedAt'];
    if (ts is Timestamp) when = ts.toDate();
    return LinkedChild(
      uid: uid,
      username: (m['childUsername'] ?? '').toString(),
      displayName: (m['childDisplayName'] ?? '').toString(),
      avatar: (m['childAvatar'] ?? '👤').toString(),
      linkedAt: when,
      status: (m['status'] ?? 'pending').toString(),
    );
  }
}

class ParentInvite {
  final String parentUid;
  final String parentUsername;
  final String parentDisplayName;
  final DateTime requestedAt;
  final String status;

  const ParentInvite({
    required this.parentUid,
    required this.parentUsername,
    required this.parentDisplayName,
    required this.requestedAt,
    required this.status,
  });

  factory ParentInvite.fromMap(String parentUid, Map<String, dynamic> m) {
    DateTime when = DateTime.now();
    final ts = m['requestedAt'];
    if (ts is Timestamp) when = ts.toDate();
    return ParentInvite(
      parentUid: parentUid,
      parentUsername: (m['parentUsername'] ?? '').toString(),
      parentDisplayName: (m['parentDisplayName'] ?? '').toString(),
      requestedAt: when,
      status: (m['status'] ?? 'pending').toString(),
    );
  }
}

/// Ebeveyn paneli "öğretmen duyuruları" kartı için hafif DTO.
class ParentAnnouncement {
  final String className;
  final String message;
  final String teacherName;
  final DateTime when;
  const ParentAnnouncement({
    required this.className,
    required this.message,
    required this.teacherName,
    required this.when,
  });
}

/// Ebeveyn paneli "yaklaşan ödevler" kartı için hafif DTO.
class ParentUpcomingHomework {
  final String classId;
  final String className;
  final String title;
  final String subject;
  final DateTime dueAt;
  final bool submitted;
  const ParentUpcomingHomework({
    required this.classId,
    required this.className,
    required this.title,
    required this.subject,
    required this.dueAt,
    required this.submitted,
  });

  bool get isOverdue => DateTime.now().isAfter(dueAt);
}

/// Ebeveyn paneli "öğretmen notları/tebrikleri" kartı için hafif DTO.
class ParentTeacherNote {
  final String className;
  final String text;
  final String kind; // 'note' | 'praise'
  final DateTime when;
  const ParentTeacherNote({
    required this.className,
    required this.text,
    required this.kind,
    required this.when,
  });

  bool get isPraise => kind == 'praise';
}

/// Ebeveyn paneli "Bilgi Ligi başarıları" kartı için hafif DTO.
class ParentLeagueStats {
  final int attempts;
  final double averageScore;
  final double bestScore;
  final int streakDays;
  final DateTime? lastAttemptAt;
  const ParentLeagueStats({
    required this.attempts,
    required this.averageScore,
    required this.bestScore,
    required this.streakDays,
    required this.lastAttemptAt,
  });

  bool get hasData => attempts > 0;
}

class ParentLinkService {
  ParentLinkService._();
  static final _fs = FirebaseFirestore.instance;

  static String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  /// Ebeveyn → çocuk username ile bağlantı isteği.
  static Future<LinkRequestResult> requestLink(String childUsername) async {
    final myUid = _myUid;
    if (myUid == null) return LinkRequestResult.notAuthed;
    final cleanUsername = childUsername.trim().toLowerCase();
    if (cleanUsername.isEmpty) return LinkRequestResult.childNotFound;

    try {
      // Çocuğun uid'ini bul
      final query = await _fs
          .collection('users')
          .where('username', isEqualTo: cleanUsername)
          .limit(1)
          .get();
      if (query.docs.isEmpty) return LinkRequestResult.childNotFound;
      final childDoc = query.docs.first;
      final childUid = childDoc.id;
      if (childUid == myUid) return LinkRequestResult.selfLink;
      final childData = childDoc.data();

      // Ebeveyn kendi profilini oku (çocuğa göstermek için)
      final myProfile = await _fs.collection('users').doc(myUid).get();
      final myData = myProfile.data() ?? const <String, dynamic>{};

      // Mevcut bağlantı var mı?
      final existing = await _fs
          .collection('parent_links')
          .doc(myUid)
          .collection('children')
          .doc(childUid)
          .get();
      if (existing.exists) {
        final st = (existing.data()?['status'] ?? '').toString();
        if (st == 'active') return LinkRequestResult.alreadyLinked;
        if (st == 'pending') return LinkRequestResult.pending;
        // 'rejected' veya başka bir eski durum: aşağıdaki set() Firestore'da
        // UPDATE sayılır ve kurallar parent_links/child_invites update'ini
        // yalnız ['status','acceptedAt'] alanlarına kısıtladığından 5 alanlık
        // yazım permission-denied alır. Eski kayıtları SİL → set() CREATE olur,
        // böylece çocuk bir kez reddetse de ebeveyn yeniden istek gönderebilir.
        try {
          await _fs.collection('parent_links').doc(myUid)
              .collection('children').doc(childUid).delete();
        } catch (_) {}
        try {
          await _fs.collection('child_invites').doc(childUid)
              .collection('from').doc(myUid).delete();
        } catch (_) {}
      }

      final now = FieldValue.serverTimestamp();
      // Hem ebeveynin koleksiyonuna hem çocuğun gelen kutusuna yaz.
      final batch = _fs.batch();
      batch.set(
        _fs.collection('parent_links').doc(myUid)
            .collection('children').doc(childUid),
        {
          'childUsername': childData['username'] ?? '',
          'childDisplayName': childData['displayName'] ?? '',
          'childAvatar': childData['avatar'] ?? '👤',
          'linkedAt': now,
          'status': 'pending',
        },
        SetOptions(merge: true),
      );
      batch.set(
        _fs.collection('child_invites').doc(childUid)
            .collection('from').doc(myUid),
        {
          'parentUsername': myData['username'] ?? '',
          'parentDisplayName': myData['displayName'] ?? '',
          'requestedAt': now,
          'status': 'pending',
        },
        SetOptions(merge: true),
      );
      // Çocuğa bildirim doc'u — pushOnNotificationCreated yakalar.
      batch.set(
        _fs.collection('notifications').doc(childUid)
            .collection('items').doc(),
        {
          'type': 'parent_link_request',
          'fromUsername': myData['username'] ?? 'Ebeveyn',
          'fromDisplayName': myData['displayName'] ?? '',
          'when': now,
          'read': false,
        },
      );
      await batch.commit();
      return LinkRequestResult.success;
    } catch (e) {
      debugPrint('[ParentLink] requestLink fail: $e');
      return LinkRequestResult.error;
    }
  }

  // ── Kod tabanlı bağlantı (çocuk profilinden üretilir) ───────────────────
  /// Ambiguous karakter (0/O, 1/I/L) çıkartılmış alfabe.
  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static String _newCode() {
    final rng = math.Random.secure();
    final buf = StringBuffer('EBEV-');
    for (int i = 0; i < 6; i++) {
      buf.write(_codeAlphabet[rng.nextInt(_codeAlphabet.length)]);
    }
    return buf.toString();
  }

  /// Çocuk profilinden çağrılır. 6 karakterlik kısa ömürlü (15 dk) kod
  /// üretir ve Firestore'a yazar. Aynı çocuk için varsa süresi dolmamış
  /// önceki kodu döndürür — gereksiz yazım önlenir. Ebeveyn bu kodu girer.
  static Future<ChildLinkCode?> generateChildLinkCode() async {
    final myUid = _myUid;
    if (myUid == null) return null;
    try {
      // Daha önce aktif (süresi dolmamış) kodu var mı? Varsa onu döndür.
      final existing = await _fs
          .collection('parent_link_codes')
          .where('childUid', isEqualTo: myUid)
          .limit(5)
          .get();
      final now = DateTime.now();
      for (final d in existing.docs) {
        final m = d.data();
        final ts = m['expiresAt'];
        if (ts is Timestamp && ts.toDate().isAfter(now)) {
          return ChildLinkCode(code: d.id, expiresAt: ts.toDate());
        }
      }
      // Benzersiz yeni kod üret (en fazla 5 deneme)
      String? code;
      for (int attempt = 0; attempt < 5; attempt++) {
        final candidate = _newCode();
        final ex = await _fs
            .collection('parent_link_codes').doc(candidate).get();
        if (!ex.exists) { code = candidate; break; }
      }
      if (code == null) return null;
      final expires = now.add(const Duration(minutes: 15));
      await _fs.collection('parent_link_codes').doc(code).set({
        'childUid': myUid,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expires),
      });
      return ChildLinkCode(code: code, expiresAt: expires);
    } catch (e) {
      debugPrint('[ParentLink] generateChildLinkCode fail: $e');
      return null;
    }
  }

  /// Ebeveyn tarafı: kodu yazar, çocuğa bağlantı isteği oluşturulur. Kod
  /// kontrol edilir → childUid bulunur → mevcut requestLink akışına gider.
  /// Kod kullanıldığında doc silinir (tek kullanımlık değil ama bağlantı
  /// kurulduğunda gereksiz — temizlik için kaldırıyoruz).
  static Future<LinkRequestResult> requestLinkByCode(String rawCode) async {
    final myUid = _myUid;
    if (myUid == null) return LinkRequestResult.notAuthed;
    final code = rawCode.trim().toUpperCase();
    if (!RegExp(r'^EBEV-[A-Z0-9]{6}$').hasMatch(code)) {
      return LinkRequestResult.invalidCode;
    }
    try {
      final codeDoc = await _fs
          .collection('parent_link_codes').doc(code).get();
      if (!codeDoc.exists) return LinkRequestResult.codeExpired;
      final data = codeDoc.data() ?? const <String, dynamic>{};
      final childUid = (data['childUid'] ?? '').toString();
      final expTs = data['expiresAt'];
      if (childUid.isEmpty) return LinkRequestResult.codeExpired;
      if (expTs is Timestamp && expTs.toDate().isBefore(DateTime.now())) {
        return LinkRequestResult.codeExpired;
      }
      if (childUid == myUid) return LinkRequestResult.selfLink;

      // Çocuğun username'i ile mevcut requestLink akışını çağır.
      final childProfile =
          await _fs.collection('users').doc(childUid).get();
      final childUsername =
          (childProfile.data()?['username'] ?? '').toString();
      if (childUsername.isEmpty) return LinkRequestResult.childNotFound;
      final res = await requestLink(childUsername);
      // Kod kullanıldı → sil (idempotent — bir daha geçerli olmasın).
      if (res == LinkRequestResult.success ||
          res == LinkRequestResult.pending ||
          res == LinkRequestResult.alreadyLinked) {
        try {
          await _fs.collection('parent_link_codes').doc(code).delete();
        } catch (_) {}
      }
      return res;
    } catch (e) {
      debugPrint('[ParentLink] requestLinkByCode fail: $e');
      return LinkRequestResult.error;
    }
  }

  /// Çocuk gelen ebeveyn isteklerini stream eder (in-app onay UI'ı için).
  /// Auth yoksa `Stream.value([])` — StreamBuilder spinner'da takılmasın diye
  /// boş liste emit ediyoruz (Stream.empty hiç emit etmeden tamamlanır).
  static Stream<List<ParentInvite>> incomingInvitesStream() {
    // Web simülasyonunda Firebase başlatılmaz; singleton'a dokunma.
    if (Firebase.apps.isEmpty) return Stream.value(const <ParentInvite>[]);
    final myUid = _myUid;
    if (myUid == null) return Stream.value(const <ParentInvite>[]);
    return _fs
        .collection('child_invites')
        .doc(myUid)
        .collection('from')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ParentInvite.fromMap(d.id, d.data()))
            .toList());
  }

  /// Çocuk → isteği KABUL et. Hem child_invites hem parent_links → 'active'.
  static Future<bool> acceptInvite(String parentUid) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    try {
      final batch = _fs.batch();
      batch.update(
        _fs.collection('child_invites').doc(myUid)
            .collection('from').doc(parentUid),
        {'status': 'active', 'acceptedAt': FieldValue.serverTimestamp()},
      );
      batch.update(
        _fs.collection('parent_links').doc(parentUid)
            .collection('children').doc(myUid),
        {'status': 'active', 'acceptedAt': FieldValue.serverTimestamp()},
      );
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[ParentLink] accept fail: $e');
      return false;
    }
  }

  /// Çocuk → isteği REDDET.
  static Future<bool> rejectInvite(String parentUid) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    try {
      final batch = _fs.batch();
      batch.update(
        _fs.collection('child_invites').doc(myUid)
            .collection('from').doc(parentUid),
        {'status': 'rejected'},
      );
      batch.update(
        _fs.collection('parent_links').doc(parentUid)
            .collection('children').doc(myUid),
        {'status': 'rejected'},
      );
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[ParentLink] reject fail: $e');
      return false;
    }
  }

  /// Ebeveynin bağlı çocuklarını stream eder.
  /// Auth yoksa `Stream.value([])` — Stream.empty StreamBuilder'ı sonsuza
  /// kadar spinner'da bırakır (data emit etmeden tamamlanır).
  static Stream<List<LinkedChild>> linkedChildrenStream() {
    final myUid = _myUid;
    if (myUid == null) return Stream.value(const <LinkedChild>[]);
    return _fs
        .collection('parent_links')
        .doc(myUid)
        .collection('children')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => LinkedChild.fromMap(d.id, d.data()))
            .toList());
  }

  /// Ebeveyn bir çocuğun temel istatistiklerini okur (read-only).
  /// PomodoroStats + Premium status + solutions count.
  static Future<Map<String, dynamic>> readChildStats(String childUid) async {
    final result = <String, dynamic>{
      'username': '',
      'displayName': '',
      'streakDays': 0,
      'todayPhases': 0,
      'totalPhases': 0,
      'solutionsCount': 0,
      'lastActive': null,
    };
    try {
      // Profil
      final userDoc = await _fs.collection('users').doc(childUid).get();
      final userData = userDoc.data() ?? const <String, dynamic>{};
      result['username'] = userData['username'] ?? '';
      result['displayName'] = userData['displayName'] ?? '';
      result['lastActive'] = userData['lastSeen'];

      // Pomodoro — yol pomodoro_stats/main (PomodoroStats servisinin yazdığı yer)
      final pomoSnap = await _fs
          .collection('users')
          .doc(childUid)
          .collection('pomodoro_stats')
          .doc('main')
          .get();
      final pomoData = pomoSnap.data() ?? const <String, dynamic>{};
      result['streakDays'] = pomoData['streakDays'] ?? 0;
      result['todayPhases'] = pomoData['todayPhases'] ?? 0;
      result['totalPhases'] = pomoData['totalPhases'] ?? 0;

      // Çözüm sayısı
      final solCount = await _fs
          .collection('users')
          .doc(childUid)
          .collection('solutions')
          .count()
          .get();
      result['solutionsCount'] = solCount.count ?? 0;
    } catch (e) {
      debugPrint('[ParentLink] readChildStats fail: $e');
    }
    return result;
  }

  /// Ebeveyn için çocuğun son 7 gün aktivite verisini Firestore'dan okur.
  /// Veri yoksa empty döner — UI grafiklerde "veri yok" gösterir.
  /// Yol: users/{childUid}/activity/{yyyyMMdd}
  static Future<List<Map<String, dynamic>>> readChild7DayActivity(
      String childUid) async {
    final result = <Map<String, dynamic>>[];
    final now = DateTime.now();
    try {
      for (int d = 6; d >= 0; d--) {
        final day = DateTime(now.year, now.month, now.day - d);
        final key = '${day.year}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}';
        final snap = await _fs
            .collection('users').doc(childUid)
            .collection('activity').doc(key)
            .get();
        if (snap.exists) {
          final m = Map<String, dynamic>.from(snap.data() ?? const {});
          m['dateKey'] = key;
          result.add(m);
        } else {
          result.add({'dateKey': key});
        }
      }
    } catch (e) {
      debugPrint('[ParentLink] readChild7DayActivity fail: $e');
    }
    return result;
  }

  /// Çocuğun son özetlerini oku (üst 6 tane).
  /// Yol: users/{childUid}/summaries/* (collection name proje-spesifik)
  static Future<List<Map<String, dynamic>>> readChildRecentSummaries(
      String childUid) async {
    try {
      final snap = await _fs
          .collection('users').doc(childUid)
          .collection('summaries')
          .orderBy('createdAt', descending: true)
          .limit(6)
          .get();
      return snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['_id'] = d.id;
        return m;
      }).toList();
    } catch (e) {
      debugPrint('[ParentLink] readChildSummaries fail: $e');
      return [];
    }
  }

  /// Kod → childUid çözer (bağlamadan önce slot'a yazmak için). Geçersiz /
  /// süresi dolmuş kodda null döner.
  static Future<String?> resolveCodeChildUid(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (!RegExp(r'^EBEV-[A-Z0-9]{6}$').hasMatch(code)) return null;
    try {
      final doc =
          await _fs.collection('parent_link_codes').doc(code).get();
      if (!doc.exists) return null;
      final exp = doc.data()?['expiresAt'];
      if (exp is Timestamp && exp.toDate().isBefore(DateTime.now())) {
        return null;
      }
      final cu = (doc.data()?['childUid'] ?? '').toString();
      return cu.isEmpty ? null : cu;
    } catch (e) {
      debugPrint('[ParentLink] resolveCodeChildUid fail: $e');
      return null;
    }
  }

  /// Bağlı çocuğun BU HAFTASININ (Pzt→Paz) ham aktivite kayıtlarını okur.
  /// Kaynak: users/{childUid}/study_activities (cihazın _ActivityStore cloud
  /// kopyası). Gelişim Paneli kategori/gün kırılımı için kullanılır.
  /// Format: {dateKey, weekday, type, subject, topic, sec}.
  static Future<List<Map<String, dynamic>>> readChildWeekEntries(
      String childUid) async {
    final out = <Map<String, dynamic>>[];
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: now.weekday - 1));
      final snap = await _fs
          .collection('users')
          .doc(childUid)
          .collection('study_activities')
          .where('whenTs', isGreaterThanOrEqualTo: Timestamp.fromDate(monday))
          .get();
      String two(int n) => n.toString().padLeft(2, '0');
      for (final d in snap.docs) {
        final m = d.data();
        final ts = m['whenTs'];
        if (ts is! Timestamp) continue;
        final w = ts.toDate().toLocal();
        out.add({
          'dateKey': '${w.year}-${two(w.month)}-${two(w.day)}',
          'weekday': w.weekday,
          'type': (m['type'] ?? '').toString(),
          'subject': (m['subject'] ?? '').toString(),
          'topic': (m['topic'] ?? '').toString(),
          'sec': (m['durationSec'] as num?)?.toInt() ?? 0,
        });
      }
    } catch (e) {
      debugPrint('[ParentLink] readChildWeekEntries fail: $e');
    }
    return out;
  }

  /// Bağlı çocuğun SON N GÜNÜNÜN günlük aktivite dökümanları (aylık rapor).
  /// users/{childUid}/activity/{yyyy-MM-dd}.
  static Future<List<Map<String, dynamic>>> readChildActivityDays(
      String childUid, int days) async {
    final result = <Map<String, dynamic>>[];
    final now = DateTime.now();
    try {
      for (int d = days - 1; d >= 0; d--) {
        final day = DateTime(now.year, now.month, now.day - d);
        final key = '${day.year}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}';
        final snap = await _fs
            .collection('users').doc(childUid)
            .collection('activity').doc(key).get();
        if (snap.exists) {
          final m = Map<String, dynamic>.from(snap.data() ?? const {});
          m['dateKey'] = key;
          result.add(m);
        } else {
          result.add({'dateKey': key});
        }
      }
    } catch (e) {
      debugPrint('[ParentLink] readChildActivityDays fail: $e');
    }
    return result;
  }

  /// Bağlı çocuğun SON N GÜNÜNÜN ham aktivite kayıtları (study_activities).
  static Future<List<Map<String, dynamic>>> readChildEntriesDays(
      String childUid, int days) async {
    final out = <Map<String, dynamic>>[];
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day - (days - 1));
      final snap = await _fs
          .collection('users').doc(childUid)
          .collection('study_activities')
          .where('whenTs', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .get();
      String two(int n) => n.toString().padLeft(2, '0');
      for (final d in snap.docs) {
        final m = d.data();
        final ts = m['whenTs'];
        if (ts is! Timestamp) continue;
        final w = ts.toDate().toLocal();
        out.add({
          'dateKey': '${w.year}-${two(w.month)}-${two(w.day)}',
          'type': (m['type'] ?? '').toString(),
          'subject': (m['subject'] ?? '').toString(),
          'topic': (m['topic'] ?? '').toString(),
          'sec': (m['durationSec'] as num?)?.toInt() ?? 0,
        });
      }
    } catch (e) {
      debugPrint('[ParentLink] readChildEntriesDays fail: $e');
    }
    return out;
  }

  /// Bağlı çocuğun katıldığı tüm sınıflardaki YAKLAŞAN ödevlerini döndürür.
  /// Yayında olan (publishAt geçmiş) ve son tarihi geçmemiş VEYA son 3 günde
  /// geçmiş ödevler dahil. Her ödev için çocuğun teslim durumu okunur.
  /// Sonuç dueAt'a göre artan sıralı.
  static Future<List<ParentUpcomingHomework>> readChildUpcomingHomeworks(
      String childUid) async {
    final out = <ParentUpcomingHomework>[];
    try {
      final classes = await ClassService.joinedClassesFor(childUid);
      final now = DateTime.now();
      final cutoffPast = now.subtract(const Duration(days: 3));
      for (final cls in classes) {
        final hws = await HomeworkService.classHomeworks(cls.classId);
        for (final hw in hws) {
          if (!hw.isPublished) continue;
          if (hw.dueAt.isBefore(cutoffPast)) continue; // çok eski
          // Teslim durumu
          bool submitted = false;
          try {
            final subDoc = await _fs
                .collection('classes').doc(cls.classId)
                .collection('homeworks').doc(hw.id)
                .collection('submissions').doc(childUid)
                .get();
            final st = (subDoc.data()?['status'] ?? '').toString();
            submitted = st == 'submitted' || st == 'late';
          } catch (_) {}
          out.add(ParentUpcomingHomework(
            classId: cls.classId,
            className: cls.className,
            title: hw.title.isEmpty ? hw.topic : hw.title,
            subject: hw.subject,
            dueAt: hw.dueAt,
            submitted: submitted,
          ));
        }
      }
      out.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    } catch (e) {
      debugPrint('[ParentLink] readChildUpcomingHomeworks fail: $e');
    }
    return out;
  }

  /// Bağlı çocuğun katıldığı sınıflardaki ÖĞRETMEN DUYURULARINI döndürür.
  /// Kaynak: classes/{classId}/content (type == 'announcement'). En yeni üstte.
  static Future<List<ParentAnnouncement>> readChildAnnouncements(
      String childUid) async {
    final out = <ParentAnnouncement>[];
    try {
      final classes = await ClassService.joinedClassesFor(childUid);
      for (final cls in classes) {
        final content = await ClassService.classContentStream(cls.classId).first;
        for (final m in content) {
          if ((m['type'] ?? '').toString() != 'announcement') continue;
          final payload =
              (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
          DateTime when = DateTime.now();
          final ts = m['sharedAt'];
          if (ts is Timestamp) when = ts.toDate();
          out.add(ParentAnnouncement(
            className: cls.className,
            message: (payload['message'] ?? '').toString(),
            teacherName: (payload['teacherName'] ?? '').toString(),
            when: when,
          ));
        }
      }
      out.sort((a, b) => b.when.compareTo(a.when));
    } catch (e) {
      debugPrint('[ParentLink] readChildAnnouncements fail: $e');
    }
    return out;
  }

  /// Bağlı çocuğun katıldığı sınıflardaki öğretmen NOTLARI/TEBRİKLERİNİ
  /// (paylaşılanları) döndürür. Kaynak: ClassService.notesStream(onlyShared:
  /// true) — öğretmen tarafı "veli panelinde de görünür" diyerek bu notu
  /// paylaşır (bkz. teacher_homework_detail_screen.dart), ama daha önce
  /// HİÇBİR ebeveyn ekranı bu stream'i okumuyordu — sessizce kayboluyordu.
  static Future<List<ParentTeacherNote>> readChildNotes(
      String childUid) async {
    final out = <ParentTeacherNote>[];
    try {
      final classes = await ClassService.joinedClassesFor(childUid);
      for (final cls in classes) {
        final notes = await ClassService.notesStream(
                cls.classId, childUid, onlyShared: true)
            .first;
        for (final n in notes) {
          out.add(ParentTeacherNote(
            className: cls.className,
            text: n.text,
            kind: n.kind,
            when: n.createdAt,
          ));
        }
      }
      out.sort((a, b) => b.when.compareTo(a.when));
    } catch (e) {
      debugPrint('[ParentLink] readChildNotes fail: $e');
    }
    return out;
  }

  /// Bağlı çocuğun Bilgi Ligi (quiz/yarışma) performansını okur —
  /// league_attempts koleksiyonundan (cloud; LeagueScores yerelde
  /// SharedPreferences kullandığı için ebeveyn cihazından erişilemez).
  /// NOT: Öğrenci hiç Şehir/Ülke konumu seçmediyse cloud'a hiç attempt
  /// yazılmamış olabilir (LeagueScores.add — konum zorunlu) → attempts=0
  /// dönebilir, bu bilinen bir sınırdır.
  static Future<ParentLeagueStats> readChildLeagueStats(
      String childUid) async {
    try {
      final snap = await _fs
          .collection('league_attempts')
          .where('uid', isEqualTo: childUid)
          .orderBy('when', descending: true)
          .limit(200)
          .get();
      if (snap.docs.isEmpty) {
        return const ParentLeagueStats(
          attempts: 0, averageScore: 0, bestScore: 0,
          streakDays: 0, lastAttemptAt: null,
        );
      }
      double total = 0;
      double best = 0;
      final days = <DateTime>{};
      DateTime? lastAt;
      for (final d in snap.docs) {
        final m = d.data();
        final score = (m['score'] as num?)?.toDouble() ?? 0;
        total += score;
        if (score > best) best = score;
        final ts = m['when'];
        if (ts is Timestamp) {
          final when = ts.toDate();
          lastAt ??= when;
          days.add(DateTime(when.year, when.month, when.day));
        }
      }
      // currentStreak() (league_scores.dart) ile AYNI algoritma: bugünden
      // (yoksa dünden, 1 gün tolerans) geriye ardışık gün sayımı.
      int streak = 0;
      final today = DateTime.now();
      DateTime cursor = DateTime(today.year, today.month, today.day);
      if (!days.contains(cursor)) {
        cursor = cursor.subtract(const Duration(days: 1));
      }
      if (days.contains(cursor)) {
        while (days.contains(cursor)) {
          streak++;
          cursor = cursor.subtract(const Duration(days: 1));
        }
      }
      return ParentLeagueStats(
        attempts: snap.docs.length,
        averageScore: total / snap.docs.length,
        bestScore: best,
        streakDays: streak,
        lastAttemptAt: lastAt,
      );
    } catch (e) {
      debugPrint('[ParentLink] readChildLeagueStats fail: $e');
      return const ParentLeagueStats(
        attempts: 0, averageScore: 0, bestScore: 0,
        streakDays: 0, lastAttemptAt: null,
      );
    }
  }

  /// Ebeveyn kontrolü ayarlarını kaydeder. Çocuğun uygulamasının okuyup
  /// uygulayabilmesi için `parental_controls/{childUid}` yoluna yazar.
  /// NOT: Limitlerin gerçek uygulanması (kullanımı engelleme) çocuk
  /// uygulamasında ayrıca ele alınmalı + Firestore kuralları eklenmeli.
  /// Ebeveyn-bazlı alt-koleksiyon: her ebeveyn KENDİ kısıtlarını yazar,
  /// birden fazla bağlı ebeveyn (anne+baba) varken birbirini ezmez.
  static DocumentReference<Map<String, dynamic>> _controlsDocFor(
          String childUid, String parentUid) =>
      _fs.collection('parental_controls').doc(childUid)
          .collection('byParent').doc(parentUid);

  static Future<bool> saveParentalControls(
    String childUid, {
    required bool timeLimitEnabled,
    required int dailyLimitMinutes,
    required bool quietHoursEnabled,
    required int quietStartMinutes, // gün içi dakika (0-1439)
    required int quietEndMinutes,
  }) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    try {
      await _controlsDocFor(childUid, myUid).set({
        'parentUid': myUid,
        'timeLimitEnabled': timeLimitEnabled,
        'dailyLimitMinutes': dailyLimitMinutes,
        'quietHoursEnabled': quietHoursEnabled,
        'quietStartMinutes': quietStartMinutes,
        'quietEndMinutes': quietEndMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[ParentLink] saveParentalControls fail: $e');
      return false;
    }
  }

  /// Giriş yapan ebeveynin KENDİ kısıtlarını okur (ayar ekranını doldurmak
  /// için — başka bağlı ebeveynin ayarını değil, kendisininkini görmeli).
  static Future<Map<String, dynamic>?> readParentalControls(
      String childUid) async {
    final myUid = _myUid;
    if (myUid == null) return null;
    try {
      final doc = await _controlsDocFor(childUid, myUid).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      debugPrint('[ParentLink] readParentalControls fail: $e');
      return null;
    }
  }

  /// TÜM bağlı ebeveynlerin kısıtlarını okur — çocuk cihazında enforcement
  /// için (ParentalControlsService), en kısıtlayıcısı uygulanır.
  static Future<List<Map<String, dynamic>>> readAllParentalControls(
      String childUid) async {
    try {
      final snap = await _fs.collection('parental_controls').doc(childUid)
          .collection('byParent').get();
      return snap.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('[ParentLink] readAllParentalControls fail: $e');
      return const [];
    }
  }

  /// Ebeveyn bağlantıyı sonlandırır (çocuk verisi artık görünmez).
  static Future<bool> unlinkChild(String childUid) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    try {
      final batch = _fs.batch();
      batch.delete(
        _fs.collection('parent_links').doc(myUid)
            .collection('children').doc(childUid),
      );
      batch.delete(
        _fs.collection('child_invites').doc(childUid)
            .collection('from').doc(myUid),
      );
      // Kendi ebeveyn-kontrolü dokümanını da sil — yoksa bağlantı kesilse
      // bile çocuk cihazında eski kısıt kalıcı olarak asılı kalıyordu.
      batch.delete(_controlsDocFor(childUid, myUid));
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[ParentLink] unlink fail: $e');
      return false;
    }
  }
}
