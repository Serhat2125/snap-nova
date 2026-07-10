import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart' show localeService;
import '../services/gemini_service.dart';
import '../services/runtime_translator.dart';
import 'ai_result_screen.dart';

import '../features/calculator/calc_engine.dart';
import '../theme/app_theme.dart';
// ═══════════════════════════════════════════════════════════════════════════════
//  CalculatorScreen — Yeni tasarım (Qanda tarzı)
//  • Üst: problem girişi (dotted underline)
//  • Alt: özel klavye
//     - Üst satır: abc sekmesi + geçmiş/←/→/⏎/⌫
//     - Orta satır: 4 kategori pill (+/-, f(x)/log, sin/cos, lim/∫)
//     - Alt: seçili sekmenin içeriği (grid)
// ═══════════════════════════════════════════════════════════════════════════════

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

enum _Tab { abc, ops, funcs, trig, calc }

class _CalculatorScreenState extends State<CalculatorScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  _Tab _tab = _Tab.abc;
  String _result = '';
  bool _solving = false;
  bool _isRad = false; // açı birimi: false = derece (varsayılan), true = radyan
  final List<String> _history = [];
  static const _cursorGreen = Color(0xFF22C55E);
  static const _cursorOrange = Color(0xFFFF6A00);
  static const _btnBlue = Color(0xFF2563EB);
  static const _placeholder = '□';


  /// Long-press alternatiflerinde görünen etiket → gerçekte eklenecek şablon.
  /// (Etiket ham eklenirse motor ayrıştıramıyordu: 'ⁿ√' gibi.)
  static const _altTemplates = <String, String>{
    'ⁿ√': '√[□](□)',
    '∛': '∛(□)',
    '∜': '∜(□)',
    '{}': '{□}',
    '[]': '[□]',
  };

  // Tema-duyarlı yüzeyler — koyu temada da doğru görünsün (eskiden sabit
  // beyaz/gri değerlerdi, koyu temada klavye beyaz yama gibi kalıyordu).
  Color get _keyBg => AppPalette.card(context);
  Color get _borderColor => AppPalette.border(context);
  Color get _tabSelected => AppPalette.cardMuted(context);

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_evaluate);
  }

  @override
  void dispose() {
    _altOverlay?.remove();
    _altOverlay = null;
    _ctrl.removeListener(_evaluate);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Bake tarayıcısı kayıtları — CalcEquationSolver'ın SABİT sonuç metinleri.
  // Sonuç pill'i bunları `_result.tr()` ile DİNAMİK çevirir; bake tarayıcısı
  // yalnız literal '...'.tr() gördüğü için burada literal olarak da geçmeleri
  // gerekir, yoksa 55 dile bake edilmezler.
  // ignore: unused_element
  static List<String> _solverPhraseKeysForBake() => [
        'Her değer için doğru'.tr(),
        'Çözüm yok'.tr(),
        'Doğru'.tr(),
        'Yanlış'.tr(),
        'Gerçek çözüm yok'.tr(),
      ];

  // ── Canlı sonuç hesaplama — her metin değişikliğinde UI yenilensin ────────
  void _evaluate() {
    if (!mounted) return;
    setState(() {
      // Çok satırlı girişte SON dolu satır değerlendirilir (⏎ yeni ifade
      // başlatır) — eskiden satırlar birleşip yanlış sonuç üretiyordu:
      // "2+2⏎3+3" → "2+23+3" = 28 gibi.
      final lines = _ctrl.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final text = lines.isEmpty ? '' : lines.last;
      if (text.isEmpty || text.contains(_placeholder)) {
        _result = '';
        return;
      }
      // Karşılaştırma operatörü var mı? → denklem / eşitsizlik olarak çöz
      if (text.contains(RegExp(r'[<>=≤≥≠]'))) {
        final solved = CalcEquationSolver.solve(text, isDeg: !_isRad);
        _result = solved ?? '';
        return;
      }
      // Düz ifade
      try {
        final v = CalcEvaluator().eval(text, isDeg: !_isRad);
        _result = (v.isNaN || v.isInfinite) ? '' : _fmt(v);
      } catch (_) {
        _result = '';
      }
    });
  }

  String _fmt(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e13) {
      return v.toInt().toString();
    }
    // Çok büyük/küçük değerler bilimsel gösterimle (20! gibi)
    if (v.abs() >= 1e13 || (v != 0 && v.abs() < 1e-8)) {
      var s = v.toStringAsExponential(6);
      s = s.replaceFirst(RegExp(r'\.?0+e'), 'e');
      return s;
    }
    var s = v.toStringAsFixed(8);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  void _clearAll() {
    _ctrl.clear();
    setState(() => _result = '');
  }

  void _commitEnter() {
    // Önce sıradaki placeholder'a atla
    if (_jumpToNextPlaceholder()) return;
    // Yoksa geçmişe kaydet + yeni satır
    final t = _ctrl.text.trim();
    if (t.isNotEmpty &&
        (_history.isEmpty || _history.first != t)) {
      _history.insert(0, t);
      if (_history.length > 50) _history.removeLast();
    }
    _insert('\n');
  }

  // ── Yapay zeka ile çöz ─────────────────────────────────────────────────────
  Future<void> _solveWithAi() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _solving) return;
    setState(() => _solving = true);
    try {
      final res = await GeminiService.solveHomework(
        question: q,
        solutionType: 'Adım Adım Çöz',
        subject: 'Matematik',
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AiResultScreen(
            result: res,
            imagePath: '',
            solutionType: 'Adım Adım Çöz',
            modelName: 'QuAlsar',
          ),
        ),
      );
    } on GeminiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.userMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'Hata'.tr()}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _solving = false);
    }
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.6,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'Geçmiş'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Spacer(),
                      if (_history.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(_history.clear);
                            Navigator.pop(ctx);
                          },
                          child: Text('Temizle'.tr()),
                        ),
                    ],
                  ),
                  Divider(),
                  Expanded(
                    child: _history.isEmpty
                        ? Center(
                            child: Text(
                              'Geçmiş boş'.tr(),
                              style: GoogleFonts.poppins(
                                  color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _history.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 10),
                            itemBuilder: (_, i) {
                              final h = _history[i];
                              return ListTile(
                                title: Text(
                                  h,
                                  style: GoogleFonts.poppins(fontSize: 16),
                                ),
                                onTap: () {
                                  _ctrl.text = h;
                                  _ctrl.selection = TextSelection.collapsed(
                                      offset: h.length);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Girdi işlemleri ────────────────────────────────────────────────────────
  // Imleç bir □ üzerindeyse: □'yi s ile değiştir. s'de □ varsa imleci ilk □'ye koy.
  // Normal durumda: s'yi imleçe ekle. s'de □ varsa imleci ilk □'ye koy.
  void _insert(String s, {int cursorBack = 0}) {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;

    final onPlaceholder = start == end &&
        start < text.length &&
        text[start] == _placeholder &&
        !s.contains('\n');

    String newText;
    int cursorPos;

    if (onPlaceholder && cursorBack == 0) {
      // □'yi s ile değiştir
      newText = text.replaceRange(start, start + 1, s);
      final idx = s.indexOf(_placeholder);
      if (idx >= 0) {
        cursorPos = start + idx;
      } else {
        // Yeni şablonda □ yoksa, metindeki bir sonraki □'ye otomatik atla
        final next = newText.indexOf(_placeholder, start + s.length);
        cursorPos = next >= 0 ? next : start + s.length;
      }
    } else {
      newText = text.replaceRange(start, end, s);
      final idx = s.indexOf(_placeholder);
      if (cursorBack > 0) {
        cursorPos = start + s.length - cursorBack;
      } else if (idx >= 0) {
        cursorPos = start + idx;
      } else {
        cursorPos = start + s.length;
      }
    }

    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorPos),
    );
  }


  // Sonraki placeholder'a atla (Tab davranışı)
  bool _jumpToNextPlaceholder() {
    final text = _ctrl.text;
    final sel = _ctrl.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final next = text.indexOf(_placeholder, start);
    if (next < 0) return false;
    _ctrl.selection = TextSelection.collapsed(offset: next);
    return true;
  }

  void _backspace() {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    if (text.isEmpty) return;
    if (sel.start != sel.end && sel.start >= 0) {
      final newText = text.replaceRange(sel.start, sel.end, '');
      _ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start),
      );
      return;
    }
    final cursor = sel.start < 0 ? text.length : sel.start;
    if (cursor == 0) return;
    final newText = text.replaceRange(cursor - 1, cursor, '');
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor - 1),
    );
  }

  void _moveCursor(int delta) {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final cursor = sel.start < 0 ? text.length : sel.start;
    final next = (cursor + delta).clamp(0, text.length);
    _ctrl.selection = TextSelection.collapsed(offset: next);
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.card(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: AppPalette.textPrimary(context), size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Hesap makinesi'.tr(),
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppPalette.textPrimary(context),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLatexPreview(),
                  if (_result.isNotEmpty) _buildResultPill(),
                  Spacer(),
                  if (_ctrl.text.isNotEmpty) _buildActionRow(),
                ],
              ),
            ),
            _buildKeyboardPanel(),
          ],
        ),
      ),
    );
  }

  // ── LaTeX görsel önizleme ──────────────────────────────────────────────────
  // Metin TEK parça render edilir; imleç, LaTeX içine gömülü turuncu karet
  // (□ üstündeyse vurgulu kutu) olarak gösterilir. Eskiden metin imleçten
  // ikiye bölünüp iki ayrı parça render ediliyordu — imleç lim/∫/kesir gibi
  // bir şablonun İÇİNDEYKEN desen regex'leri eşleşemiyor, limit Photomath'taki
  // gibi "lim altında a→b⁺" yerine düz "lim_( □ → □⁺)(□)" görünüyordu.
  Widget _buildLatexPreview() {
    final text = _ctrl.text;
    final isEmpty = text.trim().isEmpty;

    // İmleç konumunu güvenli sınırlara çek
    var cursorPos = _ctrl.selection.start;
    if (cursorPos < 0 || cursorPos > text.length) cursorPos = text.length;

    final marked = text.replaceRange(cursorPos, cursorPos, calcCaretMark);
    final lines = marked.split('\n');

    return GestureDetector(
      onTap: () {
        // Boş alanda tıklayınca: bir sonraki □'ye atla (varsa)
        final t = _ctrl.text;
        if (!t.contains(_placeholder)) return;
        final cur = _ctrl.selection.start < 0 ? 0 : _ctrl.selection.start;
        var next = t.indexOf(_placeholder, cur + 1);
        if (next < 0) next = t.indexOf(_placeholder);
        if (next >= 0) {
          setState(() {
            _ctrl.selection = TextSelection.collapsed(offset: next);
          });
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
        constraints: BoxConstraints(minHeight: 56),
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: isEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _BlinkingCursor(
                      color: _cursorOrange,
                      width: 2.5,
                      height: 30,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Bir sayısal soru girin...'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines)
                      if (line.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: _renderLatexSegment(line),
                        ),
                  ],
                ),
        ),
      ),
    );
  }

  // Tek bir metin parçasını LaTeX olarak render et; hatalıysa düz metne düş
  Widget _renderLatexSegment(String segment) {
    final latex = calcToLatex(segment);
    return Math.tex(
      latex,
      textStyle: TextStyle(
        fontSize: 28,
        color: AppPalette.textPrimary(context),
      ),
      onErrorFallback: (_) => Text(
        segment.replaceAll(calcCaretMark, '|'),
        style: GoogleFonts.poppins(
          fontSize: 24,
          color: AppPalette.textPrimary(context),
        ),
      ),
    );
  }

  // ── Sonuç: yeşil pill, sorunun altında ─────────────────────────────────────
  Widget _buildResultPill() {
    // Denklem sonucu ("x < 6", "y₁ = -2 ..." gibi) ise "=" öneki yok;
    // sayı ise "=" ekle
    final isTextResult = RegExp(r'^([a-zA-ZαβθρφΦω][₁₂]? |Her |Çözüm|Doğru|Yanlış|Gerçek)')
        .hasMatch(_result);
    // Sabit metin sonuçları ("Her değer için doğru" / "Çözüm yok" / "Doğru")
    // çevrilir; dinamik "x < 6" gibi denklem sonuçları matematik notasyonu
    // olduğu için .tr() kaydına (gereksiz benzersiz string) sokulmaz.
    final isFixedPhrase =
        RegExp(r'^(Her |Çözüm|Doğru|Yanlış|Gerçek)').hasMatch(_result);
    final display =
        isTextResult ? (isFixedPhrase ? _result.tr() : _result) : '= $_result';
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 0),
      child: GestureDetector(
        onTap: () {
          if (isTextResult) return;
          _ctrl.text = _result;
          _ctrl.selection =
              TextSelection.collapsed(offset: _result.length);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _cursorGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _cursorGreen, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded,
                  color: _cursorGreen, size: 16),
              SizedBox(width: 6),
              Text(
                display,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _cursorGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Alt butonlar: [Ekranı Temizle]   [Çözümü Göster] ───────────────────────
  Widget _buildActionRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _pillButton(
            label: localeService.tr('clear_screen'),
            onTap: _clearAll,
            color: _btnBlue,
          ),
          _pillButton(
            label: _solving ? localeService.tr('solving') : localeService.tr('show_solution_btn'),
            onTap: _solving ? null : _solveWithAi,
            color: Color(0xFFFF6A00),
            filled: true,
          ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required VoidCallback? onTap,
    required Color color,
    bool filled = false,
  }) {
    final bg = filled ? color : AppPalette.card(context);
    final fg = filled ? Colors.white : color;
    return Material(
      color: bg,
      elevation: filled ? 1 : 0,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: 150,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color, width: 1.3),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }


  // ── Alt klavye paneli ──────────────────────────────────────────────────────
  Widget _buildKeyboardPanel() {
    return Container(
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        border: Border(
          top: BorderSide(color: _borderColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _topNavRow(),
          SizedBox(height: 12),
          _categoryPills(),
          SizedBox(height: 10),
          _tabContent(),
        ],
      ),
    );
  }

  // ── Üst satır: abc + nav ikonları (eşit aralıklı) ──────────────────────────
  Widget _topNavRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _abcTab(),
        _navIcon(icon: Icons.schedule_rounded, onTap: _showHistory),
        _navIcon(icon: Icons.arrow_back_rounded, onTap: () => _moveCursor(-1)),
        _navIcon(
            icon: Icons.arrow_forward_rounded, onTap: () => _moveCursor(1)),
        _navIcon(icon: Icons.keyboard_return_rounded, onTap: _commitEnter),
        _backspaceButton(),
      ],
    );
  }

  Widget _backspaceButton() {
    return GestureDetector(
      onTap: _backspace,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppPalette.border(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Icon(
          Icons.backspace_outlined,
          size: 26,
          color: AppPalette.textPrimary(context),
        ),
      ),
    );
  }

  Widget _abcTab() {
    final selected = _tab == _Tab.abc;
    return GestureDetector(
      onTap: () => setState(() => _tab = _Tab.abc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _tabSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'abc',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: AppPalette.textPrimary(context),
          ),
        ),
      ),
    );
  }

  Widget _navIcon({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 24, color: AppPalette.textPrimary(context)),
      ),
    );
  }

  // ── Kategori pill satırı ───────────────────────────────────────────────────
  Widget _categoryPills() {
    return Row(
      children: [
        Expanded(
          child: _pill(
            tab: _Tab.ops,
            topLeft: '+',
            topRight: '−',
            bottomLeft: '×',
            bottomRight: '÷',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _pill(
            tab: _Tab.funcs,
            topLeft: 'f(x)',
            topRight: 'e',
            bottomLeft: 'log',
            bottomRight: 'ln',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _pill(
            tab: _Tab.trig,
            topLeft: 'sin',
            topRight: 'cos',
            bottomLeft: 'tan',
            bottomRight: 'cot',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _pill(
            tab: _Tab.calc,
            topLeft: 'lim',
            topRight: 'dx',
            bottomLeft: '∫',
            bottomRight: 'Σ ∞',
          ),
        ),
      ],
    );
  }

  Widget _pill({
    required _Tab tab,
    required String topLeft,
    required String topRight,
    required String bottomLeft,
    required String bottomRight,
  }) {
    final selected = _tab == tab;
    // Seçili pill: metin/zemin tersine döner (koyu temada beyaz pill +
    // koyu yazı) — her iki temada yüksek kontrast.
    final bg = selected ? AppPalette.textPrimary(context) : AppPalette.card(context);
    final fg = selected ? AppPalette.bg(context) : AppPalette.textPrimary(context);
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: selected ? AppPalette.textPrimary(context) : _borderColor,
              width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _pillText(topLeft, fg),
                SizedBox(width: 5),
                _pillText(topRight, fg),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _pillText(bottomLeft, fg),
                SizedBox(width: 5),
                _pillText(bottomRight, fg),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillText(String text, Color color) => Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
          height: 1.2,
        ),
      );

  // ── Seçili sekmenin içeriği ────────────────────────────────────────────────
  Widget _tabContent() {
    switch (_tab) {
      case _Tab.abc:
        return _abcGrid();
      case _Tab.ops:
        return _opsGrid();
      case _Tab.funcs:
        return _funcsGrid();
      case _Tab.trig:
        return _trigGrid();
      case _Tab.calc:
        return _calcGrid();
    }
  }

  // ── abc klavyesi: 8 sütunlu grid (a-z) + son satır (y z α β θ ρ Φ) ─────────
  Widget _abcGrid() {
    const keys = [
      ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
      ['i', 'j', 'k', 'l', 'm', 'n', 'o', 'p'],
      ['q', 'r', 's', 't', 'u', 'v', 'w', 'x'],
      ['y', 'z', 'α', 'β', 'θ', 'ρ', 'Φ', ''],
    ];
    return Column(
      children: keys
          .map((row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: row
                      .map((k) => Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: k.isEmpty
                                  ? SizedBox(height: 56)
                                  : _gridKey(k),
                            ),
                          ))
                      .toList(),
                ),
              ))
          .toList(),
    );
  }

  Widget _gridKey(String label) {
    return Material(
      color: _keyBg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _insert(label),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _borderColor, width: 1),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: AppPalette.textPrimary(context),
            ),
          ),
        ),
      ),
    );
  }

  // ── İşlem sekmesi (6x4 grid) ───────────────────────────────────────────────
  // Sol 2 sütun: şablon tuşları (beyaz, kırmızı nokta → long-press alternatifleri)
  // Orta 3 sütun: sayı tuşları (açık gri)
  // Sağ 1 sütun: operatörler (beyaz)
  Widget _opsGrid() {
    final rows = <List<_OpCell>>[
      [
        _OpCell.tpl('(□)',
            onTap: () => _insert('(□)'),
            alts: const ['(', ')', '{}', '[]']),
        _OpCell.tpl('>',
            onTap: () => _insert('>'),
            alts: const ['≥', '<', '≤', '≠']),
        _OpCell.num('7'),
        _OpCell.num('8'),
        _OpCell.num('9'),
        _OpCell.op('÷', value: '÷'),
      ],
      [
        _OpCell.frac(
            onTap: () => _insert('□/□'),
            alts: const ['½', '¼', '¾', '⅓']),
        _OpCell.sqrtTpl(
            onTap: () => _insert('√(□)'),
            alts: const ['∛', '∜', 'ⁿ√']),
        _OpCell.num('4'),
        _OpCell.num('5'),
        _OpCell.num('6'),
        _OpCell.op('×', value: '*'),
      ],
      [
        _OpCell.sqTpl(
            onTap: () => _insert('^2'),
            alts: const ['^3', '^n', '^(-1)']),
        _OpCell.tpl('x',
            onTap: () => _insert('x'),
            alts: const ['y', 'z', 't', 'θ', 'α']),
        _OpCell.num('1'),
        _OpCell.num('2'),
        _OpCell.num('3'),
        _OpCell.op('−', value: '-'),
      ],
      [
        _OpCell.tpl('π',
            onTap: () => _insert('π'),
            alts: const ['π/2', 'π/3', 'π/4']),
        _OpCell.tpl('%',
            onTap: () => _insert('%'),
            alts: const ['‰', '°']),
        _OpCell.num('0'),
        _OpCell.num(','),
        _OpCell.num('='),
        _OpCell.op('+', value: '+'),
      ],
    ];
    return Column(
      children: rows
          .map((row) => Row(
                children: row
                    .map((c) => Expanded(child: _opKey(c)))
                    .toList(),
              ))
          .toList(),
    );
  }

  Widget _opKey(_OpCell c) {
    Color bg;
    switch (c.kind) {
      case _OpKind.num:
        bg = AppPalette.cardMuted(context);
        break;
      case _OpKind.op:
      case _OpKind.tpl:
        bg = AppPalette.card(context);
        break;
    }
    final key = GlobalKey();
    final hasAlts = c.alts.isNotEmpty;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (c.kind == _OpKind.num) {
          _insert(c.label);
        } else if (c.kind == _OpKind.op) {
          _insert(c.value!);
        } else {
          c.onTap?.call();
        }
      },
      onLongPress: hasAlts ? () => _showAltPopup(key, c.alts) : null,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: _borderColor, width: 0.6),
        ),
        child: Stack(
          children: [
            Center(
              child: c.child ??
                  Text(
                    c.label,
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
            ),
            if (hasAlts)
              Positioned(
                left: 2,
                right: 2,
                bottom: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    c.alts.join(' '),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE11D48),
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Long-press alternatif karakter popup'ı ──────────────────────────────────
  OverlayEntry? _altOverlay;

  void _showAltPopup(GlobalKey anchorKey, List<String> alts) {
    _altOverlay?.remove();
    final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;

    final screenW = MediaQuery.of(context).size.width;
    const itemW = 56.0;
    const itemH = 54.0;
    final totalW = itemW * alts.length + 8;
    var left = offset.dx + size.width / 2 - totalW / 2;
    if (left < 8) left = 8;
    if (left + totalW > screenW - 8) left = screenW - totalW - 8;
    final top = offset.dy - itemH - 10;

    _altOverlay = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissAlt,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(14),
              color: AppPalette.card(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: alts.map((s) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        // Etiket ≠ eklenecek metin olabilir (ⁿ√ → √[□](□))
                        _insert(_altTemplates[s] ?? s);
                        _dismissAlt();
                      },
                      child: Container(
                        width: itemW,
                        height: itemH,
                        alignment: Alignment.center,
                        child: Text(
                          s,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.textPrimary(context),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_altOverlay!);
  }

  void _dismissAlt() {
    _altOverlay?.remove();
    _altOverlay = null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Fonksiyon sekmesi (6x4 grid — tamamı beyaz, şablon/metin)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _funcsGrid() {
    final rows = <List<Widget>>[
      [
        _fnCell(const _AbsGlyph(),
            onTap: () => _insert('|□|')),
        _fnCellText('f(x)', onTap: () => _insert('f(□)')),
        _fnCellText('log₁₀', onTap: () => _insert('log(□)')),
        _fnCell(const _NRootGlyph(),
            onTap: () => _insert('√[□](□)')),
        _fnCellText('i', onTap: () => _insert('i')),
        _fnCell(const _ListGlyph(),
            onTap: () => _insert('□,□,□')),
      ],
      [
        _fnCell(const _SubGlyph(),
            onTap: () => _insert('□_□')),
        _fnCell(const _FxCallGlyph(),
            onTap: () => _insert('□(□)')),
        _fnCellText('log₂', onTap: () => _insert('logb(2,□)')),
        _fnCell(const _NPrGlyph(),
            onTap: () => _insert('□P□')),
        _fnCellText('z', onTap: () => _insert('z')),
        _fnCellText('!', onTap: () => _insert('!')),
      ],
      [
        _fnCellText('e', onTap: () => _insert('e')),
        _fnCellText('f(x,y)', onTap: () => _insert('f(□,□)')),
        _fnCell(const _LogBaseGlyph(),
            onTap: () => _insert('logb(□,□)')),
        _fnCell(const _NCrGlyph(),
            onTap: () => _insert('□C□')),
        _fnCell(const _ConjGlyph(),
            onTap: () => _insert('conj(□)')),
        _fnCell(const _MatrixGlyph(),
            onTap: () => _insert('[□]')),
      ],
      [
        _fnCellText('exp', onTap: () => _insert('exp(□)')),
        _fnCell(const _TwoArgGlyph(),
            onTap: () => _insert('□(□,□)')),
        _fnCellText('ln', onTap: () => _insert('ln(□)')),
        _fnCell(const _BinomGlyph(),
            onTap: () => _insert('C(□,□)')),
        _fnCellText('sign', onTap: () => _insert('sign(□)')),
        _fnCell(const _DetGlyph(),
            onTap: () => _insert('det(□)')),
      ],
    ];
    return Column(
      children: rows
          .map((row) => Row(
                children: row.map((w) => Expanded(child: w)).toList(),
              ))
          .toList(),
    );
  }

  Widget _fnCell(Widget child, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          border: Border.all(color: _borderColor, width: 0.6),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _fnCellText(String label, {required VoidCallback onTap}) {
    return _fnCell(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppPalette.textPrimary(context),
            ),
          ),
        ),
      ),
      onTap: onTap,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Kalkülüs sekmesi (5x4 grid)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _calcGrid() {
    final rows = <List<Widget?>>[
      [
        _fnCell(const _LimGlyph(),
            onTap: () => _insert('lim_(□→□)(□)')),
        _fnCell(const _DdxGlyph(),
            onTap: () => _insert('(d/dx)(□)')),
        _fnCell(const _IntDxGlyph(),
            onTap: () => _insert('∫(□)dx')),
        _fnCell(const _DyDxGlyph(),
            onTap: () => _insert('dy/dx')),
        _fnCell(const _SeqGlyph(),
            onTap: () => _insert('a_□')),
      ],
      [
        _fnCell(const _LimPlusGlyph(),
            onTap: () => _insert('lim_(□→□⁺)(□)')),
        _fnCell(const _DdnGlyph(),
            onTap: () => _insert('(d/d□)(□)')),
        _fnCell(const _IntDnGlyph(),
            onTap: () => _insert('∫(□)d□')),
        _fnCellText('dx', onTap: () => _insert(' dx')),
        _fnCell(const _ListEllipsisGlyph(),
            onTap: () => _insert('□,□,□,...')),
      ],
      [
        _fnCell(const _LimMinusGlyph(),
            onTap: () => _insert('lim_(□→□⁻)(□)')),
        _fnCell(const _DdnNthGlyph(),
            onTap: () => _insert('(d^□/d□^□)(□)')),
        _fnCell(const _IntDefGlyph(),
            onTap: () => _insert('∫_(□)^(□)(□)d□')),
        _fnCellText('dy', onTap: () => _insert(' dy')),
        _fnCell(const SizedBox.shrink(), onTap: () {}),
      ],
      [
        _fnCellText('∞', onTap: () => _insert('∞')),
        _fnCell(const SizedBox.shrink(), onTap: () {}),
        _fnCell(const _SumGlyph(),
            onTap: () => _insert('Σ_(□)^(□)(□)')),
        _fnCell(const _PrimeGlyph(),
            onTap: () => _insert("y'")),
        _fnCell(const SizedBox.shrink(), onTap: () {}),
      ],
    ];
    return Column(
      children: rows
          .map((row) => Row(
                children: row
                    .map((w) => Expanded(child: w ?? const SizedBox.shrink()))
                    .toList(),
              ))
          .toList(),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Trigonometri sekmesi (6x4 grid)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _trigGrid() {
    final rows = <List<Widget>>[
      [
        // Derece/radyan modu — Photomath'taki gibi gerçek bir toggle.
        // (Eskiden onTap boştu, tuş hiçbir şey yapmıyordu.)
        _fnCell(
          Text(
            _isRad ? 'rad' : 'deg',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _btnBlue,
            ),
          ),
          onTap: () {
            setState(() => _isRad = !_isRad);
            _evaluate();
          },
        ),
        _fnCellText('sin', onTap: () => _insert('sin(□)')),
        _fnCellText('cos', onTap: () => _insert('cos(□)')),
        _fnCellText('tan', onTap: () => _insert('tan(□)')),
        _fnCellText('cot', onTap: () => _insert('cot(□)')),
        _fnCellText('sec', onTap: () => _insert('sec(□)')),
      ],
      [
        _fnCell(const _Deg1Glyph(),
            onTap: () => _insert('□°')),
        _fnCellText('arcsin', onTap: () => _insert('asin(□)')),
        _fnCellText('arccos', onTap: () => _insert('acos(□)')),
        _fnCellText('arctan', onTap: () => _insert('atan(□)')),
        _fnCellText('arccot', onTap: () => _insert('acot(□)')),
        _fnCellText('arcsec', onTap: () => _insert('asec(□)')),
      ],
      [
        _fnCell(const _Deg2Glyph(),
            onTap: () => _insert("□°□'")),
        _fnCellText('sinh', onTap: () => _insert('sinh(□)')),
        _fnCellText('cosh', onTap: () => _insert('cosh(□)')),
        _fnCellText('tanh', onTap: () => _insert('tanh(□)')),
        _fnCellText('coth', onTap: () => _insert('coth(□)')),
        _fnCellText('sech', onTap: () => _insert('sech(□)')),
      ],
      [
        _fnCell(const _Deg3Glyph(),
            onTap: () => _insert("□°□'□\"")),
        _fnCellText('arsinh', onTap: () => _insert('asinh(□)')),
        _fnCellText('arcosh', onTap: () => _insert('acosh(□)')),
        _fnCellText('artanh', onTap: () => _insert('atanh(□)')),
        _fnCellText('arcoth', onTap: () => _insert('acoth(□)')),
        _fnCellText('arsech', onTap: () => _insert('asech(□)')),
      ],
    ];
    return Column(
      children: rows
          .map((row) => Row(
                children: row.map((w) => Expanded(child: w)).toList(),
              ))
          .toList(),
    );
  }
}

enum _OpKind { num, op, tpl }

class _OpCell {
  final String label;
  final String? value;
  final _OpKind kind;
  final VoidCallback? onTap;
  final Widget? child;
  final List<String> alts;
  const _OpCell._(this.label, this.kind,
      {this.value, this.onTap, this.child, this.alts = const []});

  factory _OpCell.num(String label) => _OpCell._(label, _OpKind.num);
  factory _OpCell.op(String label, {required String value}) =>
      _OpCell._(label, _OpKind.op, value: value);
  factory _OpCell.tpl(String label,
          {required VoidCallback onTap, List<String> alts = const []}) =>
      _OpCell._(label, _OpKind.tpl, onTap: onTap, alts: alts);

  // Özel gösterimler — kesir, karekök, kare
  factory _OpCell.frac(
          {required VoidCallback onTap, List<String> alts = const []}) =>
      _OpCell._(
        '/', _OpKind.tpl,
        onTap: onTap,
        child: const _FracGlyph(),
        alts: alts,
      );
  factory _OpCell.sqrtTpl(
          {required VoidCallback onTap, List<String> alts = const []}) =>
      _OpCell._(
        '√', _OpKind.tpl,
        onTap: onTap,
        child: const _SqrtGlyph(),
        alts: alts,
      );
  factory _OpCell.sqTpl(
          {required VoidCallback onTap, List<String> alts = const []}) =>
      _OpCell._(
        '²', _OpKind.tpl,
        onTap: onTap,
        child: const _SquareGlyph(),
        alts: alts,
      );
}

// ── Özel şablon glifleri ────────────────────────────────────────────────────
class _FracGlyph extends StatelessWidget {
  const _FracGlyph();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DottedBox(width: 18, height: 12),
        Container(width: 22, height: 1, color: AppPalette.textPrimary(context)),
        _DottedBox(width: 18, height: 12),
      ],
    );
  }
}

class _SqrtGlyph extends StatelessWidget {
  const _SqrtGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '√',
          style: TextStyle(
            fontSize: 26,
            color: AppPalette.textPrimary(context),
            fontWeight: FontWeight.w400,
          ),
        ),
        SizedBox(width: 2),
        _DottedBox(width: 16, height: 16),
      ],
    );
  }
}

