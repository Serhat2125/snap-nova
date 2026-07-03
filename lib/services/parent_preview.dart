// ═══════════════════════════════════════════════════════════════════════════
//  ParentPreview — Ebeveynin "Öğrenci Paneli" önizleme modu.
//
//  Ebeveyn, ParentShellScreen'deki "Öğrenci Paneli" sekmesiyle çocuğunun
//  gördüğü öğrenci deneyimine girer (Kütüphanem ve altındaki her şey).
//  GEZEBİLİR ama ÜRETEMEZ: konu özeti/sınav sorusu üretimi, yarışma
//  (Rakip Bul / Bilgi Ligi quiz / grup yarışı) ve ödev teslimi kapalıdır —
//  amaç çocuğun neleri çalışabileceğini görmek, onun adına iş yapmak değil.
//
//  Kullanım (üretim/yarışma tetikleyicisinin en başında):
//    if (ParentPreview.guard(context)) return;
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'runtime_translator.dart';

class ParentPreview {
  ParentPreview._();

  /// Önizleme açık mı? ParentShellScreen önizlemeye girerken true yapar,
  /// önizleme rotası kapanınca false'a döner.
  static bool active = false;

  /// Üretim/yarışma eylemlerinin başında çağrılır. Önizleme aktifse
  /// kullanıcıya kısa bir açıklama gösterir ve true döner (çağıran return
  /// etmeli); değilse false döner ve akış normal devam eder.
  static bool guard(BuildContext context) {
    if (!active) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(
        '👁️ Öğrenci paneli önizlemesi — bu işlem yalnızca öğrenci '
        'hesabında yapılabilir. Burada çocuğunun neler çalışabileceğini '
        'görüyorsun.'.tr(),
        style: GoogleFonts.poppins(fontSize: 12.5, height: 1.4),
      ),
    ));
    return true;
  }
}
