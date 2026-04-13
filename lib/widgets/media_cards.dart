import 'package:flutter/material.dart';
import '../services/media_handler_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  MediaCards — Video / Web / Test tıklanabilir kart widget'ları
//
//  LatexText tarafından [VIDEO: ...], [WEB: ...], [TEST: ...] etiketleri
//  algılandığında bu widget'lar render edilir.
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Video Kartı — YouTube ────────────────────────────────────────────────────
class VideoCard extends StatefulWidget {
  final String title;
  final String query;
  const VideoCard({super.key, required this.title, required this.query});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);
    await MediaHandlerService.openYouTubeSearch(widget.query);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return _MediaCardBase(
      onTap: _open,
      loading: _loading,
      accentColor: const Color(0xFF38BDF8),   // sky-400 — açık mavi
      icon: Icons.play_circle_filled_rounded,
      badge: 'Video',
      badgeIcon: Icons.smart_display_rounded,
      title: widget.title,
      subtitle: widget.query,
      subtitlePrefix: '🔍 ',
    );
  }
}

// ─── Web / PDF Kartı ─────────────────────────────────────────────────────────
class WebCard extends StatefulWidget {
  final String title;
  final String query;
  const WebCard({super.key, required this.title, required this.query});

  @override
  State<WebCard> createState() => _WebCardState();
}

class _WebCardState extends State<WebCard> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);
    await MediaHandlerService.openWebSource(widget.query);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return _MediaCardBase(
      onTap: _open,
      loading: _loading,
      accentColor: const Color(0xFF93C5FD),   // blue-300 — buz mavisi
      icon: Icons.menu_book_rounded,
      badge: 'Kaynak',
      badgeIcon: Icons.open_in_new_rounded,
      title: widget.title,
      subtitle: widget.query,
      subtitlePrefix: '📖 ',
    );
  }
}

// ─── Test / Platform Kartı ────────────────────────────────────────────────────
class TestCard extends StatefulWidget {
  final String title;
  final String query;
  const TestCard({super.key, required this.title, required this.query});

  @override
  State<TestCard> createState() => _TestCardState();
}

class _TestCardState extends State<TestCard> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);
    await MediaHandlerService.openTestPlatform(widget.query);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return _MediaCardBase(
      onTap: _open,
      loading: _loading,
      accentColor: const Color(0xFF7DD3FC),   // sky-300 — açık mavi
      icon: Icons.quiz_rounded,
      badge: 'Test',
      badgeIcon: Icons.arrow_forward_ios_rounded,
      title: widget.title,
      subtitle: widget.query,
      subtitlePrefix: '✏️ ',
    );
  }
}

// ─── Ortak kart tasarımı ─────────────────────────────────────────────────────

class _MediaCardBase extends StatelessWidget {
  final VoidCallback onTap;
  final bool loading;
  final Color accentColor;
  final IconData icon;
  final String badge;
  final IconData badgeIcon;
  final String title;
  final String subtitle;
  final String subtitlePrefix;

  const _MediaCardBase({
    required this.onTap,
    required this.loading,
    required this.accentColor,
    required this.icon,
    required this.badge,
    required this.badgeIcon,
    required this.title,
    required this.subtitle,
    required this.subtitlePrefix,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2A),   // koyu lacivert arka plan
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withValues(alpha: loading ? 0.70 : 0.35),
            width: 1.2,
          ),
          boxShadow: loading
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.20),
                    blurRadius: 14,
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Sol ikon kutusu ──────────────────────────────────────────────
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: accentColor.withValues(alpha: 0.30), width: 1),
              ),
              child: loading
                  ? Padding(
                      padding: const EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentColor,
                      ),
                    )
                  : Icon(icon, color: accentColor, size: 24),
            ),
            const SizedBox(width: 12),

            // ── Başlık + arama ipucu ─────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$subtitlePrefix$subtitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.40),
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── Sağ badge ────────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    badge,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(badgeIcon, color: accentColor, size: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
