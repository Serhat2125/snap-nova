// ═══════════════════════════════════════════════════════════════════════════
//  TeacherDashboardScreen — Öğretmenin ana ekranı.
//
//  Sınıfların listesi: ad + okul + ders + sınıf kodu + öğrenci sayısı.
//  Karta tıklayınca sınıf detayına gider (öğrenci listesi + içerik dağıtımı).
//  Sağ altta "+ Yeni Sınıf" butonu.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'notifications_inbox_screen.dart';
import 'onboarding_screen.dart';
import 'teacher_class_detail_screen.dart';
import 'teacher_onboarding_screen.dart';

class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({super.key});

  Future<void> _showSettingsSheet(BuildContext context) async {
    final ink = AppPalette.textPrimary(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_box_rounded,
                  color: Color(0xFF7C3AED)),
              title: Text('Yeni sınıf oluştur'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const TeacherOnboardingScreen(),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded,
                  color: Color(0xFF10B981)),
              title: Text('Hesap tipini değiştir'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
              subtitle: Text('Öğrenci veya ebeveyn moduna geç'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11, color: AppPalette.textSecondary(context))),
              onTap: () async {
                Navigator.pop(ctx);
                await AccountService.instance.setType(AccountType.student);
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => OnboardingScreen()),
                  (r) => false,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded,
                  color: Color(0xFFEF4444)),
              title: Text('Çıkış yap'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: const Color(0xFFEF4444))),
              onTap: () async {
                Navigator.pop(ctx);
                await AuthService.signOut();
                await AccountService.instance.clear();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => OnboardingScreen()),
                  (r) => false,
                );
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                ),
              ),
              alignment: Alignment.center,
              child: const Text('👨‍🏫', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 10),
            Text('Öğretmen Paneli'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_rounded, color: ink),
            tooltip: 'Bildirimler'.tr(),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const NotificationsInboxScreen(),
            )),
          ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: ink),
            tooltip: 'Menü'.tr(),
            onPressed: () => _showSettingsSheet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const TeacherOnboardingScreen(),
        )),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: Text('Yeni Sınıf'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: StreamBuilder<List<TeacherClass>>(
          stream: ClassService.myClassesStream(),
          builder: (context, snap) {
            // Firestore'dan hata gelirse (izin reddi, ağ, vs.) spinner'da
            // takılmayalım — empty state göster, kullanıcı + ile yeni sınıf
            // ekleyebilir veya tekrar açabilir.
            if (snap.hasError) return _buildEmpty(context);
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final classes = snap.data ?? const <TeacherClass>[];
            if (classes.isEmpty) return _buildEmpty(context);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: classes.length,
              itemBuilder: (ctx, i) => _ClassCard(cls: classes[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7C3AED).withValues(alpha: 0.10),
              ),
              alignment: Alignment.center,
              child: const Text('👨‍🏫', style: TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 18),
            Text('Henüz sınıf yok'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 8),
            Text(
              'Sağ alttaki + ile ilk sınıfını oluştur, öğrencilerinle paylaşabileceğin kodu al.'
                  .tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13, color: AppPalette.textSecondary(context),
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final TeacherClass cls;
  const _ClassCard({required this.cls});

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TeacherClassDetailScreen(cls: cls),
        )),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.border(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10, offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.class_rounded,
                        color: Color(0xFF7C3AED), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cls.name,
                            style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${cls.schoolName} · ${cls.subject}',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5, color: muted,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: muted),
                ],
              ),
              const SizedBox(height: 12),
              // Sınıf kodu kartı — kopyalanabilir
              GestureDetector(
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: cls.code));
                  messenger.showSnackBar(SnackBar(
                    content: Text('Sınıf kodu kopyalandı'.tr()),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: AppPalette.bg(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text('🔑', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SINIF KODU'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: muted, letterSpacing: 1.0,
                                )),
                            Text(cls.code,
                                style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: ink, letterSpacing: 1.3,
                                )),
                          ],
                        ),
                      ),
                      Icon(Icons.copy_rounded, size: 18,
                          color: const Color(0xFF7C3AED)),
                    ],
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
