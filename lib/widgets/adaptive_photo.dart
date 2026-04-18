import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  AdaptivePhoto — Fotoğrafı kendi en-boy oranına göre çerçeveler.
//  • Sabit yükseklik/AspectRatio YOK; görsel TAM görünür (BoxFit.contain).
//  • En fazla ekran yüksekliğinin [maxHeightFactor] katı kadar yer kaplar.
//  • Ham dosya tek sefer decode edilir, en-boy oranı state'te tutulur.
// ═══════════════════════════════════════════════════════════════════════════════

class AdaptivePhoto extends StatefulWidget {
  final String path;
  final double maxHeightFactor;
  final double borderRadius;
  final BoxBorder? border;
  final Color background;
  final Widget? overlay;

  const AdaptivePhoto({
    super.key,
    required this.path,
    this.maxHeightFactor = 0.55,
    this.borderRadius = 14,
    this.border,
    this.background = const Color(0xFFF0F2F5),
    this.overlay,
  });

  @override
  State<AdaptivePhoto> createState() => _AdaptivePhotoState();
}

class _AdaptivePhotoState extends State<AdaptivePhoto> {
  double? _ratio; // width / height

  @override
  void initState() {
    super.initState();
    _loadDimensions();
  }

  @override
  void didUpdateWidget(covariant AdaptivePhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _ratio = null;
      _loadDimensions();
    }
  }

  Future<void> _loadDimensions() async {
    try {
      final file = File(widget.path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      if (!mounted) return;
      setState(() => _ratio = img.width / img.height);
      img.dispose();
    } catch (_) {
      // Dekode edilemezse default 4:3 ile devam et
      if (!mounted) return;
      setState(() => _ratio = 4 / 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * widget.maxHeightFactor;
    // Yükleme esnasında kısa placeholder — layout zıplamasın diye 4:3 başlar
    final ratio = _ratio ?? (4 / 3);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: widget.border,
      ),
      constraints: BoxConstraints(maxHeight: maxH),
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(widget.path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                color: widget.background,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.black26,
                  size: 36,
                ),
              ),
            ),
            if (widget.overlay != null) widget.overlay!,
          ],
        ),
      ),
    );
  }
}
