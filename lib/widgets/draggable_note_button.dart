// DraggableNoteButton — özet sayfasında üst katman (overlay) olarak yüzen,
// her yere sürüklenebilen sticky-note butonu. Tıklayınca bottom sheet açılır;
// kullanıcı serbest not yazar; topicId bazlı SharedPreferences'a kaydedilir;
// sayfa tekrar açıldığında not otomatik yüklenir.
//
// Kullanım:
//   Stack(children: [
//     YourPageContent(...),
//     DraggableNoteOverlay(topicId: 'atom_yapısı', topicName: 'Atom ve Yapısı'),
//   ])

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notu aç/düzenle bottom sheet'i — hem floating button hem toolbar tarafından
/// kullanılır. Tek kaynak / single source of truth.
Future<void> openTopicNoteSheet({
  required BuildContext context,
  required String topicId,
  required String topicName,
  Color color = const Color(0xFFFFB800),
}) async {
  final prefs = await SharedPreferences.getInstance();
  final initial = prefs.getString('note_text_$topicId') ?? '';
  if (!context.mounted) return;
  final ctrl = TextEditingController(text: initial);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.sticky_note_2_rounded,
                        color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('$topicName Notları',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: GoogleFonts.poppins(
                      fontSize: 14.5, height: 1.55, color: Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Bu konu için kişisel notlarını buraya yaz…',
                    hintStyle: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.black38),
                    filled: true,
                    fillColor: const Color(0xFFFFFBEA),
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: color.withValues(alpha: 0.4), width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: color, width: 1.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => ctrl.clear(),
                    icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                    label: const Text('Temizle'),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.black54),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (ctrl.text.trim().isEmpty) {
                        await prefs.remove('note_text_$topicId');
                      } else {
                        await prefs.setString(
                            'note_text_$topicId', ctrl.text);
                      }
                      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Kaydet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  ctrl.dispose();
}

class DraggableNoteOverlay extends StatefulWidget {
  /// Notun saklandığı benzersiz anahtar — aynı konu farklı sayfalarda
  /// açılsa bile aynı id verilirse tek not paylaşılır.
  final String topicId;

  /// Bottom sheet başlığında kullanılır: "$topicName Notları".
  final String topicName;

  /// Buton zemini (default: amber). Renk teması ekrana uyumlu olmasın diye
  /// dış parametre.
  final Color color;

  const DraggableNoteOverlay({
    super.key,
    required this.topicId,
    required this.topicName,
    this.color = const Color(0xFFFFB800),
  });

  @override
  State<DraggableNoteOverlay> createState() => _DraggableNoteOverlayState();
}

class _DraggableNoteOverlayState extends State<DraggableNoteOverlay> {
  static const _btnSize = 56.0;
  // Pref keys
  String get _posKey => 'note_fab_pos_${widget.topicId}';
  String get _textKey => 'note_text_${widget.topicId}';

  Offset? _pos; // null → ilk frame'de default'a yerleş
  bool _hasNote = false;
  bool _saved = false; // ilk yükleme bitti mi

  @override
  void initState() {
    super.initState();
    _loadPosAndNote();
  }

  Future<void> _loadPosAndNote() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble('${_posKey}_dx');
    final dy = prefs.getDouble('${_posKey}_dy');
    final txt = prefs.getString(_textKey) ?? '';
    if (!mounted) return;
    setState(() {
      if (dx != null && dy != null) _pos = Offset(dx, dy);
      _hasNote = txt.trim().isNotEmpty;
      _saved = true;
    });
  }

  Future<void> _persistPos(Offset p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_posKey}_dx', p.dx);
    await prefs.setDouble('${_posKey}_dy', p.dy);
  }

  Future<String> _loadText() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_textKey) ?? '';
  }

  Future<void> _saveText(String text) async {
    final prefs = await SharedPreferences.getInstance();
    if (text.trim().isEmpty) {
      await prefs.remove(_textKey);
    } else {
      await prefs.setString(_textKey, text);
    }
    if (!mounted) return;
    setState(() => _hasNote = text.trim().isNotEmpty);
  }

  Future<void> _openSheet(BuildContext ctx) async {
    final initial = await _loadText();
    if (!mounted) return;
    final ctrl = TextEditingController(text: initial);
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true, // resizeToAvoidBottomInset analogu
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                // Başlık + kapat
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.sticky_note_2_rounded,
                          color: widget.color, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${widget.topicName} Notları',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Notes alanı — geniş + okunaklı
                Flexible(
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      height: 1.55,
                      color: Colors.black,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Bu konu için kişisel notlarını buraya yaz…',
                      hintStyle: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.black38,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFFFFBEA),
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: widget.color.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: widget.color,
                          width: 1.6,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Aksiyon butonları: temizle + kaydet
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        ctrl.clear();
                      },
                      icon: const Icon(Icons.cleaning_services_rounded,
                          size: 16),
                      label: const Text('Temizle'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black54,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _saveText(ctrl.text);
                        if (sheetCtx.mounted) {
                          Navigator.of(sheetCtx).pop();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ctrl.text.trim().isEmpty
                                  ? 'Not silindi'
                                  : 'Not kaydedildi'),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Kaydet'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_saved) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (ctx, cons) {
        // Default konum: sağ alt (margin ile).
        final pos = _pos ??
            Offset(
              cons.maxWidth - _btnSize - 16,
              cons.maxHeight - _btnSize - 100, // Test FAB üstünde
            );
        return Stack(
          children: [
            Positioned(
              left: pos.dx,
              top: pos.dy,
              child: GestureDetector(
                onTap: () => _openSheet(context),
                onPanUpdate: (d) {
                  setState(() {
                    final nx = (pos.dx + d.delta.dx)
                        .clamp(0.0, cons.maxWidth - _btnSize);
                    final ny = (pos.dy + d.delta.dy)
                        .clamp(0.0, cons.maxHeight - _btnSize);
                    _pos = Offset(nx, ny);
                  });
                },
                onPanEnd: (_) {
                  if (_pos != null) _persistPos(_pos!);
                },
                child: _NoteFab(color: widget.color, hasNote: _hasNote),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NoteFab extends StatelessWidget {
  final Color color;
  final bool hasNote;
  const _NoteFab({required this.color, required this.hasNote});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            color,
            color.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.40),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.sticky_note_2_rounded,
              color: Colors.white, size: 26),
          if (hasNote)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
