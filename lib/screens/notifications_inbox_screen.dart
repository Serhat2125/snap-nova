// ═══════════════════════════════════════════════════════════════════════════
//  NotificationsInboxScreen — Tüm hesap tipleri için ortak bildirim merkezi.
//
//  Firestore: notifications/{uid}/items/* okunur (zaman sırası).
//  Tipler:
//    parent_link_request  → ebeveyn istek
//    homework_assigned    → yeni ödev
//    homework_reminder    → 2 saat uyarı
//    streak_milestone     → ödül/başarı
//    +diğerleri (custom)
//
//  Tıklayınca:
//    - parent_link_request → Profile (banner ile onay)
//    - homework_assigned/reminder → StudentHomeworksScreen
//    - Diğer → işaretle ve kapat
// ═══════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/account_service.dart';
import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'student_homeworks_screen.dart';

/// Öğretmen hesabının gelen kutusunda görünmesi gereken bildirim tipleri.
/// (Öğrenci-tipi davet/ödev bildirimleri öğretmene gösterilmez; öğretmen
/// yalnızca sınıfından gelen GERİ BİLDİRİMLERİ görür.)
const Set<String> _kTeacherNotifTypes = {
  'student_joined',
  'homework_submission',
  'homework_published',
  'homework_all_done',
  'parent_message',
  'class_activity',
};

