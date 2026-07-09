// ═══════════════════════════════════════════════════════════════════════════════
//  ContestGroupService — Kayıtlı bilgi yarışı grupları.
//
//  FİKİR:
//    Bir grup yarışı yapıldıktan sonra o grup İSİMLENDİRİLİP kaydedilir. Böylece
//    aynı arkadaşlarla tekrar tekrar yarışılabilir. Her grubun bir adı, profil
//    emojisi ve durum mesajı vardır; sahibi bunları istediği zaman değiştirebilir.
//    Kayıtlı gruplar herkesin "Bilgi Yarışı" sekmesinde Grup Yarışı bannerının
//    hemen altında yatayda (en fazla 4 grup) görünür.
//
//    Gruba basınca yeni bir yarış başlatılır ve grubun TÜM üyelerine anında
//    bildirim gider ("<kullanıcı> grup yarışı açtı ve seni davet etti").
//
//  ŞEMA:
//    contest_groups/{groupId}
//      name, avatar (emoji), status (durum mesajı)
//      ownerUid, ownerName
//      memberUids: [uid...]        ← arrayContains sorgusu için
//      members: [ {uid, username, avatar} ]
//      lastSubjectKey/Name/Emoji/Topic   ← son yarışın kısayolu (opsiyonel)
//      createdAt, updatedAt
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'user_profile_service.dart';

class ContestGroup {
  final String id;
  final String name;
  final String avatar;
  final String status;
  final String ownerUid;
  final String ownerName;
  final List<String> memberUids;
  final List<Map<String, dynamic>> members;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ContestGroup({
    required this.id,
    required this.name,
    required this.avatar,
    required this.status,
    required this.ownerUid,
    required this.ownerName,
    required this.memberUids,
    required this.members,
    this.createdAt,
    this.updatedAt,
  });

  int get memberCount => memberUids.length;