class _SquareGlyph extends StatelessWidget {
  const _SquareGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DottedBox(width: 18, height: 18),
        SizedBox(width: 2),
        Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text(
            '2',
            style: TextStyle(
              fontSize: 13,
              color: AppPalette.textPrimary(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Fonksiyon sekmesi glifleri ──────────────────────────────────────────────
class _AbsGlyph extends StatelessWidget {
  const _AbsGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _Bar(),
        SizedBox(width: 2),
        _DottedBox(width: 16, height: 16),
        SizedBox(width: 2),
        const _Bar(),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1.2, height: 22, color: AppPalette.textPrimary(context));
}

class _NRootGlyph extends StatelessWidget {
  const _NRootGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _DottedBox(width: 10, height: 10),
        ),
        Text(
          '√',
          style: TextStyle(
              fontSize: 22, color: AppPalette.textPrimary(context), fontWeight: FontWeight.w400),
        ),
        SizedBox(width: 1),
        _DottedBox(width: 14, height: 14),
      ],
    );
  }
}

class _ListGlyph extends StatelessWidget {
  const _ListGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DottedBox(width: 10, height: 12),
        Text(',',
            style: TextStyle(fontSize: 18, color: AppPalette.textPrimary(context))),
        _DottedBox(width: 10, height: 12),
        Text(',',
            style: TextStyle(fontSize: 18, color: AppPalette.textPrimary(context))),
        _DottedBox(width: 10, height: 12),
      ],
    );
  }
}

