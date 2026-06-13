# 3D Ders UI Tasarım Brifingi — Kimya & Fizik Derslerini Biyoloji Standardına Getir

## Görev
`assets/` klasöründeki kimya ve fizik 3D ders HTML dosyalarını, biyoloji derslerindeki tasarımın **birebir aynısı** olacak şekilde güncelle. Altın örnek dosya:

**REFERANS (altın örnek):** `assets/denetleyici-duzenleyici-sistem.html`
Bu dosyanın dock yapısı, etiket sistemi, kamera çerçevelemesi, bilgi paneli renkleri ve araçlar popup'ı standarttır. Önce bu dosyayı oku ve anla.

## Hedef dosyalar
**Kimya:** atom-periyodik, atom-teorisi-orbitaller, kimyasal-baglar, kimyasal-tepkimeler, maddenin-yapisi, molekul-geometrisi, mol-stokiyometri, organik-kimya, karisimlar-cozeltiler
**Fizik:** elektrik, dalgalar, optik-mercekler, basit-makineler, bileske-kuvvet-vektorler, akiskanlar-mekanigi, golge-olusumu-isik-yayilmasi, temel-kavramlar

## ÖN ADIM — mimari tespiti
Her dosya iki mimariden birini kullanır; önce hangisi olduğunu tespit et:
- **Group A** (`labelAnchors` dizisi + `updateLabels()` fonksiyonu + `shapeGroup` var): etiketler manuel anchor'larla yönetilir.
- **Group B** (`addLabel()` + `CSS2DRenderer` + `updateLeaderLines()` + `#infoList` id'si var): etiketler CSS2D ile 3B noktada.
Hangi mimaride olduğuna göre ilgili maddeyi uygula.

---

## 1. ALT DOCK BAR — 3 sekme
Ekranın en altında YALNIZCA 3 sekme olmalı: `📖 sade` | `🌿 araçlar` | `☰` (ders ayarları).
- Diğer tüm eski ikon butonları (`btnCompare, btnTable, btnExam, btnAsk, btnTts, btnPalette, btnSend, btnTheme, btnFs, btnStory`) `display:none` yapılıp `<body>`'ye taşınmalı (silinmez — popup'tan tetiklenecekler).
- `#toolsRow` düzeni: `display:grid; grid-template-columns:1fr 1fr 1fr; justify-items:center; align-items:center;` → araçlar her zaman tam ortada, sol/sağ sekmeye eşit mesafede.
- **Dock bar görünümü:** tam ekran genişliği (en soldan en sağa), arka plan `rgba(12,15,22,0.97)` (gri-siyah), üst çerçeve `border-top:2px solid #2f8fd0` (mavi).
- 3 sekmenin çerçeve çizgileri **mavi** (`#2f8fd0`).

## 2. ARAÇLAR POPUP (🌿 sekme)
Araçlar sekmesine basınca yukarı doğru açılan popup. İkon **🌿** (açık yeşil), etiket yazısı açık yeşil (`#7fe6a8`). 7 öğe, her biri ilgili gizli butona delege eder (`.click()`):
1. ⚖️ Karşılaştırma Tablosu → `btnCompare`
2. 📋 Bilgi Tablosu → `btnTable`
3. 📝 Test Soruları Oluştur → `btnExam` (Flutter köprüsü: `_bridge({action:'exam',...})`)
4. 🤖 AI Destek → `btnAsk` (`_bridge({action:'ai',...})`)
5. 🔊 Sesli Mod → `btnTts`
6. 🎨 Renk Paleti → `palettePop` aç (`display:block!important`; kapatırken `setProperty('display','none','important')` kullan — yoksa `!important` ezilemez!)
7. ✈️ Gönder → `FlutterNativeShot.postMessage('1')` (yoksa `btnSend`)
Popup açılınca arka planda blur overlay (`#_popBlur`) göster.

## 3. DERS AYARLARI (☰ sekme) — DEĞİŞKENLER DE BURAYA
Ders ayarları popup'ı (`menuPop`) içinde şunlar olmalı:
- Eğitim Seviyesi (İlkokul/Ortaokul/Lise/Sınav/Üniversite)
- Konum (3B vücut/sahne haritası, varsa)
- Konu/Yapı seçici
- **DEĞİŞKENLER / PARAMETRELER sekmesi**: ana ekranda ayrı durmamalı; ders ayarları popup'ının İÇİNE taşınmalı. (Şu an `stackRow` / `sceneVarsBody` / `sp-toggle` olarak ana ekranda ayrı duruyorsa, `menuPop` içine al.)

## 4. SADE / DETAYLI TOGGLE
`📖 sade` sekmesine basınca mod değişir (sade↔detaylı), buton ikonu/yazısı güncellenir (`📖 sade` ↔ `📚 detaylı`). İçerik gerçekten değişmeli:
- **Sade:** bölüm başına ilk ~2 cümle.
- **Detaylı:** tüm cümleler.
Mevcut `panelMode` içindeki `data-mode` öğesinin click handler'ı `currentMode`'u değiştirip içeriği yeniden render etmeli (`loadOverviewTopic()` veya `selectSub()`).

