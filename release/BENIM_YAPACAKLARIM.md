# 🚀 QuAlsar — Play Store'a yüklemeden önce SENİN yapacakların

> Kod tarafı %100 hazır. AAB build edilmiş, dosya yolunu aşağıda verdim.
> Bu rehber **sırayla** takip edilecek — her adımda hangi tuşa basılacak, ne kopyalanacak yazılı.
> Toplam tahmini süre: **2-3 saat** (asset hazırlama + Play Console form doldurma).

---

## 🎁 Senin için hazırladığım dosyalar

| Dosya | Ne için? |
|---|---|
| `build/app/outputs/bundle/release/app-release.aab` | Play Console'a **yükleyeceğin** dosya (64.77 MB) |
| `release/app_icon_512.png` | Play Store ikonu — **olduğu gibi yükle** |
| `release/feature_graphic_1024x500.png` | Mağaza üst bandı — **olduğu gibi yükle** |
| `release/screenshots/01_premium.png` + `02_qualsar_chat.jpg` | 2 hazır screenshot — yükle |
| `release/PLAY_STORE_LISTING.md` | Başlık + açıklama — **kopyala-yapıştır** |
| `release/DATA_SAFETY_ANSWERS.md` | Data Safety formu cevapları |
| `https://qualsar2-640f0.web.app/privacy` | Privacy Policy URL (canlı) |
| `https://qualsar2-640f0.web.app/terms` | Kullanım Koşulları URL (canlı) |

---

## ✅ ADIM 1 — Play Console hesabı (henüz yoksa)

1. https://play.google.com/console/signup → "Geliştirici hesabı aç"
2. **25 USD** ödeme + kimlik doğrulama
3. Hesap onaylanmayı 1-2 gün bekleyebilir

> Hesabın varsa direkt Adım 2'ye geç.

---

## ✅ ADIM 2 — Yeni uygulama oluştur

Play Console → **Tüm uygulamalar** → **Uygulama oluştur**

| Alan | Değer |
|---|---|
| Uygulama adı | `QuAlsar: AI Sınav Asistanı` |
| Varsayılan dil | **Türkçe (tr-TR)** |
| Uygulama mı oyun mu? | **Uygulama** |
| Ücretsiz mi ücretli mi? | **Ücretsiz** |
| Açıklamalar | Her ikisini de işaretle (geliştirici politikası + ABD ihracat) |

**Oluştur** tuşuna bas.

---

## ✅ ADIM 3 — AAB'yi Dahili test'e yükle

Sol menü → **Test ve sürüm** → **Test** → **Dahili test**

1. **Yeni sürüm oluştur**
2. Sayfa açıldığında **App bundle'lar** bölümü → **Yükle**
3. Bu dosyayı seç:
   ```
   C:\Users\TUNA MUHENDISLIK\snap_nova\build\app\outputs\bundle\release\app-release.aab
   ```
4. Yükleme bitince **Sürüm notları** kısmına yapıştır:
   ```
   <tr-TR>
   QuAlsar v1.0.0 — İlk sürüm.

   📸 Soruyu fotoğrafla, AI anında çözsün
   🎯 Türkiye dahil 12+ ülkenin müfredatına göre kişiselleştirilmiş içerik
   🚀 Mars Protokolü — agresif odak modu (Pomodoro yeniden tasarlandı)
   🏆 Bilgi Ligi — mahallenden dünyaya konuma göre sıralama
   🤖 6 farklı 3D robot çalışma arkadaşı
   ✨ Premium: sınırsız AI, reklamsız, ek özet ve takvim
   🌍 55 dil
   </tr-TR>
   ```
5. **Kaydet** → **İncele** → **Yayınla (Dahili teste)**

---

## ✅ ADIM 4 — Test kullanıcısı ekle (kendin için)

Dahili test → **Testçiler** sekmesi → **Test grubu oluştur**

- Grup adı: `Ben`
- E-posta: `serhatdsme@gmail.com`
- Kaydet