class _SubGlyph extends StatelessWidget {
  const _SubGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DottedBox(width: 16, height: 16),
        SizedBox(width: 2),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _DottedBox(width: 10, height: 10),
        ),
      ],
    );
  }
}

class _FxCallGlyph extends StatelessWidget {
  const _FxCallGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DottedBox(width: 14, height: 16),
        Text('(',
            style: TextStyle(fontSize: 22, color: AppPalette.textPrimary(context))),
        _DottedBox(width: 12, height: 14),
        Text(')',
            style: TextStyle(fontSize: 22, color: AppPalette.textPrimary(context))),
      ],
    );
  }
}

class _NPrGlyph extends StatelessWidget {
  const _NPrGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DottedBox(width: 12, height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Text('P',
              style: TextStyle(
                  fontSize: 20,
                  color: AppPalette.textPrimary(context),
                  fontWeight: FontWeight.w500)),
        ),
        _DottedBox(width: 12, height: 14),
      ],
    );
  }
}

class _NCrGlyph extends StatelessWidget {
  const _NCrGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DottedBox(width: 12, height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Text('C',
              style: TextStyle(
                  fontSize: 20,
                  color: AppPalette.textPrimary(context),
                  fontWeight: FontWeight.w500)),
        ),
        _DottedBox(width: 12, height: 14),
      ],
    );
  }
}

