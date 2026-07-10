// ═══════════════════════════════════════════════════════════════════════════════
//  CalcEngine — Hesap makinesi saf mantığı (UI bağımsız, test edilebilir).
//
//  • CalcEvaluator      : aritmetik + trig + fonksiyonlar + postfix operatörler
//  • CalcEquationSolver : 1 değişkenli doğrusal + ikinci derece denklem/eşitsizlik
//  • calcToLatex        : klavye notasyonu → flutter_math_fork LaTeX
//
//  calculator_screen.dart bu motoru kullanır; test/calculator_engine_test.dart
//  davranışı sabitler. Motor mantığı DEĞİŞİRSE testler birlikte güncellenmeli.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

/// İmleç sentineli — LaTeX önizlemede imleç konumuna eklenir; calcToLatex
/// bunu turuncu karete (imleç bir □ üstündeyse vurgulu kutuya) çevirir.
final String calcCaretMark = String.fromCharCode(0x01);

// ── Metin → LaTeX dönüştürücüsü ─────────────────────────────────────────
// Klavye ile girilen custom notasyonu flutter_math_fork'un anlayacağı LaTeX'e çevirir.
String calcToLatex(String input) {
  if (input.isEmpty) return '';
  var s = input;

  // Placeholder kutusu
  s = s.replaceAll('□', r'{\square}');

  // Türev: (d/dx)(X) → \frac{d}{dx}(X) ;  (d/d{}).. benzerleri
  s = s.replaceAllMapped(
    RegExp(r'\(d/dx\)'),
    (m) => r'\frac{d}{dx}',
  );
  s = s.replaceAllMapped(
    RegExp(r'\(d/d(\{\\square\})\)'),
    (m) => '\\frac{d}{d${m[1]}}',
  );
  s = s.replaceAllMapped(
    RegExp(r'\(d\^(\{\\square\})/d(\{\\square\})\^(\{\\square\})\)'),
    (m) => '\\frac{d^${m[1]}}{d${m[2]}^${m[3]}}',
  );

  // lim_(a→b)(X), lim_(a→b⁺)(X), lim_(a→b⁻)(X)
  s = s.replaceAllMapped(
    RegExp(r'lim_\(([^()]*?)→([^()]*?)⁺\)'),
    (m) => '\\lim_{${m[1]} \\to ${m[2]}^+}',
  );
  s = s.replaceAllMapped(
    RegExp(r'lim_\(([^()]*?)→([^()]*?)⁻\)'),
    (m) => '\\lim_{${m[1]} \\to ${m[2]}^-}',
  );
  s = s.replaceAllMapped(
    RegExp(r'lim_\(([^()]*?)→([^()]*?)\)'),
    (m) => '\\lim_{${m[1]} \\to ${m[2]}}',
  );

  // İntegral: ∫_(a)^(b)(f)dx ve ∫(f)dx
  s = s.replaceAllMapped(
    RegExp(r'∫_\(([^()]*?)\)\^\(([^()]*?)\)'),
    (m) => '\\int_{${m[1]}}^{${m[2]}}',
  );
  s = s.replaceAll('∫', r'\int ');

  // Σ_(a)^(b)(f)
  s = s.replaceAllMapped(
    RegExp(r'Σ_\(([^()]*?)\)\^\(([^()]*?)\)'),
    (m) => '\\sum_{${m[1]}}^{${m[2]}}',
  );
  s = s.replaceAll('Σ', r'\sum ');

  // Alt indis: a_b (basit tek karakter)
  s = s.replaceAllMapped(
    RegExp(r'([a-zA-Z])_([a-zA-Z0-9]|\{\\square\})'),
    (m) => '${m[1]}_{${m[2]}}',
  );

  // Karekök ve n-kök
  s = s.replaceAllMapped(
    RegExp(r'√\[([^\[\]]*?)\]\(([^()]*?)\)'),
    (m) => '\\sqrt[${m[1]}]{${m[2]}}',
  );
  s = s.replaceAllMapped(
    RegExp(r'√\(([^()]*?)\)'),
    (m) => '\\sqrt{${m[1]}}',
  );
  s = s.replaceAllMapped(
    RegExp(r'∛\(([^()]*?)\)'),
    (m) => '\\sqrt[3]{${m[1]}}',
  );
  s = s.replaceAllMapped(
    RegExp(r'∜\(([^()]*?)\)'),
    (m) => '\\sqrt[4]{${m[1]}}',
  );
  s = s.replaceAll('√', r'\sqrt ');
  s = s.replaceAll('∛', r'\sqrt[3]');
  s = s.replaceAll('∜', r'\sqrt[4]');

  // Mutlak değer: |X|
  s = s.replaceAllMapped(
    RegExp(r'\|([^|]+)\|'),
    (m) => '\\left|${m[1]}\\right|',
  );

  // det(X), conj(X) gibi
  s = s.replaceAllMapped(
    RegExp(r'\bconj\(([^()]*?)\)'),
    (m) => '\\overline{${m[1]}}',
  );
  s = s.replaceAllMapped(
    RegExp(r'\bdet\(([^()]*?)\)'),
    (m) => '\\det\\left(${m[1]}\\right)',
  );

  // logb(taban, değer) → tabanlı logaritma
  s = s.replaceAllMapped(
    RegExp(r'logb\(([^(),;]*?)[,;]([^();]*?)\)'),
    (m) => '\\log_{${m[1]}}(${m[2]})',
  );
  // Trigonometri ve log fonksiyonları (KaTeX'in tanıdığı adlar)
  s = s.replaceAllMapped(
    RegExp(
        r'\b(sin|cos|tan|cot|sec|csc|sinh|cosh|tanh|coth|log|ln|exp|arcsin|arccos|arctan)\('),
    (m) => '\\${m[1]}(',
  );
  // KaTeX'te komutu olmayan fonksiyonlar → \operatorname{...}
  s = s.replaceAllMapped(
    RegExp(r'\b(arccot|arcsec|arccsc|sech|csch|sign)\('),
    (m) => '\\operatorname{${m[1]}}(',
  );
  // Ters hiperbolikler: asinh( → sinh^{-1}(
  s = s.replaceAllMapped(
    RegExp(r'\b(a)(sinh|cosh|tanh|coth|sech|csch)\('),
    (m) => '\\operatorname{${m[2]}}^{-1}(',
  );
  // asin vs → \sin^{-1}
  s = s.replaceAllMapped(
    RegExp(r'\b(a)(sin|cos|tan|cot|sec|csc)\('),
    (m) => '\\${m[2]}^{-1}(',
  );

  // Üstler: x^2, x^{2}
  s = s.replaceAllMapped(
    RegExp(r'\^(\d+(?:\.\d+)?)'),
    (m) => '^{${m[1]}}',
  );
  s = s.replaceAll('^(-1)', '^{-1}');
  s = s.replaceAll('^n', '^{n}');

  // Kesir: a/b (basit) — sadece iki placeholder arasında kullanırız.
  // İmleç sentineli kutunun önündeyse kesrin İÇİNDE kalmalı (payda/payın
  // kutusu vurgulanır); aksi halde karet kesrin dışına düşüyordu.
  s = s.replaceAllMapped(
    RegExp('($calcCaretMark?\\{\\\\square\\})/($calcCaretMark?\\{\\\\square\\})'),
    (m) => '\\frac{${m[1]}}{${m[2]}}',
  );

  // Operatörler ve sabitler
  s = s.replaceAll('π', '\\pi ');
  s = s.replaceAll('×', '\\cdot ');
  s = s.replaceAll('÷', '\\div ');
  s = s.replaceAll('∞', '\\infty ');
  s = s.replaceAll('≥', '\\ge ');
  s = s.replaceAll('≤', '\\le ');
  s = s.replaceAll('≠', '\\ne ');
  s = s.replaceAll('≈', '\\approx ');
  s = s.replaceAll('→', '\\to ');
  // % LaTeX'te yorum karakteridir — kaçırılmazsa ifadenin kalanı YUTULUR
  s = s.replaceAll('%', r'\%');
  s = s.replaceAll('‰', r'\text{‰}');
  s = s.replaceAll('°', r'^{\circ}');
  // Birleşik kesir karakterleri
  s = s.replaceAll('½', r'\frac{1}{2}');
  s = s.replaceAll('¼', r'\frac{1}{4}');
  s = s.replaceAll('¾', r'\frac{3}{4}');
  s = s.replaceAll('⅓', r'\frac{1}{3}');

  // İmleç sentineli: hemen ardından □ geliyorsa o kutu vurgulanır,
  // değilse turuncu dikey karet çizilir. EN SON çalışmalı ki yukarıdaki
  // desen kuralları sentineli grup içeriği olarak taşıyabilsin.
  s = s.replaceFirst(
    '$calcCaretMark{\\square}',
    r'{\textcolor{#FF6A00}{\square}}',
  );
  s = s.replaceAll(
    calcCaretMark,
    r'{\textcolor{#FF6A00}{\rule[-0.24em]{0.09em}{1.25em}}}',
  );

  return s;
}


