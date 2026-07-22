// ═══════════════════════════════════════════════════════════════════════════════
//  DueloMatchmakingService — gerçek zamanlı bilgi yarışı eşleştirmesi.
//
//  Akış:
//    1. findMatch(criteria) çağrılır.
//       • presence/{userId} yazılır (online + profil).
//       • matchmaking_queue/{docId} oluşturulur.
//       • Aynı kriterlerde bekleyen ilk uygun kullanıcıya bakılır.
//         - Bulursa: duelo_sessions/{sid} oluşturulur, iki queue doc
//           status=matched + matchedSessionId olarak güncellenir.
//         - Bulamazsa: queue doc snapshot'ını dinler; başka biri kendisiyle
//           eşleşirse (status=matched), onun yarattığı session'a katılır.
//    2. timeoutSeconds içinde match yoksa null döner; çağıran taraf
//       mock fallback'e geçer.
//
//  Bu servis backend'siz tek başına çalışmaz — Firebase + Firestore gerekir.
//  Tüm hatalar loglanır ama kullanıcı akışı kırılmaz; hata → null dönüş.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'error_logger.dart';
import 'user_profile_service.dart';

// Eşleşme isteği kriterleri.
class DueloMatchCriteria {
  final String userId;
  final String username;
  final String flag;
  final String country;
  /// Kullanıcının Bilgi Ligi'nde kayıtlı şehri — ülke-içi düellolarda
  /// rakibe "Rakibin: <şehir>'den" olarak gösterilir. Boş olabilir.
  final String city;
  final String level; // primary | middle | high | university
  final String grade; // "11", "lgs" vb.
  final String? track; // sayisal, sozel, ipa ...
  final String scope; // 'world' | 'country'
  final String subjectKey;
  final String? topic;
  final int elo;
  /// Oyun tipi: 'test' (soru çözme) | 'match' (eşleştirme kartları).
  /// Kuyruk filtresine dahildir — eskiden kriter değildi ve test arayan,
  /// eşleştirme arayanla "eşleşip" iki tarafın da kilitlenmesine yol
  /// açabiliyordu (uyumsuz modlar aynı session'a düşüyordu).
  final String raceType;

  DueloMatchCriteria({
    required this.userId,
    required this.username,
    required this.flag,
    required this.country,
    this.city = '',
    required this.level,
    required this.grade,
    this.track,
    required this.scope,
    required this.subjectKey,
    this.topic,
    this.elo = 1000,
    this.raceType = 'test',
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'username': username,
        'flag': flag,
        'country': country,
        'city': city,
        'level': level,
        'grade': grade,
        'track': track,
        'scope': scope,
        'subjectKey': subjectKey,
        'topic': topic,
        'elo': elo,
        'raceType': raceType,
        'status': 'waiting',
        'createdAt': FieldValue.serverTimestamp(),
      };
}

// Başarılı bir eşleşme sonucu.
class DueloMatchResult {
  final String sessionId;
  final String opponentUserId;
  final String opponentUsername;
  final String opponentFlag;
  final String opponentCountry;
  /// Rakibin Bilgi Ligi'nde kayıtlı şehri (kuyruğa yazdığı değer) — boş
  /// olabilir; UI boşsa ülkeye düşer.
  final String opponentCity;
  final int opponentElo;
  // Session sahibi olan kullanıcı (iki taraf aynı soruları görmesi için
  // deterministik üretim) — true ise bu istemci session'u yarattı, sorular
  // burada üretilecek.
  final bool isOwner;

