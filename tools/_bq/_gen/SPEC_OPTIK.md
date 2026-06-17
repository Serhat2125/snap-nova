# OPTİK (Kırılma & Mercekler) — Profesör Düzeyi Titizlik Eki

`SPEC.md` + `SPEC_FIZIK.md` kurallarına EKtir. Bu derste hata KABUL EDİLMEZ:
sayısal sonuçlar, işaret kuralları, tanımlar ve diyagram ölçüleri eksiksiz/doğru olmalı.
Görsel oranı bu derste **~%40**.

## Tanımlar (net ve doğru kullan)
- **Kırılma indisi:** n = c/v (c: ışığın boşluktaki hızı 3·10⁸ m/s). Daima n ≥ 1.
- **Asal eksen, optik merkez (O), asal odak (F), odak uzaklığı (f), eğrilik merkezi (M/C),
  eğrilik yarıçapı (R):** aynalarda R = 2·f.
- **Dioptri:** D = 1/f (f metre cinsinden). Yakınsak mercek +, ıraksak mercek −.

## İşaret ve denklem kuralları (TR müfredatı — TUTARLI uygula)
- **Mercek/ayna denklemi:** 1/f = 1/a + 1/b  (a: cisim uzaklığı, b: görüntü uzaklığı).
- **Büyütme:** G = |b/a| = boy(görüntü)/boy(cisim).
- **Odak işareti:** ince (yakınsak) mercek f > 0; kalın (ıraksak) mercek f < 0.
  Çukur ayna f > 0; tümsek ayna f < 0.
- **Görüntü uzaklığı b:** gerçek görüntü b > 0; sanal görüntü b < 0.
- Iraksak mercek ve tümsek aynada görüntü **daima sanal, düz, küçük** ve cisim tarafındadır.
- Yakınsak mercek/çukur aynada görüntü cisim konumuna göre değişir:
  cisim 2F (veya C) dışında → gerçek, ters, küçük; 2F'de → gerçek, ters, eşit;
  F–2F arasında → gerçek, ters, büyük; F'de → görüntü sonsuzda/oluşmaz;
  F içinde → sanal, düz, büyük (büyüteç).

## Snell, tam yansıma, görünür derinlik, prizma
- **Snell yasası:** n₁·sinθ₁ = n₂·sinθ₂ (açılar normalle ölçülür).
- Çok yoğundan az yoğuna geçişte ışın normalden **uzaklaşır**; tersi yaklaşır.
- **Sınır (kritik) açı:** sinθ_s = n₂/n₁ (n₁ > n₂). θ > θ_s → **tam yansıma**.
- **Görünür derinlik:** dik bakışta gerçek derinlik/görünür derinlik = n_ortam/n_göz ≈ n (havadan).
- **Prizma:** beyaz ışık renklerine ayrışır (dispersiyon); mor en çok, kırmızı en az sapar
  (n_mor > n_kırmızı).

## Sayısal çözüm titizliği (ZORUNLU)
- Her sayısal soruda `steps` içinde formülü yaz → değerleri yerine koy → sonucu birimiyle ver.
- Birim her zaman yazılır (cm, m, D, °). Ondalık ayraç **virgül** (örn. 1,5).
- Sonuçlar fiziksel olarak tutarlı olmalı (kontrol et: işaret, görüntü tipi, büyütme).
- sin/cos değerleri makul olsun (30°→0,5; 37°→0,6; 45°→0,71; 53°→0,8; 60°→0,87).

## Işın diyagramı (SVG) ölçü/doğruluk kuralları (~%40 soruda fig)
- **Asal ekseni** yatay çiz (yatay çizgi). Merceği dikey, ince kenarlı için iki ucu sivri ↕,
  kalın kenarlı için ortası ince çiz; aynayı uygun yay/çizgi ile göster.
- **F ve 2F (veya F ve C) noktalarını asal eksende SİMETRİK ve oranlı yerleştir**
  (2F = 2×OF uzaklığı; ölçü tutarlı olsun). Noktaları etiketle (F, 2F/C, O).
- Cismi dik bir ok (yukarı) olarak çiz; görüntüyü doğru konum/boy/yönde çiz.
- En az iki temel ışını **doğru** çiz: (1) asal eksene paralel gelen → kırıldıktan sonra
  F'den geçer; (2) optik merkezden/tepeden geçen → sapmadan devam; (gerekirse 3) F'den
  gelen → asal eksene paralel çıkar. Işın yönleri ve kesişim noktası görüntüyle tutarlı olsun.
- Sanal görüntü ve sanal ışınları kesikli (`stroke-dasharray='4 3'`) çiz.
- Mesafe etiketleri (a, b, f) gerekiyorsa eksende ölçü çizgisiyle göster; değerler soruyla uyumlu.
- Açı diyagramlarında **normal** (yüzeye dik, kesikli) ve gelme/kırılma açılarını normalden ölçülü çiz.

DOĞRULAMA (öncekilere ek): her sayısal sorunun çözümünü zihinsel kontrol et (1/f=1/a+1/b,
G=b/a, Snell, R=2f). Diyagramdaki F/2F simetrisini ve ışın doğruluğunu gözden geçir.
Bitince: toplam soru, kaç görsel (~%40) ve sayısal soruların doğrulandığını bildir.
