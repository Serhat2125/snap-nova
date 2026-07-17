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
import 'qualsar_arena_screen.dart';
import 'group_contest_screen.dart';

/// Öğretmen hesabının gelen kutusunda görünmesi gereken bildirim tipleri.
/// (Öğrenci-tipi davet/ödev bildirimleri öğretmene gösterilmez; öğretmen
/// yalnızca sınıfından gelen GERİ BİLDİRİMLERİ görür.)
const Set<String> _kTeacherNotifTypes = {
  'student_joined',
  'student_join_request',
  'homework_submission',
  'homework_published',
  'homework_all_done',
  'parent_message',
  'parent_ack', // velinin sessiz geri bildirimi (👍 gördü / 🎯 evde çalışacağız)
  'class_activity',
};

/// EBEVEYN hesabının gelen kutusunda görünecek tipler — bildirimler ya
/// ÇOCUKTAN (ödev verildi/teslim etti/derse davet) ya ÖĞRETMENDEN (not,
/// duyuru) ya da haftalık çalışma özetinden gelir. Öğrenci-tipi sosyal
/// bildirimler (arkadaşlık, düello, seri, lig...) ebeveyne GÖSTERİLMEZ.
const Set<String> kParentNotifTypes = {
  'teacher_note', // öğretmenden not/takdir
  'weekly_summary', // haftalık çalışma özeti (şu derse bu kadar çalıştı)
  'child_homework', // çocuğa ödev verildi (fan-out)
  'child_submission', // çocuk ödevini teslim etti (fan-out)
  'child_class_invite', // öğretmen çocuğu derse davet etti (fan-out)
  'child_announcement', // öğretmen sınıfa mesaj/duyuru attı (fan-out)
};

