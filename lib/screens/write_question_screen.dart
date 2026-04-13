import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  WriteQuestionScreen — Sözlü Soru & MIUI Klavye
// ═══════════════════════════════════════════════════════════════════════════════

class WriteQuestionScreen extends StatefulWidget {
  const WriteQuestionScreen({super.key});
  @override
  State<WriteQuestionScreen> createState() => _WriteQuestionScreenState();
}

class _WriteQuestionScreenState extends State<WriteQuestionScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final List<_Msg> _messages = [
    const _Msg(
      text: 'Merhaba! 👋 Nasıl yardımcı olabilirim?\n\n'
          'Matematik, fizik, kimya, biyoloji, tarih, edebiyat veya herhangi bir konu hakkında soru sorabilirsin. '
          'Sana adım adım çözüm veya açıklama sunacağım.',
      isAI: true,
    ),
  ];

  bool _isSending = false;

  // ── Sözlü soru → AI yanıtı ───────────────────────────────────────────────────

  static const _responses = {
    'türev': '📐 **Türev Nedir?**\n\n'
        'Türev, bir fonksiyonun anlık değişim hızını ifade eder.\n\n'
        '**Temel Formül:**\n f\'(x) = lim(h→0) [f(x+h) - f(x)] / h\n\n'
        '**Kurallar:**\n'
        '• Üs kuralı: d/dx(xⁿ) = n·xⁿ⁻¹\n'
        '• Çarpım: (fg)\' = f\'g + fg\'\n'
        '• Zincir: (f∘g)\' = f\'(g(x))·g\'(x)\n\n'
        '**Örnek:** f(x) = 3x² → f\'(x) = 6x',

    'integral': '∫ **İntegral Nedir?**\n\n'
        'İntegral, türevin tersi işlemidir — eğrinin altındaki alanı hesaplar.\n\n'
        '**Temel Formül:**\n ∫xⁿ dx = xⁿ⁺¹/(n+1) + C\n\n'
        '**Kurallar:**\n'
        '• ∫sin(x)dx = -cos(x) + C\n'
        '• ∫cos(x)dx = sin(x) + C\n'
        '• ∫eˣdx = eˣ + C\n'
        '• ∫(1/x)dx = ln|x| + C\n\n'
        '**Örnek:** ∫(2x + 3)dx = x² + 3x + C',

    'newton': '⚡ **Newton\'un Hareket Yasaları**\n\n'
        '**1. Yasa (Eylemsizlik):** Üzerine net kuvvet etki etmeyen cisim durumunu korur.\n\n'
        '**2. Yasa (Kuvvet):** F = m × a\n'
        '→ Kuvvet = Kütle × İvme\n\n'
        '**3. Yasa (Etki-Tepki):** Her etkiye eşit ve zıt bir tepki vardır.\n\n'
        '**Birimler:**\n'
        '• Kuvvet: Newton (N) = kg·m/s²\n'
        '• Kütle: kg\n'
        '• İvme: m/s²',

    'enerji': '⚡ **Enerji Türleri ve Dönüşümü**\n\n'
        '**Kinetik Enerji:** Ek = ½mv²\n'
        '**Potansiyel Enerji:** Ep = mgh\n'
        '**Mekanik Enerji:** Em = Ek + Ep = sabit\n\n'
        '**Enerji Korunumu:**\n'
        'Kapalı sistemde toplam enerji sabittir.\n\n'
        '**İş-Enerji Teoremi:**\n'
        'W = ΔEk = Ek₂ - Ek₁',

    'mol': '🧪 **Mol Kavramı**\n\n'
        '1 mol = 6,022 × 10²³ tanecik (Avogadro sayısı)\n\n'
        '**Formüller:**\n'
        '• n = m / M (mol = kütle / molar kütle)\n'
        '• N = n × Nₐ (tanecik sayısı)\n'
        '• V = n × 22,4 L (STP\'de)\n\n'
        '**Örnek:** 36 g su (M=18)\n'
        '→ n = 36/18 = 2 mol su',

    'hücre': '🔬 **Hücre Bölünmesi**\n\n'
        '**Mitoz:**\n'
        '• Amaç: Büyüme, onarım\n'
        '• Sonuç: 2 diploid hücre (2n)\n'
        '• Evreler: Profaz → Metafaz → Anafaz → Telofaz\n\n'
        '**Mayoz:**\n'
        '• Amaç: Üreme hücresi üretimi\n'
        '• Sonuç: 4 haploid hücre (n)\n'
        '• Mayoz I + Mayoz II olmak üzere 2 aşama',

    'denklem': '📐 **İkinci Dereceden Denklem**\n\n'
        'ax² + bx + c = 0 formunda denklem.\n\n'
        '**Diskriminant:** Δ = b² - 4ac\n'
        '• Δ > 0 → İki gerçel kök\n'
        '• Δ = 0 → Bir çifte kök\n'
        '• Δ < 0 → Gerçel kök yok\n\n'
        '**Çözüm Formülü:**\n'
        'x = (-b ± √Δ) / 2a',

    'asit': '🧪 **Asit-Baz Kavramı**\n\n'
        '**Arrhenius Tanımı:**\n'
        '• Asit: H⁺ veren madde\n'
        '• Baz: OH⁻ veren madde\n\n'
        '**pH Ölçeği:** 0 - 14\n'
        '• pH < 7 → Asidik\n'
        '• pH = 7 → Nötr\n'
        '• pH > 7 → Bazik\n\n'
        '**Nötrleşme:** Asit + Baz → Tuz + Su\n'
        'H₂SO₄ + 2NaOH → Na₂SO₄ + 2H₂O',

    'osmanlı': '📚 **Osmanlı Devleti**\n\n'
        '**Kuruluş:** 1299 – Osman Bey\n'
        '**Yıkılış:** 1922 – Türkiye Cumhuriyeti\'nin ilanıyla\n\n'
        '**Önemli Padişahlar:**\n'
        '• Fatih Sultan Mehmet (İstanbul\'un Fethi, 1453)\n'
        '• Yavuz Sultan Selim (Mısır\'ın alınması)\n'
        '• Kanuni Sultan Süleyman (En geniş sınırlar)\n\n'
        '**En Uzun Süren Hanedan:** 623 yıl',

    'edebiyat': '📖 **Türk Edebiyatı Dönemleri**\n\n'
        '**İslam Öncesi:** Sözlü gelenek, koşuk ve sagular\n'
        '**Divan Edebiyatı:** Arap-Fars etkisi, gazel-kaside\n'
        '**Tanzimat (1860):** Şinasi, Namık Kemal, Ziya Paşa\n'
        '**Servet-i Fünun:** Tevfik Fikret, Halit Ziya\n'
        '**Cumhuriyet:** Nazım Hikmet, Orhan Veli, Yaşar Kemal',
  };

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_Msg(text: text, isAI: false));
      _isSending = true;
    });
    _ctrl.clear();
    _scrollDown();

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg(text: _getResponse(text), isAI: true));
        _isSending = false;
      });
      _scrollDown();
    });
  }

  String _getResponse(String q) {
    final lower = q.toLowerCase();
    for (final entry in _responses.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    if (lower.contains('merhaba') || lower.contains('selam')) {
      return 'Merhaba! 😊 Hangi konuda yardımcı olmamı istersin? Matematiğin herhangi bir konusunu, fen bilimlerini veya sosyal bilimleri sorabilirsin.';
    }
    if (lower.contains('nasıl') && lower.contains('çal')) {
      return 'Sana şu şekilde yardımcı olabilirim:\n\n• Konu açıklaması\n• Adım adım çözüm\n• Formüller ve kurallar\n• Örnek sorular\n\nHerhangi bir konu veya soru türünü yazabilirsin!';
    }
    return '🤔 Sorunuzu anlamaya çalışıyorum...\n\n'
        'Daha spesifik bir konu veya soru yazarsan daha iyi yardımcı olabilirim. Örneğin:\n'
        '• "Türev nasıl alınır?"\n'
        '• "Newton\'un yasaları nelerdir?"\n'
        '• "Mol hesabı nasıl yapılır?"\n\n'
        'Hangi konuyu öğrenmek istiyorsun?';
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(child: _buildMessages()),
          _buildInputRow(),
          _MiuiKeyboard(
            controller: _ctrl,
            onSend: _send,
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 10),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: AppColors.cyan.withValues(alpha: 0.12))),
        ),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.cyan),
            onPressed: () => Navigator.pop(context),
          ),
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF0070FF)]),
              boxShadow: [BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.30), blurRadius: 8)],
            ),
            child: const Icon(Icons.psychology_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Soruyu Yaz',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            Text('Sözlü soru & AI çözüm',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ]),
        ]),
      );

  Widget _buildMessages() => ListView.builder(
        controller: _scrollCtrl,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        itemCount: _messages.length + (_isSending ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _messages.length) return _typingDots();
          return _MsgBubble(msg: _messages[i]);
        },
      );

  Widget _buildInputRow() => Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        color: const Color(0xFF111118),
        child: Row(children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 38, maxHeight: 90),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C28),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.28)),
              ),
              child: TextField(
                controller: _ctrl,
                readOnly: true,   // sistem klavye açılmıyor
                showCursor: true,
                maxLines: null,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                decoration: const InputDecoration(
                  hintText: 'Sorunuzu yazın...',
                  hintStyle: TextStyle(
                      color: Color(0xFF4A4A68), fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF0070FF)]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.30),
                    blurRadius: 8)],
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.black87, size: 18),
            ),
          ),
        ]),
      );

  Widget _typingDots() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18), topRight: Radius.circular(18),
              bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4),
            ),
            border: Border.all(color: AppColors.cyan.withValues(alpha: 0.15)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (int i = 0; i < 3; i++)
              _Dot(delay: Duration(milliseconds: i * 200)),
          ]),
        ),
      );
}

