// ═══════════════════════════════════════════════════════════════════════════
//  AccountTypeScreen — Auth sonrası gösterilen hesap tipi seçim ekranı.
//
//  Onboarding'in Auth aşamasından sonra çağrılır. Kullanıcı tipini seçer:
//  • Öğrenci → mevcut onboarding'e devam (Grade selection)
//  • Ebeveyn → ParentDashboardScreen (boş durumda FAB ile çocuk ekleyebilir)
//  • Öğretmen → TeacherDashboardScreen (boş durumda FAB ile sınıf oluşturur)
//
//  Not: Önceki sürümde Parent/Teacher için ayrı Onboarding formu vardı; ancak
//  "öğretmen seçtiğimde sayfa açılmıyor" şikayeti üzerine doğrudan dashboard'a
//  yönlendiriyoruz — boş ekran kullanıcıyı sıkıştırmıyor, FAB net çağrı yapıyor.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/account_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'onboarding_screen.dart';
import 'parent_dashboard_screen.dart';
import 'teacher_dashboard_screen.dart';

class AccountTypeScreen extends StatefulWidget {
  /// Öğrenci seçince çağrılır → onboarding'e devam et.
  final VoidCallback onStudentSelected;
  const AccountTypeScreen({super.key, required this.onStudentSelected});

  @override
  State<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends State<AccountTypeScreen> {
  bool _saving = false;

  Future<void> _pick(AccountType t) async {
    if (_saving) return;
    setState(() => _saving = true);
    await AccountService.instance.setType(t);
    if (!mounted) return;

    // Ebeveyn/Öğretmen seçilince student-onboarding artık geçersiz —
    // pref'i true yap ki açılışta tekrar gösterilmesin. Tüm stack temizlenir
    // (pushAndRemoveUntil), onboarding'in altta kalmasını engeller.
    if (t == AccountType.parent || t == AccountType.teacher) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(OnboardingScreen.prefKey, true);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _saving = false);

    switch (t) {
      case AccountType.student:
        widget.onStudentSelected();
        break;
      case AccountType.parent:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const ParentDashboardScreen(),
          ),
          (route) => false, // tüm stack temizlensin
        );
        break;
      case AccountType.teacher:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const TeacherDashboardScreen(),
          ),
          (route) => false,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.person_pin_rounded,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(height: 18),
              Text('Hangi hesap tipisin?'.tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(context),
                    letterSpacing: -0.3,
                  )),
              const SizedBox(height: 8),
              Text(
                'Seçimin uygulamanın senin için açılacağı modu belirler.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppPalette.textSecondary(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _typeCard(
                        AccountType.student,
                        title: 'Öğrenci'.tr(),
                        desc: 'Sorularını çöz, sınıfında yarış, AI Koç ile çalış.'.tr(),
                        color: const Color(0xFF2563EB),
                      ),
                      const SizedBox(height: 12),
                      _typeCard(
                        AccountType.parent,
                        title: 'Ebeveyn'.tr(),
                        desc: 'Çocuğunun çalışma süresini ve başarısını izle.'.tr(),
                        color: const Color(0xFF10B981),
                      ),
                      const SizedBox(height: 12),
                      _typeCard(
                        AccountType.teacher,
                        title: 'Öğretmen'.tr(),
                        desc: 'Sınıfını yönet, içerik dağıt, ilerlemeyi gör.'.tr(),
                        color: const Color(0xFF7C3AED),
                      ),
                    ],
                  ),
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeCard(
    AccountType t, {
    required String title,
    required String desc,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _saving ? null : () => _pick(t),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.30), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(t.emoji, style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        )),
                    const SizedBox(height: 4),
                    Text(desc,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: AppPalette.textSecondary(context),
                          height: 1.4,
                        )),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: color.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
