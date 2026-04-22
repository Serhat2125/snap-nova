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
import 'package:flutter/foundation.dart';

// Eşleşme isteği kriterleri.
class DueloMatchCriteria {
  final String userId;
  final String username;
  final String flag;
  final String country;
  final String level; // primary | middle | high | university
  final String grade; // "11", "lgs" vb.
  final String? track; // sayisal, sozel, ipa ...
  final String scope; // 'world' | 'country'
  final String subjectKey;
  final String? topic;
  final int elo;

  DueloMatchCriteria({
    required this.userId,
    required this.username,
    required this.flag,
    required this.country,
    required this.level,
    required this.grade,
    this.track,
    required this.scope,
    required this.subjectKey,
    this.topic,
    this.elo = 1000,
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'username': username,
        'flag': flag,
        'country': country,
        'level': level,
        'grade': grade,
        'track': track,
        'scope': scope,
        'subjectKey': subjectKey,
        'topic': topic,
        'elo': elo,
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
    required this.opponentElo,
    required this.isOwner,
  });
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
          .where('subjectKey', isEqualTo: c.subjectKey);
      if (c.scope == 'country') {
        q = q.where('country', isEqualTo: c.country);
      }

      // Topic varsa önce topic-eşleşen aday; yoksa aynı dersten herhangi biri
      // (lobby aşamasında konu zorunlu tutulmuyorsa bu esnek).
      final snap = await q.limit(10).get();
      final candidates = snap.docs
          .where((d) => d.data()['userId'] != c.userId)
          .toList();

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
          'elo': c.elo,
        };
        final playerB = {
          'userId': pickData['userId'],
          'username': pickData['username'],
          'flag': pickData['flag'],
          'country': pickData['country'],
          'elo': pickData['elo'] ?? 1000,
        };

        await db.runTransaction((tx) async {
          tx.set(sessionRef, {
            'ownerUserId':
                ownerIsMe ? c.userId : pickData['userId'],
            'playerA': playerA,
            'playerB': playerB,
            'subjectKey': c.subjectKey,
            'topic': c.topic ?? pickData['topic'],
            'scope': c.scope,
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
          tx.update(pick!.reference, {
            'status': 'matched',
            'matchedSessionId': sessionId,
            'matchedAt': FieldValue.serverTimestamp(),
          });
        });

        _log('Eşleştirildi → session $sessionId (owner=$ownerIsMe)');
        return DueloMatchResult(
          sessionId: sessionId,
          opponentUserId: (pickData['userId'] ?? '').toString(),
          opponentUsername:
              (pickData['username'] ?? 'anonim').toString(),
          opponentFlag: (pickData['flag'] ?? '🏳️').toString(),
          opponentCountry: (pickData['country'] ?? '').toString(),
          opponentElo:
              (pickData['elo'] as num?)?.toInt() ?? 1000,
          isOwner: ownerIsMe,
        );
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
        } catch (_) {}
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

  // Rövanş isteği — rakibin userId'sini biliyorsak Firestore'a bildirim
  // dokümanı yazar. Client tarafı bu koleksiyonu dinleyince bildirim gösterir.
  // Şu an dev modda opponent mock olduğu için yalnızca best-effort log.
  static Future<void> requestRematch({
    required String opponentUsername,
    required String subjectName,
    required String topicName,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('rematch_requests').add({
        'opponentUsername': opponentUsername,
        'subjectName': subjectName,
        'topicName': topicName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _log('Rövanş isteği yazıldı → @$opponentUsername');
    } catch (e) {
      _log('requestRematch hata: $e');
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