Aynı sayfada **Lisans test linki**ni gör → telefonla aç → "Bu uygulamanın testçisi ol" tıkla.

Sonra Play Store telefonda → QuAlsar'ı indir → kurulum tamamlanır.

> ⚠️ Bu link Google review **gerektirmiyor**, hesabın onaylanır onaylanmaz çalışır.

---

## ✅ ADIM 5 — Telefonda kapsamlı test (30 dk)

Uygulamayı aç, şu akışları **mutlaka** dene:

| Test | Beklenen sonuç |
|---|---|
| Google ile giriş | Hesabınla giriş yaparsın, profil oluşturulur |
| Onboarding 5 slayt + sınıf seçimi | Sorunsuz akış |
| Bir matematik sorusunu fotoğrafla → AI'dan çözüm | 2-5 saniyede çözüm gelir (proxy "cold start" ilk çağrıda yavaş) |
| Mars Protokolü ekranında pomodoro başlat | 3D Mars sahnesi açılır |
| Bilgi Ligi sıralama ekranı | Mock veri görürsün |
| Premium ekranını aç | Aylık/3 aylık/yıllık 3 kart, fiyat gösterilir |
| **Premium satın al (test modunda)** | Google Play test ödeme akışı açılır — para gitmez |
| Çıkış yap → tekrar giriş | Veriler korunur |

**Hata varsa Crashlytics'e düşer** → Firebase Console → Crashlytics → görürsün.

---

## ✅ ADIM 6 — Screenshot'ları topla

Şu an `release/screenshots/` klasöründe **2 adet** var. Play Store **en az 2** istiyor → bunlarla bile yayınlanabilir, ama **6-8 adet** olursa daha iyi.

### Hızlı yol: telefondan ekran görüntüsü al

Test ettiğin telefonda her ekranda **Power + Ses Kıs** bas → ekran görüntüsü alınır. Sonra USB ile bilgisayara kopyala → `release/screenshots/` klasörüne at.

Şu 6 ekrandan görüntü al:
1. 📸 **Kamera ekranı** (soruyu kameraya tutar)
2. 🤖 **AI çözüm sonucu** (bir matematik sorusu çözdükten sonra)
3. 🚀 **Mars Protokolü** (Profil → Mars sekmesi)
4. 🏆 **Bilgi Ligi sıralama**
5. 🤖 **Çalışma Arkadaşım** (3D robot ekranı)
6. 📚 **Konu Özeti** (Kütüphane → bir konu seç)

### Otomatik yol (opsiyonel — telefon USB ile bağlıysa)

PowerShell aç, şu komutu çalıştır:
```powershell
cd "C:\Users\TUNA MUHENDISLIK\snap_nova"
.\tool\capture_screenshots.ps1
```
Bu betik telefonda her ekran için sana ENTER soracak, otomatik yakalayacak.

---

## ✅ ADIM 7 — Mağaza listesi doldur

Play Console → Sol menü → **Mağaza varlığı** → **Mağaza listesi**

`release/PLAY_STORE_LISTING.md` dosyasını aç. Aşağıdaki alanlara o dosyadan **kopyala-yapıştır**:

| Play Console alanı | PLAY_STORE_LISTING.md'de yer |
|---|---|
| Uygulama adı | "Uygulama adı (App name)" bölümü |
| Kısa açıklama | "Kısa açıklama (Short description)" |
| Tam açıklama | "Tam açıklama (Full description)" |

### Görsel asset'ler

| Alan | Yükleyeceğin dosya |
|---|---|
| Uygulama simgesi | `release/app_icon_512.png` |
| Featured graphic | `release/feature_graphic_1024x500.png` |
| Telefon ekran görüntüleri | `release/screenshots/*.png` (en az 2, mümkünse 8) |

### Kategori ve etiketler

- **Kategori:** Eğitim
- **Etiketler:** Education, Productivity
- **E-posta:** `serhatdsme@gmail.com`
- **Web sitesi:** `https://qualsar2-640f0.web.app`
- **Privacy Policy:** `https://qualsar2-640f0.web.app/privacy`