class _LogBaseGlyph extends StatelessWidget {
  const _LogBaseGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('log',
            style: TextStyle(fontSize: 17, color: AppPalette.textPrimary(context))),
        SizedBox(width: 2),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _DottedBox(width: 9, height: 9),
        ),
      ],
    );
  }
}

class _ConjGlyph extends StatelessWidget {
  const _ConjGlyph();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 1.2, color: AppPalette.textPrimary(context)),
        Padding(
          padding: EdgeInsets.only(top: 1),
          child: Text('Z',
              style: TextStyle(
                  fontSize: 18,
                  color: AppPalette.textPrimary(context),
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

class _MatrixGlyph extends StatelessWidget {
  const _MatrixGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('[',
            style: TextStyle(
                fontSize: 30,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w300,
                height: 1)),
        SizedBox(width: 2),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DottedBox(width: 8, height: 8),
                SizedBox(width: 2),
                _DottedBox(width: 8, height: 8),
              ],
            ),
            SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DottedBox(width: 8, height: 8),
                SizedBox(width: 2),
                _DottedBox(width: 8, height: 8),
              ],
            ),
          ],
        ),
        SizedBox(width: 2),
        Text(']',
            style: TextStyle(
                fontSize: 30,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w300,
                height: 1)),
      ],
    );
  }
}

