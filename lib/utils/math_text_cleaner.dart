// ═══════════════════════════════════════════════════════════════════════════
//  cleanMathText — AI'ın ürettiği LaTeX/markup artıklarını temiz Unicode metne
//  çevirir. Uygulama kuralı (education format): ekranda $/LaTeX kodu GÖRÜNMEZ;
//  alt/üst indis ve semboller Unicode ile yazılır (H₂O, CO₂, →, ×, Δ …).
//
//  Örn:  "\( \text{BaCl}_2\text{(aq)} \to \text{BaSO}_4 \)"
//     →  "BaCl₂(aq) → BaSO₄"
// ═══════════════════════════════════════════════════════════════════════════

const Map<String, String> _subscripts = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
  'n': 'ₙ', 'x': 'ₓ', 'a': 'ₐ',
};

const Map<String, String> _superscripts = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾', 'n': 'ⁿ',
};

// LaTeX komut → Unicode sembol.
const Map<String, String> _symbols = {
  r'\to': '→', r'\rightarrow': '→', r'\Rightarrow': '⇒',
  r'\leftarrow': '←', r'\leftrightarrow': '↔', r'\rightleftharpoons': '⇌',
  r'\times': '×', r'\cdot': '·', r'\div': '÷', r'\pm': '±', r'\mp': '∓',
  r'\leq': '≤', r'\geq': '≥', r'\neq': '≠', r'\approx': '≈',
  r'\equiv': '≡', r'\infty': '∞', r'\propto': '∝',
  r'\Delta': 'Δ', r'\delta': 'δ', r'\alpha': 'α', r'\beta': 'β',
  r'\gamma': 'γ', r'\theta': 'θ', r'\lambda': 'λ', r'\mu': 'μ',
  r'\pi': 'π', r'\rho': 'ρ', r'\sigma': 'σ', r'\omega': 'ω',
  r'\Omega': 'Ω', r'\degree': '°', r'\circ': '°',
  r'\sqrt': '√', r'\sum': '∑', r'\int': '∫', r'\partial': '∂',
  r'\le': '≤', r'\ge': '≥', r'\ne': '≠', r'\rightarrowfill': '→',
};

String _mapRun(String run, Map<String, String> table) {
  final sb = StringBuffer();
  for (final ch in run.split('')) {
    sb.write(table[ch] ?? ch);
  }
  return sb.toString();
}

/// LaTeX/markup artıklı metni temiz Unicode'a çevirir. Zaten temiz metni bozmaz.
String cleanMathText(String input) {
  if (input.isEmpty) return input;
  var s = input;
  if (!s.contains(RegExp(r'[\\${}^_]'))) return s; // temiz → dokunma

  // 1) Matematik sınırlayıcıları kaldır: \( \) \[ \] $$ $
  s = s
      .replaceAll(r'\(', ' ')
      .replaceAll(r'\)', ' ')
      .replaceAll(r'\[', ' ')
      .replaceAll(r'\]', ' ')
      .replaceAll(r'\!', '')
      .replaceAll(r'\,', ' ')
      .replaceAll(r'\;', ' ')
      .replaceAll(r'\ ', ' ')
      .replaceAll(r'$$', '')
      .replaceAll(r'$', '');

  // 2) \text{...}, \mathrm{...}, \mathbf{...} → içeriği aynen bırak
  final wrapCmd = RegExp(r'\\(?:text|mathrm|mathbf|mathit|mathsf|operatorname)\s*\{([^{}]*)\}');
  for (var i = 0; i < 6 && wrapCmd.hasMatch(s); i++) {
    s = s.replaceAllMapped(wrapCmd, (m) => m.group(1) ?? '');
  }
  // \frac{a}{b} → (a/b)
  final frac = RegExp(r'\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}');
  for (var i = 0; i < 6 && frac.hasMatch(s); i++) {
    s = s.replaceAllMapped(frac, (m) => '(${m.group(1)}/${m.group(2)})');
  }

  // 3) Semboller (\to, \times, \Delta …). Uzun anahtar önce.
  final keys = _symbols.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    s = s.replaceAll(k, _symbols[k]!);
  }

  // 4) Alt indis: _{...} ve _x
  s = s.replaceAllMapped(
      RegExp(r'_\{([^{}]*)\}'), (m) => _mapRun(m.group(1) ?? '', _subscripts));
  s = s.replaceAllMapped(
      RegExp(r'_([0-9A-Za-z+\-=()])'), (m) => _mapRun(m.group(1) ?? '', _subscripts));
  // 5) Üst indis: ^{...} ve ^x
  s = s.replaceAllMapped(
      RegExp(r'\^\{([^{}]*)\}'), (m) => _mapRun(m.group(1) ?? '', _superscripts));
  s = s.replaceAllMapped(
      RegExp(r'\^([0-9A-Za-z+\-=()])'), (m) => _mapRun(m.group(1) ?? '', _superscripts));

  // 6) Kalan LaTeX süslü parantez/backslash'leri temizle
  s = s.replaceAll('{', '').replaceAll('}', '');
  s = s.replaceAll(RegExp(r'\\[a-zA-Z]+'), ''); // bilinmeyen komutlar
  s = s.replaceAll('\\', '');

  // 7) Fazla boşlukları sadeleştir
  s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  return s;
}
