// ═══════════════════════════════════════════════════════════════════════════
//  ParentActionsPill — Gelişim Paneli'nin sağ üstündeki oval aksiyon grubu
//  (Paylaş ✈️ / Renk Paleti 🎨 / Yardım ?) — ebeveyn alt ekranlarında da aynı
//  işlevle kullanılır:
//    • Paylaş: ekranın görüntüsünü alır, paylaşım sayfasını açar (WhatsApp…).
//    • Palet : sayfa arka plan rengini değiştiren şerit açar (kalıcı,
//              ekran-başına SharedPreferences anahtarı).
//    • ?     : ekrana özel "nasıl çalışır" yardım penceresi.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:math' show pi;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_help_dialog.dart';

/// Ekranın [shotKey] RepaintBoundary görüntüsünü PNG olarak alıp paylaşım
/// sayfasını açar — pill ve hamburger menü ortak kullanır.
Future<void> sharePageShot(
    BuildContext context, GlobalKey shotKey, String shareText) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await Future.delayed(const Duration(milliseconds: 60));
    final boundary =
        shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || boundary.debugNeedsPaint) {
      messenger.showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Ekran henüz hazır değil, tekrar dene.'.tr())));
      return;
    }
    final image = await boundary.toImage(pixelRatio: 2.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      messenger.showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Görüntü oluşturulamadı.'.tr())));
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/qualsar_paylasim_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    await Share.shareXFiles([XFile(file.path)], text: shareText);
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('${'Paylaşım başarısız'.tr()}: $e')));
  }
}

/// AppBar `actions`ına konan oval pill. Ekran tarafında bir [shotKey]
/// (RepaintBoundary anahtarı), palet aç/kapa state'i ve yardım maddeleri
/// verilir.
class ParentActionsPill extends StatelessWidget {
  final GlobalKey shotKey;
  /// Paylaşım metni (ör. "1. Çocuk — Öğretmen Mesajları 📬").
  final String shareText;
  final bool paletteOpen;
  final VoidCallback onPaletteToggle;
  final String helpTitle;
  final List<TeacherHelpItem> helpItems;
  /// Verilirse en başa yeşil ➕ düğmesi eklenir (Gelişim Paneli'ndeki
  /// "çocuk ekle" gibi).
  final VoidCallback? onAdd;
  const ParentActionsPill({
    super.key,
    required this.shotKey,
    required this.shareText,
    required this.paletteOpen,
    required this.onPaletteToggle,
    required this.helpTitle,
    required this.helpItems,
    this.onAdd,
  });

  Future<void> _share(BuildContext context) =>
      sharePageShot(context, shotKey, shareText);

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    Widget btn(Widget icon, String tooltip, VoidCallback onTap) => IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
          icon: icon,
          tooltip: tooltip,
          onPressed: onTap,
        );
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.isDark(context)
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppPalette.border(context)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onAdd != null)
              btn(
                const Icon(Icons.add_circle_rounded,
                    color: Color(0xFF10B981)),
                'Çocuk ekle'.tr(),
                onAdd!,
              ),
            // Paylaş — ekran görüntüsü + paylaşım sayfası.
            btn(
              Transform.rotate(
                angle: -pi / 4,
                child:
                    const Icon(Icons.send_rounded, color: Color(0xFF25D366)),
              ),
              'Paylaş'.tr(),
              () => _share(context),
            ),
            // Renk paleti — gradyan simge; açıkken X.
            btn(
              paletteOpen
                  ? Icon(Icons.close_rounded, color: ink)
                  : ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (r) => const LinearGradient(
                        colors: [
                          Color(0xFFFF6A00),
                          Color(0xFFDB2777),
                          Color(0xFF7C3AED),
                          Color(0xFF2563EB),
                        ],
                      ).createShader(r),
                      child: const Icon(Icons.palette_rounded,
                          color: Colors.white),
                    ),
              'Renk'.tr(),
              onPaletteToggle,
            ),
            // Yardım "?"
            btn(
              Icon(Icons.help_outline_rounded, color: ink),
              'Nasıl çalışır?'.tr(),
              () => showTeacherHelpDialog(context,
                  title: helpTitle, items: helpItems),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sayfa arka plan rengi seçme şeridi — palet açıkken içeriğin üstünde
/// gösterilir. Seçim ekran-başına SharedPreferences'a kalıcı yazılır.
class PageBgPaletteStrip extends StatelessWidget {
  final ValueChanged<Color?> onPick; // null → varsayılana dön
  const PageBgPaletteStrip({super.key, required this.onPick});

  static const _colors = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF0F172A),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            // Varsayılana dön
            GestureDetector(
              onTap: () => onPick(null),
              child: Container(
                width: 34,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppPalette.border(context)),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.refresh_rounded,
                    size: 18, color: AppPalette.textSecondary(context)),
              ),
            ),
            ..._colors.map((c) => GestureDetector(
                  onTap: () => onPick(c),
                  child: Container(
                    width: 34,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.black.withValues(alpha: 0.15)),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Ekran-başına kalıcı sayfa rengi yükle/kaydet yardımcıları.
class PageBgPrefs {
  PageBgPrefs._();

  static Future<Color?> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt('page_bg_$key');
      return v == null ? null : Color(v);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String key, Color? c) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (c == null) {
        await prefs.remove('page_bg_$key');
      } else {
        await prefs.setInt('page_bg_$key', c.toARGB32());
      }
    } catch (_) {}
  }
}