// ═══════════════════════════════════════════════════════════════════════════
//  CalcEvaluator — aritmetik + trig (derece/radyan) + değişken + örtük çarpım
//  + yüzde/permil/derece-dakika-saniye postfix'leri + faktöriyel + nPr/nCr
//  + n. kök (√[n], ∛, ∜) + |x| + logb(a,b) + tam fonksiyon seti
// ═══════════════════════════════════════════════════════════════════════════
class CalcEvaluator {
  late String _s;
  int _i = 0;
  late Map<String, double> _vars;
  late bool _isDeg;
  int _absDepth = 0; // |...| içinde miyiz — kapanış çubuğu atom başlatmasın

  /// Desteklenen fonksiyon adları — UZUN ad önce (prefix çakışması olmasın:
  /// asinh < asin < sin sırası korunmalı). CalcEquationSolver değişken
  /// tespitinde de bu listeyi kullanır.
  static const fnNames = [
    'arcsin', 'arccos', 'arctan', 'arccot', 'arcsec', 'arccsc',
    'asinh', 'acosh', 'atanh', 'acoth', 'asech', 'acsch',
    'sinh', 'cosh', 'tanh', 'coth', 'sech', 'csch',
    'asin', 'acos', 'atan', 'acot', 'asec', 'acsc',
    'sign', 'sqrt', 'logb', 'log', 'ln', 'exp', 'abs',
    'sin', 'cos', 'tan', 'cot', 'sec', 'csc',
  ];