  DueloMatchResult({
    required this.sessionId,
    required this.opponentUserId,
    required this.opponentUsername,
    required this.opponentFlag,
    required this.opponentCountry,
    this.opponentCity = '',
    required this.opponentElo,
    required this.isOwner,
  });
}

/// Arkadaşa-davet inbox kaydı — duelo_invites/{me}/inbox/{id}.
class DueloInvite {
  final String id;
  final String fromUid;
  final String fromUsername;
  final String fromDisplayName;
  final String fromAvatar;
  final String? subjectKey;
  final String? topic;
  final int questionCount; // yarışma soru sayısı (davet ayarı)
  final String questionType; // 'mc' (çoktan seçmeli) | 'tf' (doğru-yanlış)
  final DateTime sentAt;
  final String status; // pending | accepted | rejected
  final String? sessionId; // accept'ten sonra dolar
  const DueloInvite({
    required this.id,
    required this.fromUid,
    required this.fromUsername,
    required this.fromDisplayName,
    required this.fromAvatar,
    required this.sentAt,
    required this.status,
    this.subjectKey,
    this.topic,
    this.questionCount = 5,
    this.questionType = 'mc',
    this.sessionId,
  });

  factory DueloInvite.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    final ts = m['sentAt'];
    final when = ts is Timestamp ? ts.toDate() : DateTime.now();
    return DueloInvite(
      id: doc.id,
      fromUid: (m['fromUid'] ?? '').toString(),
      fromUsername: (m['fromUsername'] ?? '').toString(),
      fromDisplayName: (m['fromDisplayName'] ?? '').toString(),
      fromAvatar: (m['fromAvatar'] ?? '').toString(),
      sentAt: when,
      status: (m['status'] ?? 'pending').toString(),
      subjectKey: m['subjectKey']?.toString(),
      topic: m['topic']?.toString(),
      questionCount: (m['questionCount'] as int?) ?? 5,
      questionType: (m['questionType'] ?? 'mc').toString(),
      sessionId: m['sessionId']?.toString(),
    );
  }
}

class DueloMatchmakingService {
  static const _tag = '[Duelo.Match]';
  static const _queueCol = 'matchmaking_queue';
  static const _sessionCol = 'duelo_sessions';
  static const _presenceCol = 'presence';

  static void _log(String m) {
    if (kDebugMode) debugPrint('$_tag $m');
  }

