// ═══════════════════════════════════════════════════════════════════════════
//  Öğretmen branşları — öncelik-sıralı düz liste + branş seçim modalı.
//
//  "Branşını seç" butonuyla açılan pencereyi (showTeacherBranchPicker) besler.
//  Tek kaynak: yeni branş eklemek için sadece aşağıdaki listeye satır ekle;
//  sıralama = uygulamaya yatkınlık (en üstte en olası branşlar).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

/// Tüm öğretmen branşları — düz liste, ÖNCELİK SIRASIYLA.
/// Sıralama: uygulamayı en çok kullanmaya yatkın (sınav/soru ağırlıklı)
/// branşlar başta; sözel ve beceri/destek branşları sonda.
const List<String> kAllTeacherBranches = [
  // Sayısal — soru/test ağırlıklı, app'e en yatkın
  'Matematik (Lise)',
  'İlköğretim Matematik (5-8. Sınıf)',
  'Fizik',
  'Kimya',
  'Biyoloji',
  'Fen Bilimleri (Ortaokul)',
  // Sosyal — sınav ağırlıklı
  'Tarih',
  'Coğrafya',
  // Dil ve edebiyat
  'Türk Dili ve Edebiyatı (Lise)',
  'Türkçe (Ortaokul)',
  'İngilizce',
  'Sosyal Bilgiler (Ortaokul)',
  'Felsefe Grubu (Psikoloji, Sosyoloji, Mantık)',
  'Din Kültürü ve Ahlak Bilgisi',
  // Diğer yabancı diller
  'Almanca',
  'Fransızca',
  'İspanyolca',
  'Arapça',
  'Rusça',
  // Teknoloji
  'Bilişim Teknolojileri ve Yazılım (Kodlama/Robotik)',
  'Teknoloji ve Tasarım',
  // Temel eğitim
  'Sınıf Öğretmenliği (İlkokul 1-4)',
  'Okul Öncesi Öğretmenliği',
  // Destek & özel
  'Rehberlik / Psikolojik Danışman (PDR)',
  'Özel Eğitim Öğretmenliği',
  // Sanat & spor
  'Beden Eğitimi ve Spor',
  'Görsel Sanatlar (Resim)',
  'Müzik',
];

/// Branş seçim modalını açar. Seçilen branşı döndürür (iptal → null).
Future<String?> showTeacherBranchPicker(
  BuildContext context, {
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TeacherBranchSheet(selected: selected),
  );
}

class _TeacherBranchSheet extends StatefulWidget {
  final String? selected;
  const _TeacherBranchSheet({this.selected});

  @override
  State<_TeacherBranchSheet> createState() => _TeacherBranchSheetState();
}

class _TeacherBranchSheetState extends State<_TeacherBranchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    // Kategori başlıkları olmadan düz ders listesi — sadece branş adları.
    final branches = q.isEmpty
        ? kAllTeacherBranches
        : kAllTeacherBranches
            .where((b) => b.toLowerCase().contains(q))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: AppPalette.bg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42, height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.border(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Branşını seç'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppPalette.textPrimary(context),
                          )),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded,
                          color: AppPalette.textSecondary(context)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppPalette.card(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppPalette.border(context)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextField(
                    autofocus: false,
                    onChanged: (v) => setState(() => _query = v),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textPrimary(context),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Branş ara…'.tr(),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 20, color: AppPalette.textSecondary(context)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: branches.isEmpty
                    ? Center(
                        child: Text('Sonuç bulunamadı'.tr(),
                            style: GoogleFonts.poppins(
                              color: AppPalette.textSecondary(context),
                              fontWeight: FontWeight.w600,
                            )),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: branches.length,
                        itemBuilder: (ctx, i) =>
                            _branchRow(context, branches[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _branchRow(BuildContext context, String b) {
    final isSel = b == widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pop(context, b),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: isSel
                  ? const Color(0xFF7C3AED).withValues(alpha: 0.12)
                  : AppPalette.card(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSel
                    ? const Color(0xFF7C3AED)
                    : AppPalette.border(context),
                width: isSel ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(b.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight:
                            isSel ? FontWeight.w800 : FontWeight.w600,
                        color: AppPalette.textPrimary(context),
                      )),
                ),
                if (isSel)
                  const Icon(Icons.check_circle_rounded,
                      size: 20, color: Color(0xFF7C3AED)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
