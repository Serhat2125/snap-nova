// ═══════════════════════════════════════════════════════════════════════════
//  AccountTypeScreen — Auth sonrası gösterilen hesap tipi seçim ekranı.
//
//  Onboarding'in Auth aşamasından sonra çağrılır. Kullanıcı tipini seçer:
//  • Öğrenci → mevcut onboarding'e devam (Grade selection)
//  • Ebeveyn → ParentDashboardScreen (boş durumda FAB ile çocuk ekleyebilir)
//  • Öğretmen → TeacherShellScreen (Panel/Sınıflar/Analiz sekmeleri)
//
//  Not: Önceki sürümde Parent/Teacher için ayrı Onboarding formu vardı; ancak
//  "öğretmen seçtiğimde sayfa açılmıyor" şikayeti üzerine doğrudan dashboard'a
//  yönlendiriyoruz — boş ekran kullanıcıyı sıkıştırmıyor, FAB net çağrı yapıyor.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/teacher_branches.dart';
import '../services/account_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'onboarding_screen.dart';
import 'parent_shell_screen.dart';
import 'teacher_shell_screen.dart';

class AccountTypeScreen extends StatefulWidget {
  /// Öğrenci seçince çağrılır → onboarding'e devam et.
  final VoidCallback onStudentSelected;
  const AccountTypeScreen({super.key, required this.onStudentSelected});

  @override
  State<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends State<AccountTypeScreen> {
  bool _saving = false;

  // Öğretmen seçilince inline form açılır (diğer kartlar gizlenir).
  bool _teacherMode = false;
  final _teacherName = TextEditingController();
  String? _branch;
  String? _teacherError;

  @override
  void dispose() {
    _teacherName.dispose();
    super.dispose();
  }

  Future<void> _openBranchPicker() async {
    final sel = await showTeacherBranchPicker(context, selected: _branch);
    if (sel != null && mounted) setState(() => _branch = sel);
  }

  Future<void> _continueTeacher() async {
    if (_saving) return;
    final name = _teacherName.text.trim();
    if (name.isEmpty) {
      setState(() => _teacherError = 'Kullanıcı adı zorunludur.'.tr());
      return;
    }
    if (_branch == null) {
      setState(() => _teacherError = 'Lütfen branşını seç.'.tr());
      return;
    }
    setState(() {
      _saving = true;
      _teacherError = null;
    });
    await AccountService.instance.setType(AccountType.teacher);
    await AccountService.instance
        .saveTeacherProfile(username: name, branch: _branch!);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(OnboardingScreen.prefKey, true);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TeacherShellScreen()),
      (route) => false,
    );
  }

  /// Rol değiştirme onayı: cloud'da farklı bir tip kayıtlıysa kullanıcı
  /// bilgilendirilir. Aynı e-posta ile rol değişimi ARTIK SERBEST — veriler
  /// uid+koleksiyon bazlı ayrı tutulduğundan karışmaz, eski role dönülebilir.
  /// true → yeni rolle devam et; false → vazgeçildi (mevcut ekranda kal).
  Future<bool> _guardExistingRole(AccountType want) async {
    final existing = await AccountService.instance.fetchCloudType();
    if (existing == null || existing == want) return true;
    if (!mounted) return false;
    setState(() => _saving = false);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Rolü değiştir?'.tr()),
        content: Text(
          '${'Bu e-posta şu an şu rolle kayıtlı:'.tr()} '
          '${existing.emoji} ${existing.tr}.\n\n'
          '${want.emoji} ${want.tr} '
          '${'moduna geçmek istediğine emin misin? Eski rolünün verileri silinmez, istediğinde geri dönebilirsin.'.tr()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('${want.tr} ${'olarak devam et'.tr()}'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _pick(AccountType t) async {
    if (_saving) return;
    // Öğretmen: hemen yönlendirme — inline formu aç.
    if (t == AccountType.teacher) {
      if (!await _guardExistingRole(AccountType.teacher)) return;
      if (!mounted) return;
      setState(() => _teacherMode = true);
      return;
    }
    setState(() => _saving = true);
    if (!await _guardExistingRole(t)) return;
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
            builder: (_) => const ParentShellScreen(),
          ),
          (route) => false, // tüm stack temizlensin
        );
        break;
      case AccountType.teacher:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const TeacherShellScreen(),
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
                  child: _teacherMode
                      ? _teacherForm()
                      : Column(
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

  // Öğretmen seçilince gösterilen inline form: öğretmen kartı + kullanıcı adı
  // + branş seçimi. Diğer hesap tipleri gizlenir.
  Widget _teacherForm() {
    const purple = Color(0xFF7C3AED);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Seçili öğretmen kartı (tıklayınca geri dönüp tipi değiştirebilir).
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          decoration: BoxDecoration(
            color: purple.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: purple, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: purple.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text('👨‍🏫', style: TextStyle(fontSize: 30)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Öğretmen'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        )),
                    const SizedBox(height: 2),
                    Text('Sınıfını yönet, içerik dağıt, ilerlemeyi gör.'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppPalette.textSecondary(context),
                          height: 1.35,
                        )),
                  ],
                ),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _teacherMode = false;
                          _teacherError = null;
                        }),
                child: Text('Değiştir'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: purple,
                    )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // Kullanıcı adını seç
        Text('Kullanıcı adını seç'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppPalette.textPrimary(context),
            )),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.border(context)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            controller: _teacherName,
            style: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: AppPalette.textPrimary(context),
            ),
            decoration: InputDecoration(
              hintText: 'örn: Ayşe Öğretmen'.tr(),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              prefixIcon: Icon(Icons.badge_rounded, size: 20,
                  color: AppPalette.textSecondary(context)),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Branşını seç
        Text('Branşını seç'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppPalette.textPrimary(context),
            )),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _saving ? null : _openBranchPicker,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(
                color: AppPalette.card(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _branch != null ? purple : AppPalette.border(context),
                  width: _branch != null ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.school_rounded, size: 20,
                      color: _branch != null
                          ? purple
                          : AppPalette.textSecondary(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      (_branch ?? 'Branşını seç').tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight:
                            _branch != null ? FontWeight.w700 : FontWeight.w600,
                        color: _branch != null
                            ? AppPalette.textPrimary(context)
                            : AppPalette.textSecondary(context),
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded,
                      color: AppPalette.textSecondary(context)),
                ],
              ),
            ),
          ),
        ),

        if (_teacherError != null) ...[
          const SizedBox(height: 14),
          Text(_teacherError!,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFEF4444),
              )),
        ],
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: purple,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _saving ? null : _continueTeacher,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white),
                  )
                : Text('Devam et'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    )),
          ),
        ),
      ],
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
