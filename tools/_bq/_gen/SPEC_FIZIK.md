# FİZİK Soru Bankası — Görsel (SVG) Eklentisi

Bu dosya, ana `SPEC.md` kurallarına EK olarak fizik soruları için geçerlidir.
ÖNCE `SPEC.md`'yi oku, sonra burayı uygula.

## Görsel soru oranı (ZORUNLU)
Fizikte sorular görsel sorulur. Her gruptaki soruların **yaklaşık %60'ı** bir
şekil (`fig`) içermelidir. Kalan %40 kavramsal/sayısal (şekilsiz) olabilir.
- İlkokulda görsel oranı daha da yüksek olabilir (somut şekil iyidir).
- Şekil, sorunun KURGUSUNU gösterir; soru "şekildeki..." diye şekle atıfta bulunur.

## `fig` alanı — satır içi SVG
Soru nesnesine (ve istersen çözüm adımına `steps[i].fig`) `fig` alanı ekle:
```json
{
  "q": "Şekildeki düzenekte cismin perdedeki gölge boyu nasıl değişir?",
  "fig": "<svg viewBox='0 0 320 180'>...</svg>",
  "steps": [{"t":"...","a":"...","d":"..."}],
  "ans": "...",
  "o": ["...","...","...","..."]
}
```

### SVG kuralları (KESİN)
- Tek parça, kendine yeten `<svg viewBox='0 0 G Y'>...</svg>` (örn. viewBox='0 0 320 180').
- **Tüm attribute'larda TEK TIRNAK kullan** (örn. `cx='40'`), çift tırnak KULLANMA —
  böylece JS string'i temiz kalır.
- `width`/`height` attribute'u KOYMA; ölçek viewBox ile gelir (kapsayıcı %100 sığdırır).
- Arka plan AÇIK renkli (#f5f7fa). Bu yüzden çizgi/yazılarda KOYU renk kullan:
  çizgi/kenar `#1a2b45`, yazı `#1a2b45`. Dolgularda canlı renk serbest
  (ışık #ffd54a, gölge #33415588, su #4aa3df, vektör/ok #e0552b, cisim #5b6b85).
- İZİN VERİLEN etiketler: `svg, g, rect, circle, ellipse, line, polyline, polygon,
  path, text, defs, marker, tspan`. `<script>`, `<image>`, `href`, `<foreignObject>`
  KESİNLİKLE YOK.
- Yazılar Türkçe ve kısa; `font-size='12'`–`'14'`, gerekiyorsa `text-anchor='middle'`.
- Ok ucu gerekiyorsa `<defs><marker>` ile tanımla veya küçük bir `<polygon>` üçgen çiz.
- Şekil sade, okunur, etiketli olsun (eksen/yön/değer etiketleri). Karmaşa yok.
- Sayı/birim etiketlerinde TR ondalık virgül (3,5 cm), Unicode üs (cm², 30°).

### Örnek 1 — Gölge (nokta kaynak + cisim + perde)
```
<svg viewBox='0 0 320 180'><circle cx='38' cy='90' r='20' fill='#ffd54a' stroke='#d9a400'/><text x='38' y='150' font-size='12' text-anchor='middle' fill='#1a2b45'>Lamba</text><rect x='150' y='62' width='12' height='56' fill='#5b6b85'/><text x='156' y='135' font-size='11' text-anchor='middle' fill='#1a2b45'>Cisim</text><line x1='252' y1='18' x2='252' y2='162' stroke='#1a2b45' stroke-width='3'/><text x='268' y='95' font-size='11' fill='#1a2b45'>Perde</text><line x1='58' y1='90' x2='252' y2='40' stroke='#f0a500' stroke-width='1.5'/><line x1='58' y1='90' x2='252' y2='140' stroke='#f0a500' stroke-width='1.5'/></svg>
```

### Örnek 2 — Güneş tutulması (Güneş–Ay–Dünya hizası)
```
<svg viewBox='0 0 320 140'><circle cx='40' cy='70' r='26' fill='#ffd54a' stroke='#d9a400'/><text x='40' y='120' font-size='11' text-anchor='middle' fill='#1a2b45'>Güneş</text><circle cx='170' cy='70' r='8' fill='#9aa6b8' stroke='#1a2b45'/><text x='170' y='100' font-size='11' text-anchor='middle' fill='#1a2b45'>Ay</text><circle cx='270' cy='70' r='18' fill='#4aa3df' stroke='#1a2b45'/><text x='270' y='110' font-size='11' text-anchor='middle' fill='#1a2b45'>Dünya</text><polygon points='66,58 162,66 162,74 66,82' fill='#ffe9a8'/></svg>
```

DOĞRULAMA (SPEC.md'ye ek): yazdıktan sonra node ile parse et; ayrıca her `fig`
değerinin '<svg' ile başlayıp '</svg>' ile bittiğini, içinde `<script`/`href`/`"`
(çift tırnak) GEÇMEDİĞİNİ ve görsel oranının ~%60 olduğunu kontrol et. Bitince
toplam soru sayısı + kaçında `fig` olduğunu bildir.
