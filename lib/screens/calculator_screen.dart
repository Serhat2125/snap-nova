import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/gemini_service.dart';
import 'ai_result_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  CalculatorScreen — Qanda tarzı
//  • Üst: LaTeX ifade önizleme + canlı sonuç
//  • Aksiyon satırı: Grafik Çiz / Adım Adım Çöz
//  • Grafik (açılır)
//  • Klavye: Temel / Bilimsel sekmeli
// ═══════════════════════════════════════════════════════════════════════════════

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // İfade: kullanıcı dostu unicode (π, √, ², sin, vs.)
  String _expr = '';
  String _result = '';
  bool _isDeg = true;
  bool _showGraph = false;
  bool _stepLoading = false;
  final List<_HistoryItem> _history = [];

  static const _orange = Color(0xFFFF6A00);
  static const _orangeDark = Color(0xFFE85D00);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── İfade düzenleme ────────────────────────────────────────────────────────
  void _append(String s) => setState(() {
        _expr += s;
        _evaluate();
      });

  void _backspace() => setState(() {
        if (_expr.isEmpty) return;
        // Son fonksiyon adı bir bütün olarak silinsin
        for (final fn in _Engine.functions) {
          if (_expr.endsWith(fn)) {
            _expr = _expr.substring(0, _expr.length - fn.length);
            _evaluate();
            return;
          }
        }
        _expr = _expr.substring(0, _expr.length - 1);
        _evaluate();
      });

  void _clear() => setState(() {
        _expr = '';
        _result = '';
      });

  void _evaluate() {
    if (_expr.trim().isEmpty) {
      _result = '';
      return;
    }
    try {
      final v = _Engine.evaluate(_expr, isDeg: _isDeg);
      if (v.isNaN) {
        _result = '';
      } else {
        _result = _Engine.format(v);
      }
    } catch (_) {
      _result = '';
    }
  }

  void _onEquals() {
    if (_result.isEmpty) return;
    final latex = _Engine.toLatex(_expr);
    setState(() {
      _history.insert(0, _HistoryItem(expr: _expr, latex: latex, result: _result));
      if (_history.length > 50) _history.removeLast();
      _expr = _result;
      _evaluate();
    });
  }

  // ── Grafik ─────────────────────────────────────────────────────────────────
  List<FlSpot> _graphSpots() {
    if (_expr.isEmpty) return const [];
    final spots = <FlSpot>[];
    const n = 200;
    const minX = -10.0, maxX = 10.0;
    for (var i = 0; i <= n; i++) {
      final x = minX + (maxX - minX) * i / n;
      try {
        final y = _Engine.evaluate(_expr, isDeg: _isDeg, variables: {'x': x});
        if (y.isFinite && y.abs() < 1000) spots.add(FlSpot(x, y));
      } catch (_) {}
    }
    return spots;
  }

  // ── Adım adım çöz ──────────────────────────────────────────────────────────
  Future<void> _solveSteps() async {
    if (_expr.trim().isEmpty || _stepLoading) return;
    setState(() => _stepLoading = true);
    try {
      final latex = _Engine.toLatex(_expr);
      final prompt = 'Aşağıdaki ifadeyi adım adım çöz ve sonucunu ver. '
          'Türkçe yanıt ver. LaTeX formatını koru.\n\nİfade: $latex';
      final res = await GeminiService.solveHomework(
        question: prompt,
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
            solutionType: 'Adım Adım Çözüm',
            modelName: 'QuAlsar',
          ),
        ),
      );
    } on GeminiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      if (mounted) setState(() => _stepLoading = false);
    }
  }

  // ── Geçmiş bottom sheet ────────────────────────────────────────────────────
  void _openHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Geçmiş',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (_history.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(_history.clear);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Temizle',
                            style: TextStyle(color: _orange)),
                      ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: _history.isEmpty
                      ? Center(
                          child: Text(
                            'Geçmiş boş',
                            style: GoogleFonts.poppins(
                                color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _history.length,
                          separatorBuilder: (_, __) => const Divider(height: 16),
                          itemBuilder: (_, i) {
                            final h = _history[i];
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _expr = h.expr;
                                  _evaluate();
                                });
                                Navigator.pop(ctx);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Math.tex(h.latex,
                                        textStyle: const TextStyle(
                                            fontSize: 16, color: Colors.black)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '= ${h.result}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: _orange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          'Hesap Makinesi',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () => setState(() => _isDeg = !_isDeg),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _orange),
              ),
              alignment: Alignment.center,
              child: Text(
                _isDeg ? 'DEG' : 'RAD',
                style: GoogleFonts.poppins(
                  color: _orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            onPressed: _openHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDisplay(),
          _buildActionRow(),
          if (_showGraph) _buildGraph(),
          Expanded(child: _buildKeyboard()),
        ],
      ),
    );
  }

  Widget _buildDisplay() {
    final latex = _Engine.toLatex(_expr);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: _expr.isEmpty
                  ? Text(
                      '0',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                      ),
                    )
                  : Math.tex(
                      latex,
                      textStyle: const TextStyle(
                        fontSize: 26,
                        color: Colors.black,
                      ),
                      onErrorFallback: (_) => Text(
                        _expr,
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          color: Colors.black,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _result.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _result));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sonuç kopyalandı'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
            child: Text(
              _result.isEmpty ? ' ' : '= $_result',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _actionChip(
              icon: Icons.show_chart_rounded,
              label: _showGraph ? 'Grafiği Gizle' : 'Grafik Çiz',
              onTap: () => setState(() => _showGraph = !_showGraph),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actionChip(
              icon: _stepLoading
                  ? Icons.hourglass_top_rounded
                  : Icons.auto_awesome_rounded,
              label: _stepLoading ? 'Çözülüyor…' : 'Adım Adım Çöz',
              filled: true,
              onTap: _solveSteps,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: filled ? _orange : _orange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _orange, width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: filled ? Colors.white : _orange),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: filled ? Colors.white : _orange,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraph() {
    final spots = _graphSpots();
    return Container(
      height: 200,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: spots.isEmpty
          ? Center(
              child: Text(
                'Grafik için ifadeye x değişkeni ekle\n(örn. x^2 + 2x − 3)',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            )
          : LineChart(
              LineChartData(
                minX: -10,
                maxX: 10,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.grey.shade200, strokeWidth: 1),
                  getDrawingVerticalLine: (_) => FlLine(
                      color: Colors.grey.shade200, strokeWidth: 1),
                ),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: _orange,
                    barWidth: 2.2,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Klavye ─────────────────────────────────────────────────────────────────
  Widget _buildKeyboard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Column(
        children: [
          TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: _orange,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: _orange,
            indicatorWeight: 2.5,
            labelStyle: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Temel'),
              Tab(text: 'Bilimsel'),
              Tab(text: 'Fonksiyon'),
              Tab(text: 'İstatistik'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _basicPad(),
                _sciPad(),
                _fnPad(),
                _statPad(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _basicPad() {
    final rows = <List<_Key>>[
      [
        _Key.fn('AC', onTap: _clear, color: Colors.red.shade400),
        _Key.fn('( )', onTap: () => _append(
            _expr.lastIndexOf('(') > _expr.lastIndexOf(')') ? ')' : '(')),
        _Key.fn('%', onTap: () => _append('%')),
        _Key.op('÷', value: '/'),
      ],
      [
        _Key.num('7'), _Key.num('8'), _Key.num('9'),
        _Key.op('×', value: '*'),
      ],
      [
        _Key.num('4'), _Key.num('5'), _Key.num('6'),
        _Key.op('−', value: '-'),
      ],
      [
        _Key.num('1'), _Key.num('2'), _Key.num('3'),
        _Key.op('+', value: '+'),
      ],
      [
        _Key.fn('x', onTap: () => _append('x')),
        _Key.num('0'),
        _Key.num('.'),
        _Key.fn('=', onTap: _onEquals, color: _orangeDark, white: true),
      ],
      [
        _Key.fn('⌫', onTap: _backspace, color: Colors.grey.shade400),
      ],
    ];
    return _padGrid(rows);
  }

  Widget _sciPad() {
    final rows = <List<_Key>>[
      [
        _Key.fn('sin', onTap: () => _append('sin(')),
        _Key.fn('cos', onTap: () => _append('cos(')),
        _Key.fn('tan', onTap: () => _append('tan(')),
        _Key.fn('⌫', onTap: _backspace, color: Colors.grey.shade400),
      ],
      [
        _Key.fn('sin⁻¹', onTap: () => _append('asin(')),
        _Key.fn('cos⁻¹', onTap: () => _append('acos(')),
        _Key.fn('tan⁻¹', onTap: () => _append('atan(')),
        _Key.fn('AC', onTap: _clear, color: Colors.red.shade400),
      ],
      [
        _Key.fn('xʸ', onTap: () => _append('^')),
        _Key.fn('x²', onTap: () => _append('^2')),
        _Key.fn('√', onTap: () => _append('sqrt(')),
        _Key.fn('|x|', onTap: () => _append('abs(')),
      ],
      [
        _Key.fn('log', onTap: () => _append('log(')),
        _Key.fn('ln', onTap: () => _append('ln(')),
        _Key.fn('eˣ', onTap: () => _append('exp(')),
        _Key.fn('n!', onTap: () => _append('!')),
      ],
      [
        _Key.fn('π', onTap: () => _append('π')),
        _Key.fn('e', onTap: () => _append('e')),
        _Key.fn('(', onTap: () => _append('(')),
        _Key.fn(')', onTap: () => _append(')')),
      ],
      [
        _Key.fn('x', onTap: () => _append('x')),
        _Key.fn('=', onTap: _onEquals, color: _orangeDark, white: true),
      ],
    ];
    return _padGrid(rows);
  }

  Widget _fnPad() {
    final rows = <List<_Key>>[
      [
        _Key.fn('gcd', onTap: () => _append('gcd(')),
        _Key.fn('lcm', onTap: () => _append('lcm(')),
        _Key.fn('mod', onTap: () => _append('mod(')),
        _Key.fn('⌫', onTap: _backspace, color: Colors.grey.shade400),
      ],
      [
        _Key.fn('min', onTap: () => _append('min(')),
        _Key.fn('max', onTap: () => _append('max(')),
        _Key.fn(',', onTap: () => _append(',')),
        _Key.fn('AC', onTap: _clear, color: Colors.red.shade400),
      ],
      [
        _Key.fn('nPr', onTap: () => _append('nPr(')),
        _Key.fn('nCr', onTap: () => _append('nCr(')),
        _Key.fn('n!', onTap: () => _append('!')),
        _Key.fn('|x|', onTap: () => _append('abs(')),
      ],
      [
        _Key.fn('floor', onTap: () => _append('floor(')),
        _Key.fn('ceil', onTap: () => _append('ceil(')),
        _Key.fn('round', onTap: () => _append('round(')),
        _Key.fn('sign', onTap: () => _append('sign(')),
      ],
      [
        _Key.fn('log_b', onTap: () => _append('logb(')),
        _Key.fn('root', onTap: () => _append('root(')),
        _Key.fn('(', onTap: () => _append('(')),
        _Key.fn(')', onTap: () => _append(')')),
      ],
      [
        _Key.fn('x', onTap: () => _append('x')),
        _Key.fn('=', onTap: _onEquals, color: _orangeDark, white: true),
      ],
    ];
    return _padGrid(rows);
  }

  Widget _statPad() {
    final rows = <List<_Key>>[
      [
        _Key.fn('sum', onTap: () => _append('sum(')),
        _Key.fn('ort', onTap: () => _append('mean(')),
        _Key.fn('med', onTap: () => _append('median(')),
        _Key.fn('⌫', onTap: _backspace, color: Colors.grey.shade400),
      ],
      [
        _Key.fn('var', onTap: () => _append('var(')),
        _Key.fn('σ', onTap: () => _append('stdev(')),
        _Key.fn('min', onTap: () => _append('min(')),
        _Key.fn('max', onTap: () => _append('max(')),
      ],
      [
        _Key.fn('say', onTap: () => _append('count(')),
        _Key.fn('fark', onTap: () => _append('range(')),
        _Key.fn(',', onTap: () => _append(',')),
        _Key.fn('AC', onTap: _clear, color: Colors.red.shade400),
      ],
      [
        _Key.num('7'), _Key.num('8'), _Key.num('9'),
        _Key.op('×', value: '*'),
      ],
      [
        _Key.num('4'), _Key.num('5'), _Key.num('6'),
        _Key.fn('(', onTap: () => _append('(')),
      ],
      [
        _Key.num('1'), _Key.num('2'), _Key.num('3'),
        _Key.fn(')', onTap: () => _append(')')),
      ],
      [
        _Key.num('0'),
        _Key.num('.'),
        _Key.fn('=', onTap: _onEquals, color: _orangeDark, white: true),
      ],
    ];
    return _padGrid(rows);
  }

  Widget _padGrid(List<List<_Key>> rows) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: rows
            .map((r) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: r
                          .map(
                            (k) => Expanded(
                              flex: k.flex,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: _KeyButton(
                                  k: k,
                                  onNumber: _append,
                                  onOp: _append,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ─── Tuş modeli ──────────────────────────────────────────────────────────────

enum _KeyKind { num, op, fn }

class _Key {
  final String label;
  final String? value;
  final _KeyKind kind;
  final VoidCallback? onTap;
  final Color? color;
  final bool white;
  final int flex;
  _Key._(this.label, this.kind,
      {this.value, this.onTap, this.color, this.white = false, this.flex = 1});
  factory _Key.num(String label, {int flex = 1}) =>
      _Key._(label, _KeyKind.num, value: label, flex: flex);
  factory _Key.op(String label, {required String value, int flex = 1}) =>
      _Key._(label, _KeyKind.op, value: value, flex: flex);
  factory _Key.fn(String label,
          {required VoidCallback onTap,
          Color? color,
          bool white = false,
          int flex = 1}) =>
      _Key._(label, _KeyKind.fn,
          onTap: onTap, color: color, white: white, flex: flex);
}

class _KeyButton extends StatelessWidget {
  final _Key k;
  final void Function(String) onNumber;
  final void Function(String) onOp;
  const _KeyButton(
      {required this.k, required this.onNumber, required this.onOp});

  @override
  Widget build(BuildContext context) {
    final base = k.color ??
        (k.kind == _KeyKind.op
            ? const Color(0xFFFFF0E0)
            : k.kind == _KeyKind.fn
                ? const Color(0xFFF1F3F7)
                : Colors.white);
    final textColor = k.white
        ? Colors.white
        : (k.kind == _KeyKind.op
            ? const Color(0xFFFF6A00)
            : Colors.black87);
    return Material(
      color: base,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          switch (k.kind) {
            case _KeyKind.num:
              onNumber(k.value!);
              break;
            case _KeyKind.op:
              onOp(k.value!);
              break;
            case _KeyKind.fn:
              k.onTap?.call();
              break;
          }
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: k.kind == _KeyKind.num
                ? Border.all(color: Colors.grey.shade200)
                : null,
          ),
          child: Text(
            k.label,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryItem {
  final String expr;
  final String latex;
  final String result;
  const _HistoryItem(
      {required this.expr, required this.latex, required this.result});
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _Engine — ifade ayrıştır, hesapla, LaTeX'e çevir
// ═══════════════════════════════════════════════════════════════════════════════

class _Engine {
  // Klavye tuşlarının ürettiği fonksiyon adları (backspace bunları bir bütün siler)
  static const functions = [
    'asin(', 'acos(', 'atan(', 'sinh(', 'cosh(', 'tanh(',
    'sin(', 'cos(', 'tan(', 'log(', 'ln(', 'exp(', 'sqrt(', 'abs(',
    'gcd(', 'lcm(', 'mod(', 'min(', 'max(', 'nPr(', 'nCr(',
    'floor(', 'ceil(', 'round(', 'sign(', 'logb(', 'root(',
    'sum(', 'mean(', 'median(', 'var(', 'stdev(', 'count(', 'range(',
  ];

  static String format(double v) {
    if (v.isNaN) return 'NaN';
    if (v.isInfinite) return v > 0 ? '∞' : '-∞';
    if (v == v.roundToDouble() && v.abs() < 1e13) return v.toInt().toString();
    var s = v.toStringAsFixed(8);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  static double evaluate(String expr,
      {bool isDeg = true, Map<String, double> variables = const {}}) {
    return _Parser(expr, isDeg: isDeg, vars: variables).parse();
  }

  // Basit LaTeX dönüşümü: sqrt(...) → \sqrt{...}, ^2 → ^{2}, * → \cdot, / → \frac{}{}
  static String toLatex(String expr) {
    if (expr.isEmpty) return '';
    var s = expr;
    s = s.replaceAllMapped(RegExp(r'sqrt\(([^()]*)\)'),
        (m) => '\\sqrt{${m[1]}}');
    s = s.replaceAllMapped(RegExp(r'abs\(([^()]*)\)'),
        (m) => '\\left|${m[1]}\\right|');
    s = s.replaceAllMapped(RegExp(r'\^(\d+(?:\.\d+)?)'), (m) => '^{${m[1]}}');
    s = s.replaceAll('*', '\\cdot ');
    s = s.replaceAll('/', '\\div ');
    s = s.replaceAll('π', '\\pi ');
    s = s.replaceAllMapped(RegExp(r'\b(sin|cos|tan|log|ln|exp)\('),
        (m) => '\\${m[1]}(');
    s = s.replaceAllMapped(RegExp(r'\b(asin|acos|atan)\('),
        (m) => '\\${m[1]!.substring(1)}^{-1}(');
    return s;
  }
}

class _Parser {
  final String _s;
  final bool isDeg;
  final Map<String, double> vars;
  int _i = 0;

  _Parser(String s, {required this.isDeg, this.vars = const {}})
      : _s = s.replaceAll(' ', '');

  double parse() {
    final v = _expr();
    if (_i != _s.length) {
      throw FormatException('Unexpected at $_i: ${_s.substring(_i)}');
    }
    return v;
  }

  double _expr() {
    var v = _term();
    while (_i < _s.length && (_ch == '+' || _ch == '-')) {
      final op = _s[_i++];
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _factor();
    while (_i < _s.length &&
        (_ch == '*' || _ch == '/' || _ch == '%' ||
            // implicit: 2π, 3x, 4(, 2sin(
            (_isImplicit()))) {
      if (_isImplicit()) {
        v *= _factor();
        continue;
      }
      final op = _s[_i++];
      final r = _factor();
      if (op == '*') {
        v *= r;
      } else if (op == '/') {
        v = r == 0 ? double.nan : v / r;
      } else {
        v = v % r;
      }
    }
    return v;
  }

  bool _isImplicit() {
    if (_i >= _s.length) return false;
    final c = _ch;
    return c == '(' ||
        c == 'π' ||
        c == 'x' ||
        c == 'e' ||
        RegExp(r'[a-z]').hasMatch(c);
  }

  double _factor() {
    var b = _unary();
    while (_i < _s.length && _ch == '^') {
      _i++;
      final e = _unary();
      b = math.pow(b, e).toDouble();
    }
    // postfix !
    while (_i < _s.length && _ch == '!') {
      _i++;
      final n = b.toInt();
      if (n < 0 || n > 20) return double.nan;
      var f = 1;
      for (var k = 2; k <= n; k++) { f *= k; }
      b = f.toDouble();
    }
    return b;
  }

  double _unary() {
    if (_i < _s.length && _ch == '-') {
      _i++;
      return -_unary();
    }
    if (_i < _s.length && _ch == '+') _i++;
    return _atom();
  }

  double _atom() {
    if (_i >= _s.length) throw const FormatException('EOF');
    final c = _ch;

    if (c == '(') {
      _i++;
      final v = _expr();
      if (_i < _s.length && _ch == ')') _i++;
      return v;
    }
    if (c == 'π') {
      _i++;
      return math.pi;
    }
    if (c == 'e' && !_peekFunc()) {
      _i++;
      return math.e;
    }
    if (c == 'x') {
      _i++;
      final v = vars['x'];
      if (v == null) throw const FormatException('x not defined');
      return v;
    }
    if (RegExp(r'[0-9.]').hasMatch(c)) {
      final st = _i;
      while (_i < _s.length && RegExp(r'[0-9.]').hasMatch(_ch)) { _i++; }
      return double.parse(_s.substring(st, _i));
    }
    // Çok argümanlı fonksiyonlar
    const multiArg = [
      'gcd','lcm','mod','min','max','nPr','nCr',
      'floor','ceil','round','sign','logb','root',
      'sum','mean','median','var','stdev','count','range',
    ];
    for (final fn in multiArg) {
      if (_s.startsWith(fn, _i) &&
          _i + fn.length < _s.length &&
          _s[_i + fn.length] == '(') {
        _i += fn.length + 1; // ad + '('
        final args = <double>[];
        if (_ch != ')') {
          args.add(_expr());
          while (_i < _s.length && _ch == ',') {
            _i++;
            args.add(_expr());
          }
        }
        if (_i < _s.length && _ch == ')') _i++;
        return _applyMulti(fn, args);
      }
    }
    // Tek argümanlı fonksiyonlar
    for (final fn in const [
      'asin','acos','atan','sinh','cosh','tanh',
      'sin','cos','tan','log','ln','exp','sqrt','abs',
    ]) {
      if (_s.startsWith(fn, _i)) {
        _i += fn.length;
        double arg;
        if (_i < _s.length && _ch == '(') {
          _i++;
          arg = _expr();
          if (_i < _s.length && _ch == ')') _i++;
        } else {
          arg = _atom();
        }
        return _apply(fn, arg);
      }
    }
    throw FormatException('Unexpected "$c" at $_i');
  }

  bool _peekFunc() {
    // 'exp' gibi fonksiyon kontrolü — 'e' tek başınaysa sabit, 'exp' ise fonksiyon
    return _s.startsWith('exp', _i);
  }

  double _apply(String fn, double x) {
    final r = isDeg ? math.pi / 180 : 1.0;
    final d = isDeg ? 180 / math.pi : 1.0;
    switch (fn) {
      case 'sin':  return math.sin(x * r);
      case 'cos':  return math.cos(x * r);
      case 'tan':  return math.tan(x * r);
      case 'asin': return math.asin(x) * d;
      case 'acos': return math.acos(x) * d;
      case 'atan': return math.atan(x) * d;
      case 'sinh': return (math.exp(x) - math.exp(-x)) / 2;
      case 'cosh': return (math.exp(x) + math.exp(-x)) / 2;
      case 'tanh':
        final e = math.exp(2 * x);
        return (e - 1) / (e + 1);
      case 'log':  return math.log(x) / math.ln10;
      case 'ln':   return math.log(x);
      case 'exp':  return math.exp(x);
      case 'sqrt': return math.sqrt(x);
      case 'abs':  return x.abs();
      default:     return x;
    }
  }

  double _applyMulti(String fn, List<double> a) {
    if (a.isEmpty) return double.nan;
    int ii(double v) => v.round();
    int g(int x, int y) => y == 0 ? x.abs() : g(y, x % y);
    double sortNth(List<double> list, int n) {
      final s = [...list]..sort();
      return s[n];
    }

    switch (fn) {
      case 'gcd':
        return a.map(ii).reduce((x, y) => g(x.abs(), y.abs())).toDouble();
      case 'lcm':
        return a.map(ii).reduce((x, y) {
          final gg = g(x.abs(), y.abs());
          return gg == 0 ? 0 : (x.abs() ~/ gg) * y.abs();
        }).toDouble();
      case 'mod':
        if (a.length < 2 || a[1] == 0) return double.nan;
        return a[0] % a[1];
      case 'min': return a.reduce(math.min);
      case 'max': return a.reduce(math.max);
      case 'nPr':
        if (a.length < 2) return double.nan;
        final n = ii(a[0]), r = ii(a[1]);
        if (n < 0 || r < 0 || r > n) return double.nan;
        var p = 1;
        for (var k = 0; k < r; k++) { p *= (n - k); }
        return p.toDouble();
      case 'nCr':
        if (a.length < 2) return double.nan;
        final n = ii(a[0]), r = ii(a[1]);
        if (n < 0 || r < 0 || r > n) return double.nan;
        final rr = math.min(r, n - r);
        var num = 1, den = 1;
        for (var k = 0; k < rr; k++) {
          num *= (n - k);
          den *= (k + 1);
        }
        return (num / den);
      case 'floor': return a[0].floorToDouble();
      case 'ceil':  return a[0].ceilToDouble();
      case 'round': return a[0].roundToDouble();
      case 'sign':  return a[0] == 0 ? 0 : (a[0] > 0 ? 1 : -1);
      case 'logb':
        if (a.length < 2 || a[0] <= 0 || a[0] == 1 || a[1] <= 0) {
          return double.nan;
        }
        return math.log(a[1]) / math.log(a[0]);
      case 'root':
        if (a.length < 2 || a[0] == 0) return double.nan;
        return math.pow(a[1], 1 / a[0]).toDouble();
      case 'sum':
        return a.reduce((x, y) => x + y);
      case 'mean':
        return a.reduce((x, y) => x + y) / a.length;
      case 'median':
        final s = [...a]..sort();
        final n = s.length;
        return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
      case 'var':
        final m = a.reduce((x, y) => x + y) / a.length;
        return a.map((v) => (v - m) * (v - m)).reduce((x, y) => x + y) /
            a.length;
      case 'stdev':
        final m = a.reduce((x, y) => x + y) / a.length;
        final v = a.map((z) => (z - m) * (z - m)).reduce((x, y) => x + y) /
            a.length;
        return math.sqrt(v);
      case 'count': return a.length.toDouble();
      case 'range':
        return sortNth(a, a.length - 1) - sortNth(a, 0);
      default: return double.nan;
    }
  }

  String get _ch => _s[_i];
}
