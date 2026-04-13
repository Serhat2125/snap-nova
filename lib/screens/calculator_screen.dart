import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  CalculatorScreen — Photomath tarzı hesap makinası
//  • Üst panel: LaTeX benzeri ifade önizleme + canlı sonuç
//  • Alt panel: Özel klavye (Temel / Bilimsel sekme)
//  • Bellek barı, geçmiş, DEG/RAD toggle
// ═══════════════════════════════════════════════════════════════════════════════

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  String _expr = '';
  String _display = '0';
  bool _justEvaluated = false;
  bool _isDeg = true;
  double _memory = 0;
  bool _memHasValue = false;
  final List<String> _history = [];
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Hesaplama ─────────────────────────────────────────────────────────────────

  String _fmt(double n) {
    if (n.isNaN) return 'Tanımsız';
    if (n.isInfinite) return n > 0 ? '∞' : '-∞';
    if (n == n.roundToDouble() && n.abs() < 1e13) return n.toInt().toString();
    String s = n
        .toStringAsPrecision(10)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  double _eval(String raw) {
    final s = raw
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('π', '${math.pi}')
        .replaceAll('e', '${math.e}')
        .replaceAll('√(', 'sqrt(')
        .replaceAll('√', 'sqrt(');
    return _Parser(s, isDeg: _isDeg).evaluate();
  }

  void _liveEval() {
    if (_expr.isEmpty) {
      setState(() => _display = '0');
      return;
    }
    try {
      final v = _eval(_expr);
      setState(() => _display = _fmt(v));
    } catch (_) {
      // ifade eksik — son sonucu koru
    }
  }

  void _press(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (k) {
        case 'AC':
          _expr = '';
          _display = '0';
          _justEvaluated = false;
          return;
        case 'C':
          if (_expr.isNotEmpty) {
            _expr = _expr.substring(0, _expr.length - 1);
          } else {
            _display = '0';
          }
          _justEvaluated = false;
          _liveEval();
          return;
        case '=':
          if (_expr.isEmpty) return;
          try {
            final opens =
                '('.allMatches(_expr).length - ')'.allMatches(_expr).length;
            final full = _expr + (')' * opens.clamp(0, 10));
            final v = _eval(full);
            final res = _fmt(v);
            _history.insert(0, '$_expr = $res');
            if (_history.length > 50) _history.removeLast();
            _expr = res;
            _display = res;
            _justEvaluated = true;
          } catch (_) {
            _display = 'Hata';
            _justEvaluated = false;
          }
          return;
        case '±':
          if (_expr.startsWith('-')) {
            _expr = _expr.substring(1);
          } else if (_expr.isNotEmpty) {
            _expr = '-$_expr';
          }
          _liveEval();
          return;
        case '%':
          _expr += '%';
          _liveEval();
          return;
        case 'MC':
          _memory = 0;
          _memHasValue = false;
          return;
        case 'MR':
          if (_memHasValue) {
            if (_justEvaluated || _expr.isEmpty) {
              _expr = _fmt(_memory);
            } else {
              _expr += _fmt(_memory);
            }
            _justEvaluated = false;
            _liveEval();
          }
          return;
        case 'M+':
          try {
            _memory += _eval(_expr.isEmpty ? '0' : _expr);
            _memHasValue = true;
          } catch (_) {}
          return;
        case 'M-':
          try {
            _memory -= _eval(_expr.isEmpty ? '0' : _expr);
            _memHasValue = true;
          } catch (_) {}
          return;
        case 'n!':
          _expr += '!';
          _liveEval();
          return;
        default:
          if (_justEvaluated && _isOperator(k)) {
            _justEvaluated = false;
          } else if (_justEvaluated && !_isOperator(k)) {
            _expr = '';
            _justEvaluated = false;
          }
          _expr += k;
          _liveEval();
      }
    });
  }

  bool _isOperator(String k) =>
      k == '+' || k == '-' || k == '×' || k == '÷' || k == '^';

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A18),
      body: SafeArea(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: Column(
            children: [
              _buildHeader(),
              _buildDisplayPanel(),
              _buildMemBar(),
              _buildTabBar(),
              Expanded(child: _buildKeyboard()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.cyan),
              onPressed: () => Navigator.pop(context),
            ),
            const Text(
              'Hesap Makinası',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            // DEG / RAD toggle
            GestureDetector(
              onTap: () => setState(() => _isDeg = !_isDeg),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.35)),
                ),
                child: Text(
                  _isDeg ? 'DEG' : 'RAD',
                  style: const TextStyle(
                      color: AppColors.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Geçmiş
            GestureDetector(
              onTap: () => setState(() => _showHistory = !_showHistory),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _showHistory
                      ? AppColors.cyan.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.history_rounded,
                    color: AppColors.textSecondary, size: 18),
              ),
            ),
          ],
        ),
      );

  // ── Display panel — Photomath tarzı ifade önizleme ─────────────────────────

  Widget _buildDisplayPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: _showHistory ? 200 : 130,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.04),
            blurRadius: 20,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: _showHistory ? _buildHistoryList() : _buildExprDisplay(),
    );
  }

  // LaTeX benzeri ifade önizleme
  Widget _buildExprDisplay() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // İfade önizleme (üstte, soluk)
        if (_expr.isNotEmpty && !_justEvaluated)
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: _ExprPreview(expr: _expr),
              ),
            ),
          ),

        // Ana sonuç
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              color: _justEvaluated ? AppColors.cyan : Colors.white,
              fontSize: 56,
              fontWeight: FontWeight.w200,
              letterSpacing: -1,
            ),
            child: Text(_display),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryList() => _history.isEmpty
      ? Center(
          child: Text('Henüz hesaplama yok',
              style: TextStyle(color: AppColors.textMuted)))
      : ListView.separated(
          reverse: false,
          physics: const BouncingScrollPhysics(),
          itemCount: _history.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.05),
          ),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () {
              final parts = _history[i].split(' = ');
              if (parts.length == 2) {
                setState(() {
                  _expr = parts[1];
                  _display = parts[1];
                  _justEvaluated = true;
                  _showHistory = false;
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _history[i],
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ),
        );

  // ── Hafıza barı ───────────────────────────────────────────────────────────────

  Widget _buildMemBar() => Container(
        height: 32,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            for (final k in ['MC', 'MR', 'M+', 'M-'])
              Expanded(
                child: GestureDetector(
                  onTap: () => _press(k),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: k == 'MR' && _memHasValue
                            ? AppColors.cyan.withValues(alpha: 0.50)
                            : AppColors.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        k,
                        style: TextStyle(
                          color: k == 'MR' && _memHasValue
                              ? AppColors.cyan
                              : AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  // ── Sekme barı ─────────────────────────────────────────────────────────────────

  Widget _buildTabBar() => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: TabBar(
          controller: _tab,
          indicator: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.black87,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: const [Tab(text: 'Temel'), Tab(text: 'Bilimsel')],
        ),
      );

  // ── Klavye ────────────────────────────────────────────────────────────────────

  Widget _buildKeyboard() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: TabBarView(
          controller: _tab,
          children: [_basicPad(), _sciPad()],
        ),
      );

  // Temel klavye
  static const _basicKeys = [
    ['AC', '±', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '-'],
    ['1', '2', '3', '+'],
    ['0', '.', 'C', '='],
  ];

  Widget _basicPad() => Column(
        children: _basicKeys
            .map((row) => Expanded(
                  child: Row(
                    children: row.map((k) => _buildKey(k)).toList(),
                  ),
                ))
            .toList(),
      );

  // Bilimsel klavye
  static const _sciRows = [
    ['sin', 'cos', 'tan', 'sin⁻¹', 'cos⁻¹', 'tan⁻¹'],
    ['log', 'ln', 'log₂', '√(', 'x²', 'xʸ'],
    ['n!', '|x|', '10^(', 'e^(', '(', ')'],
    ['π', 'e', '1/x', 'mod', 'C', '='],
  ];

  static const _numRow = ['7', '8', '9', '÷', '×'];
  static const _numRow2 = ['4', '5', '6', '+', '-'];
  static const _numRow3 = ['1', '2', '3', '.', '0'];

  Widget _sciPad() => Column(children: [
        ..._sciRows.map((row) => Expanded(
              child: Row(
                  children: row.map((k) => _buildKey(k, fontSize: 11)).toList()),
            )),
        Expanded(
            child: Row(children: _numRow.map((k) => _buildKey(k)).toList())),
        Expanded(
            child: Row(children: _numRow2.map((k) => _buildKey(k)).toList())),
        Expanded(
            child: Row(children: _numRow3.map((k) => _buildKey(k)).toList())),
      ]);

  // ── Tek tuş ───────────────────────────────────────────────────────────────────

  Widget _buildKey(String label, {double fontSize = 17}) {
    final isOp =
        label == '÷' || label == '×' || label == '-' || label == '+';
    final isEq = label == '=';
    final isClear = label == 'AC' || label == 'C';
    final isSci = !RegExp(r'^[0-9.]$').hasMatch(label) &&
        !isOp &&
        !isEq &&
        !isClear;

    String displayLabel = label;
    String pressKey = label;

    // Tuş etiketi ↔ basılı değer eşlemeleri
    const keyMap = {
      'x²': (display: 'x²', press: '^2'),
      'xʸ': (display: 'xʸ', press: '^'),
      '1/x': (display: '1/x', press: '1/('),
      'mod': (display: 'mod', press: '%'),
      '|x|': (display: '|x|', press: 'abs('),
      '10^(': (display: '10ˣ', press: '10^('),
      'e^(': (display: 'eˣ', press: 'e^('),
      'log₂': (display: 'log₂', press: 'log₂('),
      'sin⁻¹': (display: 'sin⁻¹', press: 'sin⁻¹('),
      'cos⁻¹': (display: 'cos⁻¹', press: 'cos⁻¹('),
      'tan⁻¹': (display: 'tan⁻¹', press: 'tan⁻¹('),
      'sin': (display: 'sin', press: 'sin('),
      'cos': (display: 'cos', press: 'cos('),
      'tan': (display: 'tan', press: 'tan('),
      'log': (display: 'log', press: 'log('),
      'ln': (display: 'ln', press: 'ln('),
      '√(': (display: '√', press: '√('),
    };

    final mapped = keyMap[label];
    if (mapped != null) {
      displayLabel = mapped.display;
      pressKey = mapped.press;
    }

    // Renk şeması
    Color bg, fg;
    Gradient? grad;

    if (isEq) {
      bg = Colors.transparent;
      fg = Colors.black87;
      grad = const LinearGradient(
        colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (isClear) {
      bg = const Color(0xFFEF4444).withValues(alpha: 0.15);
      fg = const Color(0xFFEF4444);
      grad = null;
    } else if (isOp) {
      bg = AppColors.cyan.withValues(alpha: 0.12);
      fg = AppColors.cyan;
      grad = null;
    } else if (isSci) {
      bg = const Color(0xFF151530);
      fg = const Color(0xFFBB99FF);
      grad = null;
    } else {
      bg = const Color(0xFF13132A);
      fg = Colors.white;
      grad = null;
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: GestureDetector(
          onTap: () => _press(pressKey),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            decoration: BoxDecoration(
              gradient: grad,
              color: grad == null ? bg : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isEq
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.05),
                width: 0.5,
              ),
              boxShadow: isEq
                  ? [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : [],
            ),
            child: Center(
              child: Text(
                displayLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: fontSize,
                  fontWeight: isEq || isOp ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _ExprPreview — Photomath tarzı ifade önizleme
//  Üst simgeler (², ³), fonksiyon adları ve operatörler farklı boyut/renkle
//  gösterilir — gerçek LaTeX render'a altyapı hazır.
// ═══════════════════════════════════════════════════════════════════════════════

class _ExprPreview extends StatelessWidget {
  final String expr;
  const _ExprPreview({required this.expr});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(children: _tokenize(expr)),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
    );
  }

  List<InlineSpan> _tokenize(String s) {
    final spans = <InlineSpan>[];
    int i = 0;

    while (i < s.length) {
      // Fonksiyon adı
      final fnMatch =
          RegExp(r'^(sin⁻¹|cos⁻¹|tan⁻¹|sinh|cosh|tanh|sin|cos|tan|log₂|log|ln|sqrt|abs)')
              .matchAsPrefix(s, i);
      if (fnMatch != null) {
        spans.add(TextSpan(
          text: fnMatch.group(0),
          style: const TextStyle(
            color: Color(0xFFBB99FF),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ));
        i += fnMatch.group(0)!.length;
        continue;
      }

      // Üst simge karakterler (², ³, ⁻¹ vs.)
      if ('²³⁴⁵⁶⁷⁸⁹'.contains(s[i])) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Text(
            s[i],
            style: const TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ));
        i++;
        continue;
      }

      // Operatörler
      if ('×÷+-^%'.contains(s[i])) {
        spans.add(TextSpan(
          text: ' ${s[i]} ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.70),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ));
        i++;
        continue;
      }

      // Parantezler
      if ('()'.contains(s[i])) {
        spans.add(TextSpan(
          text: s[i],
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.50),
            fontSize: 15,
          ),
        ));
        i++;
        continue;
      }

      // π, e sabitleri
      if (s[i] == 'π' || s[i] == 'e') {
        spans.add(TextSpan(
          text: s[i],
          style: const TextStyle(
            color: Color(0xFF10B981),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ));
        i++;
        continue;
      }

      // Rakamlar ve nokta
      spans.add(TextSpan(
        text: s[i],
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 15,
          fontWeight: FontWeight.w300,
        ),
      ));
      i++;
    }

    return spans;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  İfade Ayrıştırıcı (Recursive Descent Parser)
// ═══════════════════════════════════════════════════════════════════════════════

class _Parser {
  final String _s;
  final bool isDeg;
  int _i = 0;

  _Parser(this._s, {required this.isDeg});

  double evaluate() => _addSub();

  double _addSub() {
    double v = _mulDiv();
    while (_i < _s.length) {
      if (_ch == '+') {
        _i++;
        v += _mulDiv();
      } else if (_ch == '-') {
        _i++;
        v -= _mulDiv();
      } else {
        break;
      }
    }
    return v;
  }

  double _mulDiv() {
    double v = _pow();
    while (_i < _s.length) {
      if (_ch == '*') {
        _i++;
        v *= _pow();
      } else if (_ch == '/') {
        _i++;
        final d = _pow();
        v = d == 0 ? double.infinity : v / d;
      } else if (_ch == '%') {
        _i++;
        v = v % _pow();
      } else {
        break;
      }
    }
    return v;
  }

  double _pow() {
    double b = _factorial();
    if (_i < _s.length && _ch == '^') {
      _i++;
      b = math.pow(b, _pow()).toDouble();
    }
    return b;
  }

  double _factorial() {
    double v = _unary();
    while (_i < _s.length && _ch == '!') {
      _i++;
      final n = v.toInt();
      if (n < 0 || n > 20) return double.nan;
      int f = 1;
      for (int k = 2; k <= n; k++) { f *= k; }
      v = f.toDouble();
    }
    return v;
  }

  double _unary() {
    _ws();
    if (_i < _s.length && _ch == '-') {
      _i++;
      return -_func();
    }
    if (_i < _s.length && _ch == '+') _i++;
    return _func();
  }

  static const _fns = [
    'sin⁻¹', 'cos⁻¹', 'tan⁻¹', 'sinh', 'cosh', 'tanh',
    'sin', 'cos', 'tan', 'log₂', 'log', 'ln', 'sqrt', 'abs',
  ];

  double _func() {
    _ws();
    for (final fn in _fns) {
      if (_s.startsWith(fn, _i)) {
        _i += fn.length;
        _ws();
        double arg;
        if (_i < _s.length && _ch == '(') {
          _i++;
          arg = _addSub();
          if (_i < _s.length && _ch == ')') _i++;
        } else {
          arg = _prim();
        }
        return _apply(fn, arg);
      }
    }
    return _prim();
  }

  double _apply(String fn, double x) {
    final r = isDeg ? math.pi / 180 : 1.0;
    final d = isDeg ? 180 / math.pi : 1.0;
    switch (fn) {
      case 'sin': return math.sin(x * r);
      case 'cos': return math.cos(x * r);
      case 'tan': return math.tan(x * r);
      case 'sin⁻¹': return math.asin(x) * d;
      case 'cos⁻¹': return math.acos(x) * d;
      case 'tan⁻¹': return math.atan(x) * d;
      case 'sinh': return (math.exp(x) - math.exp(-x)) / 2;
      case 'cosh': return (math.exp(x) + math.exp(-x)) / 2;
      case 'tanh': final e = math.exp(2 * x); return (e - 1) / (e + 1);
      case 'log': return math.log(x) / math.ln10;
      case 'log₂': return math.log(x) / math.log(2);
      case 'ln': return math.log(x);
      case 'sqrt': return math.sqrt(x);
      case 'abs': return x.abs();
      default: return x;
    }
  }

  double _prim() {
    _ws();
    if (_i >= _s.length) return 0;
    if (_ch == '(') {
      _i++;
      final v = _addSub();
      if (_i < _s.length && _ch == ')') _i++;
      return v;
    }
    // π sabiti
    if (_ch == 'π') {
      _i++;
      return math.pi;
    }
    // Rakam
    final st = _i;
    while (_i < _s.length && (_isDigit(_ch) || _ch == '.')) { _i++; }
    if (_i == st) throw FormatException('Unexpected char at $_i');
    return double.parse(_s.substring(st, _i));
  }

  void _ws() {
    while (_i < _s.length && _ch == ' ') { _i++; }
  }

  String get _ch => _s[_i];
  bool _isDigit(String c) => RegExp(r'[0-9]').hasMatch(c);
}