  static const _vulgar = <String, String>{
    '½': '1/2', '¼': '1/4', '¾': '3/4', '⅓': '1/3',
  };

  double eval(String input,
      {Map<String, double> vars = const {},
      bool isDeg = true}) {
    _vars = vars;
    _isDeg = isDeg;
    var s = input
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .replaceAll(' ', '')
        .replaceAll('\n', '');
    // Karma sayı: 2½ = 2 + 1/2; tek başına ½ = 1/2
    s = s.replaceAllMapped(RegExp(r'(\d)([½¼¾⅓])'),
        (m) => '(${m[1]}+${_vulgar[m[2]]!})');
    _vulgar.forEach((k, v) {
      s = s.replaceAll(k, '($v)');
    });
    // İki argümanlı çağrılarda (logb/C/P) ilk üst-düzey virgül AYIRICIDIR;
    // ';' yapılır ki ondalık-virgül dönüşümü onu yutmasın: logb(2,8) ≠ log(2.8)
    s = _protectArgCommas(s);
    // Ondalık virgül → nokta (TR klavye ',' tuşu)
    s = s.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
    _s = s;
    _i = 0;
    _absDepth = 0;
    if (_s.isEmpty) return double.nan;
    final v = _expr();
    if (_i != _s.length) {
      throw FormatException('trailing: ${_s.substring(_i)}');
    }
    return v;
  }

  /// logb(/C(/P( çağrılarının ilk üst-düzey virgülünü ';' yapar.
  /// ',' → ';' aynı uzunlukta olduğundan indeksler kaymaz.
  static String _protectArgCommas(String s) {
    final chars = s.split('');
    for (int i = 0; i < s.length; i++) {
      int start = -1;
      if (s.startsWith('logb(', i)) {
        start = i + 5;
      } else if ((s[i] == 'C' || s[i] == 'P') &&
          i + 1 < s.length &&
          s[i + 1] == '(') {
        start = i + 2;
      }
      if (start < 0) continue;
      var depth = 1;
      for (int j = start; j < s.length; j++) {
        final c = s[j];
        if (c == '(' || c == '[' || c == '{') depth++;
        if (c == ')' || c == ']' || c == '}') {
          depth--;
          if (depth == 0) break;
        }
        if (c == ',' && depth == 1) {
          chars[j] = ';';
          break;
        }
      }
    }
    return chars.join();
  }

