// ═══════════════════════════════════════════════════════════════════════════
//  TeacherInviteStudentScreen — Kullanıcı adıyla öğrenci arayıp sınıfa davet.
//
//  Kod paylaşımına ek olarak: öğretmen @kullanıcıadı ile QuAlsar'lı öğrenciyi
//  arar → "Davet Et" → öğrenciye bildirim gider → öğrenci onaylayınca sınıfa
//  katılır (ClassService.joinByClassId). Öğrenci KENDİSİ eklendiği için
//  Firestore kuralları ihlal edilmez.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';

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
  // Canlı arama: her tuşta 250 ms bekleyip sorgular; geciken eski sorgu
  // cevabı yenisini ezmesin diye token kontrolü yapılır.
  Timer? _debounce;
  int _queryToken = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Yazarken tetiklenir — "ser" yazınca ser… ile başlayanlar hemen gelir.
  void _onQueryChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _searched = false;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    final token = ++_queryToken;
    setState(() => _searching = true);
    final res = await ClassService.searchStudents(q);
    if (!mounted || token != _queryToken) return;
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
      // Davet gitti → arama alanını TEMİZLE; sıradaki öğrenci için yer aç.
      setState(() {
        _invited.add(r.uid);
        _results = const [];
        _searched = false;
        _searchCtrl.clear();
      });
      messenger.showSnackBar(SnackBar(
        // İsim .tr() DIŞINDA — interpolasyonlu anahtar sözlükte eşleşmez.
        content: Text('${'Davet gönderildi'.tr()}: @${r.username}'),
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
        // Arama paneli EKRANIN TAM ORTASINDA — kutu + canlı sonuçlar tek
        // çerçevede; sonuç geldikçe panel aşağı doğru büyür.
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppPalette.card(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: _kBrand.withValues(alpha: 0.30)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 18, offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Arama kutusu — yazdıkça sonuçlar canlı gelir.
                    Container(
                      decoration: BoxDecoration(
                        color: AppPalette.bg(context),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: AppPalette.border(context)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded,
                              color: muted, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              onChanged: _onQueryChanged,
                              onSubmitted: (_) => _search(),
                              style: GoogleFonts.poppins(
                                fontSize: 13.5, fontWeight: FontWeight.w600,
                                color: ink,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Kullanıcı adı yaz — sonuçlar anında gelir'
                                        .tr(),
                                hintStyle: GoogleFonts.poppins(
                                    fontSize: 13, color: muted),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 13),
                              ),
                            ),
                          ),
                          if (_searching)
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _kBrand),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 380),
                      child: _buildResults(context, ink, muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, Color ink, Color muted) {
    if (!_searched) {
      return _hint(context, '🔍',
          'Sınıfına eklemek istediğin öğrencinin kullanıcı adını yazmaya '
          'başla — eşleşenler anında listelenir.'.tr());
    }
    if (_results.isEmpty) {
      return _hint(context, '🤷',
          'Bu kullanıcı adıyla öğrenci bulunamadı.'.tr());
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 2),
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
              UserAvatar(
                uid: r.uid,
                avatar: r.avatar,
                size: 40,
                emojiSize: 20,
                background: _kBrand.withValues(alpha: 0.10),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 34)),
          const SizedBox(height: 10),
          Text(text,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13, color: AppPalette.textSecondary(c),
                height: 1.45,
              )),
        ],
      ),
    );
  }
}
