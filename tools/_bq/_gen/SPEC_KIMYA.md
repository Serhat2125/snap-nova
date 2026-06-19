# KİMYA Soru Bankası — Profesör Düzeyi Titizlik Eki

`SPEC.md` kurallarına EKtir. ÖNCE `SPEC.md`'yi oku, sonra burayı uygula.
Kimyada hata KABUL EDİLMEZ: formüller, denklem denklikleri, yükler, sayısal sonuçlar
ve birimler eksiksiz/doğru olmalı. Görsel (SVG `fig`) oranı kimyada **~%30** (atom/molekül
şeması, bağ, periyodik konum, tepkime düzeneği gerektiğinde).

## Gösterim kuralları (TUTARLI uygula)
- **Formüller Unicode ile**: alt indis için alt simge yerine normal rakam KULLANMA; gerçek
  alt indis Unicode yoksa düz yaz ama tutarlı ol. Tercih: H₂O, CO₂, O₂, N₂, CaCO₃, H₂SO₄,
  NaCl, NH₃, CH₄, C₆H₁₂O₆, HCl, NaOH, H₃O⁺, OH⁻, SO₄²⁻, NO₃⁻, CO₃²⁻, PO₄³⁻, NH₄⁺.
  (Alt indis Unicode: ₀₁₂₃₄₅₆₇₈₉ ; üst/yük: ⁺ ⁻ ² ³ ⁴ ⁵ ⁶.)
- **Yükler** üst simge: Na⁺, Cl⁻, Mg²⁺, Al³⁺, Fe²⁺/Fe³⁺, O²⁻, Ca²⁺.
- **Tepkime oku** →, **denge** ⇌, **çift yön** ⇌. Isı/koşul ok üstüne yazılmaz; gerekiyorsa
  metinde belirt ("ısı verir", "katalizör eşliğinde").
- **Hal belirteçleri** gerektiğinde: (k) katı, (s) sıvı, (g) gaz, (suda) sulu çözelti.
- **LaTeX / `$...$` / `\(...\)` / markdown `**` KESİNLİKLE YASAK** (SPEC.md). Sadece `<b>`.
- Ondalık ayraç **virgül** (1,5 mol; 22,4 L; 6,02). Birim her zaman yazılır (mol, g, L, kJ, °C, atm, M).

## Denklem denkliği (ZORUNLU)
- Her tepkime denklemi **denk** olmalı (atom sayıları iki tarafta eşit, yük korunur).
- Sayısal sorularda `steps` içinde: denklemi yaz → katsayı/mol oranını belirt → değerleri
  yerine koy → sonucu birimiyle ver. Mol oranını açıkça göster.
- Örnek denk tepkimeler (doğru kullan): 2H₂ + O₂ → 2H₂O ; CH₄ + 2O₂ → CO₂ + 2H₂O ;
  N₂ + 3H₂ ⇌ 2NH₃ ; 2Na + Cl₂ → 2NaCl ; CaCO₃ → CaO + CO₂ ; HCl + NaOH → NaCl + H₂O.

## Sabitler ve değerler (TR müfredatı — tutarlı)
- Avogadro sayısı N_A = 6,02·10²³ tane/mol.
- Normal koşullarda (NK: 0 °C, 1 atm) 1 mol gaz = **22,4 L**.
- mol = kütle(g) / molmüktarı(g/mol) = tanecik / N_A = hacim(L) / 22,4 (NK gaz).
- Molarite M = mol / hacim(L). Kütle yüzdesi = (çözünen/çözelti)·100.
- Atom kütleleri (g/mol): H=1, C=12, N=14, O=16, Na=23, Mg=24, S=32, Cl=35,5, K=39, Ca=40, Fe=56.
- pH = −log[H⁺]; nötr pH=7 (25 °C); asit <7, baz >7. pH + pOH = 14.

## Konu bazlı doğruluk notları
- **Maddenin Yapısı:** saf madde (element/bileşik) vs karışım (homojen/heterojen); fiziksel
  vs kimyasal değişim; hal değişimi adları (erime, donma, buharlaşma, yoğuşma, süblimleşme).
