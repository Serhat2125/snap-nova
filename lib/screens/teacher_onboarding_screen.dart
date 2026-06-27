// ═══════════════════════════════════════════════════════════════════════════
//  TeacherOnboardingScreen — Öğretmen hesabı için ilk kurulum.
//
//  Öğretmen ilk sınıfını oluşturur (okul + sınıf adı + ders + seviye).
//  Sonra TeacherDashboard'a yönlendirilir.
//  "Daha sonra" seçerse dashboard direkt açılır, sonra sınıf ekleyebilir.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../data/teacher_branches.dart';
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
  // Ders = sınıfın branşı. Hesap kurulumundaki branş varsayılan gelir ama
  // bu ekrandan değiştirilebilir (bir öğretmen farklı derslere sınıf açabilir).
  String? _subject = AccountService.instance.teacherBranch;
  // Başlangıçta seçili değil → kullanıcı "Eğitim seviyesini belirle" görür.
  String? _level;
  bool _saving = false;
  String? _error;

  // Profil sunumu (foto + durum mesajı).
  String? _photoPath = AccountService.instance.teacherPhotoPath;
  String? _status = AccountService.instance.teacherStatus;

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
    if (_level == null) {
      setState(() => _error = 'Önce eğitim seviyesini belirle.'.tr());
      return;
    }
    if (_subject == null || _subject!.trim().isEmpty) {
      setState(() => _error = 'Önce dersi (branşı) seç.'.tr());
      return;
    }
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
      subject: _subject!,
      level: _level!,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (cls == null) {
      setState(() => _error = 'Sınıf oluşturulamadı. İnternet bağlantını '
          'kontrol et ve tekrar dene.'.tr());
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
              _profileAvatar(),
              if (_status != null && _status!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_status!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w600,
                      color: AppPalette.textSecondary(context),
                    )),
              ] else ...[
                const SizedBox(height: 6),
                Text('Fotoğraf ve durum eklemek için dokun'.tr(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w500,
                      color: AppPalette.textSecondary(context).withValues(alpha: 0.6),
                    )),
              ],
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

              _dropdown('Eğitim seviyesini belirle'.tr(), _level, _levels,
                  (v) => setState(() => _level = v)),
              const SizedBox(height: 10),
              _subjectField(),
              const SizedBox(height: 10),
              _field(_school, 'Okul adı'.tr(), Icons.apartment_rounded,
                  const Color(0xFF0EA5E9)),
              const SizedBox(height: 10),
              _field(_name, 'Sınıf adı (örn: 10-A)'.tr(), Icons.class_rounded,
                  const Color(0xFFF59E0B)),

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

  // ── Ders (branş) seçimi — girişteki branş picker'ını kullanır ────────────
  Widget _subjectField() {
    final selected = _subject != null && _subject!.trim().isNotEmpty;
    return GestureDetector(
      onTap: () async {
        final picked = await showTeacherBranchPicker(context,
            selected: _subject);
        if (picked != null && mounted) setState(() => _subject = picked);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border(context)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: Row(
          children: [
            // Canlı, renkli ders ikonu (seçiliyken yeşil, boşken soluk).
            Icon(Icons.menu_book_rounded, size: 20,
                color: selected
                    ? const Color(0xFF10B981)
                    : AppPalette.textSecondary(context).withValues(alpha: 0.5)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected ? _subject!.tr() : 'Hangi ders? (branşı seç)'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: selected ? 14 : 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected
                      ? AppPalette.textPrimary(context)
                      : AppPalette.textSecondary(context)
                          .withValues(alpha: 0.5),
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded,
                color: AppPalette.textSecondary(context)),
          ],
        ),
      ),
    );
  }

  // ── Profil avatarı (foto + kalem rozeti) ─────────────────────────────────
  Widget _profileAvatar() {
    final hasPhoto = _photoPath != null && File(_photoPath!).existsSync();
    return GestureDetector(
      onTap: _editProfile,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 84, height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
              ),
              image: hasPhoto
                  ? DecorationImage(
                      image: FileImage(File(_photoPath!)), fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: hasPhoto
                ? null
                : const Text('👨‍🏫', style: TextStyle(fontSize: 38)),
          ),
          // Kalem rozeti — öğretmen düzenlenebilir olduğunu anlasın.
          Positioned(
            right: -2, bottom: -2,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
                shape: BoxShape.circle,
                border: Border.all(color: AppPalette.bg(context), width: 2.5),
              ),
              child: const Icon(Icons.edit_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile() async {
    final statusCtrl = TextEditingController(text: _status ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 18,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () async {
                    await _pickPhoto();
                    setSheet(() {});
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 96, height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                          ),
                          image: (_photoPath != null &&
                                  File(_photoPath!).existsSync())
                              ? DecorationImage(
                                  image: FileImage(File(_photoPath!)),
                                  fit: BoxFit.cover)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: (_photoPath != null &&
                                File(_photoPath!).existsSync())
                            ? null
                            : const Icon(Icons.add_a_photo_rounded,
                                color: Colors.white, size: 28),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text('Fotoğrafı değiştirmek için dokun'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: AppPalette.textSecondary(context).withValues(alpha: 0.7),
                    )),
              ),
              const SizedBox(height: 20),
              Text('Durum mesajı'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 12.5, fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context),
                  )),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppPalette.bg(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppPalette.border(context)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: statusCtrl,
                  maxLength: 60,
                  style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppPalette.textPrimary(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'örn: 10. sınıf fizik öğretmeni'.tr(),
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w400,
                      color: AppPalette.textSecondary(context).withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    final s = statusCtrl.text.trim();
                    await AccountService.instance
                        .saveTeacherPresentation(status: s);
                    if (mounted) setState(() => _status = s);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text('Kaydet'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: Colors.white,
                      )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    statusCtrl.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800, maxHeight: 800, imageQuality: 85,
      );
      if (picked == null) return;
      // Kalıcı klasöre kopyala (image_picker geçici dosya döndürür).
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.split('.').last;
      final dest = '${dir.path}/teacher_avatar.$ext';
      await File(picked.path).copy(dest);
      await AccountService.instance.saveTeacherPresentation(photoPath: dest);
      if (mounted) setState(() => _photoPath = dest);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Fotoğraf yüklenemedi.'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      Color iconColor) {
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
          // Soluk, küçük örnek metin — öğretmen bunun ipucu olduğunu anlasın.
          hintStyle: GoogleFonts.poppins(
            fontSize: 12.5, fontWeight: FontWeight.w400,
            color: AppPalette.textSecondary(context).withValues(alpha: 0.5),
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          // Canlı, renkli ikon.
          prefixIcon: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }

  // Eğitim seviyesine göre değişen ikon. null → henüz seçilmemiş (genel ikon).
  IconData _levelIcon(String? level) {
    switch (level) {
      case 'İlkokul':
        return Icons.backpack_rounded;        // ilkokul → çanta
      case 'Ortaokul':
        return Icons.auto_stories_rounded;     // ortaokul → açık kitap
      case 'Lise':
        return Icons.school_rounded;           // lise → mezuniyet kepi
      case 'Üniversite':
        return Icons.account_balance_rounded;  // üniversite → kampüs binası
      default:
        return Icons.tune_rounded;             // seçilmemiş → ayar/belirle
    }
  }

  Widget _dropdown(String label, String? value, List<String> options,
      ValueChanged<String> onChange) {
    final selected = value != null;
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          // Seçiliyken canlı mor; seçilmemişken soluk.
          Icon(_levelIcon(value), size: 20,
              color: selected
                  ? const Color(0xFF7C3AED)
                  : AppPalette.textSecondary(context).withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          Expanded(
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
                // Seçim yokken soluk, küçük ipucu metni.
                hint: Text(label,
                    style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w400,
                      color:
                          AppPalette.textSecondary(context).withValues(alpha: 0.5),
                    )),
                // Kapalı görünümde sol lider ikon yeterli; burada sadece metin.
                selectedItemBuilder: (_) => options
                    .map((o) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(o.tr()),
                        ))
                    .toList(),
                items: options.map((o) => DropdownMenuItem(
                  value: o,
                  child: Row(
                    children: [
                      Icon(_levelIcon(o), size: 18,
                          color: AppPalette.textSecondary(context)),
                      const SizedBox(width: 8),
                      Text(o.tr()),
                    ],
                  ),
                )).toList(),
                onChanged: (v) { if (v != null) onChange(v); },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
