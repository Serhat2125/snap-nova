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

import '../services/tts_service.dart';
import '../services/gemini_service.dart';
import 'academic_planner.dart';

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
      ..addJavaScriptChannel(
        // Sınav oluştur / AI'ya sor / Sesli anlatım köprüsü
        'FlutterBridge',
        onMessageReceived: (msg) => _handleBridge(msg.message),
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

  /// HTML'den gelen aksiyonlar: 'exam' → Sınav Oluştur sayfası,
  /// 'ai' → AI'ya Sor sohbeti, 'speak'/'stopSpeak' → sesli anlatım (TTS).
  Future<void> _handleBridge(String message) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final action = data['action'] as String? ?? '';
    if (action == 'speak') {
      final text = (data['text'] as String? ?? '').trim();
      if (text.isNotEmpty) {
        try {
          await TtsService.stop();
          // Cümlelere böl ve sırayla doğal (insansı) oku — uzun metinde de akıcı.
          final sentences = text
              .split(RegExp(r'(?<=[.!?…:])\s+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty);
          for (final s in sentences) {
            TtsService.enqueue(s);
          }
        } catch (_) {}
      }
      return;
    }
    if (action == 'stopSpeak') {
      try { await TtsService.stop(); } catch (_) {}
      return;
    }
    if (!mounted) return;
    if (action == 'exam') {
      // Kütüphanedeki Test Oluştur sayfası; o anki ders+konu ön seçili gelir.
      final subject = (data['subject'] as String? ?? '').trim();
      final topic = (data['topic'] as String? ?? '').trim();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AcademicPlanner(
            mode: LibraryMode.questions,
            autoOpenSubject: subject.isEmpty ? null : subject,
            autoOpenTopic: topic.isEmpty ? null : topic,
          ),
        ),
      );
    } else if (action == 'ai') {
      // Koç akışı DEĞİL — doğrudan "Sana nasıl yardımcı olabilirim?" paneli.
      final topic = (data['topic'] as String? ?? '').trim();
      final level = (data['level'] as String? ?? '').trim();
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AskAiSheet(topic: topic, level: level),
      );
    }
  }

  @override
  void dispose() {
    // Dersten çıkınca sesli anlatımı durdur.
    if (!kIsWeb) {
      try { TtsService.stop(); } catch (_) {}
    }
    super.dispose();
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
    return PopScope(
      // Mobilde geri tuşunu biz yönetiriz: önce HTML'deki açık pencereyi kapat.
      canPop: kIsWeb || _controller == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final ctrl = _controller;
        // Açık bir pencere/panel varsa WebView geçmişinde geri git → HTML popstate
        // SADECE o pencereyi kapatır (derse devam). Açık pencere yoksa dersten çık.
        if (ctrl != null && await ctrl.canGoBack()) {
          ctrl.goBack();
        } else if (mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
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
      ), // Scaffold
    ); // PopScope
  }
}

/// 3D dersten 🤖 ile açılan hafif soru-cevap paneli.
/// Koç akışı yok: "Sana nasıl yardımcı olabilirim?" der, kullanıcı sorar, cevap gelir.
class _AskAiSheet extends StatefulWidget {
  final String topic;
  final String level;
  const _AskAiSheet({this.topic = '', this.level = ''});

  // Profesyonel ders uzmanı biçim kuralları (yıldız/markdown YASAK).
  static const String styleRules =
      'Sen alanında uzman, profesyonel bir ders öğretmenisin. Şu kurallara KESİNLİKLE uy:\n'
      '• Yıldız (*), kare (#), alt çizgi (_), backtick (`), markdown ve garip sembol KULLANMA.\n'
      '• KISA ve NET cevap ver: en fazla birkaç cümle ya da 3-5 kısa madde; gereksiz uzatma, tekrar etme.\n'
      '• Doğrudan sorunun cevabına odaklan; gereksiz giriş/özet ekleme.\n'
      '• Gerektiğinde maddeleri tek tek, her satır "• " ile yaz.\n'
      '• Alt başlık gerekiyorsa kısa yaz ve sonuna iki nokta üst üste koy (örn. "Tanım:").\n'
      '• Yerinde, az sayıda emoji kullanabilirsin (🌍, 🔭, 💡 gibi).\n'
      '• Cevabı yalnızca düz metin olarak ver.';

  // Eğitim seviyesine göre dil/derinlik talimatı.
  static String levelRule(String level) {
    switch (level) {
      case 'İlkokul':
        return 'Öğrenci İLKOKUL seviyesinde. Çok basit, günlük dille, kısa cümlelerle ve somut örneklerle anlat. Terimleri sadeleştir.';
      case 'Ortaokul':
        return 'Öğrenci ORTAOKUL seviyesinde. Sade ama biraz daha açıklayıcı; temel terimleri kısaca tanımla.';
      case 'Lise':
        return 'Öğrenci LİSE seviyesinde. Doğru terimleri kullan, nedenleriyle kısaca açıkla.';
      case 'Sınavlara Hazırlık':
        return 'Öğrenci SINAVLARA HAZIRLIK seviyesinde. Sınavda çıkan ayrıntılara ve sık yapılan hatalara kısa ve net değin.';
      case 'Üniversite':
        return 'Öğrenci ÜNİVERSİTE seviyesinde. Akademik terimlerle, doğru ve derinlemesine ama yine de KISA cevap ver.';
      default:
        return 'Öğrencinin seviyesine uygun konuş; basitten gerekirse derine in.';
    }
  }

