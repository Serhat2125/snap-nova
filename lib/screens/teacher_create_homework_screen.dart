// ═══════════════════════════════════════════════════════════════════════════
//  TeacherCreateHomeworkScreen — "AI ile Ödev Oluştur" formunu kendi tam
//  ekranında barındırır. (Eskiden sınıf detayındaki Ödevler sekmesinde
//  gömülüydü; o sekme kaldırılınca buraya taşındı.)
//  Form: AiHomeworkGeneratorWidget → üretir → önizleme ekranına geçer.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../services/class_service.dart';
import '../theme/app_theme.dart';
import '../widgets/teacher_widgets.dart';

class TeacherCreateHomeworkScreen extends StatelessWidget {
  /// Seçilen sınıf(lar). İlk sınıf form varsayılanlarını (seviye/branş)
  /// belirler; ödev üretildiğinde tüm seçilen sınıflara gönderilir.
  final List<TeacherClass> classes;
  const TeacherCreateHomeworkScreen({super.key, required this.classes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: AiHomeworkGeneratorWidget(
            cls: classes.first,
            additionalClassIds:
                classes.skip(1).map((c) => c.id).toList(),
          ),
        ),
      ),
    );
  }
}
