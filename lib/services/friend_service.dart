// ═══════════════════════════════════════════════════════════════════════════════
//  FriendService — Arkadaşlık ilişkileri (Firestore tabanlı).
//
//  ŞEMA:
//    users/{uid}
//      username        : string (lower, [a-z0-9_], 3-20)
//      displayName     : string
//      avatar          : string (emoji veya url)
//      country         : string
//      grade           : string
//      createdAt       : Timestamp
//      lastSeen        : Timestamp
//      searchTokens    : [string]   ← prefix tokens, username araması için
//
//    friend_requests/{toUid}/inbox/{fromUid}
//      fromUid         : string
//      fromUsername    : string
//      fromDisplayName : string
//      fromAvatar      : string
//      sentAt          : Timestamp
//      status          : 'pending' | 'accepted' | 'rejected'
//
//    friends/{uid}/list/{friendUid}
//      uid             : string
//      username        : string
//      displayName     : string
//      avatar          : string
//      since           : Timestamp
//
//  AKIŞ:
//    1. A → sendRequest(B)
//       • friend_requests/B/inbox/A doc'unu pending olarak yarat
//       • A'nın notifications/A koleksiyonuna ekle (B kabul edince güncellenir)
//    2. B kabul ederse acceptRequest(A)
//       • friends/A/list/B  ve  friends/B/list/A  oluşur (atomic batch)
//       • friend_requests/B/inbox/A → status='accepted'
//       • notifications/A → "B isteğini kabul etti"
//    3. B reddederse rejectRequest(A)
//       • friend_requests/B/inbox/A → status='rejected'
//
//  AUTH yoksa tüm metotlar sessiz null/false döner — UI graceful'la güner.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FriendUser {
  final String uid;
  final String username;
  final String displayName;
  final String avatar;
  final String? country;
  final String? grade;
  final String statusMessage;
  /// Base64 data URL veya emoji. UI bunu doğrudan Image.memory/Text ile render edebilir.
  final String avatarData;
  const FriendUser({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.avatar,
    this.country,
    this.grade,
    this.statusMessage = '',
    this.avatarData = '',
  });

  factory FriendUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return FriendUser(
      uid: doc.id,
      username: (m['username'] ?? '').toString(),
      displayName: (m['displayName'] ?? '').toString(),
      avatar: (m['avatar'] ?? '').toString(),
      country: m['country']?.toString(),
      grade: m['grade']?.toString(),
      statusMessage: (m['statusMessage'] ?? '').toString(),
      avatarData: (m['avatarData'] ?? '').toString(),
    );
  }
}

class FriendRequest {
  final String fromUid;
  final String fromUsername;
  final String fromDisplayName;
  final String fromAvatar;
  final DateTime sentAt;
  final String status; // pending | accepted | rejected
  const FriendRequest({
    required this.fromUid,
    required this.fromUsername,
    required this.fromDisplayName,
    required this.fromAvatar,
    required this.sentAt,
    required this.status,
  });

  factory FriendRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    final ts = m['sentAt'];
    DateTime when = DateTime.now();
    if (ts is Timestamp) when = ts.toDate();
    return FriendRequest(
      fromUid: (m['fromUid'] ?? doc.id).toString(),
      fromUsername: (m['fromUsername'] ?? '').toString(),
      fromDisplayName: (m['fromDisplayName'] ?? '').toString(),
      fromAvatar: (m['fromAvatar'] ?? '').toString(),
      sentAt: when,
      status: (m['status'] ?? 'pending').toString(),
    );
  }
}

class Friend {
  final String uid;
  final String username;
  final String displayName;
  final String avatar;
  final DateTime since;
  const Friend({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.avatar,
    required this.since,
  });

  factory Friend.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    final ts = m['since'];
    DateTime when = DateTime.now();
    if (ts is Timestamp) when = ts.toDate();
    return Friend(
      uid: (m['uid'] ?? doc.id).toString(),
      username: (m['username'] ?? '').toString(),
      displayName: (m['displayName'] ?? '').toString(),
      avatar: (m['avatar'] ?? '').toString(),
      since: when,
    );
  }
}

