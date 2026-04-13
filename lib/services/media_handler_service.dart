import 'package:url_launcher/url_launcher.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  MediaHandlerService — Video / Web / Test URL açıcı
//
//  Tüm medya tetikleyicilerini bu tek dosyada topla.
//  İleride farklı platform (WebView, in-app browser) eklemek için
//  sadece bu dosyayı değiştirmek yeterli.
// ═══════════════════════════════════════════════════════════════════════════════

class MediaHandlerService {
  // ── YouTube: Önce YouTube uygulamasını dene, yoksa tarayıcıya geç ────────────
  static Future<void> openYouTubeSearch(String query) async {
    final encoded = Uri.encodeQueryComponent(query);

    // YouTube uygulaması (varsa)
    final appUri = Uri.parse('youtube://results?search_query=$encoded');
    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri);
      return;
    }

    // Tarayıcı fallback
    final webUri =
        Uri.parse('https://www.youtube.com/results?search_query=$encoded');
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  // ── Web kaynakları: Google arama veya doğrudan URL ───────────────────────────
  static Future<void> openWebSource(String query) async {
    Uri uri;

    // Eğer zaten bir URL'yse doğrudan aç
    if (query.startsWith('http://') || query.startsWith('https://')) {
      uri = Uri.parse(query);
    } else {
      final encoded = Uri.encodeQueryComponent(query);
      uri = Uri.parse('https://www.google.com/search?q=$encoded');
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Test platformları ─────────────────────────────────────────────────────────
  static Future<void> openTestPlatform(String query) async {
    final encoded = Uri.encodeQueryComponent(query);
    final uri = Uri.parse('https://www.google.com/search?q=$encoded');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Doğrudan URL aç (video veya döküman) ─────────────────────────────────────
  static Future<void> openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // YouTube video — uygulamayı dene
    if (url.contains('youtube.com/watch') || url.contains('youtu.be/')) {
      String? videoId;
      if (url.contains('youtu.be/')) {
        videoId = url.split('youtu.be/').last.split('?').first.split('&').first;
      } else {
        videoId = uri.queryParameters['v'];
      }
      if (videoId != null && videoId.isNotEmpty) {
        final appUri = Uri.parse('youtube://watch?v=$videoId');
        if (await canLaunchUrl(appUri)) {
          await launchUrl(appUri);
          return;
        }
      }
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
