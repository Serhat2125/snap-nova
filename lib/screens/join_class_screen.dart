// ═══════════════════════════════════════════════════════════════════════════
//  JoinClassScreen — Öğrencinin öğretmenden aldığı kodla sınıfa katılma.
//
//  Profile menüsünden veya Kütüphane'den açılır. Kullanıcı kodu yazar:
//  - Geçerli kod → sınıfa katılır
//  - Hatalı kod → hata gösterilir
//  - Mevcut sınıflarına liste olarak buradan da bakabilir
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

class JoinClassScreen extends StatefulWidget {
  const JoinClassScreen({super.key});

  @override
  State<JoinClassScreen> createState() => _JoinClassScreenState();
}

class _JoinClassScreenState extends State<JoinClassScreen> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  String? _msg;
  bool _success = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _msg = null;
    });
    final res = await ClassService.joinByCode(text);
    if (!mounted) return;
    setState(() => _sending = false);
    switch (res) {
      case JoinClassResult.success:
        setState(() {
          _success = true;
          _msg = 'Sınıfa katıldın! Aşağıdaki listede görebilirsin.'.tr();
        });
        _ctrl.clear();
        break;
      case JoinClassResult.pendingApproval:
        setState(() {
          _success = true;
          _msg = 'Katılma isteğin öğretmenine iletildi. Öğretmenin '
              'onaylayınca sınıf içeriklerini ve ödevleri görebileceksin.'.tr();
        });
        _ctrl.clear();
        break;
      case JoinClassResult.invalidCode:
        setState(() => _msg =
            'Kod geçersiz. Öğretmeninin paylaştığı 5 haneli kodu gir.'.tr());
        break;
      case JoinClassResult.classNotFound:
        setState(() => _msg = 'Bu kodla bir sınıf bulunamadı.'.tr());
        break;
      case JoinClassResult.alreadyJoined:
        setState(() => _msg = 'Bu sınıfa zaten katılmıştın.'.tr());
        break;
      case JoinClassResult.selfJoin:
        setState(() => _msg = 'Kendi sınıfına öğrenci olarak katılamazsın.'.tr());
        break;
      case JoinClassResult.notAuthed:
        setState(() => _msg = 'Giriş yapman gerekiyor.'.tr());
        break;
      case JoinClassResult.error:
        setState(() => _msg = 'Bağlantı sorunu. Tekrar dene.'.tr());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Sınıfa Katıl'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Kod giriş kartı ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppPalette.card(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppPalette.border(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Text('🔑',
                              style: TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('Öğretmeninden aldığın kodu yaz'.tr(),
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: ink,
                              )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: AppPalette.bg(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppPalette.border(context)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: _ctrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _join(),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9\-]')),
                          LengthLimitingTextInputFormatter(11),
                        ],
                        style: GoogleFonts.poppins(
                          fontSize: 17, fontWeight: FontWeight.w900,
                          color: ink, letterSpacing: 1.5,
                        ),
                        decoration: InputDecoration(
                          hintText: 'XXXXX',
                          hintStyle: GoogleFonts.poppins(
                            color: AppPalette.textSecondary(context)
                                .withValues(alpha: 0.5),
                            letterSpacing: 1.5,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    if (_msg != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _success
                              ? const Color(0xFF10B981).withValues(alpha: 0.08)
                              : const Color(0xFFEF4444).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(_success
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                                size: 16,
                                color: _success
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_msg!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: ink, height: 1.4,
                                  )),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _sending ? null : _join,
                        child: _sending
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white),
                              )
                            : Text('Katıl'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                )),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Katıldığım sınıflar ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
              child: Row(
                children: [
                  Icon(Icons.history_edu_rounded,
                      color: AppPalette.textSecondary(context), size: 18),
                  const SizedBox(width: 6),
                  Text('KATILDIĞIM SINIFLAR'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w800,
                        color: AppPalette.textSecondary(context),
                        letterSpacing: 1.0,
                      )),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<JoinedClass>>(
                stream: ClassService.myJoinedClassesStream(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2));
                  }
                  final classes = snap.data!;
                  if (classes.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Henüz hiçbir sınıfa katılmadın.'.tr(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: AppPalette.textSecondary(context),
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: classes.length,
                    itemBuilder: (ctx, i) {
                      final c = classes[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: AppPalette.card(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppPalette.border(context)),
                        ),
                        child: Row(
                          children: [
                            const Text('🏫',
                                style: TextStyle(fontSize: 22)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(c.className,
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: ink,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      if (c.isPending) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF59E0B)
                                                .withValues(alpha: 0.14),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text('Onay bekliyor'.tr(),
                                              style: GoogleFonts.poppins(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    const Color(0xFFB45309),
                                              )),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (c.teacherDisplayName.isNotEmpty)
                                    Text(c.teacherDisplayName,
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: AppPalette
                                              .textSecondary(context),
                                        )),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.exit_to_app_rounded,
                                  size: 18,
                                  color: AppPalette.textSecondary(context)),
                              tooltip: 'Sınıftan çık'.tr(),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    backgroundColor: AppPalette.card(dCtx),
                                    title: Text('Sınıftan çık?'.tr()),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(
                                            dCtx, false),
                                        child: Text('Vazgeç'.tr()),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(
                                            dCtx, true),
                                        child: Text('Çık'.tr()),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await ClassService.leaveClass(c.classId);
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
