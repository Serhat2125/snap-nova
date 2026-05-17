// ═══════════════════════════════════════════════════════════════════════════════
//  SummaryRatingTable — Konu özetinin altında 1-10 tablo değerlendirmesi.
//
//  5 boyut, her biri 1-10 ölçek:
//    • Doğruluk
//    • Anlaşılırlık
//    • Kapsam
//    • Görsel düzen
//    • Genel beğeni
//
//  Kullanıcı zaten oy verdiyse mevcut oyu gösterir (değiştirebilir).
//  Toplam ortalama altta "Genel: 8,4/10" gibi. Submit ile Firestore'a yazılır.
//
//  AppPalette ile dark mode uyumlu. localeService.tr() ile çevrili.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show localeService;
import '../services/runtime_translator.dart';
import '../services/summary_cache_service.dart';
import '../theme/app_theme.dart';

class SummaryRatingTable extends StatefulWidget {
  /// Hangi cache parent dokümanı.
  final String cacheDocId;

  /// Hangi aday dokümanı.
  final String candidateDocId;

  /// Bu canonical mi yoksa hâlâ aday mı? (Banner için)
  final bool isCanonical;

  /// Cache'ten gelmişse mevcut ortalama puanı göster.
  final double? existingAvg;
  final int existingCount;

  const SummaryRatingTable({
    super.key,
    required this.cacheDocId,
    required this.candidateDocId,
    this.isCanonical = false,
    this.existingAvg,
    this.existingCount = 0,
  });

  @override
  State<SummaryRatingTable> createState() => _SummaryRatingTableState();
}

class _SummaryRatingTableState extends State<SummaryRatingTable> {
  static const _dimensions = <_Dim>[
    _Dim('accuracy', '🎯', 'Doğruluk', 'Bilgi gerçek mi?'),
    _Dim('clarity', '💡', 'Anlaşılırlık', 'Net açıklama mı?'),
    _Dim('coverage', '📚', 'Kapsam', 'Konuyu tam mı anlatıyor?'),
    _Dim('layout', '📐', 'Görsel düzen', 'Yapı/tablo/formül düzgün mü?'),
    _Dim('overall', '⭐', 'Genel beğeni', 'Tavsiye eder misin?'),
  ];

  final Map<String, int?> _ratings = {
    for (final d in _dimensions) d.key: null,
  };
  bool _busy = false;
  bool _submitted = false;
  String? _error;