// ─── Mesaj balonu ─────────────────────────────────────────────────────────────

class _MsgBubble extends StatelessWidget {
  final _Msg msg;
  const _MsgBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: msg.isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.80),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: msg.isAI
              ? null
              : const LinearGradient(
                  colors: [AppColors.cyan, Color(0xFF0070FF)]),
          color: msg.isAI ? AppColors.surface : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(msg.isAI ? 4 : 18),
            bottomRight: Radius.circular(msg.isAI ? 18 : 4),
          ),
          border: msg.isAI
              ? Border.all(color: AppColors.cyan.withValues(alpha: 0.16))
              : null,
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: msg.isAI ? Colors.white : Colors.black87,
            fontSize: 13,
            height: 1.55,
          ),
        ),
      ),
    );
  }
}

// ─── Animasyonlu nokta ────────────────────────────────────────────────────────

class _Dot extends StatefulWidget {
  final Duration delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    Future.delayed(widget.delay, () { if (mounted) _c.forward(); });
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Opacity(
            opacity: 0.3 + _c.value * 0.7,
            child: Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(
                  color: AppColors.cyan, shape: BoxShape.circle),
            ),
          ),
        ),
      );
}

// ─── Mesaj modeli ─────────────────────────────────────────────────────────────

class _Msg {
  final String text;
  final bool isAI;
  const _Msg({required this.text, required this.isAI});
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MIUI (Redmi 12 Pro) Klavye
// ═══════════════════════════════════════════════════════════════════════════════

class _MiuiKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;