class _DetGlyph extends StatelessWidget {
  const _DetGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _Bar(),
        SizedBox(width: 2),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DottedBox(width: 7, height: 7),
                SizedBox(width: 2),
                _DottedBox(width: 7, height: 7),
              ],
            ),
            SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DottedBox(width: 7, height: 7),
                SizedBox(width: 2),
                _DottedBox(width: 7, height: 7),
              ],
            ),
          ],
        ),
        SizedBox(width: 2),
        const _Bar(),
      ],
    );
  }
}

class _TwoArgGlyph extends StatelessWidget {
  const _TwoArgGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DottedBox(width: 12, height: 14),
        Text('(',
            style: TextStyle(fontSize: 22, color: AppPalette.textPrimary(context))),
        _DottedBox(width: 10, height: 12),
        Text(',',
            style: TextStyle(fontSize: 18, color: AppPalette.textPrimary(context))),
        _DottedBox(width: 10, height: 12),
        Text(')',
            style: TextStyle(fontSize: 22, color: AppPalette.textPrimary(context))),
      ],
    );
  }
}

class _BinomGlyph extends StatelessWidget {
  const _BinomGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('(',
            style: TextStyle(
                fontSize: 30, color: AppPalette.textPrimary(context), height: 1)),
        SizedBox(width: 2),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DottedBox(width: 12, height: 10),
            SizedBox(height: 2),
            _DottedBox(width: 12, height: 10),
          ],
        ),
        SizedBox(width: 2),
        Text(')',
            style: TextStyle(
                fontSize: 30, color: AppPalette.textPrimary(context), height: 1)),
      ],
    );
  }
}

