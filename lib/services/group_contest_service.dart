// ═══════════════════════════════════════════════════════════════════════════════
//  GroupContestService — Arkadaş grubu yarışması (özel lig).
//
//  FİKİR:
//    Bir kullanıcı (sahip) bir ders+konu seçer, havuzdan/AI'dan SABİT bir soru
//    seti üretilir ve bir "grup yarışması" dokümanına gömülür. Arkadaşlar
//    davet linki/QR ile katılır, HERKES AYNI SORULARI çözer, sıralama SADECE
//    bu grup içinde yapılır (dünya/ülke sıralamasından bağımsız).
//
//  1v1 düellodan farkı: eşzamanlı değil, ASENKRON. Herkes kendi vaktinde aynı
//  seti çözer; skor (doğru sayısı) + süreye göre grup tablosunda sıralanır.
//
//  ŞEMA:
//    group_contests/{contestId}
//      ownerUid, ownerName, scope: 'friends'
//      subjectKey, subjectName, subjectEmoji, topic
//      questionCount
//      questions: [ {text, formula?, options[], correctIndex, hint, explanation,
//                    difficulty} ]   ← SABİT set, herkese aynı
//      createdAt, expiresAt
//      /participants/{uid}
//        username, avatar
//        status: 'joined' | 'done'
//        score (doğru sayısı), correct, total, durationMs, finishedAt
//        joinedAt
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'friend_service.dart';
import 'user_profile_service.dart';
import 'contest_group_service.dart';