  const _MiuiKeyboard({
    required this.controller,
    required this.onSend,
    required this.onChanged,
  });

  @override
  State<_MiuiKeyboard> createState() => _MiuiKeyboardState();
}

class _MiuiKeyboardState extends State<_MiuiKeyboard> {
  bool _shifted = false;
  bool _capsLock = false;
  bool _numMode = false;

  // ── Türkçe Q klavye ───────────────────────────────────────────────────────────

  static const _row1 = ['q','w','e','r','t','y','u','ı','o','p'];
  static const _row2 = ['a','s','d','f','g','h','j','k','l'];
  static const _row3 = ['z','x','c','v','b','n','m'];

  static const _num1 = ['1','2','3','4','5','6','7','8','9','0'];
  static const _num2 = ['-','/',':', ';','(',')',  '₺','&','@','"'];
  static const _num3 = ['.',',','?','!','\'','#','%','^','*','+'];

  // Özel Türkçe karakter satırı
  static const _trChars = ['ğ','ü','ş','ö','ç','â','î','û','é'];

  bool get _effectiveShift => _shifted || _capsLock;

  void _tapLetter(String c) {
    HapticFeedback.selectionClick();
    final out = _effectiveShift ? c.toUpperCase() : c;
    _insert(out);
    if (_shifted && !_capsLock) setState(() => _shifted = false);
  }

