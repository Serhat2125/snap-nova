// ═══════════════════════════════════════════════════════════════════════════
//  safe_dismiss — Odaklı bir TextField içeren modal sheet/dialog'u GÜVENLE
//  kapatır.
//
//  Çökme: Bir sheet/dialog içinde odaklı bir TextField varken kapatınca Flutter
//  şu hatayı atar (DEBUG'da kırmızı/sarı ekran):
//     framework.dart: Failed assertion: '_dependents.isEmpty': is not true.
//  Kaynağı InheritedElement.debugDeactivated(): route kapanırken route'un
//  FocusScope/MediaQuery InheritedElement'i HÂLÂ bağımlısı (odaklı EditableText)
//  varken deaktive ediliyor. Bu, KLAVYE KAPANMA ANİMASYONU sürerken pop
//  yapıldığında oluşur: viewInsets her frame değiştiği için alt-ağaç yeniden
//  kurulurken aynı anda kaldırılıyor, deaktivasyon sırası bozuluyor.
//
//  Çözüm: önce odağı bırak, KLAVYE TAMAMEN KAPANANA kadar (viewInsets 0 olana
//  dek, en fazla ~0.65 sn) bekle, ANCAK ondan sonra route'u kaldır. Klavye zaten
//  kapalıysa anında kapanır. Navigator await'ten ÖNCE yakalanır.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// [sheetContext]: sheet/dialog builder'ının context'i. [result]: pop değeri.
Future<void> safeDismiss(BuildContext sheetContext, [Object? result]) async {
  final nav = Navigator.of(sheetContext);

  double keyboardInset() {
    try {
      return View.of(sheetContext).viewInsets.bottom;
    } catch (_) {
      return 0;
    }
  }

  final wasOpen = keyboardInset() > 0;
  FocusManager.instance.primaryFocus?.unfocus();

  // Klavye açıksa kapanış animasyonu bitene kadar bekle (frame-frame yokla).
  // Bazı platformlarda ham viewInsets hemen 0'a düşebildiğinden, klavye açıktı
  // ise EN AZINDAN ~300ms bekleyerek Flutter tarafı animasyonun da oturmasını
  // garantiye al (mid-animation pop = _dependents.isEmpty çökmesi).
  if (wasOpen) {
    var elapsedMs = 0;
    while (elapsedMs < 300 || keyboardInset() > 0) {
      if (elapsedMs >= 640) break; // güvenlik tavanı
      await Future<void>.delayed(const Duration(milliseconds: 16));
      elapsedMs += 16;
    }
  }

  if (nav.mounted) nav.pop(result);
}
