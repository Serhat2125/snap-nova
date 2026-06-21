// ═══════════════════════════════════════════════════════════════════════════
//  TeacherInviteStudentScreen — Kullanıcı adıyla öğrenci arayıp sınıfa davet.
//
//  Kod paylaşımına ek olarak: öğretmen @kullanıcıadı ile QuAlsar'lı öğrenciyi
//  arar → "Davet Et" → öğrenciye bildirim gider → öğrenci onaylayınca sınıfa
//  katılır (ClassService.joinByClassId). Öğrenci KENDİSİ eklendiği için
//  Firestore kuralları ihlal edilmez.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherInviteStudentScreen extends StatefulWidget {
  final TeacherClass cls;
  const TeacherInviteStudentScreen({super.key, required this.cls});

  @override
  State<TeacherInviteStudentScreen> createState() =>
      _TeacherInviteStudentScreenState();
}

class _TeacherInviteStudentScreenState
    extends State<TeacherInviteStudentScreen> {
  final _searchCtrl = TextEditingController();
  List<StudentSearchResult> _results = const [];
  final Set<String> _invited = {};
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    final res = await ClassService.searchStudents(q);
    if (!mounted) return;
    setState(() {
      _results = res;
      _searching = false;
      _searched = true;
    });
  }

  Future<void> _invite(StudentSearchResult r) async {
    final ok = await ClassService.inviteStudent(
      classId: widget.cls.id,
      className: widget.cls.name,
      subject: widget.cls.subject,
      studentUid: r.uid,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      setState(() => _invited.add(r.uid));
      messenger.showSnackBar(SnackBar(
        content: Text('Davet gönderildi: @${r.username}'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('Gönderilemedi — öğrenci zaten sınıfta olabilir.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Öğrenci Davet Et'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w800, color: ink)),
            Text(widget.cls.name,
                style: GoogleFonts.poppins(fontSize: 11, color: muted),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Arama kutusu
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AppPalette.card(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppPalette.border(context)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: muted, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        style: GoogleFonts.poppins(
                          fontSize: 13.5, fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Kullanıcı adı ara...'.tr(),
                          hintStyle: GoogleFonts.poppins(
                              fontSize: 13, color: muted),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _searching ? null : _search,
                      child: Text('Ara'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w800,
                            color: _kBrand,
                          )),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _buildResults(context, ink, muted)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, Color ink, Color muted) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_searched) {
      return _hint(context, '🔍',
          'Sınıfına eklemek istediğin öğrencinin kullanıcı adını ara.'.tr());
    }
    if (_results.isEmpty) {
      return _hint(context, '🤷',
          'Bu kullanıcı adıyla öğrenci bulunamadı.'.tr());
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _results.length,
      itemBuilder: (ctx, i) {
        final r = _results[i];
        final invited = _invited.contains(r.uid);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBrand.withValues(alpha: 0.10),
                ),
                alignment: Alignment.center,
                child: Text(r.avatar, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.displayName.isEmpty ? '@${r.username}'
                        : r.displayName,
                        style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w700, color: ink,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('@${r.username}',
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: muted)),
                  ],
                ),
              ),
              if (invited)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 16, color: Color(0xFF10B981)),
                      const SizedBox(width: 4),
                      Text('Davet edildi'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 11.5, fontWeight: FontWeight.w700,
                            color: const Color(0xFF10B981),
                          )),
                    ],
                  ),
                )
              else
                TextButton(
                  onPressed: () => _invite(r),
                  style: TextButton.styleFrom(
                    foregroundColor: _kBrand,
                    backgroundColor: _kBrand.withValues(alpha: 0.10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Davet Et'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _hint(BuildContext c, String emoji, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13, color: AppPalette.textSecondary(c),
                  height: 1.45,
                )),
          ],
        ),
      ),
    );
  }
}