  /// Eşleşme ara. Timeout içinde uygun rakip bulunamazsa null döner.
  /// Match varsa DueloMatchResult döner; temizlik (queue doc silme) otomatik.
  static Future<DueloMatchResult?> findMatch(
    DueloMatchCriteria c, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    FirebaseFirestore db;
    try {
      db = FirebaseFirestore.instance;
    } catch (e) {
      _log('Firestore erişimi yok: $e');
      return null;
    }

    DocumentReference<Map<String, dynamic>>? myQueueDoc;
    try {
      // Presence (online mark) — best-effort; hata olursa umursamıyoruz.
      unawaited(db.collection(_presenceCol).doc(c.userId).set({
        'userId': c.userId,
        'username': c.username,
        'flag': c.flag,
        'country': c.country,
        'city': c.city,
        'level': c.level,
        'grade': c.grade,
        'online': true,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));

      // Aday bekleyen kullanıcıları sorgula
      Query<Map<String, dynamic>> q = db
          .collection(_queueCol)
          .where('status', isEqualTo: 'waiting')
          .where('scope', isEqualTo: c.scope)
          .where('level', isEqualTo: c.level)
          .where('grade', isEqualTo: c.grade)
          .where('subjectKey', isEqualTo: c.subjectKey)
          // Oyun tipi eşleşmesi — test arayanla eşleştirme arayan artık
          // birbirine düşmez.
          .where('raceType', isEqualTo: c.raceType);
      if (c.scope == 'country') {
        q = q.where('country', isEqualTo: c.country);
      }

      // Topic varsa önce topic-eşleşen aday; yoksa aynı dersten herhangi biri
      // (lobby aşamasında konu zorunlu tutulmuyorsa bu esnek).
      final snap = await q.limit(10).get();
      final now = DateTime.now();
      final candidates = snap.docs.where((d) {
        final m = d.data();
        if (m['userId'] == c.userId) return false;
        // HAYALET kayıt filtresi: uygulama beklerken kill edilirse queue doc
        // 'waiting' olarak sonsuza dek kalıyordu; sonraki kullanıcı bu ölü
        // kayıtla "eşleşip" hiç gelmeyecek rakibi bekliyordu. 3 dk'dan eski
        // kayıtlar aday sayılmaz.
        final ts = m['createdAt'];
        if (ts is Timestamp &&
            now.difference(ts.toDate()) > const Duration(minutes: 3)) {
          return false;
        }
        return true;
      }).toList();

      // Topic tercihi: eşleşen topic varsa önce onlar.
      DocumentSnapshot<Map<String, dynamic>>? pick;
      if (c.topic != null) {
        final sameTopic = candidates
            .where((d) => (d.data()['topic']?.toString() ?? '') == c.topic)
            .toList();
        if (sameTopic.isNotEmpty) pick = sameTopic.first;
      }
      pick ??= candidates.isNotEmpty ? candidates.first : null;

      if (pick != null) {
        // ── Rakip bulundu. Session yarat + her iki queue doc'u güncelle. ──
        final pickData = pick.data()!;
        final sessionRef = db.collection(_sessionCol).doc();
        final sessionId = sessionRef.id;

        final ownerIsMe = c.userId.compareTo(
                (pickData['userId'] ?? '').toString()) <
            0; // deterministik sahiplik

        final playerA = {
          'userId': c.userId,
          'username': c.username,
          'flag': c.flag,
          'country': c.country,
          'city': c.city,
          'elo': c.elo,
        };
        final playerB = {
          'userId': pickData['userId'],
          'username': pickData['username'],
          'flag': pickData['flag'],
          'country': pickData['country'],
          'city': pickData['city'] ?? '',
          'elo': pickData['elo'] ?? 1000,
        };

        // YARIŞ KOŞULU DÜZELTMESİ: iki kullanıcı aynı bekleyen adayı aynı
        // anda seçerse eskiden iki ayrı session açılıyor, ikinci yazan
        // matchedSessionId'yi eziyor ve ilk session'ın sahibi rakipsiz
        // oturuma kilitleniyordu. Artık transaction adayı YENİDEN OKUR;
        // hâlâ 'waiting' değilse claim başarısız sayılır ve kuyruğa girilir.
        var claimed = true;
        try {
          await db.runTransaction((tx) async {
            final fresh = await tx.get(pick!.reference);
            if ((fresh.data()?['status'] ?? '') != 'waiting') {
              throw StateError('candidate-already-matched');
            }
            tx.set(sessionRef, {
              'ownerUserId':
                  ownerIsMe ? c.userId : pickData['userId'],
              'playerA': playerA,
              'playerB': playerB,
              'subjectKey': c.subjectKey,
              'topic': c.topic ?? pickData['topic'],
              'scope': c.scope,
              'raceType': c.raceType,
              'createdAt': FieldValue.serverTimestamp(),
              'questions': [], // owner üretecek
              'progress': {
                c.userId: {'solved': 0, 'finished': false, 'elapsed': 0},
                pickData['userId']: {
                  'solved': 0,
                  'finished': false,
                  'elapsed': 0,
                },
              },
            });
            tx.update(pick.reference, {
              'status': 'matched',
              'matchedSessionId': sessionId,
              'matchedAt': FieldValue.serverTimestamp(),
            });
          });
        } catch (e) {
          _log('Aday başka biriyle eşleşmiş, kuyruğa giriliyor: $e');
          claimed = false;
        }

        if (claimed) {
          _log('Eşleştirildi → session $sessionId (owner=$ownerIsMe)');
          return DueloMatchResult(
            sessionId: sessionId,
            opponentUserId: (pickData['userId'] ?? '').toString(),
            opponentUsername:
                (pickData['username'] ?? 'anonim').toString(),
            opponentFlag: (pickData['flag'] ?? '🏳️').toString(),
            opponentCountry: (pickData['country'] ?? '').toString(),
            opponentCity: (pickData['city'] ?? '').toString(),
            opponentElo:
                (pickData['elo'] as num?)?.toInt() ?? 1000,
            isOwner: ownerIsMe,
          );
        }
        // claim başarısız → aşağıdaki kuyruk yoluna düş.
      }

      // ── Rakip yok. Kendimizi kuyruğa koy + snapshot dinle. ──────────
      myQueueDoc = await db.collection(_queueCol).add(c.toMap());
      _log('Kuyruğa alındı: ${myQueueDoc.id}. Bekleniyor...');

      final completer = Completer<DueloMatchResult?>();
      late final StreamSubscription sub;
      sub = myQueueDoc.snapshots().listen((doc) async {
        if (!doc.exists) return;
        final data = doc.data();
        if (data == null) return;
        if (data['status'] == 'matched' &&
            data['matchedSessionId'] != null) {
          final sid = data['matchedSessionId'].toString();
          final sSnap =
              await db.collection(_sessionCol).doc(sid).get();
          final sData = sSnap.data() ?? {};
          final a = sData['playerA'] as Map?;
          final b = sData['playerB'] as Map?;
          Map? opp;
          if ((a?['userId'] ?? '') == c.userId) {
            opp = b;
          } else {
            opp = a;
          }
          final isOwner =
              (sData['ownerUserId'] ?? '') == c.userId;
          if (!completer.isCompleted) {
            completer.complete(DueloMatchResult(
              sessionId: sid,
              opponentUserId: (opp?['userId'] ?? '').toString(),
              opponentUsername:
                  (opp?['username'] ?? 'anonim').toString(),
              opponentFlag: (opp?['flag'] ?? '🏳️').toString(),
              opponentCountry: (opp?['country'] ?? '').toString(),
              opponentCity: (opp?['city'] ?? '').toString(),
              opponentElo: (opp?['elo'] as num?)?.toInt() ?? 1000,
              isOwner: isOwner,
            ));
          }
          await sub.cancel();
        }
      });

      // Timeout — bulunamazsa null
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () async {
          await sub.cancel();
          return null;
        },
      );

      if (result == null) {
        _log('Timeout — rakip bulunamadı.');
      }
      return result;
    } catch (e, st) {
      _log('findMatch hata: $e\n$st');
      return null;
    } finally {
      // Queue doc temizliği — best-effort.
      if (myQueueDoc != null) {
        try {
          final d = await myQueueDoc.get();
          if (d.exists && d.data()?['status'] != 'matched') {
            await myQueueDoc.delete();
          }
        } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'duelo_matchmaking'); }
      }
    }
  }

  // Session progress güncelle — her soru çözüldüğünde.
  static Future<void> updateProgress({
    required String sessionId,
    required String userId,
    required int solved,
    required int elapsedSeconds,
    bool finished = false,
    int? correct,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final ref = db.collection(_sessionCol).doc(sessionId);
      await ref.update({
        'progress.$userId.solved': solved,
        'progress.$userId.elapsed': elapsedSeconds,
        'progress.$userId.finished': finished,
        if (correct != null) 'progress.$userId.correct': correct,
      });
    } catch (e) {
      _log('updateProgress hata: $e');
    }
  }

  // Session'daki questions alanını owner tarafı doldurur (JSON serialize).
  static Future<void> writeQuestions({
    required String sessionId,
    required List<Map<String, dynamic>> questionsJson,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      await db.collection(_sessionCol).doc(sessionId).update({
        'questions': questionsJson,
        'questionsReadyAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _log('writeQuestions hata: $e');
    }
  }

  // Session snapshot stream — diğer oyuncunun ilerlemesini izlemek için.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> sessionStream(
      String sessionId) {
    return FirebaseFirestore.instance
        .collection(_sessionCol)
        .doc(sessionId)
        .snapshots();
  }

  // Rövanş isteği — GERÇEK düello daveti olarak gönderilir. Eski hâli hiçbir
  // tarafın dinlemediği `rematch_requests` koleksiyonuna hedef uid'siz doc
  // yazıyordu: buton "istek gönderildi" dese de karşıya HİÇ ulaşmıyordu.
  // Artık kullanıcı adı `usernames/{name}` kaydından uid'ye çözülür ve normal
  // davet (duelo_invites inbox + bildirim) yolu kullanılır.
  /// true → davet gerçekten gönderildi; false → kullanıcı bulunamadı/hata.
  static Future<bool> requestRematch({
    required String opponentUsername,
    required String subjectName,
    required String topicName,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      // '@' önekiyle gelirse temizle (sonuç ekranı adları '@ad' basar).
      final uname = opponentUsername.trim().toLowerCase().replaceFirst('@', '');
      if (uname.isEmpty) return false;
      String targetUid = '';
      final reg = await db.collection('usernames').doc(uname).get();
      targetUid = (reg.data()?['uid'] ?? '').toString();
      // YEDEK: rezervasyon sistemi öncesi hesapların `usernames/{ad}` kaydı
      // yok — rövanş HİÇ gönderilemiyordu. users koleksiyonundan çöz.
      if (targetUid.isEmpty) {
        final snap = await db
            .collection('users')
            .where('username', isEqualTo: uname)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) targetUid = snap.docs.first.id;
      }
      if (targetUid.isEmpty) {
        _log('requestRematch: @$opponentUsername uid bulunamadı');
        return false;
      }
      return invite(
        targetUid: targetUid,
        targetUsername: opponentUsername,
        subjectKey: subjectName,
        topic: topicName.isEmpty ? null : topicName,
      );
    } catch (e) {
      _log('requestRematch hata: $e');
      return false;
    }
  }

  /// Belirli bir arkadaşa düello daveti gönder.
  /// `duelo_invites/{targetUid}/inbox/{auto}` doc'u yazılır.
  /// Cloud Function `onDueloInviteAccepted` kabul edilince session açar +
  /// her iki tarafa bildirim atar.
  /// Auth yoksa veya hata → false döner.
  static Future<bool> invite({
    required String targetUid,
    required String targetUsername,
    String? subjectKey,
    String? topic,
    // Yarışma ayarları: soru sayısı ve tipi ('mc' | 'tf'). Kabul edilince
    // owner tarafı bu ayarlarla soru üretir; guest session'dan aynı seti okur.
    int questionCount = 5,
    String questionType = 'mc',
  }) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || me == targetUid) return false;
    try {
      final db = FirebaseFirestore.instance;
      // Kendi profili (snapshot)
      final mySnap = await db.collection('users').doc(me).get();
      final myProfile = mySnap.data() ?? const <String, dynamic>{};
      // Alıcı hem İSMİ hem kullanıcı adını görsün. users doc'u eksik/boşsa
      // (profil hiç upsert edilmemiş) YEREL profile ve auth adına düşülür —
      // eskiden her ikisi de boş kalınca push "Birisi seninle..." diyordu.
      var myUname = (myProfile['username'] ?? '').toString().trim();
      var myDisplay = (myProfile['displayName'] ?? '').toString().trim();
      if (myUname.isEmpty || myDisplay.isEmpty) {
        try {
          final p = UserProfileService.instance;
          await p.init(); // idempotent
          if (myUname.isEmpty) myUname = p.username.trim();
          if (myDisplay.isEmpty) myDisplay = p.displayName.trim();
        } catch (_) {}
      }
      if (myDisplay.isEmpty) myDisplay = myUname;
      if (myDisplay.isEmpty) {
        myDisplay =
            (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
      }
      final myName = myDisplay;

      // Davet doc'u — fromUid + profile snapshot ile (trigger function bunları okur)
      await db
          .collection('duelo_invites')
          .doc(targetUid)
          .collection('inbox')
          .doc()
          .set({
        'fromUid': me,
        'fromUsername': myUname,
        'fromDisplayName': myName,
        'fromAvatar': myProfile['avatar'] ?? '',
        'targetUid': targetUid,
        'targetUsername': targetUsername,
        'subjectKey': subjectKey,
        'topic': topic,
        'questionCount': questionCount,
        'questionType': questionType,
        'sentAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      // In-app bildirim (FCM push'u tetikler)
      await db
          .collection('notifications')
          .doc(targetUid)
          .collection('items')
          .doc()
          .set({
        'type': 'duelo_invite',
        'fromUid': me,
        'fromUsername': myUname,
        'fromDisplayName': myName,
        'fromAvatar': myProfile['avatar'] ?? '',
        'targetUsername': targetUsername,
        'subjectKey': subjectKey,
        'topic': topic,
        'questionCount': questionCount,
        'questionType': questionType,
        'when': FieldValue.serverTimestamp(),
        'read': false,
      });
      _log('Düello daveti → @$targetUsername');
      return true;
    } catch (e) {
      _log('invite hata: $e');
      return false;
    }
  }

  /// Bekleyen düello davetlerini stream — UI badge ve inbox için.
  static Stream<List<DueloInvite>> watchInvites() {
    if (Firebase.apps.isEmpty) return Stream.value(const []);
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection('duelo_invites')
        .doc(me)
        .collection('inbox')
        .where('status', isEqualTo: 'pending')
        // orderBy('sentAt') KULLANILMAZ: (1) eşitlik + orderBy bileşik indeks
        // ister, indeks yoksa sorgu HATA verip liste sessizce boş kalıyordu
        // (zil rozeti/davet listesi "görünmüyor" şikayeti); (2) sentAt alanı
        // henüz yazılmamış (pending serverTimestamp) doc'lar sorgudan
        // düşürülüyordu. İstemcide sıralanır.
        .snapshots()
        .map((s) {
          // SÜRE AŞIMI: davetler süresiz geçerliydi — saatler sonra kabul
          // edilen davette gönderen çoktan gitmiş oluyor, kabul eden taraf
          // hiç yazılmayacak soruları bekleyip kilitleniyordu. 2 saatten
          // eski pending davetler listelenmez.
          final cutoff =
              DateTime.now().subtract(const Duration(hours: 2));
          return s.docs
              .map(DueloInvite.fromDoc)
              .where((i) => i.sentAt.isAfter(cutoff))
              .toList()
            ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
        })
        // handleError'ın return değeri YAYILMAZ (friend_service'te belgelenen
        // aynı tuzak) — hata anında sink'e boş liste basılmazsa davet sheet'i
        // sonsuz spinner'da kalıyordu.
        .transform(
            StreamTransformer<List<DueloInvite>, List<DueloInvite>>.fromHandlers(
          handleError: (e, st, sink) {
            debugPrint('[Duelo] watchInvites error: $e');
            sink.add(const <DueloInvite>[]);
          },
        ));
  }

  /// Düello davetini kabul et → Cloud Function tetiklenir, session açar.
  static Future<bool> acceptInvite({required String inviteId}) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return false;
    try {
      await FirebaseFirestore.instance
          .collection('duelo_invites')
          .doc(me)
          .collection('inbox')
          .doc(inviteId)
          .update({
        'status': 'accepted',
        'respondedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      _log('acceptInvite fail: $e');
      return false;
    }
  }

  /// Düello davetini reddet.
  static Future<bool> rejectInvite({required String inviteId}) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return false;
    try {
      await FirebaseFirestore.instance
          .collection('duelo_invites')
          .doc(me)
          .collection('inbox')
          .doc(inviteId)
          .update({
        'status': 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      _log('rejectInvite fail: $e');
      return false;
    }
  }

  // Kullanıcı vazgeçerse — queue temizlik. (Opsiyonel çağrılır.)
  static Future<void> cancelQueue(String userId) async {
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db
          .collection(_queueCol)
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'waiting')
          .get();
      for (final d in snap.docs) {
        await d.reference.delete();
      }
    } catch (e) {
      _log('cancelQueue hata: $e');
    }
  }
}
