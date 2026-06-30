// ═══════════════════════════════════════════════════════════════════════════
//  Öğretmen paneli "Bu sayfa nasıl çalışır?" yardımı — ORTAK, derli toplu
//  merkezi pencere. Her madde küçük çerçeve içinde; yatayda sol/sağ boşluklu;
//  ekranın tam ortasında açılır (showDialog). Tüm öğretmen yardım sayfaları
//  bu tek bileşeni kullanır.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const _kBrand = Color(0xFF7C3AED);

/// Tek yardım maddesi: emoji + başlık. [body] verilirse alt açıklama gösterilir
/// (başlık kalın, açıklama soluk). Verilmezse tek satır madde olarak görünür.
class TeacherHelpItem {
  final String emoji;
  final String title;
  final String? body;
  const TeacherHelpItem(this.emoji, this.title, [this.body]);
}

/// Ekranın ortasında açılan, derli toplu yardım penceresi.
/// Her madde kendi küçük çerçevesinde listelenir.
Future<void> showTeacherHelpDialog(
  BuildContext context, {
  required String title,
  required List<TeacherHelpItem> items,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      final ink = AppPalette.textPrimary(ctx);
      final muted = AppPalette.textSecondary(ctx);
      return Dialog(
        backgroundColor: AppPalette.card(ctx),
        // Yatayda sol/sağ boşluk + dikeyde nefes payı → tam ortada açılır.
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: _kBrand.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.help_outline_rounded,
                          size: 19, color: _kBrand),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(title.tr(),
                          style: GoogleFonts.poppins(
                              fontSize: 16.5, fontWeight: FontWeight.w900,
                              color: ink)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final it in items)
                          _helpCard(ctx, it, ink, muted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrand,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Anladım'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _helpCard(
    BuildContext ctx, TeacherHelpItem it, Color ink, Color muted) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: AppPalette.bg(ctx),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppPalette.border(ctx)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(it.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: it.body == null
              ? Text(it.title.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, height: 1.4,
                      fontWeight: FontWeight.w600, color: ink))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.title.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w800,
                            color: ink)),
                    const SizedBox(height: 2),
                    Text(it.body!.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 12, height: 1.4, color: muted)),
                  ],
                ),
        ),
      ],
    ),
  );
}