class NotificationsInboxScreen extends StatelessWidget {
  const NotificationsInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Bildirimler'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
        actions: [
          if (uid != null)
            IconButton(
              icon: Icon(Icons.done_all_rounded, color: ink),
              tooltip: 'Tümünü okundu işaretle'.tr(),
              onPressed: () async {
                final batch = FirebaseFirestore.instance.batch();
                final snap = await FirebaseFirestore.instance
                    .collection('notifications').doc(uid)
                    .collection('items')
                    .where('read', isEqualTo: false).get();
                for (final d in snap.docs) {
                  batch.update(d.reference, {'read': true});
                }
                await batch.commit();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: uid == null
            ? Center(child: Text('Giriş yap'.tr(),
                style: GoogleFonts.poppins(color: muted)))
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('notifications').doc(uid)
                    .collection('items')
                    .orderBy('when', descending: true)
                    .limit(50)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  // Hesap tipine göre süz: öğretmen sadece geri bildirimleri,
                  // öğrenci ise öğrenci-tipi bildirimleri görür.
                  final isTeacher = AccountService.instance.isTeacher;
                  final docs = snap.data!.docs.where((d) {
                    final t = (d.data()['type'] ?? '').toString();
                    final teacherType = _kTeacherNotifTypes.contains(t);
                    return isTeacher ? teacherType : !teacherType;
                  }).toList();
                  if (docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🔔', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 10),
                            Text('Yeni bildirim yok'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 14, fontWeight: FontWeight.w800,
                                  color: ink,
                                )),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final d = docs[i];
                      return _NotificationCard(doc: d);
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _NotificationCard({required this.doc});

  IconData _iconFor(String type) {
    switch (type) {
      case 'parent_link_request': return Icons.family_restroom_rounded;
      case 'homework_assigned':   return Icons.assignment_rounded;
      case 'homework_reminder':   return Icons.alarm_rounded;
      case 'streak_milestone':    return Icons.emoji_events_rounded;
      case 'class_invite':        return Icons.group_add_rounded;
      case 'class_announcement':  return Icons.campaign_rounded;
      case 'homework_submission': return Icons.assignment_turned_in_rounded;
      case 'student_joined':      return Icons.person_add_alt_1_rounded;
      case 'homework_published':  return Icons.send_rounded;
      case 'homework_all_done':   return Icons.task_alt_rounded;
      case 'parent_message':      return Icons.mark_email_unread_rounded;
      default:                    return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'parent_link_request': return const Color(0xFF10B981);
      case 'homework_assigned':   return const Color(0xFF7C3AED);
      case 'homework_reminder':   return const Color(0xFFEF4444);
      case 'streak_milestone':    return const Color(0xFFFBBF24);
      case 'class_invite':        return const Color(0xFF7C3AED);
      case 'class_announcement':  return const Color(0xFFF59E0B);
      case 'homework_submission': return const Color(0xFF10B981);
      case 'student_joined':      return const Color(0xFF7C3AED);
      case 'homework_published':  return const Color(0xFF7C3AED);
      case 'homework_all_done':   return const Color(0xFF10B981);
      case 'parent_message':      return const Color(0xFF0EA5E9);
      default:                    return const Color(0xFF06B6D4);
    }
  }

  String _titleFor(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'parent_link_request':
        return 'Ebeveyn bağlantı isteği'.tr();
      case 'homework_assigned':
        return '${'Yeni ödev'.tr()}: ${data['fromDisplayName'] ?? ''}';
      case 'homework_reminder':
        return '${'Ödev hatırlatma'.tr()}: ${data['fromDisplayName'] ?? ''}';
      case 'streak_milestone':
        return 'Ödül kazandın 🎉'.tr();
      case 'class_invite':
        return '${'Sınıf daveti'.tr()}: ${data['className'] ?? ''}';
      case 'class_announcement':
        return '${'Duyuru'.tr()}: ${data['className'] ?? ''}';
      case 'homework_submission':
        return '${'Ödev teslim edildi'.tr()}: ${data['fromDisplayName'] ?? ''}';
      case 'student_joined':
        return '${'Yeni öğrenci'.tr()}: ${data['fromDisplayName'] ?? ''}';
      case 'homework_published':
        return 'Ödev yayınlandı'.tr();
      case 'homework_all_done':
        return 'Herkes ödevini bitirdi 🎉'.tr();
      case 'parent_message':
        return 'Ebeveyn mesajı'.tr();
      default:
        return data['fromDisplayName']?.toString() ?? 'Bildirim'.tr();
    }
  }

  String _subtitleFor(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'parent_link_request':
        return '${data['fromDisplayName'] ?? data['fromUsername'] ?? ''} senin için izin istedi.';
      case 'homework_assigned':
        return 'Sınıfa yeni ödev geldi — bitişe kadar tamamla.';
      case 'homework_reminder':
        return 'Bu ödevin bitişine 2 saatten az kaldı.';
      case 'streak_milestone':
        final days = data['rewardDays'];
        return days != null ? '$days gün Premium ödülün hesabına eklendi.' : '';
      case 'class_invite':
        return '${data['fromDisplayName'] ?? 'Öğretmen'} seni '
            '${data['subject'] ?? ''} dersine davet etti. Katılmak için dokun.';
      case 'class_announcement':
        return (data['message'] ?? '').toString();
      case 'homework_submission':
        return '${data['fromDisplayName'] ?? 'Bir öğrenci'} '
            '"${data['homeworkTitle'] ?? ''}" ödevini teslim etti.';
      case 'student_joined':
        return '${data['className'] ?? ''} ${'sınıfından'.tr()} '
            '${data['fromDisplayName'] ?? 'bir öğrenci'} ${'katıldı.'.tr()}';
      case 'homework_published':
        return '"${data['homeworkTitle'] ?? ''}" ${'ödevin'.tr()} '
            '${data['className'] ?? ''} ${'sınıfında yayınlandı.'.tr()}';
      case 'homework_all_done':
        return '${data['className'] ?? ''} '
            '${'sınıfındaki tüm öğrenciler'.tr()} '
            '"${data['homeworkTitle'] ?? ''}" ${'ödevini tamamladı.'.tr()}';
      case 'parent_message':
        return '${data['className'] ?? ''} ${'sınıfından'.tr()} '
            '${data['fromDisplayName'] ?? 'bir öğrenci'} '
            '${'adlı öğrencinin ebeveyninden mesajın var.'.tr()}';
      default:
        return '';
    }
  }

  Future<void> _onTap(BuildContext context) async {
    // Okundu işaretle
    await doc.reference.update({'read': true});
    if (!context.mounted) return;
    final data = doc.data();
    final type = (data['type'] ?? '').toString();
    if (type == 'homework_assigned' || type == 'homework_reminder') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const StudentHomeworksScreen(),
      ));
    } else if (type == 'parent_link_request') {
      Navigator.of(context).pop();
      // Profile'a yönlendirme: kullanıcı orada banner'ı görür ve onaylar
    } else if (type == 'class_invite') {
      await _handleClassInvite(context, data);
    }
  }

  /// Öğretmen davetini kabul → öğrenci kendini sınıfa ekler (joinByClassId).
  Future<void> _handleClassInvite(
      BuildContext context, Map<String, dynamic> data) async {
    final classId = (data['classId'] ?? '').toString();
    final className = (data['className'] ?? '').toString();
    if (classId.isEmpty) return;
    final join = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Sınıfa katıl'.tr()),
        content: Text(
            '"$className" ${'sınıfına katılmak istiyor musun?'.tr()}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Katıl'.tr()),
          ),
        ],
      ),
    );
    if (join != true || !context.mounted) return;
    final res = await ClassService.joinByClassId(classId);
    if (!context.mounted) return;
    String msg;
    if (res == JoinClassResult.success) {
      msg = 'Sınıfa katıldın 🎉'.tr();
    } else if (res == JoinClassResult.alreadyJoined) {
      msg = 'Zaten bu sınıftasın.'.tr();
    } else {
      msg = 'Katılınamadı. Tekrar dene.'.tr();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final type = (data['type'] ?? '').toString();
    final read = (data['read'] ?? false) == true;
    final color = _colorFor(type);
    final whenTs = data['when'];
    DateTime? when;
    if (whenTs is Timestamp) when = whenTs.toDate();
    final whenStr = when == null ? '' : _relativeTime(when);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onTap(context),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: read
                ? AppPalette.card(context)
                : color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: read
                  ? AppPalette.border(context)
                  : color.withValues(alpha: 0.30),
              width: read ? 1 : 1.4,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                ),
                alignment: Alignment.center,
                child: Icon(_iconFor(type), color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(_titleFor(type, data),
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.textPrimary(context),
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (whenStr.isNotEmpty)
                          Text(whenStr,
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppPalette.textSecondary(context),
                              )),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(_subtitleFor(type, data),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppPalette.textSecondary(context),
                          height: 1.4,
                        )),
                  ],
                ),
              ),
              if (!read)
                Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.only(top: 6, left: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: color,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'şimdi';
    if (diff.inMinutes < 60) return '${diff.inMinutes}dk';
    if (diff.inHours < 24) return '${diff.inHours}s';
    return '${diff.inDays}g';
  }
}