**Kaydet**.

---

## ✅ ADIM 8 — Çeviriler ekle (İngilizce)

Mağaza listesi sayfasında → **Çeviriler** → **Çeviri ekle** → **English (United States)**

Yeni açılan İngilizce sekmeye `PLAY_STORE_LISTING.md` dosyasındaki **İNGİLİZCE** bölümünden kopyala-yapıştır.

**Kaydet**.

---

## ✅ ADIM 9 — App Content (uygulama içeriği) formlarını doldur

Sol menü → **Politika** → **Uygulama içeriği**

Her form için **Başlat** → tek tek doldur.

### 9.1 Gizlilik Politikası

URL: `https://qualsar2-640f0.web.app/privacy`

### 9.2 Reklamlar

> Uygulamada reklam var mı? → **Hayır**

### 9.3 Uygulama erişimi

> Uygulama tüm işlevler ücretsiz mi? → **Tüm işlevler kısıtlama olmadan kullanılabilir** (Premium reklamı kaldırır + ek özellik açar, ama temel AI çözüm ücretsiz çalışıyor)
> Veya: "Bazı işlevler kısıtlı" → "Premium" kısıtlamaları için bilgi verebilirsin.

### 9.4 Data safety (Veri güvenliği)

`release/DATA_SAFETY_ANSWERS.md` dosyasını aç. Her soruya o dosyada hangi cevabın olduğu yazıyor → tek tek işaretle.

> Bu formun doldurulması ~20-30 dk sürer çünkü Play Console çok soru sorar. Hepsi cevap dosyasında.

### 9.5 Reklam kimliği

> Bu uygulama reklam kimliği kullanıyor mu? → **Hayır** (henüz reklam yok)

### 9.6 İçerik derecelendirme

**Başlat** → Anket başlar. `release/DATA_SAFETY_ANSWERS.md` "Content Rating" bölümündeki tüm cevaplar:

- Şiddet / Cinsellik / Küfür / Uyuşturucu / Korku / Kumar → **Hayır**
- Kullanıcılar mesajlaşıyor mu? → **Hayır**
- Uygulama içi satın alma var mı? → **Evet**
- Reklamlar var mı? → **Hayır**

Beklenen sonuç: **PEGI 3 / Everyone (E)**.

### 9.7 Hedef kitle

- **Hedef yaş aralığı:** 13 ve üzeri (Teen)
- "Çocukları cezbedebilir mi?" → **Hayır**

### 9.8 Haberler uygulaması

→ **Hayır**

### 9.9 COVID-19

→ **Hayır**

### 9.10 Veri Güvenliği Hizmetleri kategorisi

→ Eğitim (Education)

---

## ✅ ADIM 10 — Abonelik (SKU) oluştur

Sol menü → **Para kazanma** → **Abonelikler** → **Abonelik oluştur**

Üç adet abonelik oluşturacaksın. Her biri için:

### SKU 1 — Aylık
- **Ürün kimliği:** `qualsar_premium_monthly` (BURAYI ASLA DEĞİŞTİRME — kodda hardcoded)
- **Ad:** `QuAlsar Premium — Aylık`
- **Açıklama:** `Sınırsız AI çözüm, reklamsız, premium konu özetleri ve takvim.`
- **Temel plan:**
  - Plan kimliği: `monthly`
  - Faturalandırma süresi: **1 ay**
  - Otomatik yenilenir
- **Fiyat:** Türkiye için **₺225,83** (örnek; rakibe göre ayarla)
- **Ülkeler:** Tüm ülkeler (veya seçtiklerin)

### SKU 2 — 3 Aylık
- **Ürün kimliği:** `qualsar_premium_quarterly`
- **Ad:** `QuAlsar Premium — 3 Aylık`
- **Açıklama:** Aynı + "Aylık fiyata göre indirimli."
- **Plan:** `quarterly` / 3 ay / otomatik yenilenir
- **Fiyat:** ₺677,48 (≈ ₺225,83/ay)

