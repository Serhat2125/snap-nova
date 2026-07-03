// ═══════════════════════════════════════════════════════════════════════════
//  StudentMaterialsScreen — Öğrencinin katıldığı sınıflardan gelen KAYNAKLAR
//  ve DUYURULAR. Öğretmenin "Kaynak/Materyal Paylaş" ve "Duyuru Yayınla"
//  akışlarıyla yazdığı içerik burada listelenir.
//
//  • material (link)  → dokun, tarayıcıda aç
//  • material (pdf)   → dokun, PDF'i aç (harici görüntüleyici)
//  • material (note)  → dokun, notu oku
//  • announcement     → duyuru metni (salt-okuma)
//
//  Kaynak: classes/{classId}/content (ClassService.classContentStream).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

class StudentMaterialsScreen extends StatefulWidget {
  const StudentMaterialsScreen({super.key});

  @override
  State<StudentMaterialsScreen> createState() => _StudentMaterialsScreenState();
}

/// Tek içerik öğesi (sınıf adıyla birlikte).
class _Item {
  final String className;
  final Map<String, dynamic> data;
  final DateTime when;
  const _Item(this.className, this.data, this.when);

  String get type => (data['type'] ?? '').toString();
  String get title => (data['title'] ?? '').toString();
  String get subject => (data['subject'] ?? '').toString();
  Map<String, dynamic> get payload =>
      (data['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get kind => (payload['kind'] ?? '').toString();
  String get url => (payload['url'] ?? '').toString();
  String get note => (payload['note'] ?? '').toString();
  String get message => (payload['message'] ?? '').toString();
}

class _StudentMaterialsScreenState extends State<StudentMaterialsScreen> {
  List<_Item> _items = [];
  bool _loading = true;
  // Yükleme hatası — sessizce "kaynak yok" göstermek yanıltıcıydı.
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final out = <_Item>[];
    try {
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid != null) {
        final joinedSnap = await FirebaseFirestore.instance
            .collection('users').doc(myUid)
            .collection('joined_classes').get();
        final classes = joinedSnap.docs
            .map((d) => JoinedClass.fromMap(d.id, d.data())).toList();
        for (final c in classes) {
          // Öğretmen onayı bekleyen (pending) üyelik: sınıf içerikleri
          // onaylanana kadar gizli kalır.
          try {
            final member = await FirebaseFirestore.instance
                .collection('classes').doc(c.classId)
                .collection('students').doc(myUid).get();
            if (!member.exists ||
                (member.data()?['status'] ?? 'active').toString() ==
                    'pending') {
              continue;
            }
          } catch (_) {/* okuma hatasında içerik gösterilmeye devam eder */}
          final content =
              await ClassService.classContentStream(c.classId).first;
          for (final m in content) {
            final type = (m['type'] ?? '').toString();
            if (type != 'material' && type != 'announcement') continue;
            DateTime when = DateTime.now();
            final ts = m['sharedAt'];
            if (ts is Timestamp) when = ts.toDate();
            out.add(_Item(c.className, m, when));
          }
        }
        out.sort((a, b) => b.when.compareTo(a.when));
      }
    } catch (_) {
      _error = true;
    }
    if (mounted) {
      setState(() {
        _items = out;
        _loading = false;
      });
    }
  }