  double _expr() {
    var v = _term();
    while (_i < _s.length && (_s[_i] == '+' || _s[_i] == '-')) {
      final op = _s[_i++];
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _unary();
    while (_i < _s.length) {
      final c = _s[_i];
      if (c == '*') {
        _i++;
        v *= _unary();
      } else if (c == '/') {
        _i++;
        final r = _unary();
        v = r == 0 ? double.nan : v / r;
      } else if (c == '%' && _modOperand()) {
        // Sağında işlenen varsa mod, yoksa _postfix yüzde olarak tüketir
        _i++;
        final r = _unary();
        v = r == 0 ? double.nan : v % r;
      } else if ((c == 'P' || c == 'C') &&
          _i + 1 < _s.length &&
          _s[_i + 1] != '(' &&
          _startsAtomAt(_i + 1)) {
        // nPr / nCr infix: 5P2, 5C2. 'C(' fonksiyon biçimi _atom'da.
        _i++;
        final r = _unary();
        v = c == 'P' ? _perm(v, r) : _comb(v, r);
      } else if (_canStartAtom()) {
        // Örtük çarpım: 2x, 2(x+1), 2sin30, 2π — güç seviyesinde bağlanır
        v *= _power();
      } else {
        break;
      }
    }
    return v;
  }

  bool _modOperand() => _startsAtomAt(_i + 1);

  bool _canStartAtom() => _startsAtomAt(_i);

  bool _startsAtomAt(int idx) {
    if (idx >= _s.length) return false;
    final c = _s[idx];
    if (c == '(' || c == '[' || c == '{' ||
        c == 'π' || c == '√' || c == '∛' || c == '∜') {
      return true;
    }
    if (c == '|') return _absDepth == 0;
    if (RegExp(r'[0-9.]').hasMatch(c)) return true;
    return RegExp(r'[a-zA-ZαβθρφΦω]').hasMatch(c);
  }

  // Tekli işaret ÜSTTEN DÜŞÜK öncelikli: -2^2 = -(2^2) = -4 (Photomath kuralı)
  double _unary() {
    if (_i < _s.length && _s[_i] == '-') {
      _i++;
      return -_unary();
    }
    if (_i < _s.length && _s[_i] == '+') {
      _i++;
      return _unary();
    }
    return _power();
  }

  double _power() {
    var v = _postfix();
    if (_i < _s.length && _s[_i] == '^') {
      _i++;
      // Üs sağdan bağlanır ve işaretli olabilir: 2^-3, 2^3^2 = 2^(3^2)
      v = math.pow(v, _unary()).toDouble();
    }
    return v;
  }

  // Postfix operatörler: ! (faktöriyel), % (yüzde), ‰ (binde), °'" (açı)
  double _postfix() {
    var v = _atom();
    while (_i < _s.length) {
      final c = _s[_i];
      if (c == '!') {
        _i++;
        v = _fact(v);
      } else if (c == '%' && !_modOperand()) {
        _i++;
        v /= 100;
      } else if (c == '‰') {
        _i++;
        v /= 1000;
      } else if (c == '°') {
        v = _dms(v);
      } else {
        break;
      }
    }
    return v;
  }

  /// Derece(-dakika-saniye): 45° ; 30°15' ; 30°15'40"
  /// Derece modunda ° kimliktir; radyan modunda radyana çevirir.
  double _dms(double deg) {
    _i++; // °
    var total = deg;
    var save = _i;
    final min = _tryNumber();
    if (min != null && _i < _s.length && _s[_i] == "'") {
      _i++;
      total += min / 60;
      save = _i;
      final sec = _tryNumber();
      if (sec != null && _i < _s.length && _s[_i] == '"') {
        _i++;
        total += sec / 3600;
      } else {
        _i = save;
      }
    } else {
      _i = save;
    }
    return _isDeg ? total : total * math.pi / 180;
  }

  double? _tryNumber() {
    final st = _i;
    while (_i < _s.length && RegExp(r'[0-9.]').hasMatch(_s[_i])) {
      _i++;
    }
    if (_i == st) return null;
    final v = double.tryParse(_s.substring(st, _i));
    if (v == null) {
      _i = st;
      return null;
    }
    return v;
  }

  double _fact(double v) {
    if (v < 0 || v != v.roundToDouble() || v > 170) return double.nan;
    var f = 1.0;
    for (var k = 2; k <= v.round(); k++) {
      f *= k;
    }
    return f;
  }

  double _perm(double n, double k) {
    if (n < 0 || k < 0 ||
        n != n.roundToDouble() || k != k.roundToDouble() ||
        k > n) {
      return double.nan;
    }
    var r = 1.0;
    for (var j = 0; j < k.round(); j++) {
      r *= n - j;
    }
    return r;
  }

  double _comb(double n, double k) {
    final p = _perm(n, k);
    return p.isNaN ? p : p / _fact(k);
  }

  /// n. kök — negatif tabanda tek dereceli kök geçerli: ∛(-8) = -2
  double _nthRoot(double x, double n) {
    if (n == 0) return double.nan;
    if (x < 0) {
      if (n == n.roundToDouble() && n.round().isOdd) {
        return -math.pow(-x, 1 / n).toDouble();
      }
      return double.nan;
    }
    return math.pow(x, 1 / n).toDouble();
  }

  double _atom() {
    if (_i >= _s.length) throw const FormatException('eof');
    final c = _s[_i];
    if (c == '(' || c == '[' || c == '{') {
      _i++;
      final v = _expr();
      if (_i < _s.length && ')]}'.contains(_s[_i])) _i++;
      return v;
    }
    if (c == '|') {
      _i++;
      _absDepth++;
      final v = _expr();
      _absDepth--;
      if (_i < _s.length && _s[_i] == '|') _i++;
      return v.abs();
    }
    if (c == 'π') {
      _i++;
      return math.pi;
    }
    if (RegExp(r'[0-9.]').hasMatch(c)) {
      final v = _tryNumber();
      if (v == null) throw const FormatException('sayı');
      return v;
    }
    if (c == '√') {
      _i++;
      // √[n](x) — n. kök
      if (_i < _s.length && _s[_i] == '[') {
        _i++;
        final n = _expr();
        if (_i < _s.length && _s[_i] == ']') _i++;
        return _nthRoot(_atom(), n);
      }
      return _nthRoot(_atom(), 2);
    }
    if (c == '∛') {
      _i++;
      return _nthRoot(_atom(), 3);
    }
    if (c == '∜') {
      _i++;
      return _nthRoot(_atom(), 4);
    }
    // C(n,k) / P(n,k) fonksiyon biçimi (virgül _protectArgCommas ile ';')
    if ((c == 'C' || c == 'P') && _i + 1 < _s.length && _s[_i + 1] == '(') {
      _i += 2;
      final a = _expr();
      if (_i < _s.length && (_s[_i] == ';' || _s[_i] == ',')) {
        _i++;
      } else {
        throw const FormatException('C/P iki argüman ister');
      }
      final b = _expr();
      if (_i < _s.length && _s[_i] == ')') _i++;
      return c == 'C' ? _comb(a, b) : _perm(a, b);
    }
    // Fonksiyonlar (parantezli veya parantezsiz: sin 30 = sin(30))
    for (final fn in fnNames) {
      if (_s.startsWith(fn, _i)) {
        _i += fn.length;
        if (fn == 'logb') {
          // logb(taban, değer)
          if (_i >= _s.length || _s[_i] != '(') {
            throw const FormatException('logb(');
          }
          _i++;
          final base = _expr();
          if (_i < _s.length && (_s[_i] == ';' || _s[_i] == ',')) {
            _i++;
          } else {
            throw const FormatException('logb iki argüman ister');
          }
          final x = _expr();
          if (_i < _s.length && _s[_i] == ')') _i++;
          if (base <= 0 || base == 1 || x <= 0) return double.nan;
          return math.log(x) / math.log(base);
        }
        double arg;
        if (_i < _s.length && _s[_i] == '(') {
          _i++;
          arg = _expr();
          if (_i < _s.length && _s[_i] == ')') _i++;
        } else {
          arg = _postfix(); // sin30° gibi postfix'li argüman da çalışsın
        }
        return _apply(fn, arg);
      }
    }
    if (c == 'e') {
      _i++;
      return math.e;
    }
    // Değişken (tek harf — Yunan harfleri dahil)
    if (RegExp(r'[a-zA-ZαβθρφΦω]').hasMatch(c)) {
      _i++;
      if (_vars.containsKey(c)) return _vars[c]!;
      throw FormatException('unknown var: $c');
    }
    throw FormatException('unexpected "$c" at $_i');
  }

  double _apply(String fn, double x) {
    final r = _isDeg ? math.pi / 180 : 1.0;
    final d = _isDeg ? 180 / math.pi : 1.0;
    switch (fn) {
      case 'sin':
        return math.sin(x * r);
      case 'cos':
        return math.cos(x * r);
      case 'tan': {
        // tan90° matematiksel tanımsız — dev yuvarlama artığı gösterme
        if (math.cos(x * r).abs() < 1e-12) return double.nan;
        return math.tan(x * r);
      }
      case 'cot': {
        final s = math.sin(x * r);
        if (s.abs() < 1e-12) return double.nan;
        return math.cos(x * r) / s;
      }
      case 'sec': {
        final c = math.cos(x * r);
        if (c.abs() < 1e-12) return double.nan;
        return 1 / c;
      }
      case 'csc': {
        final s = math.sin(x * r);
        if (s.abs() < 1e-12) return double.nan;
        return 1 / s;
      }
      case 'asin':
      case 'arcsin':
        return math.asin(x) * d;
      case 'acos':
      case 'arccos':
        return math.acos(x) * d;
      case 'atan':
      case 'arctan':
        return math.atan(x) * d;
      case 'acot':
      case 'arccot':
        return (math.pi / 2 - math.atan(x)) * d;
      case 'asec':
      case 'arcsec':
        return x == 0 ? double.nan : math.acos(1 / x) * d;
      case 'acsc':
      case 'arccsc':
        return x == 0 ? double.nan : math.asin(1 / x) * d;
      case 'sinh':
        return (math.exp(x) - math.exp(-x)) / 2;
      case 'cosh':
        return (math.exp(x) + math.exp(-x)) / 2;
      case 'tanh': {
        final e2 = math.exp(2 * x);
        return (e2 - 1) / (e2 + 1);
      }
      case 'coth': {
        final e2 = math.exp(2 * x);
        return e2 == 1 ? double.nan : (e2 + 1) / (e2 - 1);
      }
      case 'sech':
        return 2 / (math.exp(x) + math.exp(-x));
      case 'csch': {
        final dd = math.exp(x) - math.exp(-x);
        return dd == 0 ? double.nan : 2 / dd;
      }
      case 'asinh':
        return math.log(x + math.sqrt(x * x + 1));
      case 'acosh':
        return x < 1 ? double.nan : math.log(x + math.sqrt(x * x - 1));
      case 'atanh':
        return x.abs() >= 1
            ? double.nan
            : 0.5 * math.log((1 + x) / (1 - x));
      case 'acoth':
        return x.abs() <= 1
            ? double.nan
            : 0.5 * math.log((x + 1) / (x - 1));
      case 'asech':
        return (x <= 0 || x > 1)
            ? double.nan
            : math.log((1 + math.sqrt(1 - x * x)) / x);
      case 'acsch':
        return x == 0
            ? double.nan
            : math.log(1 / x + math.sqrt(1 / (x * x) + 1));
      case 'log':
        return x <= 0 ? double.nan : math.log(x) / math.ln10;
      case 'ln':
        return x <= 0 ? double.nan : math.log(x);
      case 'exp':
        return math.exp(x);
      case 'sqrt':
        return x < 0 ? double.nan : math.sqrt(x);
      case 'abs':
        return x.abs();
      case 'sign':
        return x > 0 ? 1 : (x < 0 ? -1 : 0);
      default:
        return x;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  CalcEquationSolver — 1 değişkenli doğrusal + ikinci derece denklem/eşitsizlik
//  Değişken harfi otomatik bulunur (x şart değil: 2y=10 → y=5).
//  Örnekler: 2x<12 → x<6 ; 3x+1=10 → x=3 ; x^2-x-6=0 → x₁=-2 x₂=3
// ═══════════════════════════════════════════════════════════════════════════
class CalcEquationSolver {
  static const _ops = ['≤', '≥', '≠', '=', '<', '>'];

  static String? solve(String text, {bool isDeg = true}) {
    // Karşılaştırma operatörünü bul
    String? op;
    int? idx;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (_ops.contains(c)) {
        op = c;
        idx = i;
        break;
      }
    }
    if (op == null || idx == null) return null;

    final leftRaw = text.substring(0, idx).trim();
    final rightRaw = text.substring(idx + op.length).trim();
    if (leftRaw.isEmpty || rightRaw.isEmpty) return null;
    // Zincirli karşılaştırma (5<x<10) desteklenmiyor
    if (rightRaw.split('').any(_ops.contains)) return null;

    final variable = _detectVar('$leftRaw $rightRaw');
    if (variable == null) return null;

    try {
      // g(x) = sol − sağ;  koşul: sol op sağ ⇔ g op 0
      double g(double x) {
        final vars = variable.isEmpty
            ? const <String, double>{}
            : {variable: x};
        final l = CalcEvaluator().eval(leftRaw, vars: vars, isDeg: isDeg);
        final r = CalcEvaluator().eval(rightRaw, vars: vars, isDeg: isDeg);
        return l - r;
      }

      if (variable.isEmpty) {
        // Değişkensiz ifade: 3+2=5 → Doğru
        final v = g(0);
        if (v.isNaN || v.isInfinite) return null;
        return _check(v, op, 0) ? 'Doğru' : 'Yanlış';
      }

      final g0 = g(0), g1 = g(1), g2 = g(2), g3 = g(3);
      if ([g0, g1, g2, g3].any((e) => e.isNaN || e.isInfinite)) return null;

      // Doğrusallık: ikinci fark 0
      if ((g2 - 2 * g1 + g0).abs() < 1e-6) {
        final a = g1 - g0;
        final c = g0;
        // Üçüncü örnekle doğrula (trig sahte pozitifini ele)
        if ((g3 - (a * 3 + c)).abs() > 1e-6) return null;
        if (a.abs() < 1e-12) {
          final holds = _check(c, op, 0);
          return holds ? 'Her değer için doğru' : 'Çözüm yok';
        }
        final x = -c / a;
        var resultOp = op;
        // a < 0 ise eşitsizlik yönü değişir
        if (a < 0 && const ['<', '>', '≤', '≥'].contains(op)) {
          resultOp = _flip(op);
        }
        return '$variable $resultOp ${_fmt(x)}';
      }

      // İkinci derece: üçüncü fark 0 (yalnız '=' çözülür)
      if ((g3 - 3 * g2 + 3 * g1 - g0).abs() < 1e-6 && op == '=') {
        final a = (g2 - 2 * g1 + g0) / 2;
        final b = g1 - g0 - a;
        final c = g0;
        // Dördüncü örnekle doğrula
        final g4 = g(4);
        if ((g4 - (16 * a + 4 * b + c)).abs() > 1e-5) return null;
        final disc = b * b - 4 * a * c;
        if (disc < -1e-9) return 'Gerçek çözüm yok';
        if (disc.abs() < 1e-9) {
          return '$variable = ${_fmt(-b / (2 * a))}';
        }
        final sq = math.sqrt(disc);
        var x1 = (-b - sq) / (2 * a);
        var x2 = (-b + sq) / (2 * a);
        if (x1 > x2) {
          final t = x1;
          x1 = x2;
          x2 = t;
        }
        return '$variable₁ = ${_fmt(x1)}   $variable₂ = ${_fmt(x2)}';
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Metindeki değişken harfini bul: '' = değişken yok (sabit ifade),
  /// null = birden çok farklı harf (çözülemez). e/i/π sabittir.
  static String? _detectVar(String text) {
    var t = text;
    for (final fn in CalcEvaluator.fnNames) {
      t = t.replaceAll(fn, ' ');
    }
    // nPr/nCr infix operatörleri ve C(/P( fonksiyonları değişken değildir
    t = t.replaceAll(RegExp(r'(?<=[0-9)\]}])[CP](?=[0-9(√π])'), ' ');
    t = t.replaceAll(RegExp(r'\b[CP]\('), ' (');
    final letters = <String>{};
    for (final ch in t.split('')) {
      if (ch == 'e' || ch == 'i') continue;
      if (RegExp(r'[a-zA-ZαβθρφΦω]').hasMatch(ch)) letters.add(ch);
    }
    if (letters.isEmpty) return '';
    if (letters.length == 1) return letters.first;
    return null;
  }

  static bool _check(double a, String op, double b) {
    switch (op) {
      case '<':  return a < b;
      case '>':  return a > b;
      case '≤':  return a <= b;
      case '≥':  return a >= b;
      case '≠':  return a != b;
      case '=':  return (a - b).abs() < 1e-9;
      default: return false;
    }
  }

  static String _flip(String op) {
    switch (op) {
      case '<': return '>';
      case '>': return '<';
      case '≤': return '≥';
      case '≥': return '≤';
      default: return op;
    }
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e13) {
      return v.toInt().toString();
    }
    var s = v.toStringAsFixed(6);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }
}
