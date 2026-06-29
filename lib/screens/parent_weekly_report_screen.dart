// ═══════════════════════════════════════════════════════════════════════════
//  ParentWeeklyReportScreen — Ebeveynin, çocuğunun son 7 gününü tek sayfada
//  özetleyen yazdırılabilir/paylaşılabilir PDF raporu.
//
//  Veri dashboard'dan hazır geçer (_activity, baseStats, childName). PDF,
//  pdf + printing paketleriyle üretilir; PdfPreview araç çubuğu yazdır/paylaş
//  (PDF olarak kaydet / e-posta) seçeneklerini hazır sunar.
//
//  Türkçe karakter desteği için Google Fonts (Nunito) TTF gömülür.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/education_models.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

class ParentWeeklyReportScreen extends StatelessWidget {
  final String childName;
  final List<StudentActivityModel> activity;
  final Map<String, dynamic> baseStats;
  const ParentWeeklyReportScreen({
    super.key,
    required this.childName,
    required this.activity,
    required this.baseStats,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Haftalık rapor'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
      ),
      body: PdfPreview(
        build: (format) => _buildPdf(format),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName:
            'haftalik_rapor_${childName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.pdf',
      ),
    );
  }

  // ── Toplamlar ─────────────────────────────────────────────────────────
  int get _focusMins => activity.fold<int>(0, (s, a) => s + a.focusMinutes);
  int get _summaries => activity.fold<int>(0, (s, a) => s + a.summariesCreated);
  int get _tests => activity.fold<int>(0, (s, a) => s + a.testsSolved);
  int get _photos => activity.fold<int>(0, (s, a) => s + a.photoQuestionsSolved);
  int get _correct => activity.fold<int>(0, (s, a) => s + a.correctAnswers);
  int get _wrong => activity.fold<int>(0, (s, a) => s + a.wrongAnswers);
  int get _blank => activity.fold<int>(0, (s, a) => s + a.blankAnswers);

  Map<String, (int, int)> _subjectBreakdown() {
    final correct = <String, int>{};
    final wrong = <String, int>{};
    for (final a in activity) {
      a.subjectCorrect.forEach((k, v) => correct[k] = (correct[k] ?? 0) + v);
      a.subjectWrong.forEach((k, v) => wrong[k] = (wrong[k] ?? 0) + v);
    }
    final out = <String, (int, int)>{};
    for (final k in {...correct.keys, ...wrong.keys}) {
      out[k] = (correct[k] ?? 0, wrong[k] ?? 0);
    }
    return out;
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final font = await PdfGoogleFonts.nunitoRegular();
    final bold = await PdfGoogleFonts.nunitoExtraBold();
    final semi = await PdfGoogleFonts.nunitoSemiBold();
    const green = PdfColor.fromInt(0xFF10B981);
    const ink = PdfColor.fromInt(0xFF1F2937);
    const grey = PdfColor.fromInt(0xFF6B7280);
    const lightBg = PdfColor.fromInt(0xFFF3F4F6);

    final streak = (baseStats['streakDays'] ?? 0).toString();
    final hours = (_focusMins / 60).toStringAsFixed(1);
    final totalQ = _correct + _wrong + _blank;
    final successPct =
        (_correct + _wrong) == 0 ? 0 : (_correct * 100 / (_correct + _wrong)).round();
    final subjects = _subjectBreakdown().entries.toList()
      ..sort((a, b) {
        final pa = (a.value.$1 + a.value.$2) == 0
            ? 0.0
            : a.value.$1 / (a.value.$1 + a.value.$2);
        final pb = (b.value.$1 + b.value.$2) == 0
            ? 0.0
            : b.value.$1 / (b.value.$1 + b.value.$2);
        return pb.compareTo(pa);
      });

    final range = activity.isEmpty
        ? ''
        : '${activity.first.dateKey}  —  ${activity.last.dateKey}';

    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: font, bold: bold);

    pw.Widget statBox(String label, String value) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: pw.BoxDecoration(
            color: lightBg,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(value,
                  style: pw.TextStyle(
                      font: bold, fontSize: 16, color: ink)),
              pw.SizedBox(height: 2),
              pw.Text(label,
                  style: pw.TextStyle(font: font, fontSize: 9, color: grey)),
            ],
          ),
        );

    doc.addPage(pw.Page(
      pageFormat: format,
      theme: theme,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Başlık
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(childName,
                      style: pw.TextStyle(font: bold, fontSize: 22, color: ink)),
                  pw.SizedBox(height: 2),
                  pw.Text('Haftalık Çalışma Raporu'.tr(),
                      style: pw.TextStyle(font: semi, fontSize: 12, color: green)),
                  if (range.isNotEmpty)
                    pw.Text(range,
                        style: pw.TextStyle(font: font, fontSize: 9, color: grey)),
                ],
              ),
              pw.Container(
                width: 46, height: 46,
                decoration: const pw.BoxDecoration(
                  color: green, shape: pw.BoxShape.circle),
                alignment: pw.Alignment.center,
                child: pw.Text('S',
                    style: pw.TextStyle(
                        font: bold, fontSize: 22,
                        color: const PdfColor.fromInt(0xFFFFFFFF))),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Divider(color: const PdfColor.fromInt(0xFFE5E7EB)),
          pw.SizedBox(height: 12),
          // Özet kutular
          pw.Row(children: [
            pw.Expanded(child: statBox('Odak süresi'.tr(), '$hours sa')),
            pw.SizedBox(width: 8),
            pw.Expanded(child: statBox('Seri (streak)'.tr(), '$streak gün')),
            pw.SizedBox(width: 8),
            pw.Expanded(child: statBox('Başarı'.tr(), '%$successPct')),
          ]),
          pw.SizedBox(height: 8),
          pw.Row(children: [
            pw.Expanded(child: statBox('Konu özeti'.tr(), '$_summaries')),
            pw.SizedBox(width: 8),
            pw.Expanded(child: statBox('Test'.tr(), '$_tests')),
            pw.SizedBox(width: 8),
            pw.Expanded(child: statBox('Foto-soru'.tr(), '$_photos')),
          ]),
          pw.SizedBox(height: 20),
          // Ders bazlı tablo
          pw.Text('Ders bazlı başarı'.tr(),
              style: pw.TextStyle(font: bold, fontSize: 13, color: ink)),
          pw.SizedBox(height: 8),
          if (subjects.isEmpty)
            pw.Text('Bu hafta test verisi yok.'.tr(),
                style: pw.TextStyle(font: font, fontSize: 10, color: grey))
          else
            pw.Table(
              border: pw.TableBorder.symmetric(
                inside: const pw.BorderSide(
                    color: PdfColor.fromInt(0xFFE5E7EB), width: 0.5),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: lightBg),
                  children: [
                    _cell('Ders'.tr(), semi, 10, ink),
                    _cell('Doğru'.tr(), semi, 10, ink, center: true),
                    _cell('Yanlış'.tr(), semi, 10, ink, center: true),
                    _cell('Başarı'.tr(), semi, 10, ink, center: true),
                  ],
                ),
                ...subjects.map((e) {
                  final c = e.value.$1, w = e.value.$2;
                  final p = (c + w) == 0 ? 0 : (c * 100 / (c + w)).round();
                  return pw.TableRow(children: [
                    _cell(e.key, font, 10, ink),
                    _cell('$c', font, 10, ink, center: true),
                    _cell('$w', font, 10, ink, center: true),
                    _cell('%$p', bold, 10, green, center: true),
                  ]);
                }),
              ],
            ),
          pw.SizedBox(height: 18),
          // Cevap dağılımı
          pw.Text('Test cevap dağılımı'.tr(),
              style: pw.TextStyle(font: bold, fontSize: 13, color: ink)),
          pw.SizedBox(height: 8),
          pw.Row(children: [
            _distPill('Doğru'.tr(), _correct, totalQ,
                const PdfColor.fromInt(0xFF10B981), font, bold),
            pw.SizedBox(width: 8),
            _distPill('Yanlış'.tr(), _wrong, totalQ,
                const PdfColor.fromInt(0xFFEF4444), font, bold),
            pw.SizedBox(width: 8),
            _distPill('Boş'.tr(), _blank, totalQ,
                const PdfColor.fromInt(0xFF94A3B8), font, bold),
          ]),
          pw.Spacer(),
          pw.Divider(color: const PdfColor.fromInt(0xFFE5E7EB)),
          pw.Text('Bu rapor uygulamanın ebeveyn paneli tarafından oluşturulmuştur.'.tr(),
              style: pw.TextStyle(font: font, fontSize: 8, color: grey)),
        ],
      ),
    ));
    return doc.save();
  }

  static pw.Widget _cell(String text, pw.Font f, double size, PdfColor color,
      {bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: pw.Text(text,
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
          style: pw.TextStyle(font: f, fontSize: size, color: color)),
    );
  }

  static pw.Widget _distPill(String label, int value, int total, PdfColor color,
      pw.Font font, pw.Font bold) {
    final pct = total == 0 ? 0 : (value * 100 / total).round();
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10),
        decoration: pw.BoxDecoration(
          color: PdfColor(color.red, color.green, color.blue, 0.12),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          children: [
            pw.Text('$value',
                style: pw.TextStyle(font: bold, fontSize: 16, color: color)),
            pw.Text('$label  (%$pct)',
                style: pw.TextStyle(font: font, fontSize: 9, color: color)),
          ],
        ),
      ),
    );
  }
}