  void _insert(String s) {
    final ctrl = widget.controller;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end   = sel.isValid ? sel.end   : text.length;
    final newText = text.replaceRange(start, end, s);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + s.length),
    );
    widget.onChanged(newText);
  }

  void _backspace() {
    HapticFeedback.selectionClick();
    final ctrl = widget.controller;
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (text.isEmpty) return;
    final pos = sel.isValid && sel.start > 0 ? sel.start : text.length;
    if (pos == 0) return;
    // Handle multi-byte chars (emoji etc.)
    final newText = text.characters.toList()
      ..removeAt(text.characters.toList().length - (text.length - pos + 1));
    final nt = text.replaceRange(pos - 1, pos, '');
    ctrl.value = TextEditingValue(
      text: nt,
      selection: TextSelection.collapsed(offset: pos - 1),
    );
    widget.onChanged(nt);
  }

  void _shiftTap() {
    HapticFeedback.selectionClick();
    if (_capsLock) {
      setState(() { _capsLock = false; _shifted = false; });
    } else if (_shifted) {
      setState(() { _capsLock = true; });
    } else {
      setState(() => _shifted = true);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF191922),
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Türkçe karakter barı
        _trCharBar(),
        const SizedBox(height: 4),
        if (_numMode) ...[
          _numKeyRow(_num1),
          _numKeyRow(_num2),
          _numKeyRow(_num3),
        ] else ...[
          _letterRow(_row1),
          _letterRow(_row2, center: true),
          _row3WithSpecials(),
        ],
        const SizedBox(height: 4),
        _bottomRow(),
      ]),
    );
  }

  // Türkçe ek karakterler barı
  Widget _trCharBar() => SizedBox(
        height: 32,
        child: Row(
          children: [
            ..._trChars.map((c) => _TrChar(
                  char: _effectiveShift && !_numMode ? c.toUpperCase() : c,
                  onTap: () => _tapLetter(c),
                )),
            const Spacer(),
            _TrChar(char: '↑', onTap: () {}, isAction: true),
          ],
        ),
      );

  Widget _letterRow(List<String> keys, {bool center = false}) {
    final widgets = keys.map((k) => _KeyBtn(
          label: _effectiveShift ? k.toUpperCase() : k,
          onTap: () => _tapLetter(k),
          flex: 1,
        )).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment:
            center ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (center) const SizedBox(width: 20),
          ...widgets,
          if (center) const SizedBox(width: 20),
        ],
      ),
    );
  }

  Widget _row3WithSpecials() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          // Shift
          _SpecialBtn(
            width: 42,
            onTap: _shiftTap,
            onDoubleTap: () => setState(() { _capsLock = true; _shifted = true; }),
            child: Icon(
              _capsLock
                  ? Icons.keyboard_capslock_rounded
                  : _shifted
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_up_rounded,
              color: (_shifted || _capsLock) ? AppColors.cyan : Colors.white70,
              size: 18,
            ),
          ),
          const SizedBox(width: 4),
          ..._row3.map((k) => _KeyBtn(
                label: _effectiveShift ? k.toUpperCase() : k,
                onTap: () => _tapLetter(k),
                flex: 1,
              )),
          const SizedBox(width: 4),
          // Backspace
          _SpecialBtn(
            width: 42,
            onTap: _backspace,
            onLongPress: () {
              // Hepsi sil
              widget.controller.clear();
              widget.onChanged('');
            },
            child: const Icon(Icons.backspace_outlined,
                color: Colors.white70, size: 18),
          ),
        ]),
      );

  Widget _numKeyRow(List<String> keys) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: keys
              .map((k) => _KeyBtn(label: k, onTap: () => _insert(k), flex: 1))
              .toList(),
        ),
      );

  Widget _bottomRow() => Row(children: [
        // ?123 / ABC
        _SpecialBtn(
          width: 58,
          onTap: () => setState(() => _numMode = !_numMode),
          child: Text(
            _numMode ? 'ABC' : '?123',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 4),
        // Boşluk
        Expanded(
          child: GestureDetector(
            onTap: () => _insert(' '),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF2E2E3E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: const Center(
                child: Text('boşluk',
                    style: TextStyle(
                        color: Color(0xFF888899),
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Gönder
        _SpecialBtn(
          width: 58,
          onTap: widget.onSend,
          color: AppColors.cyan.withValues(alpha: 0.18),
          borderColor: AppColors.cyan.withValues(alpha: 0.45),
          child: const Icon(Icons.send_rounded, color: AppColors.cyan, size: 18),
        ),
      ]);
}

// ─── Tuş widget'ları ──────────────────────────────────────────────────────────

class _KeyBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final int flex;

  const _KeyBtn({required this.label, required this.onTap, this.flex = 1});

  @override
  State<_KeyBtn> createState() => _KeyBtnState();
}

class _KeyBtnState extends State<_KeyBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: widget.flex,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          decoration: BoxDecoration(
            color: _pressed ? const Color(0xFF464658) : const Color(0xFF2B2B3A),
            borderRadius: BorderRadius.circular(7),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                offset: const Offset(0, 1),
                blurRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecialBtn extends StatefulWidget {
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final Widget child;
  final Color? color;
  final Color? borderColor;

  const _SpecialBtn({
    required this.width,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.onDoubleTap,
    this.color,
    this.borderColor,
  });

  @override
  State<_SpecialBtn> createState() => _SpecialBtnState();
}

class _SpecialBtnState extends State<_SpecialBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      onLongPress: widget.onLongPress,
      onDoubleTap: widget.onDoubleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.width,
        height: 42,
        decoration: BoxDecoration(
          color: _pressed
              ? const Color(0xFF3A3A4C)
              : widget.color ?? const Color(0xFF222230),
          borderRadius: BorderRadius.circular(7),
          border: widget.borderColor != null
              ? Border.all(color: widget.borderColor!)
              : Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              offset: const Offset(0, 1),
              blurRadius: 1,
            ),
          ],
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _TrChar extends StatelessWidget {
  final String char;
  final VoidCallback onTap;
  final bool isAction;

  const _TrChar({required this.char, required this.onTap, this.isAction = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isAction
              ? const Color(0xFF222230)
              : const Color(0xFF252533),
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(
          char,
          style: TextStyle(
            color: isAction ? AppColors.cyan : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