// ── Kalkülüs sekmesi glifleri ────────────────────────────────────────────────
class _LimGlyph extends StatelessWidget {
  const _LimGlyph();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('lim',
            style: TextStyle(
                fontSize: 17,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w500)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DottedBox(width: 8, height: 8),
            SizedBox(width: 2),
            Text('→',
                style: TextStyle(fontSize: 10, color: AppPalette.textPrimary(context))),
            SizedBox(width: 2),
            _DottedBox(width: 8, height: 8),
          ],
        ),
      ],
    );
  }
}

class _LimPlusGlyph extends StatelessWidget {
  const _LimPlusGlyph();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('lim +',
            style: TextStyle(
                fontSize: 17,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w500)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DottedBox(width: 8, height: 8),
            SizedBox(width: 2),
            Text('→',
                style: TextStyle(fontSize: 10, color: AppPalette.textPrimary(context))),
            SizedBox(width: 2),
            _DottedBox(width: 8, height: 8),
          ],
        ),
      ],
    );
  }
}

class _LimMinusGlyph extends StatelessWidget {
  const _LimMinusGlyph();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('lim −',
            style: TextStyle(
                fontSize: 17,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w500)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DottedBox(width: 8, height: 8),
            SizedBox(width: 2),
            Text('→',
                style: TextStyle(fontSize: 10, color: AppPalette.textPrimary(context))),
            SizedBox(width: 2),
            _DottedBox(width: 8, height: 8),
          ],
        ),
      ],
    );
  }
}

