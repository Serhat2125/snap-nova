# 🚀 QuAlsar Play Store Yayın Master Checklist

> **Bu klasördeki dosyalar Play Store'a yüklemek için her şeyi içeriyor.**
> Sırayla aç, her dosyada yazılan adımları yap.

---

## 📁 Bu klasördeki dosyalar

| Dosya | Ne için? |
|---|---|
| `00_MASTER_CHECKLIST.md` | **← Şu an okuduğun.** Genel yol haritası. |
| `KEYSTORE_AND_BUILD_GUIDE.md` | Keystore üret + SHA-1 al + AAB build et |
| `GEMINI_PROXY_DEPLOY_GUIDE.md` | Gemini API key'i güvenli backend'e taşı |
| `PRIVACY_POLICY_TR.html` + `_EN.html` | Privacy Policy sayfası — host edeceğin HTML |
| `TERMS_OF_SERVICE_TR.html` + `_EN.html` | Kullanım Koşulları — host edeceğin HTML |
| `PLAY_STORE_LISTING.md` | App adı, açıklama, screenshot caption (TR+EN) |
| `DATA_SAFETY_ANSWERS.md` | Play Console Data Safety + Content Rating formuna cevaplar |

---

## ⏱️ Toplam tahmini süre

**~6-8 saat** (ilk Play Console kurulumu dahil), birden fazla güne yayabilirsin.

