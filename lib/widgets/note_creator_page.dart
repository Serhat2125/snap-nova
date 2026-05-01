// NoteCreatorPage — Redmi Notes tarzı not editörü.
//
// Özellikler:
// • Başlık + içerik alanları, "Konu Notları" başlık formatı
// • Sağ üstte tema butonu → alt panel: 12+ farklı arka plan (renk + desen);
//   seçili olan glow border ile vurgulanır
// • Alt araç çubuğu BEYAZ zeminli — yazı yazarken görünür:
//     - Default: 🎤 Ses · 🖼️ Galeri · ............ · T (sağda)
//     - T basılınca: H1 (ince) · H2 · H3 · B (kalın) · ✕
// • Ses kaydı: tap to record/stop, dosya kaydedilir, kart olarak gösterilir,
//   tıklayınca oynatılır.
// • Notlar + ses kayıtları + tema topicId bazlı kalıcı.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NoteCreatorPage extends StatefulWidget {
  final String topicId;
  final String topicName;
  const NoteCreatorPage({
    super.key,
    required this.topicId,
    required this.topicName,
  });

  @override
  State<NoteCreatorPage> createState() => _NoteCreatorPageState();
}

class _NoteCreatorPageState extends State<NoteCreatorPage> {
  final TextEditingController _titleCtrl = TextEditingController();
  // Markdown marker'larını (# / ## / ### / **) görsel olarak gizleyen ve
  // stillerini (boyut/kalınlık) uygulayan özel controller.
  final _MarkdownEditingController _bodyCtrl = _MarkdownEditingController();
  final FocusNode _bodyFocus = FocusNode();
  String _toolMode = 'default'; // 'default' | 'text'
  bool _bgPickerOpen = false;
  int _bgIndex = 0;
  /// Palette'ten doğrudan seçilen renk — set edilirse theme.bgColor'u override eder.
  /// `_bgThemes` listesinde olmayan canlı paletteki renkler için kritik.
  int? _customBgColorValue;
  /// Galeri'den eklenen görsellerin path listesi — body üstünde küçük kartlar.
  List<String> _imagePaths = [];

  // ── Audio kayıt + playback ─────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderReady = false;
  bool _recording = false;
  String? _currentRecordPath;
  List<String> _audioPaths = [];
  String? _playingPath;

  String get _bodyKey => 'note_text_${widget.topicId}';
  String get _titleKey => 'note_title_${widget.topicId}';
  String get _bgKey => 'note_bg_${widget.topicId}';
  String get _audioKey => 'note_audio_${widget.topicId}';
  String get _stylesKey => 'note_styles_${widget.topicId}';
  String get _imagesKey => 'note_images_${widget.topicId}';
  String get _bgColorKey => 'note_bg_color_${widget.topicId}';

