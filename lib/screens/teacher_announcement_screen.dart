// ═══════════════════════════════════════════════════════════════════════════
//  TeacherAnnouncementScreen — Öğretmenin tüm sınıfa veya seçili sınıflara
//  anlık duyuru/bildirim göndermesi.
//
//  Her seçili sınıfın öğrencilerine 'class_announcement' bildirimi yazılır
//  (push function yakalar); ayrıca sınıf içerik akışına kalıcı kayıt düşer.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherAnnouncementScreen extends StatefulWidget {
  const TeacherAnnouncementScreen({super.key});

  @override
  State<TeacherAnnouncementScreen> createState() =>
      _TeacherAnnouncementScreenState();
}

class _TeacherAnnouncementScreenState extends State<TeacherAnnouncementScreen> {
  final _msgCtrl = TextEditingController();
  List<TeacherClass> _classes = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final cls = await ClassService.myClassesStream().first;
      if (!mounted) return;
      setState(() {
        _classes = cls;
        // Varsayılan: tüm sınıflar seçili.
        _selected
          ..clear()
          ..addAll(cls.map((c) => c.id));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _allSelected =>
      _classes.isNotEmpty && _selected.length == _classes.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_classes.map((c) => c.id));
      }
    });
  }

  Future<void> _send() async {
    final msg = _msgCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (msg.isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text('Duyuru metni boş olamaz.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (_selected.isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text('En az bir sınıf seç.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _sending = true);
    int totalSent = 0;
    int okClasses = 0;
    for (final c in _classes.where((c) => _selected.contains(c.id))) {
      final n = await ClassService.publishAnnouncement(
        classId: c.id,
        className: c.name,
        subject: c.subject,
        message: msg,
      );
      if (n >= 0) {
        okClasses++;
        totalSent += n;
      }
    }
    if (!mounted) return;
    setState(() => _sending = false);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(
        '${'Duyuru gönderildi'.tr()} · $okClasses ${'sınıf'.tr()}, $totalSent ${'öğrenci'.tr()}',
      ),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Duyuru Yayınla'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? _empty(context)
              : SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          children: [
                            Text('Hedef sınıflar'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w800,
                                  color: ink,
                                )),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: [
                                _chip(
                                  context,
                                  '🏫 ${'Tümü'.tr()}',
                                  _allSelected,
                                  _toggleAll,
                                ),
                                ..._classes.map((c) => _chip(
                                      context,
                                      c.name,
                                      _selected.contains(c.id),
                                      () => setState(() {
                                        if (_selected.contains(c.id)) {
                                          _selected.remove(c.id);
                                        } else {
                                          _selected.add(c.id);
                                        }
                                      }),
                                    )),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text('Duyuru mesajı'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w800,
                                  color: ink,
                                )),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _msgCtrl,
                              maxLines: 6,
                              maxLength: 500,
                              style: GoogleFonts.poppins(
                                  fontSize: 13.5, color: ink),
                              decoration: InputDecoration(
                                hintText:
                                    'Örn: Yarınki dersimiz 10:00\'a alınmıştır.'.tr(),
                                hintStyle: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: AppPalette.textSecondary(context),
                                ),
                                filled: true,
                                fillColor: AppPalette.card(context),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                      color: AppPalette.border(context)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                      color: AppPalette.border(context)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: _kBrand, width: 1.5),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Icon(Icons.notifications_active_rounded,
                                    size: 14,
                                    color: AppPalette.textSecondary(context)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Öğrencilere anlık bildirim olarak gider; ebeveyn panelinde de görünür.'.tr(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5, height: 1.4,
                                      color: AppPalette.textSecondary(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _kBrand,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _sending ? null : _send,
                            icon: _sending
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.campaign_rounded, size: 20),
                            label: Text(
                              _sending ? 'Gönderiliyor…'.tr() : 'Duyuruyu Gönder'.tr(),
                              style: GoogleFonts.poppins(
                                fontSize: 14.5, fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _chip(BuildContext c, String label, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? _kBrand.withValues(alpha: 0.12) : AppPalette.card(c),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: sel ? _kBrand : AppPalette.border(c),
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sel)
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(Icons.check_rounded, size: 14, color: _kBrand),
              ),
            Text(label,
                style: GoogleFonts.poppins(
                  fontSize: 12.5, fontWeight: FontWeight.w700,
                  color: sel ? _kBrand : AppPalette.textPrimary(c),
                )),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📢', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 14),
            Text('Henüz sınıfın yok'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 8),
            Text('Duyuru göndermek için önce bir sınıf oluştur.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13, color: AppPalette.textSecondary(context),
                )),
          ],
        ),
      ),
    );
  }
}
