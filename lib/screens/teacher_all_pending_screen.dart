// ═══════════════════════════════════════════════════════════════════════════
//  TeacherAllPendingScreen — Öğretmenin TÜM sınıflarındaki bekleyen (taslak +
//  zamanlanmış) ödevleri tek listede. Ana ekrandaki "kontrol bekleyen" özet
//  satırından açılır; öğretmen sınıfa girmeden buradan yayınlar/siler.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_pending_homeworks_screen.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherAllPendingScreen extends StatefulWidget {
  const TeacherAllPendingScreen({super.key});

  @override
  State<TeacherAllPendingScreen> createState() =>
      _TeacherAllPendingScreenState();
}

class _TeacherAllPendingScreenState extends State<TeacherAllPendingScreen> {
  List<PendingHomeworkItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await HomeworkService.allPendingForTeacher();
    if (!mounted) return;
    setState(() => _items = list);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final items = _items;
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Bekleyen Ödevler'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: ink),
            onPressed: () { setState(() => _items = null); _load(); },
          ),
        ],
      ),
      body: SafeArea(
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? _empty(context)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final it = items[i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sınıf etiketi
                            Padding(
                              padding: const EdgeInsets.only(left: 2, bottom: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.class_rounded,
                                      size: 13, color: _kBrand),
                                  const SizedBox(width: 5),
                                  Text(it.className,
                                      style: GoogleFonts.poppins(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: _kBrand)),
                                ],
                              ),
                            ),
                            PendingHomeworkCard(
                                hw: it.hw, classId: it.hw.classId),
                          ],
                        );
                      },
                    ),
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
            const Text('✅', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 14),
            Text('Bekleyen ödev yok'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(context))),
            const SizedBox(height: 8),
            Text('Taslak veya ileri tarihe zamanlanmış ödevlerin burada toplanır.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppPalette.textSecondary(context),
                    height: 1.4)),
          ],
        ),
      ),
    );
  }
}