  @override
  void initState() {
    super.initState();
    _load();
    _initRecorder();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingPath = null);
    });
  }

  Future<void> _initRecorder() async {
    try {
      await _recorder.openRecorder();
      if (mounted) setState(() => _recorderReady = true);
    } catch (e) {
      debugPrint('[NoteCreator] recorder init failed: $e');
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _titleCtrl.text = prefs.getString(_titleKey) ?? '';
    _bodyCtrl.text = prefs.getString(_bodyKey) ?? '';
    _bgIndex = prefs.getInt(_bgKey) ?? 0;
    _customBgColorValue = prefs.getInt(_bgColorKey);
    _audioPaths = prefs.getStringList(_audioKey) ?? [];
    _imagePaths = prefs.getStringList(_imagesKey) ?? [];
    // Karakter stillerini geri yükle (run-length encoded list)
    final stylesRaw = prefs.getString(_stylesKey);
    if (stylesRaw != null && stylesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(stylesRaw) as List;
        final restored = decoded.map((e) => e.toString()).toList();
        _bodyCtrl.setCharStyles(restored);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_titleCtrl.text.trim().isEmpty) {
      await prefs.remove(_titleKey);
    } else {
      await prefs.setString(_titleKey, _titleCtrl.text);
    }
    if (_bodyCtrl.text.trim().isEmpty) {
      await prefs.remove(_bodyKey);
    } else {
      await prefs.setString(_bodyKey, _bodyCtrl.text);
    }
    await prefs.setInt(_bgKey, _bgIndex);
    if (_customBgColorValue == null) {
      await prefs.remove(_bgColorKey);
    } else {
      await prefs.setInt(_bgColorKey, _customBgColorValue!);
    }
    await prefs.setStringList(_audioKey, _audioPaths);
    if (_imagePaths.isEmpty) {
      await prefs.remove(_imagesKey);
    } else {
      await prefs.setStringList(_imagesKey, _imagePaths);
    }
    // Karakter stillerini kaydet (her char için stil — text uzunluğu kadar)
    final styles = _bodyCtrl.charStyles;
    final hasNonNormal = styles.any((s) => s != 'normal');
    if (!hasNonNormal) {
      await prefs.remove(_stylesKey);
    } else {
      await prefs.setString(_stylesKey, jsonEncode(styles));
    }
  }

  @override
  void dispose() {
    _save();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    _player.dispose();
    _recorder.closeRecorder();
    super.dispose();
  }

  // ── Format butonları ──────────────────────────────────────────────────
  // H1/H2/H3 → AKTİF YAZIM stilini değiştirir; sonraki yazılan karakterler
  // bu stilde olur. Eski karakterler değişmez. Aynı butona tekrar bas →
  // normal yazıya döner.
  void _toggleStyle(String key) {
    _bodyCtrl.toggleActiveStyle(key);
  }

  void _wrapBold() {
    final sel = _bodyCtrl.selection;
    final text = _bodyCtrl.text;
    if (sel.isValid && !sel.isCollapsed) {
      final selected = sel.textInside(text);
      final replaced = '**$selected**';
      _bodyCtrl.value = TextEditingValue(
        text: sel.textBefore(text) + replaced + sel.textAfter(text),
        selection: TextSelection.collapsed(
            offset: sel.start + replaced.length),
      );
    } else {
      final pos = sel.start.clamp(0, text.length);
      const marker = '****';
      _bodyCtrl.value = TextEditingValue(
        text: text.substring(0, pos) + marker + text.substring(pos),
        selection: TextSelection.collapsed(offset: pos + 2),
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? f = await picker.pickImage(source: ImageSource.gallery);
      if (f == null) return;
      // FIX: TextField markdown render etmiyor — `![görsel](path)` ham metin
      // olarak gözüküyordu. Artık görseli ses kartları gibi ayrı bir
      // yatay sıraya ekliyoruz (body üstünde, gerçek Image.file render).
      setState(() {
        _imagePaths.add(f.path);
      });
      await _save();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Görsel eklenemedi: $e')),
        );
      }
    }
  }

  Future<void> _deleteImage(String path) async {
    setState(() => _imagePaths.remove(path));
    await _save();
  }

  // ── Ses kaydı ─────────────────────────────────────────────────────────
  Future<void> _toggleRecord() async {
    if (!_recorderReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kayıt cihazı hazırlanıyor…')),
      );
      return;
    }
    if (_recording) {
      await _stopRecord();
    } else {
      await _startRecord();
    }
  }

  Future<void> _startRecord() async {
    // Mikrofon izni
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon izni reddedildi.')),
        );
      }
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fname =
          'note_${widget.topicId}_${DateTime.now().millisecondsSinceEpoch}.aac';
      _currentRecordPath = '${dir.path}/$fname';
      await _recorder.startRecorder(
        toFile: _currentRecordPath,
        codec: Codec.aacADTS,
      );
      if (mounted) setState(() => _recording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt başlatılamadı: $e')),
        );
      }
    }
  }

  Future<void> _stopRecord() async {
    try {
      final path = await _recorder.stopRecorder();
      final filePath = path ?? _currentRecordPath;
      if (filePath != null && await File(filePath).exists()) {
        setState(() {
          _audioPaths.add(filePath);
          _recording = false;
          _currentRecordPath = null;
        });
        await _save();
      } else {
        setState(() => _recording = false);
      }
    } catch (e) {
      setState(() => _recording = false);
    }
  }

  Future<void> _playPause(String path) async {
    if (_playingPath == path) {
      await _player.stop();
      setState(() => _playingPath = null);
    } else {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      setState(() => _playingPath = path);
    }
  }

  Future<void> _deleteAudio(String path) async {
    setState(() {
      _audioPaths.remove(path);
      if (_playingPath == path) _playingPath = null;
    });
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = _bgThemes[_bgIndex];
    // Eğer paletten doğrudan renk seçilmişse onu kullan; aksi halde theme.
    final theme = _customBgColorValue != null
        ? () {
            final c = Color(_customBgColorValue!);
            final l = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
            final dark = l < 0.55;
            return _BgTheme(
              bgColor: c,
              fgColor: dark ? Colors.white : Colors.black,
              pattern: null,
            );
          }()
        : baseTheme;
    return Scaffold(
      backgroundColor: theme.bgColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: theme.bgColor,
        elevation: 0,
        foregroundColor: theme.fgColor,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.topicName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: theme.fgColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Notları',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: theme.fgColor.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        actions: [
          // Tema butonu alt toolbar'a (galerinin sağına) taşındı.
          IconButton(
            icon: Icon(Icons.check_rounded, color: theme.fgColor),
            tooltip: 'Kaydet',
            onPressed: () async {
              await _save();
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (theme.pattern != null)
            Positioned.fill(child: CustomPaint(painter: theme.pattern)),
          Column(
            children: [
              // Başlık alanı kaldırıldı — AppBar'da zaten "${topic} Notları"
              // gözüküyor; ikinci satır başlık kafa karıştırıyordu.
              const SizedBox(height: 8),
              // Ses kayıtları (varsa)
              if (_audioPaths.isNotEmpty)
                _AudioCardsRow(
                  paths: _audioPaths,
                  playing: _playingPath,
                  onPlayPause: _playPause,
                  onDelete: _deleteAudio,
                  fg: theme.fgColor,
                ),
              // Galeri görselleri (varsa) — body üstünde küçük thumbnail kartlar.
              if (_imagePaths.isNotEmpty)
                _ImageCardsRow(
                  paths: _imagePaths,
                  onDelete: _deleteImage,
                ),
              // Body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _bodyCtrl,
                    focusNode: _bodyFocus,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      height: 1.55,
                      color: theme.fgColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Notlarını buraya yaz…',
                      hintStyle: GoogleFonts.poppins(
                        fontSize: 14.5,
                        color: theme.fgColor.withValues(alpha: 0.30),
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              // Alt toolbar — BEYAZ zemin
              _BottomToolbar(
                mode: _toolMode,
                recording: _recording,
                onMic: _toggleRecord,
                onPhoto: _pickImage,
                onColorTheme: () =>
                    setState(() => _bgPickerOpen = !_bgPickerOpen),
                onTextMode: () => setState(() => _toolMode = 'text'),
                onH1: () {
                  _toggleStyle('h1');
                  _bodyFocus.requestFocus();
                },
                onH2: () {
                  _toggleStyle('h2');
                  _bodyFocus.requestFocus();
                },
                onH3: () {
                  _toggleStyle('h3');
                  _bodyFocus.requestFocus();
                },
                onBold: () {
                  _wrapBold();
                  _bodyFocus.requestFocus();
                },
                onCloseTextMode: () =>
                    setState(() => _toolMode = 'default'),
              ),
            ],
          ),
          if (_bgPickerOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BgPicker(
                themes: _bgThemes,
                selected: _bgIndex,
                customColorValue: _customBgColorValue,
                onSelect: (i) async {
                  // _bgThemes index'i geldi → custom rengi temizle.
                  setState(() {
                    _bgIndex = i;
                    _customBgColorValue = null;
                  });
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt(_bgKey, i);
                  await prefs.remove(_bgColorKey);
                },
                onSelectColor: (c) async {
                  // Paletten doğrudan renk seçildi → ARGB int sakla.
                  final v = ((c.a * 255).round() << 24) |
                      ((c.r * 255).round() << 16) |
                      ((c.g * 255).round() << 8) |
                      ((c.b * 255).round());
                  setState(() => _customBgColorValue = v);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt(_bgColorKey, v);
                },
                onClose: () => setState(() => _bgPickerOpen = false),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Alt toolbar — beyaz zemin
// ═════════════════════════════════════════════════════════════════════════
class _BottomToolbar extends StatelessWidget {
  final String mode;
  final bool recording;
  final VoidCallback onMic;
  final VoidCallback onPhoto;
  final VoidCallback onColorTheme;
  final VoidCallback onTextMode;
  final VoidCallback onH1;
  final VoidCallback onH2;
  final VoidCallback onH3;
  final VoidCallback onBold;
  final VoidCallback onCloseTextMode;

  const _BottomToolbar({
    required this.mode,
    required this.recording,
    required this.onMic,
    required this.onPhoto,
    required this.onColorTheme,
    required this.onTextMode,
    required this.onH1,
    required this.onH2,
    required this.onH3,
    required this.onBold,
    required this.onCloseTextMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom * 0.5),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: mode == 'default'
            ? Row(
                key: const ValueKey('default'),
                children: [
                  _Bbtn(
                    icon: recording
                        ? Icons.stop_circle_rounded
                        : Icons.mic_rounded,
                    label: recording ? 'Kayıt…' : 'Ses',
                    onTap: onMic,
                    color: recording
                        ? const Color(0xFFEF4444)
                        : const Color(0xFFEF4444),
                    pulse: recording,
                  ),
                  const SizedBox(width: 6),
                  _Bbtn(
                    icon: Icons.image_rounded,
                    label: 'Galeri',
                    onTap: onPhoto,
                    color: const Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 6),
                  // Tema butonu — galerinin sağında, basınca alt panel açılır.
                  _Bbtn(
                    icon: Icons.palette_rounded,
                    label: 'Renk',
                    onTap: onColorTheme,
                    color: const Color(0xFFA855F7),
                  ),
                  const Spacer(),
                  _TButton(onTap: onTextMode),
                ],
              )
            : Row(
                key: const ValueKey('text'),
                children: [
                  _Hbtn(label: 'H1', size: 12, weight: FontWeight.w400, onTap: onH1),
                  _Hbtn(label: 'H2', size: 14, weight: FontWeight.w600, onTap: onH2),
                  _Hbtn(label: 'H3', size: 16, weight: FontWeight.w800, onTap: onH3),
                  _Hbtn(label: 'B', size: 18, weight: FontWeight.w900, onTap: onBold),
                  const Spacer(),
                  _Bbtn(
                    icon: Icons.close_rounded,
                    label: 'Kapat',
                    onTap: onCloseTextMode,
                    color: Colors.black54,
                  ),
                ],
              ),
      ),
    );
  }
}

class _Bbtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool pulse;
  const _Bbtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: pulse
              ? color.withValues(alpha: 0.18)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: color.withValues(alpha: pulse ? 0.55 : 0.30),
              width: pulse ? 1.6 : 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

/// "T" butonu — sadece harf, label yok
class _TButton extends StatelessWidget {
  final VoidCallback onTap;
  const _TButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black26),
        ),
        alignment: Alignment.center,
        child: Text('T',
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.black87)),
      ),
    );
  }
}

