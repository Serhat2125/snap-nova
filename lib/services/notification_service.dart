// ═══════════════════════════════════════════════════════════════════════════════
//  NotificationService — In-app bildirim sistemi (Firestore).
//
//  ŞEMA:
//    notifications/{uid}/items/{auto}
//      type        : 'friend_request' | 'friend_accepted' | 'duelo_invite'
//                  | 'rank_passed' | 'streak_milestone'
//      fromUid?    : istek/davet gönderen
//      fromUsername?
//      fromDisplayName?
//      fromAvatar?
//      targetUsername? : düello hedefi
//      subjectKey?
//      topic?
//      when        : Timestamp
//      read        : bool
//
//  FCM push entegrasyonu gelecek aşamada — şu an in-app stream tabanlı.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum AppNotifType {
  friendRequest,
  friendAccepted,
  dueloInvite,
  rankPassed,
  streakMilestone,
  unknown,
}

extension AppNotifTypeX on AppNotifType {
  String get emoji {
    switch (this) {
      case AppNotifType.friendRequest:
        return '👥';
      case AppNotifType.friendAccepted:
        return '✅';
      case AppNotifType.dueloInvite:
        return '⚔️';
      case AppNotifType.rankPassed:
        return '📈';
      case AppNotifType.streakMilestone:
        return '🔥';
      case AppNotifType.unknown:
        return '🔔';
    }
  }

  String get titleTr {
    switch (this) {
      case AppNotifType.friendRequest:
        return 'Arkadaşlık isteği';
      case AppNotifType.friendAccepted:
        return 'İsteğini kabul etti';
      case AppNotifType.dueloInvite:
        return 'Düello daveti';
      case AppNotifType.rankPassed:
        return 'Sıralamada geçildin';
      case AppNotifType.streakMilestone:
        return 'Streak ödülü';
      case AppNotifType.unknown:
        return 'Bildirim';
    }
  }
}

AppNotifType _parseType(String? raw) {
  switch (raw) {
    case 'friend_request':
      return AppNotifType.friendRequest;
    case 'friend_accepted':
      return AppNotifType.friendAccepted;
    case 'duelo_invite':
      return AppNotifType.dueloInvite;
    case 'rank_passed':
      return AppNotifType.rankPassed;
    case 'streak_milestone':
      return AppNotifType.streakMilestone;
    default:
      return AppNotifType.unknown;
  }
}

class AppNotification {
  final String id;
  final AppNotifType type;
  final String? fromUid;
  final String? fromUsername;
  final String? fromDisplayName;
  final String? fromAvatar;
  final String? targetUsername;
  final String? subjectKey;
  final String? topic;
  final DateTime when;
  final bool read;

  const AppNotification({
    required this.id,
    required this.type,
    required this.when,
    required this.read,
    this.fromUid,
    this.fromUsername,
    this.fromDisplayName,
    this.fromAvatar,
    this.targetUsername,
    this.subjectKey,
    this.topic,
  });

  factory AppNotification.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    final ts = m['when'];
    final when = ts is Timestamp ? ts.toDate() : DateTime.now();
    return AppNotification(
      id: doc.id,
      type: _parseType(m['type']?.toString()),
      fromUid: m['fromUid']?.toString(),
      fromUsername: m['fromUsername']?.toString(),
      fromDisplayName: m['fromDisplayName']?.toString(),
      fromAvatar: m['fromAvatar']?.toString(),
      targetUsername: m['targetUsername']?.toString(),
      subjectKey: m['subjectKey']?.toString(),
      topic: m['topic']?.toString(),
      when: when,
      read: (m['read'] as bool?) ?? false,
    );
  }

  /// İnsan-okur kısa mesaj.
  String get message {
    final who = fromDisplayName?.isNotEmpty == true
        ? fromDisplayName!
        : (fromUsername?.isNotEmpty == true ? '@$fromUsername' : '');
    switch (type) {
      case AppNotifType.friendRequest:
        return '$who sana arkadaşlık isteği gönderdi';
      case AppNotifType.friendAccepted:
        return '$who arkadaşlık isteğini kabul etti';
      case AppNotifType.dueloInvite:
        final t = (targetUsername ?? '');
        return 'Düello daveti${t.isEmpty ? "" : " (@$t)"}';
      case AppNotifType.rankPassed:
        return '$who seni sıralamada geçti';
      case AppNotifType.streakMilestone:
        return 'Streak rekoru';
      case AppNotifType.unknown:
        return 'Yeni bildirim';
    }
  }
}

class NotificationService {
  static FirebaseFirestore get _fs => FirebaseFirestore.instance;
  static String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  /// Tüm bildirimler (en yeni üstte), limit ile.
  static Stream<List<AppNotification>> watch({int limit = 50}) {
    final uid = _myUid;
    if (uid == null) return Stream.value(const []);
    return _fs
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .orderBy('when', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AppNotification.fromDoc).toList())
        .handleError((e) {
      debugPrint('[NotificationService] watch error: $e');
      return const <AppNotification>[];
    });
  }

  /// Okunmamış sayım — bell badge için.
  static Stream<int> watchUnreadCount() {
    final uid = _myUid;
    if (uid == null) return Stream.value(0);
    return _fs
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length)
        .handleError((e) => 0);
  }

  static Future<void> markRead(String id) async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      await _fs
          .collection('notifications')
          .doc(uid)
          .collection('items')
          .doc(id)
          .update({'read': true});
    } catch (e) {
      debugPrint('[NotificationService] markRead fail: $e');
    }
  }

  static Future<void> markAllRead() async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      final snap = await _fs
          .collection('notifications')
          .doc(uid)
          .collection('items')
          .where('read', isEqualTo: false)
          .get();
      final batch = _fs.batch();
      for (final d in snap.docs) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[NotificationService] markAllRead fail: $e');
    }
  }
}