class FriendService {
  static FirebaseFirestore get _fs => FirebaseFirestore.instance;
  static String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  // ── PUBLIC PROFILE — login sonrası bir kez kaydedilir ─────────────────────

  /// Kullanıcının public profilini `users/{uid}` doc'una upsert eder.
  /// İlk login'de + profil değiştirildiğinde çağrılmalı.
  /// `username` benzersizliği KONTROL EDİLMEZ — bunu UI tarafı yapar.
  static Future<void> upsertMyProfile({
    required String username,
    required String displayName,
    required String avatar,
    String? country,
    String? grade,
    String? email,
    /// Kullanıcının kendi yazdığı kısa biyografi/durum mesajı. Profilde
    /// gösterilir, arkadaş kartlarında görünebilir. null → değişmez.
    String? statusMessage,
    /// 100x100 JPEG'in base64 data URL'i ("data:image/jpeg;base64,..."). Friend
    /// kartında küçük avatar olarak gösterilir. null → değişmez.
    /// Boş string ("") gönderirse cloud'daki resim silinir.
    String? avatarData,
  }) async {
    final uid = _myUid;
    if (uid == null) return;
    final clean = _normalizeUsername(username);
    final tokens = _searchTokens(clean, displayName);
    final payload = <String, dynamic>{
      'username': clean,
      'displayName': displayName.trim(),
      'avatar': avatar,
      if (country != null) 'country': country,
      if (grade != null) 'grade': grade,
      // Email — rehber eşleştirmesi için (whereIn arama). Lowercase normalize.
      if (email != null && email.isNotEmpty) 'email': email.trim().toLowerCase(),
      if (statusMessage != null) 'statusMessage': statusMessage.trim(),
      if (avatarData != null) 'avatarData': avatarData,
      'searchTokens': tokens,
      'lastSeen': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
    await _fs.collection('users').doc(uid).set(payload, SetOptions(merge: true));
  }

  /// Sadece `lastSeen` timestamp'ini günceller — uygulama açılışında çağrılır.
  static Future<void> touchLastSeen() async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      await _fs.collection('users').doc(uid).set({
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {/* offline → görmezden gel */}
  }

  /// Username benzersizlik kontrolü — true = uygun, false = alınmış.
  static Future<bool> isUsernameAvailable(String username) async {
    final clean = _normalizeUsername(username);
    if (clean.length < 3) return false;
    try {
      final snap = await _fs
          .collection('users')
          .where('username', isEqualTo: clean)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return true;
      // Kendimize aitse uygun say.
      return snap.docs.first.id == _myUid;
    } catch (e) {
      debugPrint('[FriendService] username check fail: $e');
      return false;
    }
  }

  /// Username'i ATOMİK olarak rezerve eder → gerçek benzersizlik garantisi.
  /// Sıradan `where('username')` sorgusu TOCTOU yarışına açıktır; bu metod
  /// `usernames/{ad}` doc'unu transaction içinde oluşturarak eşzamanlı iki
  /// kullanıcının aynı adı almasını engeller.
  ///
  /// Dönüş: true = ad artık bizim (yeni alındı ya da zaten bizimdi),
  ///        false = başkası almış → çağıran "başka ad gir" demeli.
  static Future<bool> claimUsername(String username) async {
    final uid = _myUid;
    if (uid == null) return false;
    final clean = _normalizeUsername(username);
    if (clean.length < 3) return false;
    try {
      // (1) Rezervasyon sistemi öncesi kayıtlı eski kullanıcılar adı yalnızca
      //     users doc'unda tutuyor olabilir. Transaction koleksiyon
      //     sorgulayamadığı için bunu ayrıca kontrol et.
      final existing = await _fs
          .collection('users')
          .where('username', isEqualTo: clean)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty && existing.docs.first.id != uid) {
        return false;
      }
      // (2) Atomik rezervasyon — doc yoksa oluştur, varsa sahibi biz miyiz bak.
      final ref = _fs.collection('usernames').doc(clean);
      return await _fs.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) {
          return (snap.data()?['uid'] ?? '').toString() == uid;
        }
        tx.set(ref, {
          'uid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
    } catch (e) {
      debugPrint('[FriendService] claimUsername fail: $e');
      return false;
    }
  }

  /// Eski username rezervasyonunu bırakır (kullanıcı adını değiştirince).
  /// Sessiz başarısız — kritik değil.
  static Future<void> releaseUsername(String username) async {
    final uid = _myUid;
    if (uid == null) return;
    final clean = _normalizeUsername(username);
    if (clean.length < 3) return;
    try {
      await _fs.collection('usernames').doc(clean).delete();
    } catch (_) {}
  }

  // ── ARAMA ─────────────────────────────────────────────────────────────────

  /// Username prefix araması — `searchTokens` arrayContains ile.
  /// Boş query → boş liste. En fazla `limit` sonuç.
  static Future<List<FriendUser>> searchUsers(String query,
      {int limit = 15}) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    try {
      final me = _myUid;
      final snap = await _fs
          .collection('users')
          .where('searchTokens', arrayContains: q)
          .limit(limit)
          .get();
      final results = snap.docs
          .where((d) => d.id != me) // kendini gösterme
          .map(FriendUser.fromDoc)
          .toList();
      // YEDEK: token araması boş döndüyse (eski/eksik searchTokens'lı doc'lar)
      // tam kullanıcı adıyla doğrudan eşleşmeyi dene — böylece kayıtlı her
      // kullanıcı adı, token'ı olmasa bile bulunur (1v1 davet için kritik).
      if (results.isEmpty) {
        final exactSnap = await _fs
            .collection('users')
            .where('username', isEqualTo: q)
            .limit(1)
            .get();
        for (final d in exactSnap.docs) {
          if (d.id != me) results.add(FriendUser.fromDoc(d));
        }
      }
      return results;
    } catch (e) {
      debugPrint('[FriendService] search fail: $e');
      return const [];
    }
  }

  static Future<FriendUser?> getUserByUsername(String username) async {
    final clean = _normalizeUsername(username);
    if (clean.isEmpty) return null;
    try {
      final snap = await _fs
          .collection('users')
          .where('username', isEqualTo: clean)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return FriendUser.fromDoc(snap.docs.first);
    } catch (e) {
      debugPrint('[FriendService] getUser fail: $e');
      return null;
    }
  }

  static Future<FriendUser?> getUserByUid(String uid) async {
    try {
      final doc = await _fs.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return FriendUser.fromDoc(doc);
    } catch (_) {
      return null;
    }
  }

  // ── İSTEK GÖNDER / KABUL / RED ────────────────────────────────────────────

  /// A → B'ye istek gönder. Aynı istek varsa idempotent (üzerine yazar).
  /// Kendine istek atılamaz, zaten arkadaşsa false döner.
  /// Başkalarına görünen ad — DAİMA kullanıcı adı (username); boşsa displayName.
  static String _publicName(Map<String, dynamic> u) {
    final un = (u['username'] ?? '').toString().trim();
    if (un.isNotEmpty) return un;
    return (u['displayName'] ?? '').toString().trim();
  }

  static Future<bool> sendRequest({required String toUid}) async {
    final fromUid = _myUid;
    if (fromUid == null || fromUid == toUid) return false;

    // Zaten arkadaşsa atla
    final existing =
        await _fs.collection('friends').doc(fromUid).collection('list').doc(toUid).get();
    if (existing.exists) return false;

    // Kendi profilimi çek (snapshot olarak isteğe gömeceğim)
    final mySnap = await _fs.collection('users').doc(fromUid).get();
    final me = mySnap.data() ?? const <String, dynamic>{};
    // Karşı tarafta DAİMA kullanıcı adı görünsün (kullanıcı ne belirlediyse o).
    // Username boşsa displayName'e düşülür.
    final myName = _publicName(me);

    final batch = _fs.batch();
    final reqRef = _fs
        .collection('friend_requests')
        .doc(toUid)
        .collection('inbox')
        .doc(fromUid);
    batch.set(reqRef, {
      'fromUid': fromUid,
      'fromUsername': me['username'] ?? '',
      'fromDisplayName': myName,
      'fromAvatar': me['avatar'] ?? '',
      'sentAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });

    // Karşı tarafa in-app bildirim
    final notifRef = _fs
        .collection('notifications')
        .doc(toUid)
        .collection('items')
        .doc();
    batch.set(notifRef, {
      'type': 'friend_request',
      'fromUid': fromUid,
      'fromUsername': me['username'] ?? '',
      'fromDisplayName': myName,
      'fromAvatar': me['avatar'] ?? '',
      'when': FieldValue.serverTimestamp(),
      'read': false,
    });

    try {
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[FriendService] sendRequest fail: $e');
      return false;
    }
  }

  /// B, A'nın isteğini kabul eder → iki yönlü arkadaşlık oluşur.
  static Future<bool> acceptRequest({required String fromUid}) async {
    final toUid = _myUid;
    if (toUid == null) return false;
    try {
      // İki kullanıcının profillerini çek (snapshot)
      final aSnap = await _fs.collection('users').doc(fromUid).get();
      final bSnap = await _fs.collection('users').doc(toUid).get();
      final a = aSnap.data() ?? const <String, dynamic>{};
      final b = bSnap.data() ?? const <String, dynamic>{};

      final batch = _fs.batch();
      // A'nın listesine B
      batch.set(
        _fs.collection('friends').doc(fromUid).collection('list').doc(toUid),
        {
          'uid': toUid,
          'username': b['username'] ?? '',
          'displayName': _publicName(b),
          'avatar': b['avatar'] ?? '',
          'since': FieldValue.serverTimestamp(),
        },
      );
      // B'nin listesine A
      batch.set(
        _fs.collection('friends').doc(toUid).collection('list').doc(fromUid),
        {
          'uid': fromUid,
          'username': a['username'] ?? '',
          'displayName': _publicName(a),
          'avatar': a['avatar'] ?? '',
          'since': FieldValue.serverTimestamp(),
        },
      );
      // Request status update
      batch.update(
        _fs
            .collection('friend_requests')
            .doc(toUid)
            .collection('inbox')
            .doc(fromUid),
        {'status': 'accepted', 'respondedAt': FieldValue.serverTimestamp()},
      );
      // A'ya kabul bildirimi
      batch.set(
        _fs.collection('notifications').doc(fromUid).collection('items').doc(),
        {
          'type': 'friend_accepted',
          'fromUid': toUid,
          'fromUsername': b['username'] ?? '',
          'fromDisplayName': _publicName(b),
          'fromAvatar': b['avatar'] ?? '',
          'when': FieldValue.serverTimestamp(),
          'read': false,
        },
      );
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[FriendService] accept fail: $e');
      return false;
    }
  }

  /// B, A'nın isteğini reddeder.
  static Future<bool> rejectRequest({required String fromUid}) async {
    final toUid = _myUid;
    if (toUid == null) return false;
    try {
      await _fs
          .collection('friend_requests')
          .doc(toUid)
          .collection('inbox')
          .doc(fromUid)
          .update({
        'status': 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[FriendService] reject fail: $e');
      return false;
    }
  }

  /// Arkadaşı sil — iki yönlü.
  static Future<bool> removeFriend({required String friendUid}) async {
    final me = _myUid;
    if (me == null) return false;
    try {
      final batch = _fs.batch();
      batch.delete(_fs
          .collection('friends')
          .doc(me)
          .collection('list')
          .doc(friendUid));
      batch.delete(_fs
          .collection('friends')
          .doc(friendUid)
          .collection('list')
          .doc(me));
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[FriendService] remove fail: $e');
      return false;
    }
  }

  // ── STREAMS ───────────────────────────────────────────────────────────────

  /// Kendi arkadaş listesini real-time dinle.
  static Stream<List<Friend>> watchFriends() {
    if (Firebase.apps.isEmpty) return Stream.value(const []);
    final uid = _myUid;
    if (uid == null) return Stream.value(const []);
    return _fs
        .collection('friends')
        .doc(uid)
        .collection('list')
        .orderBy('since', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Friend.fromDoc).toList())
        // NOT: handleError içinde `return` DEĞER YAYMAZ (Dart'ta atılır) —
        // hata anında stream sessiz kalır ve StreamBuilder spinner'da takılı
        // kalırdı. Transformer sink'e boş liste BASARAK düzeltildi.
        .transform(StreamTransformer<List<Friend>, List<Friend>>.fromHandlers(
      handleError: (e, st, sink) {
        debugPrint('[FriendService] watchFriends error: $e');
        sink.add(const <Friend>[]);
      },
    ));
  }

  /// Bekleyen gelen istekleri dinle.
  static Stream<List<FriendRequest>> watchPendingRequests() {
    if (Firebase.apps.isEmpty) return Stream.value(const []);
    final uid = _myUid;
    if (uid == null) return Stream.value(const []);
    return _fs
        .collection('friend_requests')
        .doc(uid)
        .collection('inbox')
        .where('status', isEqualTo: 'pending')
        .orderBy('sentAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(FriendRequest.fromDoc).toList())
        // handleError'da return değer yaymaz — sink'e boş liste bas (üstteki
        // watchFriends ile aynı düzeltme).
        .transform(
            StreamTransformer<List<FriendRequest>, List<FriendRequest>>.fromHandlers(
      handleError: (e, st, sink) {
        debugPrint('[FriendService] watchRequests error: $e');
        sink.add(const <FriendRequest>[]);
      },
    ));
  }

  /// Arkadaşların son aktiviteleri — `league_attempts` koleksiyonundan
  /// `uid in [friend uids]` filtresiyle çekilir. Friend listesi 30'dan büyükse
  /// chunk'lara böler (Firestore whereIn limit'i).
  static Future<List<Map<String, dynamic>>> friendsActivity({
    int limit = 30,
  }) async {
    final me = _myUid;
    if (me == null) return const [];
    try {
      final friendsSnap =
          await _fs.collection('friends').doc(me).collection('list').get();
      if (friendsSnap.docs.isEmpty) return const [];
      final uids = friendsSnap.docs.map((d) => d.id).toList();
      // Firestore whereIn limit 30 → ilk 30 arkadaşa bak.
      final batch = uids.length > 30 ? uids.sublist(0, 30) : uids;
      final attempts = await _fs
          .collection('league_attempts')
          .where('uid', whereIn: batch)
          .orderBy('when', descending: true)
          .limit(limit)
          .get();
      return attempts.docs.map((d) => d.data()).toList();
    } catch (e) {
      debugPrint('[FriendService] activity fail: $e');
      return const [];
    }
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  /// Username normalize — lower, sadece [a-z0-9_], maks 20 karakter.
  static String _normalizeUsername(String raw) {
    // ÖNCE temizle (boşluk/Türkçe/özel karakterleri at), SONRA uzunluğa göre
    // kırp. Eskiden substring bound'u orijinal `raw.length` idi; karakter
    // silinince temizlenmiş string kısalıyor ve substring RangeError atıyordu
    // (boşluk/Türkçe içeren her kullanıcı adı kaydı/araması sessizce patlıyordu).
    final cleaned =
        raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return cleaned.length > 20 ? cleaned.substring(0, 20) : cleaned;
  }

  /// Prefix search tokens — username ve displayName'in 2-N karakterlik
  /// prefix'lerini üretir. Firestore arrayContains ile arama yapmak için.
  static List<String> _searchTokens(String username, String displayName) {
    final tokens = <String>{};
    void addPrefixes(String s) {
      final lower = s.toLowerCase().trim();
      if (lower.isEmpty) return;
      for (int i = 2; i <= lower.length && i <= 20; i++) {
        tokens.add(lower.substring(0, i));
      }
    }
    addPrefixes(username);
    for (final w in displayName.toLowerCase().split(RegExp(r'\s+'))) {
      addPrefixes(w);
    }
    return tokens.toList();
  }
}