class _DdxGlyph extends StatelessWidget {
  const _DdxGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('d',
                style: TextStyle(
                    fontSize: 14,
                    color: AppPalette.textPrimary(context),
                    fontWeight: FontWeight.w500)),
            Container(width: 22, height: 1, color: AppPalette.textPrimary(context)),
            Text('dx',
                style: TextStyle(
                    fontSize: 14,
                    color: AppPalette.textPrimary(context),
                    fontWeight: FontWeight.w500)),
          ],
        ),
        SizedBox(width: 4),
        _DottedBox(width: 10, height: 12),
      ],
    );
  }
}

class _DdnGlyph extends StatelessWidget {
  const _DdnGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('d',
                style: TextStyle(
                    fontSize: 14,
                    color: AppPalette.textPrimary(context),
                    fontWeight: FontWeight.w500)),
            Container(width: 22, height: 1, color: AppPalette.textPrimary(context)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('d',
                    style: TextStyle(
                        fontSize: 14,
                        color: AppPalette.textPrimary(context),
                        fontWeight: FontWeight.w500)),
                _DottedBox(width: 8, height: 8),
              ],
            ),
          ],
        ),
        SizedBox(width: 4),
        _DottedBox(width: 10, height: 12),
      ],
    );
  }
}

class _DdnNthGlyph extends StatelessWidget {
  const _DdnNthGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('d',
                style: TextStyle(
                    fontSize: 14,
                    color: AppPalette.textPrimary(context),
                    fontWeight: FontWeight.w500)),
            Container(width: 26, height: 1, color: AppPalette.textPrimary(context)),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('d',
                    style: TextStyle(
                        fontSize: 14,
                        color: AppPalette.textPrimary(context),
                        fontWeight: FontWeight.w500)),
                _DottedBox(width: 7, height: 7),
                Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text('N',
                      style: TextStyle(
                          fontSize: 9, color: AppPalette.textPrimary(context))),
                ),
              ],
            ),
          ],
        ),
        SizedBox(width: 4),
        _DottedBox(width: 10, height: 12),
      ],
    );
  }
}

class _IntDxGlyph extends StatelessWidget {
  const _IntDxGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('∫',
            style: TextStyle(
                fontSize: 28,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w300,
                height: 1)),
        SizedBox(width: 1),
        _DottedBox(width: 10, height: 12),
        SizedBox(width: 2),
        Text('dx',
            style: TextStyle(
                fontSize: 15,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _IntDnGlyph extends StatelessWidget {
  const _IntDnGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('∫',
            style: TextStyle(
                fontSize: 28,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w300,
                height: 1)),
        SizedBox(width: 1),
        _DottedBox(width: 10, height: 12),
        SizedBox(width: 2),
        Text('d',
            style: TextStyle(
                fontSize: 15,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w500)),
        _DottedBox(width: 9, height: 9),
      ],
    );
  }
}

