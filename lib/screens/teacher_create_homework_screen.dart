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
  final TeacherClass cls;
  const TeacherCreateHomeworkScreen({super.key, required this.cls});

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
          child: AiHomeworkGeneratorWidget(cls: cls),
        ),
      ),
    );
  }
}
