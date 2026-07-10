// Hesap makinesi motoru davranış sabitleme testleri.
// Motor: lib/features/calculator/calc_engine.dart
// Photomath-parite kuralları (öncelik, yüzde, DMS, nPr/nCr, logb, kökler,
// denklem çözücü) burada kilitlenir — motor değişirse bilinçli güncellenmeli.

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_nova/features/calculator/calc_engine.dart';

void _n(String expr, double want, {bool isDeg = true, double tol = 1e-9}) {
  final got = CalcEvaluator().eval(expr, isDeg: isDeg);
  if (want.isNaN) {
    expect(got.isNaN, isTrue, reason: '$expr → $got (NaN beklenirdi)');
  } else {
    expect(got, closeTo(want, tol), reason: '$expr → $got (beklenen $want)');
  }
}

void _s(String expr, String? want, {bool isDeg = true}) {
  expect(CalcEquationSolver.solve(expr, isDeg: isDeg), want, reason: expr);
}

void main() {
  group('CalcEvaluator — aritmetik ve öncelik', () {
    test('temel işlemler', () {
      _n('2+3*4', 14);
      _n('(2)3', 6); // örtük çarpım
      _n('2,5+2,5', 5); // ondalık virgül
    });
    test('üs/işaret önceliği (Photomath kuralı)', () {
      _n('-2^2', -4);
      _n('(-2)^2', 4);
      _n('2^-3', 0.125);
      _n('2^3^2', 512); // sağdan bağlanır
    });
  });

  group('CalcEvaluator — yüzde/permil/mod', () {
    test('yüzde postfix', () {
      _n('50%', 0.5);
      _n('50%+1', 1.5);
      _n('200*10%', 20);
      _n('250‰', 0.25);
    });
    test('mod (sağında işlenen varsa)', () => _n('10%3', 1));
  });

  group('CalcEvaluator — faktöriyel ve kombinatorik', () {
    test('faktöriyel', () {
      _n('5!', 120);
      _n('0!', 1);
      _n('21!', 51090942171709440000); // eski 20 tavanı kalktı
    });
    test('nPr / nCr infix + fonksiyon biçimi', () {
      _n('5P2', 20);
      _n('5C2', 10);
      _n('C(5,2)', 10);
      _n('P(5,2)', 20);
      _n('2C(5,2)', 20); // örtük çarpım
    });
  });

  group('CalcEvaluator — kökler ve mutlak değer', () {
    test('kökler', () {
      _n('√9', 3);
      _n('√[3](27)', 3);
      _n('√[3](-8)', -2); // tek dereceli kökte negatif taban
      _n('∛(64)', 4);
      _n('∜(81)', 3);
    });
    test('mutlak değer', () {
      _n('|0-5|', 5);
      _n('|3-7|+1', 5);
      _n('2|0-3|', 6);
    });
  });

  group('CalcEvaluator — logaritma ve üstel', () {
    test('log/ln/logb', () {
      _n('log(100)', 2);
      _n('ln(e)', 1);
      _n('logb(2,8)', 3); // virgül ayırıcı korunur (ondalık sanılmaz)
      _n('logb(3,81)', 4);
    });
  });

  group('CalcEvaluator — trigonometri', () {
    test('derece modu', () {
      _n('sin(30)', 0.5, tol: 1e-12);
      _n('cot(45)', 1, tol: 1e-12);
      _n('sec(60)', 2, tol: 1e-12);
      _n('csc(30)', 2, tol: 1e-12);
      _n('tan(90)', double.nan); // tanımsız — dev sayı değil
      _n('asin(0.5)', 30);
      _n('acot(1)', 45);
    });
    test('açı notasyonu (DMS)', () {
      _n('sin(30°)', 0.5, tol: 1e-12);
      _n("45°30'", 45.5);
      _n('30°15\'36"', 30.26);
    });
    test('radyan modu + ° çevirisi', () {
      _n('sin(π/6)', 0.5, isDeg: false, tol: 1e-12);
      _n('sin(30°)', 0.5, isDeg: false, tol: 1e-12);
    });
    test('hiperbolikler', () {
      _n('sinh(0)', 0);
      _n('coth(1)', 1.3130352854993312);
      _n('atanh(0.5)', 0.5493061443340549);
      _n('sign(0-7)', -1);
    });
  });

  group('CalcEvaluator — birleşik kesirler', () {
    test('vulgar kesirler + karma sayı', () {
      _n('½', 0.5);
      _n('2½', 2.5); // karma sayı: 2 + 1/2
      _n('¾+¼', 1);
    });
  });

  group('CalcEquationSolver', () {
    test('doğrusal denklem/eşitsizlik — değişken otomatik', () {
      _s('2x<12', 'x < 6');
      _s('3x+1=10', 'x = 3');
      _s('5-2x>1', 'x < 2'); // negatif katsayı yön çevirir
      _s('2y=10', 'y = 5');
      _s('2θ=90', 'θ = 45');
    });
    test('değişkensiz ifadeler', () {
      _s('3+2=5', 'Doğru');
      _s('3+2=6', 'Yanlış');
    });
    test('özdeşlik / çözümsüz', () {
      _s('x+1=x+1', 'Her değer için doğru');
      _s('x+1=x+2', 'Çözüm yok');
    });
    test('ikinci derece', () {
      _s('x^2-x-6=0', 'x₁ = -2   x₂ = 3');
      _s('x^2=9', 'x₁ = -3   x₂ = 3');
      _s('x^2+1=0', 'Gerçek çözüm yok');
      _s('x^2-4x+4=0', 'x = 2'); // çift kök
    });
  });

  group('calcToLatex — şablon dönüşümleri', () {
    test('limit/integral/türev/toplam şablonları ham kalmaz', () {
      final cases = <String>[
        'lim_(□→□⁺)(□)',
        'lim_(□→□⁻)(□)',
        '(d/dx)(□)',
        '(d^□/d□^□)(□)',
        '∫_(□)^(□)(□)d□',
        'Σ_(□)^(□)(□)',
        '√[□](□)',
        'logb(□,□)',
        '∛(□)',
        '|□|',
        '□/□',
      ];
      for (final tpl in cases) {
        final out = calcToLatex(tpl);
        for (final ham in ['lim_(', 'logb(', '√[', '∛', 'Σ_(', '∫_(']) {
          expect(out.contains(ham), isFalse,
              reason: '$tpl → $out (ham artık: $ham)');
        }
      }
    });

    test('yüzde LaTeX yorum karakteri olarak yutulmaz', () {
      expect(calcToLatex('50%+1'), contains(r'\%'));
    });

    test('imleç şablon içindeyken kutu vurgulanır', () {
      final tpl = 'lim_(□→□⁺)(□)';
      final pos = tpl.indexOf('□');
      final marked = tpl.replaceRange(pos, pos, calcCaretMark);
      final out = calcToLatex(marked);
      expect(out, contains(r'\lim_'));
      expect(out, contains(r'\textcolor{#FF6A00}{\square}'));
      expect(out.contains(calcCaretMark), isFalse);
    });
  });
}