  Future<void> _openUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    // Öğretmen "www.site.com" gibi şemasız link yapıştırabilir —
    // şema yoksa https ekle, yoksa launchUrl hiç açamıyordu.
    var normalized = url.trim();
    if (!normalized.contains('://')) normalized = 'https://$normalized';
    final uri = Uri.tryParse(normalized);
    bool ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        // Bazı cihazlarda launchUrl false dönmek yerine istisna atar.
        ok = false;
      }
    }
    if (!ok && mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text('Bağlantı açılamadı.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Not VE duyuru tam metni aynı sheet ile okunur. [text] verilirse o
  /// gösterilir (duyuru mesajı), yoksa it.note.
  void _showNote(_Item it, {String? text}) {
    final body = text ?? it.note;
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
              Text(it.title,
                  style: GoogleFonts.poppins(
                    fontSize: 17, fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(ctx),
                  )),
              Text('${it.className} · ${it.subject}',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5, color: AppPalette.textSecondary(ctx))),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  child: Text(body,
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

  void _onTap(_Item it) {
    if (it.type == 'announcement') {
      // Kartta 6 satırda kesilen uzun duyurunun TAMAMI okunabilsin.
      _showNote(it, text: it.message);
      return;
    }
    if (it.kind == 'note') {
      _showNote(it);
    } else if (it.url.isNotEmpty) {
      _openUrl(it.url);
    }
  }

  /// Kart dokunulabilir mi? URL'si boş PDF/link kartı dokunulabilir görünüp
  /// hiçbir şey yapmıyordu — o durumda tamamen pasif bırakılır.
  bool _isTappable(_Item it) {
    if (it.type == 'announcement') return it.message.trim().isNotEmpty;
    if (it.kind == 'note') return it.note.trim().isNotEmpty;
    return it.url.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Sınıf Kaynaklarım'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: ink),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _items.isEmpty
                    // Boş/hata durumu da aşağı çekilerek yenilenebilsin.
                    ? LayoutBuilder(
                        builder: (ctx, cons) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: cons.maxHeight,
                            child: _error
                                ? _errorView(context)
                                : _empty(context),
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: _items.length,
                        itemBuilder: (ctx, i) => _card(context, _items[i]),
                      ),
              ),
      ),
    );
  }

  Widget _card(BuildContext context, _Item it) {
    final muted = AppPalette.textSecondary(context);
    final isAnnouncement = it.type == 'announcement';

    IconData icon;
    Color color;
    String typeLabel;
    if (isAnnouncement) {
      icon = Icons.campaign_rounded;
      color = const Color(0xFFF59E0B);
      typeLabel = 'Duyuru'.tr();
    } else if (it.kind == 'pdf') {
      icon = Icons.picture_as_pdf_rounded;
      color = const Color(0xFFEF4444);
      typeLabel = 'PDF'.tr();
    } else if (it.kind == 'note') {
      icon = Icons.sticky_note_2_rounded;
      color = const Color(0xFF0EA5E9);
      typeLabel = 'Ders Notu'.tr();
    } else {
      icon = Icons.link_rounded;
      color = const Color(0xFF7C3AED);
      typeLabel = 'Bağlantı'.tr();
    }

    final body = isAnnouncement ? it.message : it.title;
    final tappable = _isTappable(it);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: tappable ? () => _onTap(it) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(typeLabel,
                              style: GoogleFonts.poppins(
                                fontSize: 9.5, fontWeight: FontWeight.w800,
                                color: color,
                              )),
                        ),
                        const Spacer(),
                        Text(_relative(it.when),
                            style: GoogleFonts.poppins(
                              fontSize: 10, color: muted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(body,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5, fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: AppPalette.textPrimary(context),
                        ),
                        maxLines: isAnnouncement ? 6 : 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text('${it.className}${it.subject.isNotEmpty ? ' · ${it.subject}' : ''}',
                        style: GoogleFonts.poppins(
                          fontSize: 11, color: muted),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (tappable)
                Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk';
    if (diff.inHours < 24) return '${diff.inHours} sa';
    if (diff.inDays < 7) return '${diff.inDays} g';
    return '${when.day}.${when.month}.${when.year}';
  }

  /// Yükleme hatası görünümü — "kaynak yok" ile karışmasın.
  Widget _errorView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📡', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Kaynaklar yüklenemedi'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 6),
            Text(
              'İnternet bağlantını kontrol edip tekrar dene.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9)),
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Tekrar Dene'.tr()),
            ),
          ],
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
            const Text('📎', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Henüz kaynak yok'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 6),
            Text(
              'Öğretmenlerin paylaştığı PDF, link, not ve duyurular burada görünür.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
