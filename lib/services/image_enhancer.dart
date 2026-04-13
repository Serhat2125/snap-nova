import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ImageEnhancer — Solvely tarzı akıllı kırpma + iyileştirme
//  ─────────────────────────────────────────────────────────────────────────
//  Akış (hepsi arka planda, kullanıcı fark etmez):
//   1. Fotoğrafı decode et
//   2. İçerik yoğunluğuna göre kenar boşluklarını kırp (masa kenarı, gölgeler gitsin)
//   3. Kontrast + parlaklık iyileştir → yazılar daha belirgin olur
//   4. Unsharp mask konvolüsyonu → hafif bulanıklıkları gider
//   5. Kaliteli JPEG olarak temp'e yaz, yeni path döndür
//  İşlem `compute()` üzerinden izole'de çalışır — UI donmaz.
// ═══════════════════════════════════════════════════════════════════════════════

class ImageEnhancer {
  /// Fotoğrafı akıllıca kırpıp iyileştirir ve yeni bir geçici dosya yolu döner.
  /// Herhangi bir hata durumunda orijinal yolu geri verir (sessizce fallback).
  static Future<String> processForOcr(String srcPath) async {
    try {
      final bytes = await File(srcPath).readAsBytes();
      final processed = await compute(_processIsolate, bytes);
      if (processed == null) return srcPath;

      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/sn_enh_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(processed, flush: true);
      return out.path;
    } catch (_) {
      return srcPath;
    }
  }
}

// ── İzole üzerinde çalışan pipeline ─────────────────────────────────────────
Uint8List? _processIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // 1) Çok büyük fotoğrafları aşağı örnekle — OCR için 1800px yeter.
  img.Image image = decoded;
  if (image.width > 1800 || image.height > 1800) {
    final scale = 1800 / (image.width > image.height ? image.width : image.height);
    image = img.copyResize(
      image,
      width:  (image.width  * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  // 2) Akıllı kırpma — içerik sınırlarını ink-density ile bul.
  final cropRect = _findContentBounds(image);
  if (cropRect != null) {
    image = img.copyCrop(
      image,
      x:      cropRect.x,
      y:      cropRect.y,
      width:  cropRect.w,
      height: cropRect.h,
    );
  }

  // 3) Kontrast + parlaklık: soluk yazılar koyulaşır, kağıt beyazlaşır.
  image = img.adjustColor(
    image,
    contrast:   1.25,
    brightness: 1.04,
    saturation: 0.95,
  );

  // 4) Unsharp mask benzeri hafif netleştirme — 3x3 konvolüsyon kernel.
  image = img.convolution(
    image,
    filter: const [
       0, -1,  0,
      -1,  6, -1,
       0, -1,  0,
    ],
    div: 2,
  );

  // 5) JPEG olarak encode et (kalite 88 — boyut/kalite dengesi).
  return Uint8List.fromList(img.encodeJpg(image, quality: 88));
}

// ── İçerik bounding box'ı — ink-density tarama ──────────────────────────────
// Gri tonlamaya çevirip eşik altı piksel (karartı) yoğunluğunu satır/kolon
// bazında saydıktan sonra ilk ve son "yoğun" satır/kolonu bulur.
_CropRect? _findContentBounds(img.Image source) {
  // Taramayı hızlandırmak için küçük bir önizleme kopyası üzerinde çalış.
  const scanW = 320;
  final scale  = scanW / source.width;
  final scanH  = (source.height * scale).round();
  if (scanH < 40) return null;

  final gray = img.grayscale(img.copyResize(
    source,
    width:  scanW,
    height: scanH,
    interpolation: img.Interpolation.average,
  ));

  // Ortalama parlaklığı bul → eşiği dinamik kur.
  int sum = 0;
  final total = scanW * scanH;
  for (int y = 0; y < scanH; y++) {
    for (int x = 0; x < scanW; x++) {
      sum += gray.getPixel(x, y).r.toInt();
    }
  }
  final avg = sum / total;
  // Ortalamanın %72'si altındaki her piksel "içerik" sayılır.
  final threshold = (avg * 0.72).clamp(40, 200);

  // Satır ve sütun yoğunluklarını say.
  final rowInk = List<int>.filled(scanH, 0);
  final colInk = List<int>.filled(scanW, 0);
  for (int y = 0; y < scanH; y++) {
    for (int x = 0; x < scanW; x++) {
      if (gray.getPixel(x, y).r <= threshold) {
        rowInk[y]++;
        colInk[x]++;
      }
    }
  }

  // Minimum yoğunluk eşiği — gürültü satırlarını eler.
  final rowMin = (scanW * 0.03).round(); // satırda %3 karartı
  final colMin = (scanH * 0.03).round(); // sütunda %3 karartı

  int top = 0;
  while (top < scanH && rowInk[top] < rowMin) {
    top++;
  }
  int bottom = scanH - 1;
  while (bottom > top && rowInk[bottom] < rowMin) {
    bottom--;
  }
  int left = 0;
  while (left < scanW && colInk[left] < colMin) {
    left++;
  }
  int right = scanW - 1;
  while (right > left && colInk[right] < colMin) {
    right--;
  }

  // Geçerli bir kutu bulunamadıysa (neredeyse boş görüntü), kırpma yapma.
  if (bottom - top < scanH * 0.25 || right - left < scanW * 0.25) return null;

  // Küçük bir güvenlik marjı (+%2) — yazının tam kenarına sıfırlanmasın.
  final padY = (scanH * 0.02).round();
  final padX = (scanW * 0.02).round();
  top    = (top    - padY).clamp(0, scanH - 1);
  bottom = (bottom + padY).clamp(0, scanH - 1);
  left   = (left   - padX).clamp(0, scanW - 1);
  right  = (right  + padX).clamp(0, scanW - 1);

  // Scan koordinatlarını orijinal boyuta geri ölçekle.
  final inv = 1 / scale;
  return _CropRect(
    x: (left * inv).round(),
    y: (top  * inv).round(),
    w: ((right - left) * inv).round(),
    h: ((bottom - top) * inv).round(),
  );
}

class _CropRect {
  final int x, y, w, h;
  const _CropRect({required this.x, required this.y, required this.w, required this.h});
}