/// Yalnızca ebeveyne özgü fan-out tipleri — öğrenci kutusundan gizlenir
/// (teacher_note hem öğrenciye hem veliye gider, o yüzden burada YOK).
const Set<String> _kParentOnlyTypes = {
  'weekly_summary',
  'child_homework',
  'child_submission',
  'child_class_invite',
  'child_announcement',
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
                  // Sorgu hatasında sonsuz spinner'da takılma — boş listeyle
                  // devam et (aşağıda "Yeni bildirim yok" görünür).
                  if (snap.hasError) {
                    debugPrint('[NotifInbox] stream error: ${snap.error}');
                  } else if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  // Hesap tipine göre süz: öğretmen sadece geri bildirimleri,
                  // EBEVEYN yalnız çocuk/öğretmen kaynaklı tipleri, öğrenci
                  // ise öğrenci-tipi bildirimleri görür.
                  final isTeacher = AccountService.instance.isTeacher;
                  final isParent = AccountService.instance.isParent;
                  final docs = (snap.data?.docs ?? const []).where((d) {
                    final t = (d.data()['type'] ?? '').toString();
                    if (isTeacher) return _kTeacherNotifTypes.contains(t);
                    if (isParent) return kParentNotifTypes.contains(t);
                    return !_kTeacherNotifTypes.contains(t) &&
                        !_kParentOnlyTypes.contains(t);
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
      case 'parent_linked':       return Icons.family_restroom_rounded;
      case 'homework_assigned':   return Icons.assignment_rounded;
      case 'homework_reminder':   return Icons.alarm_rounded;
      case 'streak_milestone':    return Icons.emoji_events_rounded;
      case 'class_invite':        return Icons.group_add_rounded;
      case 'class_announcement':  return Icons.campaign_rounded;
      case 'homework_submission': return Icons.assignment_turned_in_rounded;
      case 'student_joined':      return Icons.person_add_alt_1_rounded;
      case 'student_join_request': return Icons.how_to_reg_rounded;
      case 'class_join_approved': return Icons.verified_rounded;
      case 'class_join_rejected': return Icons.person_off_rounded;
      case 'homework_published':  return Icons.send_rounded;
      case 'homework_all_done':   return Icons.task_alt_rounded;
      case 'homework_graded':     return Icons.grading_rounded;
      case 'homework_answers_shared': return Icons.key_rounded;
      case 'parent_message':      return Icons.mark_email_unread_rounded;
      case 'parent_ack':          return Icons.mark_email_read_rounded;
      case 'parent_gift':         return Icons.card_giftcard_rounded;
      case 'teacher_note':        return Icons.rate_review_rounded;
      case 'child_homework':      return Icons.assignment_rounded;
      case 'child_submission':    return Icons.task_alt_rounded;
      case 'child_class_invite':  return Icons.group_add_rounded;
      case 'child_announcement':  return Icons.campaign_rounded;
      case 'group_contest_invite': return Icons.groups_rounded;
      case 'weekly_summary':      return Icons.insights_rounded;
      case 'friend_request':      return Icons.person_add_rounded;
      case 'friend_accepted':     return Icons.handshake_rounded;
      case 'duelo_invite':        return Icons.sports_kabaddi_rounded;
      default:                    return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'parent_link_request': return const Color(0xFF10B981);
      case 'parent_linked':       return const Color(0xFF10B981);
      case 'homework_assigned':   return const Color(0xFF7C3AED);
      case 'homework_reminder':   return const Color(0xFFEF4444);
      case 'streak_milestone':    return const Color(0xFFFBBF24);
      case 'class_invite':        return const Color(0xFF7C3AED);
      case 'class_announcement':  return const Color(0xFFF59E0B);
      case 'homework_submission': return const Color(0xFF10B981);
      case 'student_joined':      return const Color(0xFF7C3AED);
      case 'student_join_request': return const Color(0xFFF59E0B);
      case 'class_join_approved': return const Color(0xFF10B981);
      case 'class_join_rejected': return const Color(0xFFEF4444);
      case 'homework_published':  return const Color(0xFF7C3AED);
      case 'homework_all_done':   return const Color(0xFF10B981);
      case 'homework_graded':     return const Color(0xFF10B981);
      case 'homework_answers_shared': return const Color(0xFFF59E0B);
      case 'parent_message':      return const Color(0xFF0EA5E9);
      case 'parent_ack':          return const Color(0xFF10B981);
      case 'parent_gift':         return const Color(0xFFEC4899);
      case 'teacher_note':        return const Color(0xFF10B981);
      case 'child_homework':      return const Color(0xFF7C3AED);
      case 'child_submission':    return const Color(0xFF10B981);
      case 'child_class_invite':  return const Color(0xFF7C3AED);
      case 'child_announcement':  return const Color(0xFFF59E0B);
      case 'group_contest_invite': return const Color(0xFF7C3AED);
      case 'weekly_summary':      return const Color(0xFF10B981);
      case 'friend_request':      return const Color(0xFF10B981);
      case 'friend_accepted':     return const Color(0xFF10B981);
      case 'duelo_invite':        return const Color(0xFFF59E0B);
      default:                    return const Color(0xFF06B6D4);
    }
  }

  String _titleFor(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'parent_link_request':
        return 'Ebeveyn bağlantı isteği'.tr();
      case 'parent_linked':
        return 'Velin bağlandı 👨‍👩‍👧'.tr();
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
      case 'student_join_request':
        return '${'Katılma isteği'.tr()}: ${data['fromDisplayName'] ?? ''}';
      case 'class_join_approved':
        return 'Sınıfa kabul edildin 🎉'.tr();
      case 'class_join_rejected':
        return 'Katılma isteğin onaylanmadı'.tr();
      case 'homework_published':
        return 'Ödev yayınlandı'.tr();
      case 'homework_all_done':
        return 'Herkes ödevini bitirdi 🎉'.tr();
      case 'homework_graded':
        return 'Ödevin değerlendirildi'.tr();
      case 'homework_answers_shared':
        return 'Cevaplar paylaşıldı 🔑'.tr();
      case 'parent_message':
        return 'Ebeveyn mesajı'.tr();
      case 'parent_ack':
        // Veli ack'i title/body'yi hazır yazar (parent_child_courses_screen).
        return (data['title'] ?? 'Veli geri bildirimi 👍'.tr()).toString();
      case 'parent_gift':
        // Veli sürprizi title/body'yi hazır yazar (parent_quick_actions).
        return (data['title'] ?? 'Ailenden sürpriz! 🎁'.tr()).toString();
      case 'group_contest_invite':
        return 'Grup yarışı daveti 🏆'.tr();
      case 'teacher_note':
        // addNote / pushOnTeacherNote title alanını doğrudan yazar.
        return (data['title'] ?? 'Öğretmeninden not 📝'.tr()).toString();
      case 'child_homework':
      case 'child_submission':
      case 'child_class_invite':
      case 'child_announcement':
        // Ebeveyn fan-out bildirimleri — title/body doc'ta hazır gelir.
        return (data['title'] ?? 'Bildirim'.tr()).toString();
      case 'weekly_summary':
        // Function title/body alanlarını yazar — doğrudan onları göster.
        return (data['title'] ?? 'Haftalık Özet 📊'.tr()).toString();
      case 'friend_request':
        return '${'Arkadaşlık isteği'.tr()}: '
            '${data['fromDisplayName'] ?? data['fromUsername'] ?? ''}';
      case 'friend_accepted':
        return 'İsteğin kabul edildi 🤝'.tr();
      case 'duelo_invite':
        return 'Düello daveti ⚔️'.tr();
      default:
        return data['fromDisplayName']?.toString() ?? 'Bildirim'.tr();
    }
  }

  String _subtitleFor(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'parent_link_request':
        return '${data['fromDisplayName'] ?? data['fromUsername'] ?? ''} ${'senin için izin istedi.'.tr()}';
      case 'parent_linked':
        return '${data['fromDisplayName'] ?? data['fromUsername'] ?? ''} ${'paylaştığın kodla bağlandı — artık gelişimini görebilir.'.tr()}';
      case 'homework_assigned':
        return 'Sınıfa yeni ödev geldi — bitişe kadar tamamla.'.tr();
      case 'homework_reminder':
        return 'Bu ödevin bitişine 2 saatten az kaldı.'.tr();
      case 'streak_milestone':
        final days = data['rewardDays'];
        return days != null ? '$days ${'gün Premium ödülün hesabına eklendi.'.tr()}' : '';
      case 'class_invite':
        return '${data['fromDisplayName'] ?? 'Öğretmen'.tr()} ${'seni'.tr()} '
            '${data['subject'] ?? ''} ${'dersine davet etti. Katılmak için dokun.'.tr()}';
      case 'class_announcement':
        return (data['message'] ?? '').toString();
      case 'homework_submission':
        return '${data['fromDisplayName'] ?? 'Bir öğrenci'.tr()} '
            '"${data['homeworkTitle'] ?? ''}" ${'ödevini teslim etti.'.tr()}';
      case 'student_joined':
        return '${data['className'] ?? ''} ${'sınıfından'.tr()} '
            '${data['fromDisplayName'] ?? 'bir öğrenci'.tr()} ${'katıldı.'.tr()}';
      case 'student_join_request':
        return '${data['fromDisplayName'] ?? 'Bir öğrenci'.tr()} '
            '"${data['className'] ?? ''}" '
            '${'sınıfına kodla katılmak istiyor. Onaylamak için dokun.'.tr()}';
      case 'class_join_approved':
        return '"${data['className'] ?? ''}" '
            '${'sınıfına katılımın öğretmenin tarafından onaylandı. '
                'Ödevlerini görmek için dokun.'.tr()}';
      case 'class_join_rejected':
        return '"${data['className'] ?? ''}" '
            '${'sınıfına katılma isteğin öğretmen tarafından onaylanmadı.'.tr()}';
      case 'homework_published':
        return '"${data['homeworkTitle'] ?? ''}" ${'ödevin'.tr()} '
            '${data['className'] ?? ''} ${'sınıfında yayınlandı.'.tr()}';
      case 'homework_all_done':
        return '${data['className'] ?? ''} '
            '${'sınıfındaki tüm öğrenciler'.tr()} '
            '"${data['homeworkTitle'] ?? ''}" ${'ödevini tamamladı.'.tr()}';
      case 'homework_graded':
        return '"${data['homeworkTitle'] ?? ''}" '
            '${'ödevin notlandırıldı — sonucunu görmek için dokun.'.tr()}';
      case 'homework_answers_shared':
        return '"${data['homeworkTitle'] ?? ''}" '
            '${'ödevinin cevapları ve çözümleri açıldı — kendi cevaplarını '
                'incelemek için dokun.'.tr()}';
      case 'parent_message':
        final pmMsg = (data['message'] ?? '').toString();
        final pmHead = '${data['className'] ?? ''} ${'sınıfından'.tr()} '
            '${data['fromDisplayName'] ?? 'bir öğrenci'.tr()} '
            '${'adlı öğrencinin ebeveyninden mesajın var.'.tr()}';
        return pmMsg.isEmpty ? pmHead : '$pmHead\n“$pmMsg”';
      case 'teacher_note':
      case 'parent_ack':
      case 'parent_gift':
        return (data['body'] ?? data['message'] ?? '').toString();
      case 'child_homework':
      case 'child_submission':
      case 'child_class_invite':
      case 'child_announcement':
        return (data['body'] ?? data['message'] ?? '').toString();
      case 'weekly_summary':
        return (data['body'] ?? '').toString();
      case 'friend_request':
        return '${data['fromDisplayName'] ?? data['fromUsername'] ?? 'Biri'.tr()} '
            '${'seninle arkadaş olmak istiyor. Görmek için dokun.'.tr()}';
      case 'friend_accepted':
        return '${data['fromDisplayName'] ?? data['fromUsername'] ?? ''} '
            '${'arkadaşlık isteğini kabul etti.'.tr()}';
      case 'duelo_invite':
        return '${data['fromDisplayName'] ?? data['fromUsername'] ?? 'Bir arkadaşın'.tr()} '
            '${'seninle yarışmak istiyor. Kabul etmek için dokun.'.tr()}';
      case 'group_contest_invite':
        final who =
            (data['fromDisplayName'] ?? data['fromUsername'] ?? 'Bir arkadaşın'.tr())
                .toString();
        final grp = (data['groupName'] ?? '').toString();
        final where = grp.isNotEmpty
            ? '"$grp" ${'grubunda'.tr()} '
            : '';
        return '$who ${'grup yarışı açtı ve'.tr()} $where'
            '${'seni'.tr()} "${data['subjectName'] ?? ''} • ${data['topic'] ?? ''}" '
            '${'yarışmasına davet etti. Katılmak için dokun.'.tr()}';
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
    if (type == 'homework_assigned' ||
        type == 'homework_reminder' ||
        type == 'homework_graded' ||
        type == 'homework_answers_shared' ||
        type == 'class_join_approved') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const StudentHomeworksScreen(),
      ));
    } else if (type == 'student_join_request') {
      await _handleJoinRequest(context, data);
    } else if (type == 'parent_link_request') {
      // Onay banner'ı yalnızca Profil sekmesinde — kullanıcıyı oraya yönelt
      // (önceden sessizce kapanıyordu, çocuk ne yapacağını bilemiyordu).
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
            'Profil sekmesini aç — ebeveyn isteğini oradaki karttan '
            'onaylayabilirsin.'.tr()),
      ));
    } else if (type == 'class_invite') {
      await _handleClassInvite(context, data);
    } else if (type == 'friend_request' || type == 'friend_accepted') {
      // Arkadaşlık isteği → Arena'da gelen istekler sheet'i açılır.
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => QuAlsarArenaScreen(openAction: 'friendRequests'),
      ));
    } else if (type == 'duelo_invite') {
      // Düello daveti → Arena'da düello davetleri sheet'i açılır.
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => QuAlsarArenaScreen(openAction: 'dueloInvites'),
      ));
    } else if (type == 'group_contest_invite') {
      // Grup yarışı daveti → yarışmayı aç (autoJoin ile katıl).
      final contestId = (data['contestId'] ?? '').toString();
      if (contestId.isNotEmpty) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              GroupContestScreen(contestId: contestId, autoJoin: true),
        ));
      }
    }
  }

  /// Öğretmen, kodla katılmak isteyen öğrencinin isteğini Onaylar/Reddeder.
  /// Onay → öğrenci 'active' olur ve mevcut ödevlerin slotları açılır;
  /// Red → öğrenci sınıftan çıkarılır. Her iki durumda öğrenciye bildirim gider.
  Future<void> _handleJoinRequest(
      BuildContext context, Map<String, dynamic> data) async {
    final classId = (data['classId'] ?? '').toString();
    final studentUid = (data['studentUid'] ?? '').toString();
    final studentName =
        (data['fromDisplayName'] ?? 'Bir öğrenci'.tr()).toString();
    final className = (data['className'] ?? '').toString();
    if (classId.isEmpty || studentUid.isEmpty) return;
    // Öğrenci hâlâ onay bekliyor mu? (Başka cihazdan işlenmiş olabilir.)
    final memberSnap = await FirebaseFirestore.instance
        .collection('classes').doc(classId)
        .collection('students').doc(studentUid).get();
    if (!context.mounted) return;
    final status =
        (memberSnap.data()?['status'] ?? '').toString();
    if (!memberSnap.exists || status != 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(memberSnap.exists
            ? 'Bu istek zaten onaylanmış.'.tr()
            : 'Bu istek artık geçerli değil.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Katılma isteği'.tr()),
        content: Text('$studentName, "$className" '
            '${'sınıfına katılmak istiyor. Onaylıyor musun?'.tr()}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Reddet'.tr(),
                style: const TextStyle(color: Color(0xFFEF4444))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Onayla'.tr()),
          ),
        ],
      ),
    );
    if (decision == null || !context.mounted) return;
    final ok = decision
        ? await ClassService.approveStudent(classId, studentUid)
        : await ClassService.rejectStudent(classId, studentUid);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(!ok
          ? 'İşlem başarısız. Tekrar dene.'.tr()
          : decision
              ? '$studentName ${'sınıfa kabul edildi.'.tr()}'
              : 'İstek reddedildi.'.tr()),
      behavior: SnackBarBehavior.floating,
    ));
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
    if (diff.inMinutes < 1) return 'şimdi'.tr();
    if (diff.inMinutes < 60) return '${diff.inMinutes}dk';
    if (diff.inHours < 24) return '${diff.inHours}s';
    return '${diff.inDays}g';
  }
}