class _Hbtn extends StatelessWidget {
  final String label;
  final double size;
  final FontWeight weight;
  final VoidCallback onTap;
  const _Hbtn({
    required this.label,
    required this.size,
    required this.weight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black26),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: size,
            fontWeight: weight,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Ses kart sırası (varsa body üstünde gösterilir)
// ═════════════════════════════════════════════════════════════════════════
class _AudioCardsRow extends StatelessWidget {
  final List<String> paths;
  final String? playing;
  final void Function(String) onPlayPause;
  final void Function(String) onDelete;
  final Color fg;
  const _AudioCardsRow({
    required this.paths,
    required this.playing,
    required this.onPlayPause,
    required this.onDelete,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = paths[i];
          final isPlaying = p == playing;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.40)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => onPlayPause(p),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Ses ${i + 1}',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFEF4444)),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => onDelete(p),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: fg.withValues(alpha: 0.55)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Image cards row — galeri'den eklenen görseller, body üstünde thumbnail
// ═════════════════════════════════════════════════════════════════════════
class _ImageCardsRow extends StatelessWidget {
  final List<String> paths;
  final void Function(String) onDelete;
  const _ImageCardsRow({required this.paths, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = paths[i];
          return GestureDetector(
            onTap: () => _showFullImage(context, p),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(p),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 80,
                      height: 80,
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_rounded,
                          color: Colors.black38),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => onDelete(p),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showFullImage(BuildContext ctx, String path) {
    showDialog<void>(
      context: ctx,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          child: Image.file(File(path)),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Bg picker — 2 satır: üstte yatay renkler, altta desenli çerçeveler
// ═════════════════════════════════════════════════════════════════════════
class _BgPicker extends StatelessWidget {
  final List<_BgTheme> themes;
  final int selected;
  /// Paletten seçilmiş custom renk (ARGB int) — selected ring için kontrol.
  final int? customColorValue;
  /// Theme dönüştürmeden, doğrudan paletteki rengi parent'a iletir.
  final ValueChanged<Color> onSelectColor;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  const _BgPicker({
    required this.themes,
    required this.selected,
    required this.customColorValue,
    required this.onSelectColor,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // Konu özetlerindeki çoklu vurgulayıcıyla AYNI 16 temel renk.
    // Ayırt edilebilir, canlı, doygun palet.
    const palette = <Color>[
      Color(0xFFFFEB3B), // sarı
      Color(0xFFFFC107), // amber
      Color(0xFFFF9800), // turuncu
      Color(0xFFFF5722), // koyu turuncu
      Color(0xFFEF4444), // kırmızı
      Color(0xFFEC4899), // pembe
      Color(0xFFA855F7), // mor
      Color(0xFF7C3AED), // koyu mor
      Color(0xFF3B82F6), // mavi
      Color(0xFF06B6D4), // cam göbeği
      Color(0xFF14B8A6), // turkuaz
      Color(0xFF22C55E), // yeşil
      Color(0xFF84CC16), // lime
      Color(0xFFEAB308), // hardal
      Color(0xFF78716C), // gri
      Color(0xFF000000), // siyah
    ];
    final swatches = palette
        .map((c) => _Swatch(
              themeIdx: null,
              bg: c,
              fg: _isDark(c) ? Colors.white : Colors.black,
            ))
        .toList();
    // Her swatch'ı themes listesine "en yakın" eşleştir — render için lazım.
    // Pratikte themes listesi boş bg'ler içeriyor; eşleşme zor olunca
    // sadece ilk theme'i kullan + custom override (selected==null gibi).
    final firstRow = swatches.take(8).toList();
    final secondRow = swatches.skip(8).take(8).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xF0111122),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Renk',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 2 satır × 8 yuvarlak
          _swatchRow(firstRow),
          const SizedBox(height: 10),
          _swatchRow(secondRow),
        ],
      ),
    );
  }

  Widget _swatchRow(List<_Swatch> row) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final s in row) ...[
          () {
            // Bu swatch'ın renk değeri (ARGB int) — customColorValue ile karşılaştırma için.
            final c = s.bg;
            final swatchVal = ((c.a * 255).round() << 24) |
                ((c.r * 255).round() << 16) |
                ((c.g * 255).round() << 8) |
                ((c.b * 255).round());
            final isActive = customColorValue == swatchVal;
            return GestureDetector(
              // FIX: tüm swatch'lar (themeIdx null olanlar bile) doğrudan
              // renk değerini parent'a yollar. Önceden "en yakın theme'i bul"
              // yapıyorduk → yanlış renk uygulanıyordu.
              onTap: () => onSelectColor(s.bg),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.bg,
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFFFFB800)
                        : Colors.white.withValues(alpha: 0.30),
                    width: isActive ? 2.5 : 1.2,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFFB800)
                                .withValues(alpha: 0.55),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }(),
        ],
      ],
    );
  }

  bool _isDark(Color c) {
    final l = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
    return l < 0.55;
  }
}

class _Swatch {
  final int? themeIdx;
  final Color bg;
  final Color fg;
  const _Swatch({required this.themeIdx, required this.bg, required this.fg});
}

// ═════════════════════════════════════════════════════════════════════════
//  Tema modeli + 12 tema (klasik + futüristik + çiçekli + modern)
// ═════════════════════════════════════════════════════════════════════════
class _BgTheme {
  final Color bgColor;
  final Color fgColor;
  final CustomPainter? pattern;
  const _BgTheme({
    required this.bgColor,
    required this.fgColor,
    this.pattern,
  });
}

final List<_BgTheme> _bgThemes = [
  // Klasik renkler
  const _BgTheme(bgColor: Colors.white, fgColor: Colors.black),
  const _BgTheme(bgColor: Color(0xFFFEF3C7), fgColor: Color(0xFF422006)), // krem
  const _BgTheme(bgColor: Color(0xFFE0F2FE), fgColor: Color(0xFF082F49)), // sky
  const _BgTheme(bgColor: Color(0xFFFCE7F3), fgColor: Color(0xFF500724)), // pink
  const _BgTheme(bgColor: Color(0xFFDCFCE7), fgColor: Color(0xFF14532D)), // green
  const _BgTheme(
      bgColor: Color(0xFF0F172A), fgColor: Color(0xFFE2E8F0)), // dark
  // Klasik desenler
  _BgTheme(
    bgColor: Colors.white,
    fgColor: const Color(0xFF1F2937),
    pattern: _LinedPaperPainter(),
  ),
  _BgTheme(
    bgColor: const Color(0xFFFFFAF0),
    fgColor: const Color(0xFF422006),
    pattern: _DotPaperPainter(),
  ),
  _BgTheme(
    bgColor: Colors.white,
    fgColor: const Color(0xFF1F2937),
    pattern: _GridPaperPainter(),
  ),
  // Çiçekli (modern/whimsical)
  _BgTheme(
    bgColor: const Color(0xFFFFF5F7),
    fgColor: const Color(0xFF500724),
    pattern: _FlowerPainter(),
  ),
  // Futüristik / cyber
  _BgTheme(
    bgColor: const Color(0xFF0A0E27),
    fgColor: const Color(0xFFE0E7FF),
    pattern: _CyberGridPainter(),
  ),
  // Dalga / abstract modern
  _BgTheme(
    bgColor: const Color(0xFFEFF6FF),
    fgColor: const Color(0xFF0C4A6E),
    pattern: _WavePainter(),
  ),
];

// ─── Çizgili kağıt ──────────────────────────────────────────────────────
class _LinedPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF93C5FD).withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    const sp = 28.0;
    for (double y = 80; y < size.height; y += sp) {
      canvas.drawLine(Offset(20, y), Offset(size.width - 20, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _DotPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFD4A373).withValues(alpha: 0.40);
    const sp = 22.0;
    for (double y = sp; y < size.height; y += sp) {
      for (double x = sp; x < size.width; x += sp) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _GridPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC7D2FE).withValues(alpha: 0.55)
      ..strokeWidth = 0.6;
    const sp = 24.0;
    for (double x = sp; x < size.width; x += sp) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = sp; y < size.height; y += sp) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Çiçekli desen — small repeating flowers ────────────────────────────
class _FlowerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final petalPaint = Paint()
      ..color = const Color(0xFFEC4899).withValues(alpha: 0.18);
    final centerPaint = Paint()
      ..color = const Color(0xFFFBBF24).withValues(alpha: 0.40);
    const sp = 60.0;
    for (double y = 30; y < size.height; y += sp) {
      for (double x = 30; x < size.width; x += sp) {
        // 6 petals
        for (int i = 0; i < 6; i++) {
          final angle = (i * math.pi * 2) / 6;
          final px = x + math.cos(angle) * 7;
          final py = y + math.sin(angle) * 7;
          canvas.drawCircle(Offset(px, py), 5, petalPaint);
        }
        canvas.drawCircle(Offset(x, y), 3, centerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Cyber grid (futüristik) ─────────────────────────────────────────────
class _CyberGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF22D3EE).withValues(alpha: 0.18)
      ..strokeWidth = 0.7;
    final glowPaint = Paint()
      ..color = const Color(0xFF8B5CF6).withValues(alpha: 0.10)
      ..strokeWidth = 1.2;
    const sp = 36.0;
    // İnce grid
    for (double x = 0; x < size.width; x += sp) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += sp) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Vurgu hatları (perspektif benzeri)
    for (double y = sp * 4; y < size.height; y += sp * 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), glowPaint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Dalga deseni — modern abstract ──────────────────────────────────────
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.20)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const sp = 40.0;
    for (double baseY = 20; baseY < size.height; baseY += sp) {
      final path = Path()..moveTo(0, baseY);
      for (double x = 0; x < size.width; x += 4) {
        final y = baseY + math.sin(x / 18) * 6;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// Suppress unused warnings for pre-imported deps
// ignore: unused_element
final _ = SystemChrome.setPreferredOrientations;

// ═══════════════════════════════════════════════════════════════════════════════
//  Per-karakter stil controller — H1/H2/H3'e basıldıktan SONRA yazılan
//  karakterler o stilde olur; eski karakterler değişmez. H butonuna tekrar
//  basılırsa stil normale döner. Bold için `**...**` markdown korunur.
// ═══════════════════════════════════════════════════════════════════════════════
class _MarkdownEditingController extends TextEditingController {
  static final _boldRe = RegExp(r'\*\*([^*\n]*?)\*\*');

  /// Karakter başına stil — `_charStyles.length == text.length` olmalı.
  /// Değerler: 'normal' | 'h1' | 'h2' | 'h3'.
  final List<String> _charStyles = [];
  String _activeStyle = 'normal';
  String _prevText = '';

  /// Aktif yazım stili — H butonuna basıldığında değişir.
  String get activeStyle => _activeStyle;

  _MarkdownEditingController() {
    addListener(_onTextChange);
  }

  /// H1/H2/H3 toggle — aynı stile basılırsa normale döner.
  void toggleActiveStyle(String key) {
    _activeStyle = (_activeStyle == key) ? 'normal' : key;
    notifyListeners();
  }

  /// Toplu yükleme — persist'ten geri restore.
  void setCharStyles(List<String> styles) {
    _charStyles
      ..clear()
      ..addAll(styles);
    // Length mismatch'i düzelt
    while (_charStyles.length < text.length) {
      _charStyles.add('normal');
    }
    while (_charStyles.length > text.length) {
      _charStyles.removeLast();
    }
    _prevText = text;
    notifyListeners();
  }

  List<String> get charStyles => List.unmodifiable(_charStyles);

  /// Text değişimini takip et — eklenen char'lara active stili uygula,
  /// silinenler için listeden çıkar.
  void _onTextChange() {
    final newText = text;
    if (newText == _prevText) return;
    // Ortak prefix/suffix hesapla → diff
    int p = 0;
    while (p < _prevText.length &&
        p < newText.length &&
        _prevText[p] == newText[p]) {
      p++;
    }
    int sOld = _prevText.length;
    int sNew = newText.length;
    while (sOld > p && sNew > p && _prevText[sOld - 1] == newText[sNew - 1]) {
      sOld--;
      sNew--;
    }
    final deletedLen = sOld - p;
    final insertedLen = sNew - p;
    // _charStyles'i güncelle
    if (deletedLen > 0) {
      // p..p+deletedLen aralığını sil
      _charStyles.removeRange(
          p.clamp(0, _charStyles.length),
          (p + deletedLen).clamp(0, _charStyles.length));
    }
    if (insertedLen > 0) {
      _charStyles.insertAll(
        p.clamp(0, _charStyles.length),
        List.filled(insertedLen, _activeStyle),
      );
    }
    // Length mismatch düzelt
    while (_charStyles.length < newText.length) {
      _charStyles.add('normal');
    }
    while (_charStyles.length > newText.length) {
      _charStyles.removeLast();
    }
    _prevText = newText;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final baseFs = base.fontSize ?? 15;
    final hidden = base.copyWith(
      color: const Color(0x00000000),
      fontSize: 0.01,
    );
    TextStyle styleFor(String key) {
      switch (key) {
        case 'h3':
          return base.copyWith(
              fontSize: baseFs * 1.55, fontWeight: FontWeight.w900);
        case 'h2':
          return base.copyWith(
              fontSize: baseFs * 1.30, fontWeight: FontWeight.w800);
        case 'h1':
          return base.copyWith(
              fontSize: baseFs * 1.10, fontWeight: FontWeight.w600);
        default:
          return base;
      }
    }

    // Length mismatch düzelt (ilk frame'lerde olabilir)
    while (_charStyles.length < text.length) {
      _charStyles.add('normal');
    }

    final spans = <InlineSpan>[];
    // Önce bold marker'larını işaretle (görünmez yapılacak char indeksleri).
    final hiddenIdx = <int>{};
    final boldRanges = <List<int>>[]; // [start, end] (içerik aralığı)
    for (final m in _boldRe.allMatches(text)) {
      // ** açılış: start..start+2
      hiddenIdx.add(m.start);
      hiddenIdx.add(m.start + 1);
      // ** kapanış: end-2..end
      hiddenIdx.add(m.end - 2);
      hiddenIdx.add(m.end - 1);
      boldRanges.add([m.start + 2, m.end - 2]);
    }
    bool isBoldAt(int i) {
      for (final r in boldRanges) {
        if (i >= r[0] && i < r[1]) return true;
      }
      return false;
    }

    // Ardışık aynı-stil karakterleri TextSpan'a grupla.
    int i = 0;
    while (i < text.length) {
      final isHidden = hiddenIdx.contains(i);
      final isBold = isBoldAt(i);
      final keyHere = _charStyles[i];
      int end = i + 1;
      while (end < text.length &&
          !isHidden == !hiddenIdx.contains(end) &&
          isBold == isBoldAt(end) &&
          _charStyles[end] == keyHere) {
        end++;
      }
      final segment = text.substring(i, end);
      var st = styleFor(keyHere);
      if (isBold) st = st.copyWith(fontWeight: FontWeight.w900);
      spans.add(TextSpan(
        text: segment,
        style: isHidden ? hidden : st,
      ));
      i = end;
    }
    return TextSpan(children: spans, style: base);
  }
}
