import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../models/topic_3d_model.dart';
import '../services/premium_status.dart';
import '../services/topic_3d_registry.dart';
import 'ai_coach_chat_screen.dart';
import 'premium_screen.dart';

/// 3D model görüntüleme ekranı — hücre, güneş sistemi, yer şekilleri gibi
/// konular için interaktif 3D görüntüleyici.
///
/// Özellikler:
///  • Üstte parça chip listesi (Çekirdek, Mitokondri…); tıkla → 3D kamera odaklanır
///  • Ortada ModelViewer — döndür/yakınlaştır, hotspot etiketleri parça üstünde
///  • Sağda toolbar: kesit, animasyon, AR, quiz, karşılaştır, AI sohbet, soru üret
///  • Altta seçili parça bilgi paneli
///
/// AR / Karşılaştırma / AI soru üretme premium özelliklerdir.
class Topic3DViewerScreen extends StatefulWidget {
  final Topic3DModel model;

  const Topic3DViewerScreen({super.key, required this.model});

  static Route<void> route(Topic3DModel model) =>
      MaterialPageRoute(builder: (_) => Topic3DViewerScreen(model: model));

  @override
  State<Topic3DViewerScreen> createState() => _Topic3DViewerScreenState();
}

class _Topic3DViewerScreenState extends State<Topic3DViewerScreen> {
  Topic3DPart? _selected;
  bool _crossSection = false;
  bool _animate = false;
  bool _compareMode = false;

  // Quiz mode state
  bool _quizMode = false;
  Topic3DPart? _quizTarget;
  String? _quizResult;
  int _quizScore = 0;
  int _quizTotal = 0;

  @override
  void initState() {
    super.initState();
    if (widget.model.parts.isNotEmpty) {
      _selected = widget.model.parts.first;
    }
  }

  void _selectPart(Topic3DPart p) {
    setState(() {
      _selected = p;
      if (_quizMode && _quizTarget != null) {
        _checkQuizAnswer(p);
      }
    });
  }

  void _toggleQuizMode() async {
    if (_quizMode) {
      setState(() {
        _quizMode = false;
        _quizTarget = null;
        _quizResult = null;
      });
      return;
    }
    setState(() {
      _quizMode = true;
      _quizScore = 0;
      _quizTotal = 0;
      _nextQuizQuestion();
    });
  }

  void _nextQuizQuestion() {
    final parts = widget.model.parts;
    final idx = math.Random().nextInt(parts.length);
    _quizTarget = parts[idx];
    _quizResult = null;
    _selected = null;
  }