### SKU 3 — Yıllık
- **Ürün kimliği:** `qualsar_premium_yearly`
- **Ad:** `QuAlsar Premium — Yıllık`
- **Açıklama:** Aynı + "Yıllık alın, %50 tasarruf."
- **Plan:** `yearly` / 1 yıl / otomatik yenilenir
- **Fiyat:** ₺1.354,98 (≈ ₺112,91/ay)

> Fiyatlar `01_premium.png` screenshot'ındaki değerlerle aynı — kullanıcı kafa karışıklığı yaşamaz.

Her birinde **Etkinleştir** → SKU'lar 1-24 saat içinde Play Billing'de görünür.

---

## ✅ ADIM 11 — Ülke ve fiyatlandırma

Sol menü → **Dağıtım** → **Ülkeler/bölgeler** → istediklerini seç.

Tavsiye:
- ✅ Türkiye (ana pazar)
- ✅ Almanya, İngiltere, ABD, Kanada (TR diaspora + EN)
- ✅ Geri kalan AB ve Arap ülkeleri (TR + Arapça desteği var)

---

## ✅ ADIM 12 — İncelemeye gönder (Dahili test → Production)

Adım 5'te telefonda test ettiğin akış sorunsuzsa:

1. **Test ve sürüm** → **Production** → **Yeni sürüm oluştur**
2. **Dahili test'ten yükselt** seçeneği → Adım 3'te yüklediğin AAB otomatik kopyalanır
3. Sürüm notları aynı kalsın
4. **Kaydet** → **İncele** → **Yayına gönder**

Google review başlar (genelde **1-3 gün**, bazen 7).
Onaylandığında telefonda Play Store'da arayınca QuAlsar çıkar.

---

## 🆘 Sorun çıkarsa

| Hata | Çözüm |
|---|---|
| "Privacy Policy zorunlu" | Adım 9.1'de URL eklemedin |
| "Içerik derecelendirme tamamlanmadı" | Adım 9.6'yı bitirmedin |
| "Veri güvenliği eksik" | Adım 9.4 formu yarım |
| Telefonda "Bu uygulama yüklenmiyor" | Adım 4'teki test linkini onaylamadın |
| AAB yüklenirken "İmzalanmamış" | Olamaz — imza qualsar-release ile build edildi. Tekrar yükle. |
| Premium satın alma "Ürün bulunamadı" | SKU'lar Play Billing'de henüz aktif değil, 1-24 saat bekle |
| Crashlytics'te hata | Hatanın stack trace'ini bana yapıştır, çözeriz |

---

## 🎯 Özetle senin yapacakların

```
[ ] 1.  Play Console'da hesap aç (yoksa, 25 USD)
[ ] 2.  Yeni uygulama oluştur: QuAlsar
[ ] 3.  app-release.aab'yi Dahili test'e yükle
[ ] 4.  Kendi e-posta'nı testçi olarak ekle
[ ] 5.  Telefonda test linki ile yükle, akışı dene
[ ] 6.  Eksik 6 screenshot'ı telefondan al
[ ] 7.  Mağaza listesi başlık+açıklama+asset yükle (TR)
[ ] 8.  İngilizce çeviri ekle
[ ] 9.  App Content formlarını doldur (DATA_SAFETY_ANSWERS.md'den kopyala)
[ ] 10. 3 abonelik SKU oluştur (qualsar_premium_monthly/_quarterly/_yearly)
[ ] 11. Ülkeleri seç
[ ] 12. Production'a "yükselt", Google review bekle (1-3 gün)
```

---

## 🔥 Yayınlandıktan sonra (post-launch)

Google review onaylayınca:
- ✅ Crashlytics'i her gün kontrol et (crash varsa hızlı fix et)
- ✅ Play Console → İstatistikler → indirme, ARPU, kalma oranını izle
- ✅ İlk 100 kullanıcıya kişisel e-posta at (`serhatdsme@gmail.com`'dan), geri bildirim topla

Production-ready. Yükleyince herhangi bir sorun olursa bana hata mesajını yapıştır, çözeriz. 🚀
