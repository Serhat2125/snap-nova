// ═══════════════════════════════════════════════════════════════════════════
//  ClassAvatar + showClassProfileDialog — Sınıf profil fotoğrafı ve durum
//  mesajı. Öğretmen sınıf kartındaki avatara basınca ortada küçük bir çerçeve
//  açılır; fotoğraf yükler (galeri → 160x160 thumbnail → base64) ve durum
//  mesajı yazar. Firebase Storage YOK — thumbnail base64 Firestore class
//  dokümanına yazılır (~10KB), profil avatarı deseniyle aynı.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const _kBrand = Color(0xFF7C3AED);

/// base64 (veya data URL) string'ten ham byte çıkarır. Geçersizse null.
Uint8List? _decodePhoto(String photoB64) {
  final v = photoB64.trim();
  if (v.isEmpty) return null;
  try {
    final raw = v.contains(',') ? v.substring(v.indexOf(',') + 1) : v;
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

/// Sınıf avatarı — fotoğraf varsa onu, yoksa varsayılan sınıf ikonunu gösterir.
class ClassAvatar extends StatelessWidget {
  final String photoB64;
  final double size;
  const ClassAvatar({super.key, required this.photoB64, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final bytes = _decodePhoto(photoB64);
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.27),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.27),
          color: _kBrand.withValues(alpha: 0.12),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.class_rounded, color: _kBrand, size: size * 0.5),
      );
}

/// Sınıf profil çerçevesini açar (fotoğraf yükle + durum mesajı).
Future<void> showClassProfileDialog(
    BuildContext context, TeacherClass cls) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ClassProfileDialog(cls: cls),
  );
}

class _ClassProfileDialog extends StatefulWidget {
  final TeacherClass cls;
  const _ClassProfileDialog({required this.cls});

  @override
  State<_ClassProfileDialog> createState() => _ClassProfileDialogState();
}

class _ClassProfileDialogState extends State<_ClassProfileDialog> {
  late final TextEditingController _status;
  late String _photoB64;
  bool _picking = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _photoB64 = widget.cls.photoB64;
    _status = TextEditingController(text: widget.cls.statusMessage);
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_picking) return;
    setState(() => _picking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 85,
      );
      if (picked == null) {
        if (mounted) setState(() => _picking = false);
        return;
      }
      final bytes = await File(picked.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('decode null');
      final thumb = img.copyResize(decoded,
          width: 160, height: 160, interpolation: img.Interpolation.average);
      final jpeg = img.encodeJpg(thumb, quality: 70);
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
      // Firestore doc 1MB limitini koru — küçük tut.
      if (dataUrl.length > 40 * 1024) {
        messenger.showSnackBar(SnackBar(
            content: Text('Fotoğraf çok büyük, daha küçük bir görsel seç'.tr())));
        if (mounted) setState(() => _picking = false);
        return;
      }
      if (mounted) {
        setState(() {
          _photoB64 = dataUrl;
          _picking = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _picking = false);
      messenger.showSnackBar(
          SnackBar(content: Text('Fotoğraf yüklenemedi, tekrar dene'.tr())));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ClassService.updateClassProfile(
      widget.cls.id,
      photoB64: _photoB64,
      statusMessage: _status.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(
          ok ? 'Sınıf profili güncellendi'.tr() : 'Güncellenemedi, tekrar dene'.tr()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Dialog(
      backgroundColor: AppPalette.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.cls.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900, color: ink,
                )),
            const SizedBox(height: 16),
            // ── Avatar + fotoğraf yükleme rozeti ──────────────────────
            GestureDetector(
              onTap: _picking ? null : _pickPhoto,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClassAvatar(photoB64: _photoB64, size: 96),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: _kBrand, shape: BoxShape.circle,
                    ),
                    child: _picking
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.photo_camera_rounded,
                            color: Colors.white, size: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _picking ? null : _pickPhoto,
              icon: const Icon(Icons.upload_rounded, size: 16),
              style: TextButton.styleFrom(foregroundColor: _kBrand),
              label: Text('Fotoğraf Yükle'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _status,
              maxLength: 120,
              maxLines: 2,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.poppins(fontSize: 13.5, color: ink),
              decoration: InputDecoration(
                hintText: 'Durum mesajı (örn. Bu hafta deneme sınavı var)'.tr(),
                hintStyle: GoogleFonts.poppins(
                    fontSize: 13, color: muted.withValues(alpha: 0.7)),
                counterText: '',
                filled: true,
                fillColor: AppPalette.bg(context),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppPalette.border(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppPalette.border(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kBrand, width: 1.6),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Vazgeç'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrand,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text('Kaydet'.tr(),
                            style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
