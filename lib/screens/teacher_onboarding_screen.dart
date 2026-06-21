// ═══════════════════════════════════════════════════════════════════════════
//  TeacherOnboardingScreen — Öğretmen hesabı için ilk kurulum.
//
//  Öğretmen ilk sınıfını oluşturur (okul + sınıf adı + ders + seviye).
//  Sonra TeacherDashboard'a yönlendirilir.
//  "Daha sonra" seçerse dashboard direkt açılır, sonra sınıf ekleyebilir.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/account_service.dart';
import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_shell_screen.dart';

class TeacherOnboardingScreen extends StatefulWidget {
  const TeacherOnboardingScreen({super.key});

  @override
  State<TeacherOnboardingScreen> createState() =>
      _TeacherOnboardingScreenState();
}

class _TeacherOnboardingScreenState extends State<TeacherOnboardingScreen> {
  final _name = TextEditingController();
  final _school = TextEditingController();
  // Ders = öğretmenin hesap kurulumunda seçtiği branş (sabit, sınıf bazında
  // değişmez — bir öğretmen tek branş verir).
  late final String _subject =
      AccountService.instance.teacherBranch ?? 'Genel';
  String _level = 'Lise';
  bool _saving = false;
  String? _error;

  static const _levels = [
    'İlkokul','Ortaokul','Lise','Üniversite',
  ];

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final school = _school.text.trim();
    if (name.isEmpty || school.isEmpty) {
      setState(() => _error = 'Sınıf adı ve okul adı zorunludur.'.tr());
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final cls = await ClassService.createClass(
      name: name,
      schoolName: school,
      subject: _subject,
      level: _level,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (cls == null) {
      setState(() => _error = 'Sınıf oluşturulamadı. Tekrar dene.'.tr());
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const TeacherShellScreen(),
      ),
      (route) => false,
    );
  }

  void _skipToDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const TeacherShellScreen(),
      ),
      (route) => false,
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
        title: Text('Öğretmen Kurulumu'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                  ),
                ),
                alignment: Alignment.center,
                child: const Text('👨‍🏫', style: TextStyle(fontSize: 36)),
              ),
              const SizedBox(height: 16),
              Text('Yeni bir sınıf oluştur'.tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 22, fontWeight: FontWeight.w900,
                    color: ink, letterSpacing: -0.3,
                  )),
              const SizedBox(height: 8),
              Text(
                'Sınıf oluşturunca öğrencilere gönderebileceğin bir kod alırsın.'
                    .tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppPalette.textSecondary(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              _dropdown('Eğitim seviyesi'.tr(), _level, _levels,
                  (v) => setState(() => _level = v)),
              const SizedBox(height: 10),
              _field(_school, 'Okul adı'.tr(), Icons.school_rounded),
              const SizedBox(height: 10),
              _field(_name, 'Sınıf adı (örn: 10-A)'.tr(), Icons.class_rounded),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFEF4444),
                    )),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _saving ? null : _create,
                  child: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                        )
                      : Text('Sınıfı Oluştur'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          )),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _skipToDashboard,
                child: Text('Daha sonra → Dashboard\'a git'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondary(context),
                      decoration: TextDecoration.underline,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: c,
        style: GoogleFonts.poppins(
          fontSize: 14, fontWeight: FontWeight.w600,
          color: AppPalette.textPrimary(context),
        ),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          prefixIcon: Icon(icon, size: 20,
              color: AppPalette.textSecondary(context)),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> options,
      ValueChanged<String> onChange) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.expand_more_rounded,
              color: AppPalette.textSecondary(context)),
          style: GoogleFonts.poppins(
            fontSize: 14, fontWeight: FontWeight.w700,
            color: AppPalette.textPrimary(context),
          ),
          hint: Text(label),
          items: options.map((o) => DropdownMenuItem(
            value: o, child: Text(o.tr()))).toList(),
          onChanged: (v) { if (v != null) onChange(v); },
        ),
      ),
    );
  }
}