/// Bir grup yarışmasının meta verisi + soruları.
class GroupContest {
  final String id;
  final String ownerUid;
  final String ownerName;
  final String subjectKey;
  final String subjectName;
  final String subjectEmoji;
  final String topic;
  final int questionCount;
  final List<Map<String, dynamic>> questions;
  final String groupId; // kayıtlı gruba bağlıysa dolu, değilse ''
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const GroupContest({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.subjectKey,
    required this.subjectName,
    required this.subjectEmoji,
    required this.topic,
    required this.questionCount,
    required this.questions,
    this.groupId = '',
    this.createdAt,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  factory GroupContest.fromDoc(
      String id, Map<String, dynamic> d) {
    final rawQs = (d['questions'] as List?) ?? const [];
    return GroupContest(
      id: id,
      ownerUid: (d['ownerUid'] ?? '').toString(),
      ownerName: (d['ownerName'] ?? '').toString(),
      subjectKey: (d['subjectKey'] ?? '').toString(),
      subjectName: (d['subjectName'] ?? '').toString(),
      subjectEmoji: (d['subjectEmoji'] ?? '🎯').toString(),
      topic: (d['topic'] ?? '').toString(),
      // Firestore sayıyı int yazsak bile double dönebilir (increment / CF /
      // JSON round-trip) → `as int?` bir double'da TypeError fırlatırdı.
      // `as num?`+toInt() her iki tipi de güvenle okur.
      questionCount: (d['questionCount'] as num?)?.toInt() ?? rawQs.length,
      questions: rawQs
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      groupId: (d['groupId'] ?? '').toString(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Bir katılımcının lobi/sıralama satırı.
class GroupParticipant {
  final String uid;
  final String username;
  final String avatar;
  final String status; // 'joined' | 'done'
  final int score; // doğru sayısı
  final int correct;
  final int total;
  final int durationMs;

  const GroupParticipant({
    required this.uid,
    required this.username,
    required this.avatar,
    required this.status,
    required this.score,
    required this.correct,
    required this.total,
    required this.durationMs,
  });

  bool get isDone => status == 'done';

  factory GroupParticipant.fromDoc(String uid, Map<String, dynamic> d) {
    return GroupParticipant(
      uid: uid,
      username: (d['username'] ?? '').toString(),
      avatar: (d['avatar'] ?? '👤').toString(),
      status: (d['status'] ?? 'joined').toString(),
      // int/double güvenli okuma — Firestore double döndürürse `as int?`
      // TypeError fırlatıp sonuç/sıralama tablosunu çökertirdi.
      score: (d['score'] as num?)?.toInt() ?? 0,
      correct: (d['correct'] as num?)?.toInt() ?? 0,
      total: (d['total'] as num?)?.toInt() ?? 0,
      durationMs: (d['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class GroupContestService {
  GroupContestService._();

  // ÖNEMLİ: `static final` alan İLK erişimde Firebase hazır değilse fırlatır
  // ve build içinden çağrıldığında kırmızı hata ekranı üretir (web'de
  // "FirebaseException is not a subtype of JavaScriptObject" olarak görünür).
  // ContestGroupService'teki düzeltmenin aynısı: getter + Firebase.apps koruması.
  static FirebaseFirestore get _fs => FirebaseFirestore.instance;
  static const _collection = 'group_contests';

  static String? get _uid {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static String inviteLinkFor(String contestId) =>
      'https://qualsar.app/grup/$contestId';

  /// Yazım anında kullanılacak (username, avatar) çifti.
  /// Yerel profil boş olabilir (kullanıcı bildirimden geldi, profil servisi
  /// henüz init edilmedi) — o durumda users/{uid} doc'undan çözülür. Eskiden
  /// doğrudan 'Oyuncu' yazılıyor ve katılımcılar birbirinin kullanıcı adını
  /// hiç göremiyordu.
  static Future<(String, String)> _myNameAvatar(String uid) async {
    final p = UserProfileService.instance;
    try {
      await p.init(); // idempotent — zaten init'liyse anında döner
    } catch (_) {}
    var uname = p.username.trim();
    var avatar = p.avatar.trim();
    if (uname.isEmpty) {
      try {
        final u = await FriendService.getUserByUid(uid);
        if (u != null) {
          uname = u.username.trim().isNotEmpty
              ? u.username.trim()
              : u.displayName.trim();
          if ((avatar.isEmpty || avatar == '👤') &&
              u.avatar.trim().isNotEmpty) {
            avatar = u.avatar.trim();
          }
        }
      } catch (_) {}
    }
    // Kullanıcı adı hiç belirlenmemişse GERÇEK AD zinciri: yerel profil adı
    // → profil ekranındaki isim (profile_name) → Google hesabı adı. Eskiden
    // hepsi boşken 'Oyuncu' yazılıyordu.
    if (uname.isEmpty) uname = p.displayName.trim();
    if (uname.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        uname = (prefs.getString('profile_name') ?? '').trim();
      } catch (_) {}
    }
    if (uname.isEmpty) {
      try {
        uname =
            (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
      } catch (_) {}
    }
    return (uname, avatar.isEmpty ? '👤' : avatar);
  }

  // ─── Oluştur ───────────────────────────────────────────────────────────────

  /// Yeni grup yarışması oluşturur, sahibi ilk katılımcı olarak ekler.
  /// [questions] taşınabilir map listesidir (text/options/correctIndex/…).
  /// Yeni yarışmanın id'sini döner; hata olursa null.
  static Future<String?> createContest({
    required String subjectKey,
    required String subjectName,
    required String subjectEmoji,
    required String topic,
    required List<Map<String, dynamic>> questions,
    // Kayıtlı bir gruba bağlıysa: katılanlar otomatik gruba eklenir.
    String? groupId,
  }) async {
    final uid = _uid;
    if (uid == null || questions.isEmpty) return null;
    try {
      final (uname, _) = await _myNameAvatar(uid);
      final ownerName = uname.isNotEmpty ? uname : 'Oyuncu';
      final now = DateTime.now();
      final docRef = _fs.collection(_collection).doc();
      await docRef.set({
        'ownerUid': uid,
        'ownerName': ownerName,
        'scope': 'friends',
        if (groupId != null) 'groupId': groupId,
        'subjectKey': subjectKey,
        'subjectName': subjectName,
        'subjectEmoji': subjectEmoji,
        'topic': topic,
        'questionCount': questions.length,
        'questions': questions,
        'createdAt': FieldValue.serverTimestamp(),
        // Uzun geçerlilik: davet çok sonra kabul edilse bile katılan kişi
        // yarışmayı çözebilsin ve sonucu diğerlerinde görünsün (1 yıl).
        'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 365))),
      });
      // Sahibi ilk katılımcı yap (lobide görünsün).
      await _joinDoc(docRef.id, uid);
      return docRef.id;
    } catch (e) {
      debugPrint('[GroupContest] createContest fail: $e');
      return null;
    }
  }

  /// Mevcut bir yarışmayı kayıtlı bir gruba bağla (sonradan "grubu kaydet").
  static Future<void> linkToGroup(String contestId, String groupId) async {
    try {
      await _fs.collection(_collection).doc(contestId).set(
        {'groupId': groupId},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[GroupContest] linkToGroup fail: $e');
    }
  }

  // ─── Katıl ───────────────────────────────────────────────────────────────

  /// Davet linki/QR ile gelen kullanıcıyı yarışmaya katılımcı yapar.
  /// Zaten katıldıysa (veya bitirdiyse) durumunu BOZMAZ.
  static Future<bool> joinContest(String contestId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _joinDoc(contestId, uid);
      // Yarışma kayıtlı bir gruba bağlıysa kullanıcıyı gruba da ekle —
      // böylece grup üyeleri kendiliğinden dolar.
      try {
        final doc =
            await _fs.collection(_collection).doc(contestId).get();
        final gid = (doc.data()?['groupId'] ?? '').toString();
        if (gid.isNotEmpty) await ContestGroupService.joinGroup(gid);
      } catch (_) {}
      return true;
    } catch (e) {
      debugPrint('[GroupContest] join fail: $e');
      return false;
    }
  }

  // ─── Kullanıcı adıyla davet ─────────────────────────────────────────────

  /// Kullanıcı adına göre arkadaşı yarışmaya davet eder — hedefin
  /// in-app bildirim kutusuna 'group_contest_invite' tipinde bildirim yazar
  /// (bildirime basınca yarışma açılır). Sonuç: 'ok' | 'notfound' | 'self'
  /// | 'error'.
  static Future<String> inviteByUsername(
    String contestId,
    String username, {
    required String subjectName,
    required String topic,
  }) async {
    final uid = _uid;
    if (uid == null) return 'error';
    try {
      final target = await FriendService.getUserByUsername(username);
      if (target == null) return 'notfound';
      if (target.uid == uid) return 'self';
      final me = UserProfileService.instance;
      final (uname, _) = await _myNameAvatar(uid);
      final myName = uname.isNotEmpty ? uname : 'Oyuncu';
      await _fs
          .collection('notifications')
          .doc(target.uid)
          .collection('items')
          .doc()
          .set({
        'type': 'group_contest_invite',
        'contestId': contestId,
        'fromUid': uid,
        'fromUsername': uname.isNotEmpty ? uname : me.username,
        'fromDisplayName': myName,
        'fromAvatar': me.avatar,
        'subjectName': subjectName,
        'topic': topic,
        'when': FieldValue.serverTimestamp(),
        'read': false,
      });
      return 'ok';
    } catch (e) {
      debugPrint('[GroupContest] inviteByUsername fail: $e');
      return 'error';
    }
  }

  static Future<void> _joinDoc(String contestId, String uid) async {
    final pRef = _fs
        .collection(_collection)
        .doc(contestId)
        .collection('participants')
        .doc(uid);
    final existing = await pRef.get();
    final (uname, avatar) = await _myNameAvatar(uid);
    if (existing.exists) {
      // Skor/durum korunur; ama kayıt vaktiyle 'Oyuncu' yazıldıysa ve artık
      // gerçek ad çözülebiliyorsa ONARILIR (eski bozuk satırlar kendini
      // düzeltsin diye).
      final old = (existing.data()?['username'] ?? '').toString().trim();
      if (uname.isNotEmpty && (old.isEmpty || old == 'Oyuncu')) {
        await pRef.set(
            {'username': uname, 'avatar': avatar}, SetOptions(merge: true));
      }
      return;
    }
    await pRef.set({
      'uid': uid, // collectionGroup sorgusu için (myContestsStream)
      'username': uname.isNotEmpty ? uname : 'Oyuncu',
      'avatar': avatar,
      'status': 'joined',
      'score': 0,
      'correct': 0,
      'total': 0,
      'durationMs': 0,
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Demo grup yarışına sahte (bot) katılımcılar ekler — kullanıcının
  /// arkadaşı/gerçek grubu olmadan da sonuç tablosu dolu görünsün. Botlar
  /// 'done' durumundadır; skorları [total] üzerinden deterministik türetilir
  /// (Math.random kullanılmaz). Yalnızca demo akışından çağrılır.
  static Future<void> seedDemoParticipants(
    String contestId,
    List<(String name, String avatar)> bots, {
    required int total,
  }) async {
    if (bots.isEmpty || total <= 0) return;
    try {
      final col = _fs
          .collection(_collection)
          .doc(contestId)
          .collection('participants');
      final batch = _fs.batch();
      var i = 0;
      for (final b in bots) {
        // Deterministik yalancı skor: %45–%92 arası doğru + değişken süre.
        final pct = 0.45 + ((b.$1.length + i * 7) % 48) / 100.0;
        final correct = (total * pct).round().clamp(0, total);
        final durationMs = 25000 + ((b.$1.length * 3 + i * 11) % 70) * 1000;
        batch.set(col.doc('demo_bot_$i'), {
          'uid': 'demo_bot_$i',
          'username': b.$1,
          'avatar': b.$2,
          'status': 'done',
          'score': correct,
          'correct': correct,
          'total': total,
          'durationMs': durationMs,
          'joinedAt': FieldValue.serverTimestamp(),
          'finishedAt': FieldValue.serverTimestamp(),
        });
        i++;
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[GroupContest] seedDemoParticipants fail: $e');
    }
  }

  // ─── Sonuç gönder ─────────────────────────────────────────────────────────

  /// Yarışı bitiren kullanıcının skorunu yazar. Idempotent değil — yeniden
  /// çözmeyi engellemek için caller [hasFinished] ile kontrol etmeli.
  static Future<void> submitResult(
    String contestId, {
    required int correct,
    required int total,
    required int durationMs,
    // Soru-bazlı cevaplar (null = boş → -1 olarak saklanır). Sonuç ekranında
    // kişi yarışı sonradan tekrar açtığında "Sorular ve Cevaplar" dökümü
    // bellekte olmasa da kalıcı kayıttan geri yüklenebilsin diye tutulur.
    List<int?>? answers,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _fs
          .collection(_collection)
          .doc(contestId)
          .collection('participants')
          .doc(uid)
          .set({
        'status': 'done',
        'score': correct,
        'correct': correct,
        'total': total,
        'durationMs': durationMs,
        if (answers != null)
          'answers': answers.map((e) => e ?? -1).toList(),
        'finishedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[GroupContest] submitResult fail: $e');
    }
  }

  /// Mevcut kullanıcının bu yarışta verdiği soru-bazlı cevapları döner
  /// (-1 → boş bırakılmış = null). Kayıt yoksa null. Sonuç ekranı, yarış
  /// başka bir oturumda çözülmüş olsa bile döküm gösterebilsin diye kullanır.
  static Future<List<int?>?> getMyAnswers(String contestId) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final doc = await _fs
          .collection(_collection)
          .doc(contestId)
          .collection('participants')
          .doc(uid)
          .get();
      final raw = doc.data()?['answers'];
      if (raw is List) {
        return raw
            .map((e) => (e is int && e >= 0) ? e : null)
            .toList();
      }
    } catch (e) {
      debugPrint('[GroupContest] getMyAnswers fail: $e');
    }
    return null;
  }

  // ─── Okuma ─────────────────────────────────────────────────────────────────

  static Future<GroupContest?> getContest(String contestId) async {
    try {
      final doc =
          await _fs.collection(_collection).doc(contestId).get();
      if (!doc.exists) return null;
      return GroupContest.fromDoc(doc.id, doc.data() ?? const {});
    } catch (e) {
      debugPrint('[GroupContest] getContest fail: $e');
      return null;
    }
  }

  /// Mevcut kullanıcı bu yarışı bitirmiş mi?
  static Future<bool> hasFinished(String contestId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final doc = await _fs
          .collection(_collection)
          .doc(contestId)
          .collection('participants')
          .doc(uid)
          .get();
      return (doc.data()?['status'] ?? '') == 'done';
    } catch (_) {
      return false;
    }
  }

  /// Yarışı kullanıcının KENDİ listesinden kaldırır — yalnız kendi
  /// participant kaydı silinir. Yarışma dokümanı ve diğer üyelerin
  /// katılımları AYNEN kalır (grup silme değildir).
  static Future<void> leaveContest(String contestId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _fs
          .collection(_collection)
          .doc(contestId)
          .collection('participants')
          .doc(uid)
          .delete();
    } catch (e) {
      debugPrint('[GroupContest] leaveContest fail: $e');
    }
  }

  /// Katılımcı/sıralama akışı — skor desc, süre asc.
  ///
  /// async* + try/catch: sorgu kurulumu veya listen SIRASINDA fırlayan hata
  /// (web interop bunu senkron fırlatabiliyor) build'i çökertmek yerine
  /// boş liste + debug log'a düşer.
  static Stream<List<GroupParticipant>> participantsStream(
      String contestId) async* {
    try {
      yield* _fs
          .collection(_collection)
          .doc(contestId)
          .collection('participants')
          .snapshots()
          .map((snap) {
        final list = snap.docs
            .map((d) => GroupParticipant.fromDoc(d.id, d.data()))
            .toList();
        // Bitirenler önce (skor desc, süre asc); bekleyenler sona.
        list.sort((a, b) {
          if (a.isDone != b.isDone) return a.isDone ? -1 : 1;
          if (a.score != b.score) return b.score.compareTo(a.score);
          return a.durationMs.compareTo(b.durationMs);
        });
        return list;
      }).transform(StreamTransformer<List<GroupParticipant>,
          List<GroupParticipant>>.fromHandlers(
        // handleError'da `return` değer yaymaz — sink'e boş liste bas
        // (friend_service'teki düzeltmeyle aynı).
        handleError: (e, st, sink) {
          debugPrint('[GroupContest] participantsStream error: $e');
          sink.add(const <GroupParticipant>[]);
        },
      ));
    } catch (e) {
      debugPrint('[GroupContest] participantsStream fail: $e');
      yield const <GroupParticipant>[];
    }
  }

  /// Mevcut kullanıcının katıldığı, süresi geçmemiş GRUP yarışmaları.
  ///
  /// • Yarışma dokümanları PARALEL çekilir — eskiden sıralı `await` zinciri
  ///   N yarışta N tur ağ beklemesi yapıyordu; sekme uzun süre boş kalıyordu.
  /// • Yalnız groupId'si DOLU yarışmalar döner: 1v1 / grupsuz yarışlar
  ///   "Arkadaşımla Yarışlarım" tarafında kalır, bu sekmeye karışmaz.
  static Stream<List<GroupContest>> myContestsStream() async* {
    // async* + try/catch: build içinden çağrıldığı için sorgu kurulumu /
    // listen sırasındaki senkron hata (web'de "FirebaseException is not a
    // subtype of JavaScriptObject" kırmızı ekranı) UI'ı çökertmesin.
    try {
      final uid = _uid;
      if (uid == null) {
        yield const <GroupContest>[];
        return;
      }
      Future<DocumentSnapshot<Map<String, dynamic>>?> safeGet(
          DocumentReference<Map<String, dynamic>> ref) async {
        try {
          return await ref.get();
        } catch (_) {
          return null;
        }
      }

      // collectionGroup ile katıldıklarımı bul → parent contest'leri çek.
      yield* _fs
          .collectionGroup('participants')
          .where('uid', isEqualTo: uid)
          .snapshots()
          .asyncMap((snap) async {
        final parents = <DocumentReference<Map<String, dynamic>>>{};
        for (final d in snap.docs) {
          final p = d.reference.parent.parent;
          if (p != null) parents.add(p);
        }
        final docs = await Future.wait(parents.map(safeGet));
        final out = <GroupContest>[];
        for (final c in docs) {
          if (c == null || !c.exists) continue;
          final contest = GroupContest.fromDoc(c.id, c.data() ?? const {});
          if (contest.groupId.isEmpty) continue; // 1v1/grupsuz → bu sekmede yok
          if (contest.isExpired) continue;
          out.add(contest);
        }
        out.sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
        return out;
      }).transform(
              StreamTransformer<List<GroupContest>, List<GroupContest>>.fromHandlers(
        // handleError'da `return` değer yaymaz — sink'e boş liste bas.
        handleError: (e, st, sink) {
          debugPrint('[GroupContest] myContestsStream error: $e');
          sink.add(const <GroupContest>[]);
        },
      ));
    } catch (e) {
      debugPrint('[GroupContest] myContestsStream fail: $e');
      yield const <GroupContest>[];
    }
  }
}
