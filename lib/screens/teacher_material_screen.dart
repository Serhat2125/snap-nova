// ═══════════════════════════════════════════════════════════════════════════
//  TeacherMaterialScreen — Öğretmenin sınıfa YAPAY ZEKA DIŞI hazır kaynak
//  paylaşması: web linki, PDF linki veya ders notu.
//
//  Sınıf içerik akışına 'material' tipinde yazılır; öğrenci/sınıf içerik
//  sekmesinde görünür. (Gerçek dosya yükleme Firebase Storage gerektirir;
//  bu ekran link + not paylaşımını destekler.)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../utils/safe_dismiss.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherMaterialScreen extends StatefulWidget {
  final TeacherClass cls;
  const TeacherMaterialScreen({super.key, required this.cls});

  @override
  State<TeacherMaterialScreen> createState() => _TeacherMaterialScreenState();
}

class _TeacherMaterialScreenState extends State<TeacherMaterialScreen> {
  String _kind = 'link'; // 'link' | 'pdf' | 'note'
  final _titleCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _sending = false;
  PlatformFile? _pickedPdf; // 'pdf' türünde yüklenecek dosya

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _isNote => _kind == 'note';
  bool get _isPdf => _kind == 'pdf';

  Future<void> _pickPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      if (f.bytes == null) {
        messenger.showSnackBar(SnackBar(
          content: Text('Dosya okunamadı, tekrar dene.'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      if (f.size > 25 * 1024 * 1024) {
        messenger.showSnackBar(SnackBar(
          content: Text('Dosya 25 MB sınırını aşıyor.'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      setState(() {
        _pickedPdf = f;
        if (_titleCtrl.text.trim().isEmpty) {
          // Dosya adından otomatik başlık önerisi (.pdf uzantısı atılır).
          _titleCtrl.text = f.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        }
      });
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text('Dosya seçilemedi.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text('Başlık gerekli.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (_isNote) {
      if (_noteCtrl.text.trim().isEmpty) {
        messenger.showSnackBar(SnackBar(
          content: Text('Not metni boş olamaz.'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    } else if (_isPdf) {
      if (_pickedPdf == null) {
        messenger.showSnackBar(SnackBar(
          content: Text('Önce bir PDF dosyası seç.'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    } else {
      final url = _urlCtrl.text.trim();
      if (url.isEmpty || !(url.startsWith('http://') || url.startsWith('https://'))) {
        messenger.showSnackBar(SnackBar(
          content: Text('Geçerli bir bağlantı gir (http/https).'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    }
    setState(() => _sending = true);

    // PDF dosyası: önce Storage'a yükle, indirme URL'ini al.
    String url = _urlCtrl.text;
    String fileName = '';
    if (_isPdf) {
      final f = _pickedPdf!;
      final res = await ClassService.uploadClassPdf(
        classId: widget.cls.id,
        fileName: f.name,
        bytes: f.bytes!,
      );
      if (res.url == null) {
        if (!mounted) return;
        setState(() => _sending = false);
        // Storage kurulmamış/kural deploy edilmemişse net mesaj ver.
        final code = res.error ?? '';
        final isSetup = code == 'unauthorized' ||
            code == 'object-not-found' ||
            code == 'unknown' ||
            code.contains('No object exists') ||
            code.contains('does not exist');
        messenger.showSnackBar(SnackBar(
          content: Text(isSetup
              ? 'PDF yüklenemedi: Depolama henüz etkin değil. PDF yerine "Web Linki" ile paylaşabilirsin.'.tr()
              : '${'PDF yüklenemedi, tekrar dene.'.tr()} ($code)'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      url = res.url!;
      fileName = f.name;
    }

    final ok = await ClassService.shareMaterial(
      classId: widget.cls.id,
      subject: widget.cls.subject,
      kind: _kind,
      title: title,
      url: url,
      note: _noteCtrl.text,
      fileName: fileName,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      await safeDismiss(context);
      messenger.showSnackBar(SnackBar(
        content: Text('Kaynak sınıfa paylaşıldı.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('Paylaşılamadı, tekrar dene.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kaynak Paylaş'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            Text(widget.cls.name,
                style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w500,
                  color: AppPalette.textSecondary(context),
                )),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                children: [
                  Text('Kaynak türü'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
                  const SizedBox(height: 10),
                  // Kademeli/merdiven diziliş: her sekme bir öncekinin bittiği
                  // yerden başlar (sağa kayar). Sekmeler geniş; dikey akış.
                  LayoutBuilder(builder: (context, c) {
                    final a = c.maxWidth;
                    // Geniş sekmeler: satırın ~%64'ü. İki kademe için sağa kayma
                    // payı (a - tabW) ikiye bölünür → 3. sekme tam sağ kenarda.
                    final tabW = (a * 0.64).clamp(190.0, 300.0);
                    final step = ((a - tabW) / 2).clamp(0.0, a);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kindTab('link', Icons.link_rounded,
                            'Web Linki'.tr(), tabW, 0),
                        const SizedBox(height: 10),
                        _kindTab('pdf', Icons.picture_as_pdf_rounded,
                            'PDF Linki'.tr(), tabW, step),
                        const SizedBox(height: 10),
                        _kindTab('note', Icons.sticky_note_2_rounded,
                            'Ders Notu'.tr(), tabW, step * 2),
                      ],
                    );
                  }),
                  const SizedBox(height: 20),
                  Text('Başlık'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
                  const SizedBox(height: 8),
                  _field(context, _titleCtrl,
                      'Örn: Üçgenler konu anlatımı'.tr(), maxLines: 1, maxLen: 80),
                  const SizedBox(height: 18),
                  if (_isNote) ...[
                    Text('Ders notu'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(height: 8),
                    _field(context, _noteCtrl,
                        'Notunu buraya yaz…'.tr(), maxLines: 8, maxLen: 3000),
                  ] else if (_isPdf) ...[
                    Text('PDF dosyası'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(height: 8),
                    _pdfPicker(context),
                  ] else ...[
                    Text('Web bağlantısı'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(height: 8),
                    _field(context, _urlCtrl, 'https://…',
                        maxLines: 1, maxLen: 500,
                        keyboard: TextInputType.url),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kBrand,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _sending ? null : _share,
                  icon: _sending
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.share_rounded, size: 20),
                  label: Text(
                    _sending ? 'Paylaşılıyor…'.tr() : 'Sınıfla Paylaş'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 14.5, fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindTab(String kind, IconData icon, String label,
      double width, double leftOffset) {
    final sel = _kind == kind;
    // Geniş dikdörtgen çerçeve; merdiven dizilim için sol kaydırma + genişlik.
    return Padding(
      padding: EdgeInsets.only(left: leftOffset),
      child: SizedBox(
        width: width,
        child: GestureDetector(
          onTap: () => setState(() => _kind = kind),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: sel ? _kBrand.withValues(alpha: 0.12) : AppPalette.card(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sel ? _kBrand : AppPalette.border(context),
              width: sel ? 1.8 : 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19,
                  color: sel ? _kBrand : AppPalette.textSecondary(context)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: sel ? _kBrand : AppPalette.textPrimary(context),
                    )),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _pdfPicker(BuildContext c) {
    final f = _pickedPdf;
    if (f == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _pickPdf,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              color: AppPalette.card(c),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _kBrand.withValues(alpha: 0.4),
                width: 1.4,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              children: [
                const Icon(Icons.upload_file_rounded, size: 30, color: _kBrand),
                const SizedBox(height: 8),
                Text('PDF dosyası seç'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w800, color: _kBrand)),
                const SizedBox(height: 2),
                Text('En fazla 25 MB'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, color: AppPalette.textSecondary(c))),
              ],
            ),
          ),
        ),
      );
    }
    final kb = (f.size / 1024).toStringAsFixed(0);
    final sizeStr = f.size >= 1024 * 1024
        ? '${(f.size / 1024 / 1024).toStringAsFixed(1)} MB'
        : '$kb KB';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kBrand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBrand.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf_rounded, size: 28, color: _kBrand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimary(c),
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(sizeStr,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, color: AppPalette.textSecondary(c))),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded,
                size: 20, color: AppPalette.textSecondary(c)),
            onPressed: () => setState(() => _pickedPdf = null),
            tooltip: 'Kaldır'.tr(),
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext c, TextEditingController ctrl, String hint,
      {int maxLines = 1, int? maxLen, TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      maxLength: maxLen,
      keyboardType: keyboard,
      style: GoogleFonts.poppins(fontSize: 13.5, color: AppPalette.textPrimary(c)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          fontSize: 13, color: AppPalette.textSecondary(c)),
        filled: true,
        fillColor: AppPalette.card(c),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppPalette.border(c)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppPalette.border(c)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kBrand, width: 1.5),
        ),
      ),
    );
  }
}
