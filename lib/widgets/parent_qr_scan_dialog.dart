// ═══════════════════════════════════════════════════════════════════════════
//  ParentQrScanDialog — Velinin, çocuğun ekranındaki bağlantı QR'ını okutması.
//
//  Çocuk Profil → "Veliyi Bağla" ekranında https://qualsar.app/veli/EBEV-XXXXXX
//  içerikli bir QR gösterir. Bu dialog QR'ı okur, kodu çıkarır ve
//  Navigator.pop(code) ile çağırana teslim eder — bağlama işlemini çağıran
//  yapar (ParentLinkService.linkByCode). Ham "EBEV-XXXXXX" içerikli QR da
//  kabul edilir.
//
//  Kullanım: final code = await showParentQrScanner(context);
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/parent_link_service.dart';
import '../services/runtime_translator.dart';

/// QR tarayıcıyı açar; okunan geçerli `EBEV-XXXXXX` kodunu döndürür,
/// kullanıcı kapatırsa null.
Future<String?> showParentQrScanner(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const ParentQrScanDialog(),
  );
}

class ParentQrScanDialog extends StatefulWidget {
  const ParentQrScanDialog({super.key});

  @override
  State<ParentQrScanDialog> createState() => _ParentQrScanDialogState();
}

class _ParentQrScanDialogState extends State<ParentQrScanDialog> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  bool _processed = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// QR içeriğinden kodu çıkarır: ham "EBEV-XXXXXX" ya da
  /// https://qualsar.app/veli/{kod} linki. Tanınmazsa null.
  String? _extractCode(String raw) {
    final direct = ParentLinkService.normalizeCode(raw);
    if (direct != null) return direct;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    for (int i = 0; i < segs.length - 1; i++) {
      if (segs[i].toLowerCase() == 'veli') {
        return ParentLinkService.normalizeCode(segs[i + 1]);
      }
    }
    return null;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processed) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    final code = _extractCode(raw);
    if (code == null) {
      setState(() => _error =
          'Bu QR tanınmadı — çocuğunun ekranındaki QuAlsar QR kodunu okut.');
      return;
    }
    _processed = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('📷', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('QR Kodu Okut'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
                IconButton(
                  onPressed: () => _controller.toggleTorch(),
                  icon: const Icon(Icons.flash_on_rounded,
                      color: Colors.white, size: 22),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (ctx, err, _) {
                    return Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '${'Kamera açılamadı:'.tr()} ${err.errorCode.name}\n${'İzin verdiğinden emin ol.'.tr()}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.white),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _error ??
                  'Telefonu, çocuğunun ekranındaki QR koda doğrult — otomatik okunur.'
                      .tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: _error != null
                      ? const Color(0xFFFF6A00)
                      : Colors.white.withValues(alpha: 0.75)),
            ),
          ],
        ),
      ),
    );
  }
}