| Adım | Süre | Engelleyici mi? |
|---|---|---|
| Keystore üretme | 10 dk | Evet (her şeyin başı) |
| Privacy Policy + Terms host etme | 30 dk | Evet (Play submit'te URL ister) |
| Play Console hesabı açma | 30 dk | Evet (25 USD ödeme) |
| Gemini proxy deploy | 1 saat | Hayır (ama güvenlik için ÖNERİLİR) |
| SKU oluşturma | 15 dk | Evet (abonelik için) |
| Data Safety + Content Rating | 30 dk | Evet |
| Store listing girme | 30 dk | Evet |
| Asset hazırlama (icon, feature, screenshot) | 2-3 saat | Evet |
| Firebase SHA-1 ekleme | 5 dk | Evet (Google Sign-In için) |
| AAB build + upload | 30 dk | Evet (son adım) |
| Internal test + production'a promote | 1-2 saat | Hayır (Google review 1-7 gün) |

---

## ✅ Sıralı yol haritası (BU SIRAYLA yap)

### FAZ 1: Hazırlık (kendi makinende)

#### Adım 1: Keystore üret
→ `KEYSTORE_AND_BUILD_GUIDE.md` bölüm 1-3 (10 dk)

✅ Çıktı: `android/app/key.jks` + `android/key.properties`  
⚠️ **KEYSTORE'U YEDEKLE** (kaybedersen uygulamayı bir daha güncelleyemezsin)

#### Adım 2: SHA-1'i Firebase'e ekle  
→ `KEYSTORE_AND_BUILD_GUIDE.md` bölüm 3 (5 dk)

✅ Sonuç: Google Sign-In production'da çalışacak

#### Adım 3: Gemini proxy deploy et (önemli güvenlik adımı)
→ `GEMINI_PROXY_DEPLOY_GUIDE.md` baştan sona (1 saat)

✅ Sonuç: API key APK'da olmayacak, hacker çekemez

---

### FAZ 2: Web tarafı

#### Adım 4: Privacy Policy + Terms sayfalarını host et
1. **Tercih edilen yöntem: Firebase Hosting** (zaten Firebase kullanıyorsun, ekstra hesap yok)
   ```powershell
   cd "C:\Users\TUNA MUHENDISLIK\snap_nova"
   firebase init hosting
   # public klasörünü "release" olarak işaretle
   firebase deploy --only hosting
   ```
   Sonuç URL: `https://qualsar2-640f0.web.app/PRIVACY_POLICY_TR.html`

2. **Alternatif: GitHub Pages** (HTML'leri GitHub repo'ya koy, Pages aç)

3. **Alternatif: Vercel/Netlify** (Drag-drop deploy)

✅ Sonuç (zaten deploy edilmiş): `https://qualsar2-640f0.web.app/privacy` ve `/terms` URL'leri çalışıyor

---

### FAZ 3: Play Console

#### Adım 5: Play Console hesabı aç
→ https://play.google.com/console/signup (30 dk + 25 USD)

#### Adım 6: Yeni uygulama oluştur
- Application name: `QuAlsar`
- Default language: Turkish (tr-TR)
- App or game: **App**
- Free or paid: **Free** (abonelik in-app olacak)

#### Adım 7: Store Listing doldur
→ `PLAY_STORE_LISTING.md` (30 dk)

- Uygulama adı, kısa açıklama, tam açıklama: dosyadan **kopyala-yapıştır**
- Privacy Policy URL: hosted URL'i yapıştır
- Web sitesi: `https://qualsar2-640f0.web.app`
- E-posta: `serhatdsme@gmail.com`

#### Adım 8: Asset'leri hazırla ve yükle
→ `PLAY_STORE_LISTING.md` "Görsel Asset Gereksinimleri" bölümü (2-3 saat)

- **App icon (512×512):** `assets/app_icon.png` (1024×1024) → Squoosh/Photopea ile 512'ye küçült
- **Feature graphic (1024×500):** Canva → "Google Play feature graphic" template → QuAlsar logosu + Mars sahne
- **Screenshot (8 adet):** `flutter run --release` ile aç → her ekrandan screenshot al:
  1. Onboarding ilk slayt
  2. Kamera çekim ekranı  
  3. AI çözüm sonucu
  4. Mars Protokolü pomodoro
  5. Bilgi Ligi sıralama
  6. Çalışma Arkadaşım 3D
  7. Konu Özeti kütüphane
  8. Premium ekranı

#### Adım 9: Data Safety doldur
→ `DATA_SAFETY_ANSWERS.md` (20 dk)

Her cevabı dosyadan **kopyala**, Play Console formunda **işaretle**.

#### Adım 10: Content Rating
→ `DATA_SAFETY_ANSWERS.md` "Content Rating" bölümü (10 dk)

Anketin her sorusuna cevap dosyada yazıyor. Beklenen: **PEGI 3 / Everyone**

#### Adım 11: Abonelik SKU'ları oluştur
Monetize → Subscriptions → Create subscription:

| SKU | Adı | Periyot | Fiyat (TRY) |
|---|---|---|---|
| `qualsar_premium_monthly` | QuAlsar Premium Aylık | 1 month | ₺49,99 |
| `qualsar_premium_quarterly` | QuAlsar Premium 3 Aylık | 3 months | ₺119,99 |
| `qualsar_premium_yearly` | QuAlsar Premium Yıllık | 1 year | ₺399,99 |

> Fiyatlar örnek; rakiplere bakıp ayarla. PricingService.dart'taki değerlerle uyumlu olsun.

---

### FAZ 4: Build & Upload

#### Adım 12: Gemini proxy'i aktif et (deploy'dan sonra)
`lib/services/gemini_service.dart`'ı aç, en üstte:
```dart
static const bool kUseProxy = false;
```
`true` yap. `secrets.dart` dosyasındaki anahtarları sil.

#### Adım 13: AAB build et
→ `KEYSTORE_AND_BUILD_GUIDE.md` bölüm 4 (30 dk)

```powershell
flutter clean
flutter build appbundle --release
```

✅ Çıktı: `build/app/outputs/bundle/release/app-release.aab`

#### Adım 14: Internal Testing track'e yükle
Play Console → Release → Testing → **Internal testing** → Create new release → AAB'yi yükle.

#### Adım 15: Test hesabı ekle
Internal testing → Tester e-postası ekle (kendi Gmail'ini).

#### Adım 16: Telefonunda test et
Play Console invitation link'e telefonda tıkla → uygulamayı indir → test et.

**Özellikle test et:**
- Abonelik satın alma (sandbox modunda gerçek para gitmez)
- Restore Purchases
- Google/Apple sign-in
- Soru çek + AI yanıt

#### Adım 17: Production'a Promote
Internal'da her şey çalışıyorsa: Release → Production → "Promote release". Google review başlar (1-7 gün).

---

## 🆘 Sorun çıkarsa

Her dosyanın altında "Sorun çıkarsa" bölümü var. Çıkamadığın yerde **hata mesajını bana yapıştır**, birlikte çözeriz.

### Yaygın hatalar:

| Hata | Çözüm |
|---|---|
| "Keystore not found" | `key.properties` dosyasındaki yolu kontrol et |
| "Out of memory" build sırasında | `android/gradle.properties`'e `org.gradle.jvmargs=-Xmx4g` ekle |
| "App not installed" tester'da | İmza eski versiyonla aynı değil — keystore'u kaybetmedin değil mi? |
| "Privacy Policy required" | Play Console'a URL eklemedin |
| Subscription "Item not available" | SKU'lar henüz Play Console'da aktif değil, 1-24 saat bekle |

---

## 📞 İletişim

Tüm hata mesajlarını / takıldığın yerleri yapıştır → çözeriz. Bu uygulama Play Store'da yayında olana kadar yanındayım.