## 5. BİLGİ PANELİ (bottomPanel)
- **Çerçeve çizgisi:** mavi `#2f8fd0`
- **Başlık:** lacivert `#3b5bd9`
- **Alt başlıklar (subhead):** yeşil `#5fd99a`
- **Vurgu/bold yazılar:** mavi `#5fc8e0` (KIRMIZI/coral YOK)
- **Madde imleri (•):** mavi `#2f8fd0`
- **İleri/geri (◀ ▶) butonları:** yeşil çerçeve + yeşil yazı (`#5fd99a`), hover'da yeşil dolgu
- **Konu/bölüm başlarındaki ikonlar (emoji) KALDIRILMALI.** Kaynakta strip et: subhead render satırında baştaki emojiyi sil. Regex: `/^[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{2BFF}\u{FE0F}\u{200D}\s]+/u`. (Group A: `li.innerHTML=t.subhead` → strip'li; Group B: `sub.textContent=el.textContent` → strip'li.)
- **X (kapat) butonu:** paneli TAMAMEN gizleme; küçültüp altta küçük bir chip olarak bırak (`bottomPanel.classList.add('info-mini')`, `hidden` class'ı varsa kaldır). Chip'e tıklanınca panel geri açılır.

## 6. ETİKETLER — referans dosyadakiyle birebir
- **Group A:** Referans dosyanın `updateLabels()` fonksiyonunu **birebir kopyala**. Özellikleri: etiketler modelin üstünde DEĞİL, çevresine radyal dağılır; anchor'dan etikete leader line (çizgi+nokta); 16 iterasyonlu çakışma çözümü (üst üste binmez); arkaya dönen etiketler kademeli soluklaşır. Bağımlılıklar: `labelAnchors, shapeGroup, _partWorldPos, tmpC/tmpV/tmpW/tmpP, labelsVisible`.
- **Group B:** `CSS2DRenderer.prototype.render`'ı wrap eden bir "declutter" shim ekle: render sonrası `.label3d` elementlerini 16 iterasyonlu çakışma çözümüyle birbirinden it; `updateLeaderLines()` zaten leader çizgisini takip eder.

## 7. SAHNE / KAMERA — model uzak olsun, TAM çıksın
- FOV = **50** (tüm dosyalarda).
- Kamera radius çarpanı: model viewport'a tam sığacak kadar uzak olmalı. Referansta `const r=cam.radius` (raw). Model kırpılıyorsa `r=cam.radius*1.2` ile uzaklaştır.
- `camera.setViewOffset(...)` dikey terimi: `Math.round(innerHeight*0.20) - _sh.cur` (modeli üstten kırpacak şekilde fazla itme; **0.24 KULLANMA**, 0.20 doğru).
- Model üstten/kenardan KIRPILMAMALI — sahneyi açıp her konuda kontrol et.

## 8. TABLOLAR (Karşılaştırma + Bilgi)
`#compareOverlay` ve `#tableOverlay` içindeki `.cmp-table` için KIRMIZI YOK:
- border: `#2f8fd0` (mavi)
- th arka plan: `linear-gradient(135deg,#1a6b8a,#1f7a5e)` (mavi→yeşil), yazı `#eafaff`
- ilk sütun yazısı: `#5fd99a` (yeşil)
- satır şeritleri/hover: mavi+yeşil rgba tonları
- başlık `#5fc8e0`, gezinme butonları mavi çerçeve
Bunları `!important` ile en sonda ekle; `:root --accent`'e DOKUNMA (tema korunsun).

## 9. RENK PALETİ
`palettePop` çerçeve çizgisi **açık** mavi-turkuaz `#aee0f0`, başlık da `#aee0f0`.

## 10. BLUR
`#_popBlur`: `background:rgba(0,0,0,0.5); backdrop-filter:blur(3px); -webkit-backdrop-filter:blur(3px);`. Araçlar/menü popup'ı açılınca devreye girer, overlay'e tıklayınca kapanır.

## 11. EK STANDART ÖĞELER
- **TTS aktif chip:** Sesli mod açıkken sağ altta kırmızı yanıp sönen "🔊 KES" butonu (`#ttsActiveChip`); `btnTts.active` class'ını MutationObserver ile izle.
- **Native screenshot:** Gönder → `FlutterNativeShot` JS kanalı.

---

## ÖNEMLİ KURALLAR
- `:root` CSS değişkenlerine (özellikle `--accent`) DOKUNMA — sadece hedefli override (`!important`) kullan; ders temasının genel rengi korunmalı, sadece tablo/panel/dock renkleri değişmeli.
- STEM içerik kuralı: Unicode sembol kullan ($/LaTeX kod artığı YOK), TR ondalık ayraç virgül.
- Tüm enjekte edilen script bloklarını syntax açısından doğrula (geçersiz bir blok sonraki tüm script'leri çökertir).
- HTML asset'leri APK'ya paketlenir → değişiklikleri görmek için uygulama yeniden derlenmeli.

## DOĞRULAMA (her dosyada kontrol et)
1. Alt barda tam 3 sekme, full-width, gri-siyah, mavi üst çizgi.
2. Araçlar ikonu 🌿; popup'taki 7 öğe ilgili butonu tetikliyor.
3. Ders ayarlarında değişkenler sekmesi var; ana ekranda ayrı değişkenler sekmesi YOK.
4. Sade/detaylı içeriği gerçekten değiştiriyor.
5. Bilgi paneli: başlık lacivert, alt başlık yeşil, vurgu mavi, çerçeve mavi, ◀▶ yeşil, konu başında emoji YOK, X'e basınca küçülüyor (kaybolmuyor).
6. Etiketler modelin üstüne binmiyor, leader çizgiyle yana dağılıyor, çakışmıyor.
7. Model her konuda tam görünüyor (kırpık değil), uzakta.
8. Tablolar mavi/yeşil (kırmızı yok).
9. Renk paleti çerçevesi açık; blur çalışıyor.
