// ═══════════════════════════════════════════════════════════════════════════
//  TeacherClassResourcesScreen — Öğretmenin bir sınıfa PAYLAŞTIĞI kaynakları
//  (web linki / PDF / ders notu) listelediği, açabildiği ve silebildiği ekran.
//
//  ClassService.shareMaterial içerik akışına 'material' tipinde yazar; bu ekran
//  classContentStream'i 'material' kayıtlarına süzerek öğretmene geri gösterir.
//  Üstteki "+" ile yeni kaynak paylaşma ekranı (TeacherMaterialScreen) açılır.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_material_screen.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherClassResourcesScreen extends StatefulWidget {
  final TeacherClass cls;
  const TeacherClassResourcesScreen({super.key, required this.cls});

  @override
  State<TeacherClassResourcesScreen> createState() =>
      _TeacherClassResourcesScreenState();
}

class _TeacherClassResourcesScreenState
    extends State<TeacherClassResourcesScreen> {
  Future<void> _openUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text('Bağlantı açılamadı.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showNote(String title, String note) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppPalette.border(ctx),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(title,
                  style: GoogleFonts.poppins(
                    fontSize: 17, fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(ctx),
                  )),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  child: Text(note,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5, height: 1.55,
                        color: AppPalette.textPrimary(ctx),
                      )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String contentId, String title) async {
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Kaynağı sil'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(ctx))),
        content: Text(
            '"$title" ${'kaynağını silmek istediğine emin misin?'.tr()}',
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppPalette.textSecondary(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await ClassService.deleteContent(
        classId: widget.cls.id, contentId: contentId);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Kaynak silindi.'.tr() : 'Silinemedi, tekrar dene.'.tr()),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _shareNew() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TeacherMaterialScreen(cls: widget.cls)));
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
            Text('Paylaşılan Kaynaklar'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            Text(widget.cls.name,
                style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w500,
                  color: AppPalette.textSecondary(context),
                )),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: _kBrand),
            tooltip: 'Kaynak paylaş'.tr(),
            onPressed: _shareNew,
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: ClassService.classContentStream(widget.cls.id),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2));
            }
            final items = (snap.data ?? const [])
                .where((m) => (m['type'] ?? '').toString() == 'material')
                .toList();
            if (items.isEmpty) return _empty(context);
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _card(context, items[i]),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kBrand,
        onPressed: _shareNew,
        icon: const Icon(Icons.share_rounded, color: Colors.white),
        label: Text('Kaynak Paylaş'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800, color: Colors.white)),
      ),
    );
  }

  Widget _card(BuildContext c, Map<String, dynamic> m) {
    final payload = (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final kind = (payload['kind'] ?? '').toString();
    final url = (payload['url'] ?? '').toString();
    final note = (payload['note'] ?? '').toString();
    final fileName = (payload['fileName'] ?? '').toString();
    final title = (m['title'] ?? '').toString();
    final id = (m['_id'] ?? '').toString();

    IconData icon;
    Color color;
    String sub;
    switch (kind) {
      case 'note':
        icon = Icons.sticky_note_2_rounded;
        color = const Color(0xFFF59E0B);
        sub = 'Ders notu'.tr();
        break;
      case 'pdf':
        icon = Icons.picture_as_pdf_rounded;
        color = const Color(0xFFEF4444);
        sub = fileName.isNotEmpty ? fileName : 'PDF'.tr();
        break;
      default:
        icon = Icons.link_rounded;
        color = const Color(0xFF0EA5E9);
        sub = url;
    }

    void onTap() {
      if (kind == 'note') {
        _showNote(title, note);
      } else if (url.isNotEmpty) {
        _openUrl(url);
      }
    }

    return Material(
      color: AppPalette.card(c),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.border(c)),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5, fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(c),
                        )),
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 11, color: AppPalette.textSecondary(c),
                        )),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: AppPalette.textSecondary(c)),
                tooltip: 'Sil'.tr(),
                onPressed: () => _confirmDelete(id, title),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📎', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 14),
            Text('Henüz kaynak paylaşmadın'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 8),
            Text('Web linki, PDF veya ders notu paylaş; öğrencilerin '
                '"Kaynaklarım" sayfasında görünür.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13, height: 1.45,
                  color: AppPalette.textSecondary(context),
                )),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _kBrand),
              onPressed: _shareNew,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text('Kaynak Paylaş'.tr(),
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