  double? get _myAvg {
    final values = _ratings.values.whereType<int>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  bool get _isComplete =>
      _ratings.values.every((v) => v != null && v >= 1 && v <= 10);

  Future<void> _submit() async {
    if (!_isComplete || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final dimensions = <String, int>{
      for (final entry in _ratings.entries) entry.key: entry.value!,
    };
    final ok = await SummaryCacheService.submitRating(
      cacheDocId: widget.cacheDocId,
      candidateDocId: widget.candidateDocId,
      dimensions: dimensions,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _submitted = ok;
      _error = ok ? null : 'Puan kaydedilemedi. İnternet bağlantını kontrol et.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final cardBg = AppPalette.card(context);
    final borderC = AppPalette.border(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderC),
        boxShadow: [
          BoxShadow(
            color: AppPalette.shadow(context),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Row(
            children: [
              const Text('📋', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bu özeti değerlendir'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
              if (widget.existingAvg != null && widget.existingCount > 0)
                _AvgPill(
                  avg: widget.existingAvg!,
                  count: widget.existingCount,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.isCanonical
                ? 'Topluluk tarafından seçilen en iyi özet. Puanın canonical sıralamayı güncel tutar.'
                    .tr()
                : 'Sen ilk 100 değerlendirenden birisin — puanın sonradan gelen öğrencileri etkileyecek 🌟'
                    .tr(),
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              color: muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),

          // Tablo
          _RatingTable(
            dimensions: _dimensions,
            ratings: _ratings,
            ink: ink,
            muted: muted,
            borderC: borderC,
            onChange: (k, v) {
              setState(() {
                _ratings[k] = v;
                _error = null;
                _submitted = false;
              });
            },
          ),

          const SizedBox(height: 14),

          // Alt: ortalama + buton + hata
          Row(
            children: [
              if (_myAvg != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6A3C).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${'Senin puanın'.tr()}: ${_myAvg!.toStringAsFixed(1)}/10',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFD15020),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              if (_submitted)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 18, color: Color(0xFF22C55E)),
                    const SizedBox(width: 6),
                    Text(
                      'Teşekkürler, kaydedildi!'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF22C55E),
                      ),
                    ),
                  ],
                )
              else
                ElevatedButton.icon(
                  onPressed: _isComplete && !_busy ? _submit : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: Text('Puanı Gönder'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6A3C),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppPalette.cardMuted(context),
                    disabledForegroundColor: muted,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    textStyle: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: Color(0xFFEF4444)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Hata bildir butonu — küçük link
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _busy ? null : () => _reportError(context),
              icon: const Icon(Icons.flag_outlined, size: 14),
              label: Text(
                'Bu özette hata var'.tr(),
                style: GoogleFonts.poppins(fontSize: 11),
              ),
              style: TextButton.styleFrom(
                foregroundColor: muted,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reportError(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await SummaryCacheService.reportError(
      cacheDocId: widget.cacheDocId,
      candidateDocId: widget.candidateDocId,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? localeService.tr('Bildirimin alındı — incelenecek.')
            : localeService.tr('Bildirim kaydedilemedi.')),
        backgroundColor:
            ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Yardımcı widget'lar
// ═══════════════════════════════════════════════════════════════════════════

class _Dim {
  final String key;
  final String emoji;
  final String label;
  final String hint;
  const _Dim(this.key, this.emoji, this.label, this.hint);
}

/// Compact bir tablo: her satır bir boyut, sağda 1-10 dot row.
class _RatingTable extends StatelessWidget {
  final List<_Dim> dimensions;
  final Map<String, int?> ratings;
  final Color ink;
  final Color muted;
  final Color borderC;
  final void Function(String key, int value) onChange;

  const _RatingTable({
    required this.dimensions,
    required this.ratings,
    required this.ink,
    required this.muted,
    required this.borderC,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderC),
      ),
      child: Column(
        children: [
          // Üst başlık satırı (görsel olarak tablo gibi)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppPalette.cardMuted(context),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    'Kriter'.tr(),
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: muted,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Puan (1-10)'.tr(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: muted,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Veri satırları
          for (int i = 0; i < dimensions.length; i++)
            _RatingRow(
              dim: dimensions[i],
              current: ratings[dimensions[i].key],
              isLast: i == dimensions.length - 1,
              borderC: borderC,
              ink: ink,
              muted: muted,
              onChange: (v) => onChange(dimensions[i].key, v),
            ),
        ],
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final _Dim dim;
  final int? current;
  final bool isLast;
  final Color borderC;
  final Color ink;
  final Color muted;
  final void Function(int value) onChange;

  const _RatingRow({
    required this.dim,
    required this.current,
    required this.isLast,
    required this.borderC,
    required this.ink,
    required this.muted,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: borderC.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(dim.emoji, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        dim.label.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  dim.hint.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          // 1-10 numara butonları (yatay scroll güvenli)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int v = 1; v <= 10; v++)
                    _NumberCell(
                      value: v,
                      selected: current == v,
                      onTap: () => onChange(v),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberCell extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _NumberCell({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFFF6A3C)
                : AppPalette.cardMuted(context),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFF6A3C)
                  : AppPalette.border(context),
              width: selected ? 0 : 1,
            ),
          ),
          child: Text(
            '$value',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: selected ? Colors.white : AppPalette.textPrimary(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvgPill extends StatelessWidget {
  final double avg;
  final int count;
  const _AvgPill({required this.avg, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB070).withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '⭐ ${avg.toStringAsFixed(1)} · $count',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFD15020),
        ),
      ),
    );
  }
}