  void _checkQuizAnswer(Topic3DPart picked) {
    _quizTotal++;
    final correct = picked.id == _quizTarget?.id;
    if (correct) _quizScore++;
    _quizResult = correct
        ? '✅ Doğru! ${picked.name} bu.'
        : '❌ Yanlış. Doğru cevap: ${_quizTarget?.name ?? '-'}';
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted || !_quizMode) return;
      setState(_nextQuizQuestion);
    });
  }

  Future<bool> _requirePremium(String featureName) async {
    final status = await PremiumStatus.read();
    if (status.isActive) return true;
    if (!mounted) return false;
    final goPremium = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Premium Özellik'),
        content: Text('$featureName premium aboneliğe özeldir. '
            'Şimdi premium aboneliğe geçmek ister misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Premium\'a Geç'),
          ),
        ],
      ),
    );
    if (goPremium == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PremiumScreen()),
      );
    }
    return false;
  }

  void _openAR() async {
    if (!await _requirePremium('AR (Artırılmış Gerçeklik)')) return;
    // ModelViewer'da `ar: true` zaten verili; kullanıcı AR butonunu modelin
    // sağ alt köşesinden açabilir. Burada bilgi mesajı gösteriyoruz.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Modelin sağ alt köşesindeki AR ikonuna dokun ve '
            'telefonu yere/masaya doğru tut.'),
      ),
    );
  }

  void _toggleCompare() async {
    if (widget.model.compareWithId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu model için karşılaştırma modeli henüz tanımlı değil.'),
        ),
      );
      return;
    }
    if (!await _requirePremium('Karşılaştırma Modu')) return;
    setState(() => _compareMode = !_compareMode);
  }

  void _openAIChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AICoachChatScreen()),
    );
  }

  void _generateQuestions() async {
    if (!await _requirePremium('AI ile Soru Üretme')) return;
    if (!mounted) return;
    // AICoachChatScreen'e yönlendir — kullanıcı orada konu adıyla soru üretme
    // isteği gönderebilir. Auto-prompt ileride eklenebilir.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${widget.model.name}" konusundan AI ile soru '
          'üretmek için sohbet ekranını aç ve sor.')),
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AICoachChatScreen()),
    );
  }

  String _hotspotsHtml() {
    final buf = StringBuffer();
    for (var i = 0; i < widget.model.parts.length; i++) {
      final p = widget.model.parts[i];
      // Quiz modunda isimleri gösterme
      final label = _quizMode ? '?' : p.name;
      buf.writeln(
        '<button class="Hotspot" slot="hotspot-${p.id}" '
        'data-position="${p.hotspotPosition}" '
        'data-normal="${p.hotspotNormal}" '
        'data-visibility-attribute="visible">'
        '<div class="HotspotAnnotation">$label</div>'
        '</button>',
      );
    }
    return buf.toString();
  }

  static const String _hotspotCss = '''
    .Hotspot {
      background: #ffffff;
      border: 2px solid #2196F3;
      border-radius: 50%;
      box-shadow: 0 2px 6px rgba(0,0,0,0.25);
      padding: 0;
      width: 24px;
      height: 24px;
      cursor: pointer;
    }
    .HotspotAnnotation {
      background: rgba(33,150,243,0.95);
      color: #fff;
      font-family: -apple-system,BlinkMacSystemFont,sans-serif;
      font-size: 11px;
      font-weight: 600;
      padding: 4px 8px;
      border-radius: 12px;
      position: absolute;
      transform: translate(8px, -100%);
      white-space: nowrap;
      pointer-events: none;
    }
  ''';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = widget.model;
    return Scaffold(
      appBar: AppBar(
        title: Text(m.name),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.view_in_ar),
            tooltip: 'AR\'da Görüntüle (Premium)',
            onPressed: _openAR,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(m, theme),
          _buildPartChips(m, theme),
          Expanded(
            child: Stack(
              children: [
                _buildModelArea(m),
                Positioned(
                  right: 8,
                  top: 8,
                  child: _buildToolbar(),
                ),
                if (_quizMode) _buildQuizOverlay(theme),
              ],
            ),
          ),
          _buildBottomPanel(theme),
        ],
      ),
    );
  }

  Widget _buildHeader(Topic3DModel m, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              m.subject,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              m.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartChips(Topic3DModel m, ThemeData theme) {
    return Container(
      height: 44,
      color: theme.colorScheme.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: m.parts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final p = m.parts[i];
          final isSelected = _selected?.id == p.id;
          return ChoiceChip(
            label: Text(p.name),
            selected: isSelected,
            onSelected: (_) => _selectPart(p),
            avatar: CircleAvatar(backgroundColor: p.color, radius: 6),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : null,
            ),
            selectedColor: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isSelected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildModelArea(Topic3DModel m) {
    final viewer = ModelViewer(
      src: m.glbUrl,
      alt: m.name,
      ar: true,
      arModes: const ['scene-viewer', 'webxr', 'quick-look'],
      autoRotate: !_quizMode && _selected == null,
      rotationPerSecond: '16deg',
      cameraControls: true,
      autoPlay: _animate && m.animationName != null,
      cameraTarget: _selected?.hotspotPosition,
      backgroundColor: const Color(0xFFF5F7FA),
      innerModelViewerHtml: _hotspotsHtml(),
      relatedCss: _hotspotCss,
      // Kesit alma için clipping aktif edilebilir (model_viewer "exposure"/
      // shadowIntensity ile basit görsel ipucu)
      exposure: _crossSection ? 0.6 : 1.0,
      shadowIntensity: _crossSection ? 0.0 : 1.0,
    );

    if (!_compareMode) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: viewer,
        ),
      );
    }

    // Karşılaştırma: bu model + compareWith model üst üste
    final compare = Topic3DRegistry.byId(m.compareWithId ?? '');
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: viewer,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: compare == null
                  ? const ColoredBox(color: Color(0xFFEEEEEE))
                  : ModelViewer(
                      src: compare.glbUrl,
                      alt: compare.name,
                      ar: false,
                      autoRotate: true,
                      cameraControls: true,
                      backgroundColor: const Color(0xFFEDF3EF),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          children: [
            _tbarBtn(Icons.refresh, 'Sıfırla', () {
              setState(() => _selected = null);
            }),
            if (widget.model.hasCrossSection)
              _tbarBtn(
                _crossSection ? Icons.layers_clear : Icons.layers,
                'Kesit',
                () => setState(() => _crossSection = !_crossSection),
                active: _crossSection,
              ),
            if (widget.model.animationName != null)
              _tbarBtn(
                _animate ? Icons.pause : Icons.play_arrow,
                'Animasyon',
                () => setState(() => _animate = !_animate),
                active: _animate,
              ),
            _tbarBtn(
              _quizMode ? Icons.school : Icons.quiz_outlined,
              'Quiz',
              _toggleQuizMode,
              active: _quizMode,
            ),
            if (widget.model.compareWithId != null)
              _tbarBtn(
                Icons.compare_arrows,
                'Karşılaştır',
                _toggleCompare,
                active: _compareMode,
              ),
            _tbarBtn(Icons.chat_bubble_outline, 'AI Sor', _openAIChat),
            _tbarBtn(Icons.auto_awesome, 'Soru Üret', _generateQuestions),
          ],
        ),
      ),
    );
  }

  Widget _tbarBtn(IconData icon, String label, VoidCallback onTap,
      {bool active = false}) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 42,
          height: 42,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: active ? Colors.blue.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon,
              size: 20, color: active ? Colors.blue.shade700 : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildQuizOverlay(ThemeData theme) {
    return Positioned(
      left: 8,
      top: 8,
      right: 60,
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.quiz, color: Colors.amber, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _quizTarget == null
                          ? 'Quiz hazırlanıyor…'
                          : '${_quizTarget!.name}'
                              ' nerede? Modelden seç.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    'Skor: $_quizScore / $_quizTotal',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
              if (_quizResult != null) ...[
                const SizedBox(height: 4),
                Text(_quizResult!,
                    style: const TextStyle(color: Colors.amber, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel(ThemeData theme) {
    final p = _selected;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: const BoxConstraints(minHeight: 110, maxHeight: 220),
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: const Offset(0, -2),
            blurRadius: 6,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: p == null
          ? Center(
              child: Text(
                'Yukarıdaki etiketlerden veya 3D model üstündeki '
                'noktalardan bir parça seç.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: p.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.info,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