class _IntDefGlyph extends StatelessWidget {
  const _IntDefGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DottedBox(width: 7, height: 7),
            SizedBox(height: 2),
            Text('∫',
                style: TextStyle(
                    fontSize: 22,
                    color: AppPalette.textPrimary(context),
                    height: 1,
                    fontWeight: FontWeight.w300)),
            SizedBox(height: 2),
            _DottedBox(width: 7, height: 7),
          ],
        ),
        SizedBox(width: 2),
        _DottedBox(width: 10, height: 10),
        SizedBox(width: 2),
        Text('d',
            style: TextStyle(
                fontSize: 14,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w500)),
        _DottedBox(width: 8, height: 8),
      ],
    );
  }
}

class _SumGlyph extends StatelessWidget {
  const _SumGlyph();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DottedBox(width: 10, height: 10),
        SizedBox(height: 1),
        Text('Σ',
            style: TextStyle(
                fontSize: 22,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w400,
                height: 1)),
        SizedBox(height: 1),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DottedBox(width: 7, height: 7),
            Text('=',
                style: TextStyle(
                    fontSize: 10, color: AppPalette.textPrimary(context))),
            _DottedBox(width: 7, height: 7),
          ],
        ),
      ],
    );
  }
}

class _DyDxGlyph extends StatelessWidget {
  const _DyDxGlyph();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('dy',
            style: TextStyle(
                fontSize: 15,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w500)),
        Container(width: 22, height: 1, color: AppPalette.textPrimary(context)),
        Text('dx',
            style: TextStyle(
                fontSize: 15,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _SeqGlyph extends StatelessWidget {
  const _SeqGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('a',
            style: TextStyle(
                fontSize: 22,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w400)),
        Padding(
          padding: EdgeInsets.only(bottom: 3),
          child: Text('n',
              style: TextStyle(
                  fontSize: 13,
                  color: AppPalette.textPrimary(context),
                  fontWeight: FontWeight.w400)),
        ),
      ],
    );
  }
}

class _ListEllipsisGlyph extends StatelessWidget {
  const _ListEllipsisGlyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DottedBox(width: 8, height: 10),
        Text(',',
            style: TextStyle(fontSize: 14, color: AppPalette.textPrimary(context))),
        _DottedBox(width: 8, height: 10),
        Text(',',
            style: TextStyle(fontSize: 14, color: AppPalette.textPrimary(context))),
        _DottedBox(width: 8, height: 10),
        Text(',',
            style: TextStyle(fontSize: 14, color: AppPalette.textPrimary(context))),
        Text('...',
            style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context))),
      ],
    );
  }
}

class _PrimeGlyph extends StatelessWidget {
  const _PrimeGlyph();
  @override
  Widget build(BuildContext context) {
    return Text("y'",
        style: TextStyle(
            fontSize: 22,
            color: AppPalette.textPrimary(context),
            fontWeight: FontWeight.w400));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _BlinkingCursor — LaTeX preview içinde sürekli yanıp sönen imleç
// ═══════════════════════════════════════════════════════════════════════════
class _BlinkingCursor extends StatefulWidget {
  final Color color;
  final double width;
  final double height;
  const _BlinkingCursor({
    required this.color,
    this.width = 2.5,
    this.height = 28,
  });

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) => Opacity(
        opacity: _ac.value > 0.5 ? 1.0 : 0.0,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      ),
    );
  }
}


// ── Trigonometri sekmesi glifleri (açı notasyonu) ───────────────────────────
class _Deg1Glyph extends StatelessWidget {
  const _Deg1Glyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _DottedBox(width: 14, height: 14),
        ),
        Text('°',
            style: TextStyle(
                fontSize: 14,
                color: AppPalette.textPrimary(context),
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _Deg2Glyph extends StatelessWidget {
  const _Deg2Glyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _DottedBox(width: 10, height: 10),
        ),
        Text('°',
            style: TextStyle(fontSize: 12, color: AppPalette.textPrimary(context))),
        SizedBox(width: 2),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _DottedBox(width: 10, height: 10),
        ),
        Text("'",
            style: TextStyle(fontSize: 14, color: AppPalette.textPrimary(context))),
      ],
    );
  }
}

class _Deg3Glyph extends StatelessWidget {
  const _Deg3Glyph();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _DottedBox(width: 8, height: 8),
        ),
        Text('°',
            style: TextStyle(fontSize: 11, color: AppPalette.textPrimary(context))),
        SizedBox(width: 1),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _DottedBox(width: 8, height: 8),
        ),
        Text("'",
            style: TextStyle(fontSize: 12, color: AppPalette.textPrimary(context))),
        SizedBox(width: 1),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _DottedBox(width: 8, height: 8),
        ),
        Text('"',
            style: TextStyle(fontSize: 12, color: AppPalette.textPrimary(context))),
      ],
    );
  }
}

class _DottedBox extends StatelessWidget {
  final double width;
  final double height;
  const _DottedBox({required this.width, required this.height});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _DottedBoxPainter(AppPalette.textSecondary(context)),
    );
  }
}

class _DottedBoxPainter extends CustomPainter {
  final Color color;
  const _DottedBoxPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    const dashW = 2.0, gap = 2.0;
    // Üst
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashW, 0), p);
      x += dashW + gap;
    }
    // Alt
    x = 0;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + dashW, size.height), p);
      x += dashW + gap;
    }
    // Sol
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dashW), p);
      y += dashW + gap;
    }
    // Sağ
    y = 0;
    while (y < size.height) {
      canvas.drawLine(
          Offset(size.width, y), Offset(size.width, y + dashW), p);
      y += dashW + gap;
    }
    // kullanılmayan rect — lint susturucu
    rect.toString();
  }

  @override
  bool shouldRepaint(covariant _DottedBoxPainter oldDelegate) =>
      oldDelegate.color != color;
}