- **Atom Teorisi / Orbitaller:** Dalton→Thomson→Rutherford→Bohr→modern model sırası ve
  her birinin katkısı/eksiği; p=e (nötr atom), kütle no=p+n; orbital türleri s(2),p(6),d(10),f(14);
  Aufbau, Pauli, Hund; elektron dizilimi (1s² 2s² 2p⁶ ...).
- **Periyodik Sistem:** grup/periyot; metal/ametal/yarımetal/soygaz; periyodik özellik
  eğilimleri — atom yarıçapı (soldan sağa azalır, yukarıdan aşağı artar), iyonlaşma enerjisi
  ve elektronegatiflik (tam tersi). Değerlik elektronu = grup ile ilişki.
- **Kimyasal Bağlar:** iyonik (metal+ametal, e aktarımı), kovalent (ametal+ametal, e ortaklığı;
  apolar/polar), metalik; Lewis yapısı, oktet, bağ polaritesi, hidrojen bağı / van der Waals.
- **Molekül Geometrisi (VSEPR):** elektron çiftine göre — doğrusal (180°), düzlem üçgen (120°),
  açısal, düzgün dörtyüzlü (109,5°), üçgen piramit; örnek: CO₂ doğrusal, H₂O açısal (~104,5°),
  NH₃ üçgen piramit, CH₄ dörtyüzlü. Bağ açısı ve ortaklanmamış çift etkisi.
- **Mol & Stokiyometri:** mol-kütle-tanecik-hacim dönüşümleri; sınırlayıcı bileşen; verim;
  denklemden mol oranıyla hesap. Sayısal sonuçları daima kontrol et (kütle korunumu).
- **Kimyasal Tepkimeler:** yanma, sentez (birleşme), analiz (ayrışma), yer değiştirme, asit-baz
  nötrleşme, çökelme; endotermik/ekzotermik; tepkime hızı ve denge (Le Chatelier) lise düzeyinde.
- **Organik Kimya:** C'nin 4 bağı; hidrokarbon sınıfları (alkan CₙH₂ₙ₊₂, alken CₙH₂ₙ, alkin CₙH₂ₙ₋₂);
  fonksiyonel gruplar (−OH alkol, −COOH karboksilik asit, −CHO aldehit, C=O keton, −NH₂ amin);
  izomeri; basit adlandırma (metan, etan, propan, bütan...).

## SVG fig kuralları (kimya, ~%30 soruda)
- `SPEC_FIZIK.md` SVG kurallarının AYNISI geçerli (tek tırnak, light arka plan #f5f7fa, koyu
  çizgi/yazı #1a2b45, width/height yok, sadece izinli etiketler, `<script>`/`href`/çift tırnak YOK).
- Kimya görselleri: atom modeli (çekirdek + elektron kabukları), Lewis nokta yapısı, molekül
  geometrisi (merkez atom + bağlar + açı), periyodik tablo konumu (grup/periyot hücresi),
  bağ şeması (e aktarımı/ortaklığı oku), basit tepkime düzeneği.
- Renk önerisi: çekirdek/proton #e0552b, elektron #2b6be0, nötron #5b6b85, bağ çizgisi #1a2b45,
  oksijen kırmızı #e0552b, hidrojen açık #cfd8e8, karbon koyu #33415588.

## DOĞRULAMA (SPEC.md + bu eke göre)
Yazdıktan sonra `node -e` ile parse et. Ayrıca:
- Her tepkime denkleminin DENK olduğunu (atom/yük), her sayısal çözümün doğruluğunu (mol/kütle/
  hacim/M/pH) zihinsel kontrol et.
- Formüllerde alt indis/yük tutarlılığını, ondalık virgülü, `fig`'lerin '<svg' ile başlayıp
  '</svg>' ile bittiğini ve çift tırnak/`href`/`<script` içermediğini doğrula.
- Bitince: toplam soru sayısı, kaçında `fig` (~%30), denklem ve sayısal soruların doğrulandığını bildir.