  @override
  State<_AskAiSheet> createState() => _AskAiSheetState();
}

/// LLM cevabındaki markdown/garip sembolleri temizler, düz profesyonel metne çevirir.
String _cleanReply(String s) {
  var t = s;
  t = t.replaceAll('\r\n', '\n');
  // Kalın/italik/başlık işaretleri
  t = t.replaceAll(RegExp(r'\*\*|__'), '');
  t = t.replaceAll(RegExp(r'`+'), '');
  t = t.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  // Satır başı madde işaretlerini "• " yap
  t = t.replaceAll(RegExp(r'^\s*[\*\-]\s+', multiLine: true), '• ');
  t = t.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '• ');
  // Kalan tekil yıldızlar
  t = t.replaceAll('*', '');
  // Fazla boş satırlar
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}

class _AskAiSheetState extends State<_AskAiSheet> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<({bool user, String text})> _msgs = [];
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _ctrl.text).trim();
    if (q.isEmpty || _sending) return;
    _ctrl.clear();
    // Geçmişi mevcut soruyu EKLEMEDEN önce topla (tekrar göndermeyelim).
    final history = <Map<String, String>>[];
    for (final m in _msgs) {
      history.add({'role': m.user ? 'user' : 'assistant', 'text': m.text});
    }
    setState(() {
      _msgs.add((user: true, text: q));
      _sending = true;
    });
    _scrollDown();
    try {
      // Profesyonel ders uzmanı kimliği + temiz biçim kuralları + konu bağlamı.
      final ctxMsg =
          '${_AskAiSheet.styleRules}\n'
          '${_AskAiSheet.levelRule(widget.level)}\n\n'
          '${widget.level.isEmpty ? '' : '[SEVİYE: ${widget.level}]\n'}'
          '${widget.topic.isEmpty ? '' : '[KONU: ${widget.topic}]\n'}'
          'Öğrencinin sorusu: $q';
      final reply = await GeminiService.chatWithCoach(
        userMessage: ctxMsg,
        history: history,
      );
      if (!mounted) return;
      setState(() => _msgs.add((user: false, text: _cleanReply(reply))));
    } catch (_) {
      if (!mounted) return;
      setState(() => _msgs.add((
            user: false,
            text: 'Şu an cevap veremedim. İnternet bağlantını kontrol edip tekrar dene.'
          )));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  // AI cevabını profesyonel biçimde render et: alt başlık (renkli), madde (• ikon), düz metin.
  Widget _formattedAnswer(String text) {
    final lines = text.split('\n');
    final widgets = <Widget>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) { widgets.add(const SizedBox(height: 6)); continue; }
      final isSub = line.endsWith(':') && line.length <= 42 && !line.startsWith('•');
      if (isSub) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(line,
              style: const TextStyle(
                  color: Color(0xFFFFD166), fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.3)),
        ));
      } else if (line.startsWith('•')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 3, left: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ',
                  style: TextStyle(color: Color(0xFF4FD6E0), fontSize: 13.5, fontWeight: FontWeight.w800)),
              Expanded(
                child: Text(line.substring(1).trim(),
                    style: const TextStyle(color: Color(0xFFEEF0FF), fontSize: 13.5, height: 1.4)),
              ),
            ],
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(line,
              style: const TextStyle(color: Color(0xFFEEF0FF), fontSize: 13.5, height: 1.42)),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: widgets);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Color(0xFF161B2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: Color(0xFF9D7FE6), width: 2)),
        ),
        child: Column(
          children: [
            // Başlık
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '🤖 Sana nasıl yardımcı olabilirim?',
                      style: TextStyle(
                        color: Color(0xFFFFD166),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFB9C2EE)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF2F3A5F)),
            // Mesajlar / boş durumda ipucu
            Expanded(
              child: _msgs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Bu konuda merak ettiğin her şeyi sorabilirsin.\nÖrn: "Mevsimler neden oluşur?"',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF8A93B0), fontSize: 13, height: 1.4),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) {
                        final m = _msgs[i];
                        return Align(
                          alignment:
                              m.user ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.78),
                            decoration: BoxDecoration(
                              color: m.user
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF1F2540),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: m.user
                                ? Text(
                                    m.text,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13.5, height: 1.4),
                                  )
                                : _formattedAnswer(m.text),
                          ),
                        );
                      },
                    ),
            ),
            if (_sending)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('AI yazıyor…',
                    style: TextStyle(color: Color(0xFF8A93B0), fontSize: 12)),
              ),
            // Giriş satırı
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(color: Color(0xFFEEF0FF), fontSize: 14),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Sorunu yaz…',
                          hintStyle: const TextStyle(color: Color(0xFF8A93B0)),
                          filled: true,
                          fillColor: const Color(0xFF1F2540),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sending ? null : () => _send(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _sending
                              ? const Color(0xFF3A4668)
                              : const Color(0xFFFFD166),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.send_rounded,
                            color: _sending ? const Color(0xFF8A93B0) : const Color(0xFF0A1420)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
