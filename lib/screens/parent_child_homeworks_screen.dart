// ═══════════════════════════════════════════════════════════════════════════
//  ParentChildHomeworksScreen — Ebeveynin, bağlı çocuğunun sınıf ÖDEVLERİNİ
//  ve sonuçlarını gördüğü ekran.
//
//  Çocuğun katıldığı sınıfları listeler; bir sınıfa basınca o sınıftaki tüm
//  ödevler + çocuğun teslim sonuçları (doğru/yanlış/boş, süre, AI yorumu)
//  TeacherStudentReportScreen ile gösterilir (öğretmenin gördüğü aynı veri).
//
//  Firestore: bağlı ebeveyn, isLinkedParent kuralı sayesinde çocuğun
//  submission'larını okuyabilir.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_student_report_screen.dart';

const _kBrand = Color(0xFF10B981);

class ParentChildHomeworksScreen extends StatefulWidget {
  final String childUid;
  final String childName;
  const ParentChildHomeworksScreen({
    super.key,
    required this.childUid,
    required this.childName,
  });

  @override
  State<ParentChildHomeworksScreen> createState() =>
      _ParentChildHomeworksScreenState();
}

class _ParentChildHomeworksScreenState
    extends State<ParentChildHomeworksScreen> {
  late Future<List<JoinedClass>> _future;

  @override
  void initState() {
    super.initState();
    _future = ClassService.joinedClassesFor(widget.childUid);
  }

  void _openClass(JoinedClass c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TeacherStudentReportScreen(
        classId: c.classId,
        studentUid: widget.childUid,
        studentName: widget.childName,
        readOnly: true, // ebeveyn: salt-okuma (çocuğun teslimine yazamaz)
      ),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Karne & Öğretmen'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            Text(widget.childName,
                style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w500,
                  color: AppPalette.textSecondary(context),
                )),
          ],
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<JoinedClass>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final classes = snap.data ?? const <JoinedClass>[];
            if (classes.isEmpty) return _empty(context);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: classes.length,
              itemBuilder: (ctx, i) => _classRow(context, classes[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _classRow(BuildContext context, JoinedClass c) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openClass(c),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _kBrand.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.class_rounded, color: _kBrand, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.className,
                        style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (c.teacherDisplayName.trim().isNotEmpty)
                      Text('${'Öğretmen'.tr()}: ${c.teacherDisplayName}',
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: AppPalette.textSecondary(context),
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppPalette.textSecondary(context)),
            ],
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
            const Text('📚', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 14),
            Text('Henüz bir sınıfa katılmamış'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 8),
            Text('Çocuğun bir öğretmenin sınıf koduyla katıldığında ödevleri '
                'burada görünür.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13, color: AppPalette.textSecondary(context),
                  height: 1.4,
                )),
          ],
        ),
      ),
    );
  }
}