  factory ContestGroup.fromDoc(String id, Map<String, dynamic> d) {
    return ContestGroup(
      id: id,
      name: (d['name'] ?? 'Grubum').toString(),
      avatar: (d['avatar'] ?? '👥').toString(),
      status: (d['status'] ?? '').toString(),
      ownerUid: (d['ownerUid'] ?? '').toString(),
      ownerName: (d['ownerName'] ?? '').toString(),
      memberUids: ((d['memberUids'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      members: ((d['members'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Gelen bir grup yarışı daveti (notifications/{uid}/items içinden).
class GroupInvite {
  final String id;
  final String contestId;
  final String groupId;
  final String groupName;
  final String fromUid;
  final String fromUsername;
  final String fromDisplayName;
  final String fromAvatar;
  final String subjectName;
  final String topic;
  final DateTime when;

  const GroupInvite({
    required this.id,
    required this.contestId,
    required this.groupId,
    required this.groupName,
    required this.fromUid,
    required this.fromUsername,
    required this.fromDisplayName,
    required this.fromAvatar,
    required this.subjectName,
    required this.topic,
    required this.when,
  });

  factory GroupInvite.fromDoc(String id, Map<String, dynamic> d) {
    final ts = d['when'];
    return GroupInvite(
      id: id,
      contestId: (d['contestId'] ?? '').toString(),
      groupId: (d['groupId'] ?? '').toString(),
      groupName: (d['groupName'] ?? '').toString(),
      fromUid: (d['fromUid'] ?? '').toString(),
      fromUsername: (d['fromUsername'] ?? '').toString(),
      fromDisplayName: (d['fromDisplayName'] ?? '').toString(),
      fromAvatar: (d['fromAvatar'] ?? '👤').toString(),
      subjectName: (d['subjectName'] ?? '').toString(),
      topic: (d['topic'] ?? '').toString(),
      when: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}

class ContestGroupService {
  ContestGroupService._();

  // Firebase app'i olmayan platformlarda (örn. web config'i henüz yok)
  // FirebaseFirestore.instance / FirebaseAuth.instance SENKRON fırlatır ve
  // build içinden çağrıldığında kırmızı hata ekranı üretir. `static final`
  // yerine getter + Firebase.apps korumasıyla güvenli erişim.
  static FirebaseFirestore get _fs => FirebaseFirestore.instance;
  static const _collection = 'contest_groups';

  static String? get _uid {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Gelen grup yarışı davetleri — en yeni en başta.
  static Stream<List<GroupInvite>> watchGroupInvites() {
    final uid = _uid;
    if (uid == null) return Stream.value(const <GroupInvite>[]);
    return _fs
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .where('type', isEqualTo: 'group_contest_invite')
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => GroupInvite.fromDoc(d.id, d.data()))
          .toList();
      list.sort((a, b) => b.when.compareTo(a.when));
      return list;
    });
  }

  /// Bir grup davetini (bildirimi) sil.
  static Future<void> dismissInvite(String inviteId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _fs
          .collection('notifications')
          .doc(uid)
          .collection('items')
          .doc(inviteId)
          .delete();
    } catch (e) {
      debugPrint('[ContestGroup] dismissInvite fail: $e');
    }
  }

  // ─── Oluştur ───────────────────────────────────────────────────────────────

  /// Yeni grup oluşturur (sahibi ilk üye). [seedMembers] verilirse (ör. bir
  /// yarışmanın katılımcıları) onlar da üye olarak eklenir. Grup id'sini döner.
  static Future<String?> createGroup({
    required String name,
    String avatar = '👥',
    String status = '',
    List<Map<String, dynamic>> seedMembers = const [],
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final p = UserProfileService.instance;
      final ownerName =
          p.username.trim().isNotEmpty ? p.username.trim() : 'Oyuncu';

      // Sahip + tohum üyeleri tekilleştir (uid bazında).
      // avatarData (base64 profil fotoğrafı) da üye kaydına eklenir —
      // diğer üyeler grup listesinde gerçek fotoğrafı görsün. Boyut guard'ı:
      // members dizisi tek dokümanda yaşar (1MB limit), aşırı büyük base64
      // yazılmaz; o durumda UI zaten users/{uid}'den canlı çeker.
      final members = <Map<String, dynamic>>[
        {
          'uid': uid,
          'username': ownerName,
          'avatar': p.avatar,
          if (p.avatarData.isNotEmpty && p.avatarData.length < 60000)
            'avatarData': p.avatarData,
        }
      ];
      final seenUids = <String>{uid};
      for (final m in seedMembers) {
        final mu = (m['uid'] ?? '').toString();
        if (mu.isEmpty || !seenUids.add(mu)) continue;
        final mAvatarData = (m['avatarData'] ?? '').toString();
        members.add({
          'uid': mu,
          'username': (m['username'] ?? 'Oyuncu').toString(),
          'avatar': (m['avatar'] ?? '👤').toString(),
          if (mAvatarData.isNotEmpty && mAvatarData.length < 60000)
            'avatarData': mAvatarData,
        });
      }

      final doc = _fs.collection(_collection).doc();
      await doc.set({
        'name': name.trim().isEmpty ? 'Grubum' : name.trim(),
        'avatar': avatar.trim().isEmpty ? '👥' : avatar.trim(),
        'status': status.trim(),
        'ownerUid': uid,
        'ownerName': ownerName,
        'memberUids': members.map((m) => m['uid']).toList(),
        'members': members,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      debugPrint('[ContestGroup] createGroup fail: $e');
      return null;
    }
  }

  // ─── Okuma ─────────────────────────────────────────────────────────────────

  /// Mevcut kullanıcının üye olduğu gruplar — en son kullanılan en başta,
  /// en fazla 4 grup.
  static Stream<List<ContestGroup>> myGroupsStream() {
    final uid = _uid;
    if (uid == null) {
      return const Stream<List<ContestGroup>>.empty();
    }
    return _fs
        .collection(_collection)
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => ContestGroup.fromDoc(d.id, d.data()))
          .toList();
      list.sort((a, b) => (b.updatedAt ?? DateTime(0))
          .compareTo(a.updatedAt ?? DateTime(0)));
      return list.take(4).toList();
    });
  }

  static Future<ContestGroup?> getGroup(String groupId) async {
    try {
      final doc = await _fs.collection(_collection).doc(groupId).get();
      if (!doc.exists) return null;
      return ContestGroup.fromDoc(doc.id, doc.data() ?? const {});
    } catch (e) {
      debugPrint('[ContestGroup] getGroup fail: $e');
      return null;
    }
  }

  // ─── Güncelle ──────────────────────────────────────────────────────────────

  /// Grup profilini güncelle (ad / emoji / durum mesajı).
  static Future<void> updateProfile(
    String groupId, {
    String? name,
    String? avatar,
    String? status,
  }) async {
    try {
      final data = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (name != null && name.trim().isNotEmpty) data['name'] = name.trim();
      if (avatar != null && avatar.trim().isNotEmpty) {
        data['avatar'] = avatar.trim();
      }
      if (status != null) data['status'] = status.trim();
      await _fs
          .collection(_collection)
          .doc(groupId)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ContestGroup] updateProfile fail: $e');
    }
  }

  /// Kullanıcıyı gruba ekle (davet linkinden/yarışa katılınca çağrılır).
  static Future<void> joinGroup(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final p = UserProfileService.instance;
      final name =
          p.username.trim().isNotEmpty ? p.username.trim() : 'Oyuncu';
      await _fs.collection(_collection).doc(groupId).set({
        'memberUids': FieldValue.arrayUnion([uid]),
        'members': FieldValue.arrayUnion([
          {
            'uid': uid,
            'username': name,
            'avatar': p.avatar,
            // Profil fotoğrafı — diğer üyeler listede görsün (boyut guard'ı
            // createGroup ile aynı gerekçe: members tek dokümanda, 1MB limit).
            if (p.avatarData.isNotEmpty && p.avatarData.length < 60000)
              'avatarData': p.avatarData,
          }
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ContestGroup] joinGroup fail: $e');
    }
  }

  /// Gruptan çık; sahibiysen grubu tamamen sil.
  static Future<void> leaveOrDelete(ContestGroup group) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      if (group.ownerUid == uid) {
        await _fs.collection(_collection).doc(group.id).delete();
      } else {
        final mine = group.members
            .where((m) => (m['uid'] ?? '').toString() == uid)
            .toList();
        await _fs.collection(_collection).doc(group.id).set({
          'memberUids': FieldValue.arrayRemove([uid]),
          if (mine.isNotEmpty) 'members': FieldValue.arrayRemove(mine),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[ContestGroup] leaveOrDelete fail: $e');
    }
  }

  // ─── Bildirim ──────────────────────────────────────────────────────────────

  /// Grubun tüm üyelerine (kendisi hariç) yarış davet bildirimi yollar.
  /// Bildirime basınca yarışma açılır (inbox 'group_contest_invite' tipini
  /// zaten işliyor).
  static Future<void> notifyMembers(
    ContestGroup group, {
    required String contestId,
    required String subjectName,
    required String topic,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final me = UserProfileService.instance;
      final myName =
          me.username.trim().isNotEmpty ? me.username.trim() : 'Oyuncu';
      final batch = _fs.batch();
      for (final m in group.memberUids) {
        if (m == uid) continue;
        final ref = _fs
            .collection('notifications')
            .doc(m)
            .collection('items')
            .doc();
        batch.set(ref, {
          'type': 'group_contest_invite',
          'contestId': contestId,
          'groupId': group.id,
          'groupName': group.name,
          'fromUid': uid,
          'fromUsername': me.username,
          'fromDisplayName': myName,
          'fromAvatar': me.avatar,
          'subjectName': subjectName,
          'topic': topic,
          'when': FieldValue.serverTimestamp(),
          'read': false,
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[ContestGroup] notifyMembers fail: $e');
    }
  }
}
