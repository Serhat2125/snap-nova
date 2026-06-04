// ============================================================
//  lib/screens/lesson_3d_screen.dart
//  3D interaktif ders ekranı (HTML + Three.js).
//
//  Asset olarak gömülen HTML dosyasını WebView'de açar.
//  loadFlutterAsset kullanılır — Android'de WebViewAssetLoader
//  üzerinden https://appassets.androidplatform.net/ ile sunulur,
//  böylece ES module import map'i (Three.js) düzgün çalışır.
//  İnternet gerektirmez.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Web'de webview_flutter desteklenmediği için HTML asset iframe ile gösterilir.
// Mobil/masaüstünde stub döner (kIsWeb ile dallanılır, çağrılmaz).
import 'html_asset_view_stub.dart'
    if (dart.library.html) 'html_asset_view_web.dart';

class Lesson3DScreen extends StatefulWidget {
  /// pubspec.yaml assets listesindeki HTML yolu
  /// (örn: 'assets/dunyanin-hareketleri.html')
  final String assetHtml;

  /// Üst çubukta görünecek başlık
  final String title;

  const Lesson3DScreen({
    super.key,
    required this.assetHtml,
    this.title = '3D Ders',
  });

  @override
  State<Lesson3DScreen> createState() => _Lesson3DScreenState();
}

class _Lesson3DScreenState extends State<Lesson3DScreen> {
  // Web'de WebViewController KULLANILMAZ (platform implementasyonu yok →
  // assertion hatası). Bu yüzden nullable ve sadece mobil/masaüstünde kurulur.
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  /// Web hedefinde iframe src'i: Flutter web asset'leri `assets/<assetKey>`
  /// yolundan sunar (assetKey zaten 'assets/...' ile başladığı için çift olur).
  String get _webAssetUrl => 'assets/${widget.assetHtml}';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // iframe anında yüklenir; yükleme katmanı gösterme.
      _loading = false;
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF070B22))
      ..addJavaScriptChannel(
        'FlutterShare',
        onMessageReceived: (msg) => _handleShare(msg.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (err) {
            // ES module veya alt-frame hataları main frame'i bozmaz —
            // sadece main frame hatalarında banner göster.
            if (err.isForMainFrame == false) return;
            if (mounted) {
              setState(() {
                _loading = false;
                _error = 'Yükleme hatası: ${err.description}';
              });
            }
          },
        ),
      )
      ..loadFlutterAsset(widget.assetHtml);
  }

  /// HTML tarafından gönderilen ekran görüntüsünü native paylaşım
  /// sayfasıyla paylaşır. WebView'de `navigator.share` desteklenmediği
  /// için paylaşım Flutter (share_plus) üzerinden yapılır.
  Future<void> _handleShare(String message) async {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final dataUrl = data['image'] as String? ?? '';
      final text = data['text'] as String? ?? '';
      final fileName = data['file'] as String? ?? 'qualsar-3d.png';

      final comma = dataUrl.indexOf(',');
      if (comma < 0) return;
      final bytes = base64Decode(dataUrl.substring(comma + 1));

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: text,
      );
    } catch (_) {
      // Paylaşım başarısızsa sessizce yut — kullanıcı tekrar deneyebilir.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161D49),
        foregroundColor: const Color(0xFFFFF4DC),
        title: Text(widget.title),
        elevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (_error == null && kIsWeb) htmlAssetView(_webAssetUrl),
            if (_error == null && !kIsWeb && _controller != null)
              WebViewWidget(controller: _controller!),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF6B9D)),
                  ),
                ),
              ),
            if (_loading && _error == null)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFFFB627)),
                    SizedBox(height: 16),
                    Text(
                      '3D ders yükleniyor...',
                      style: TextStyle(color: Color(0xFFB9C2EE)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
