# 🛡️ Gemini API Proxy Deploy Kılavuzu

> **Amaç:** Gemini API anahtarını APK'dan çıkarıp Firebase Cloud Function'a taşıyalım. Böylece hacker APK'yı çözse de anahtara ulaşamaz.
> 
> **Süre:** 30-60 dk (ilk Node.js + Firebase CLI kurulumu dahil)
> 
> **Ne zaman yap:** Play Store'a yüklemeden ÖNCE. Şu anki development'ta anahtar APK'da kalabilir.

---

## 1️⃣ Ön Hazırlık (bir kerelik)

### Node.js yükle
https://nodejs.org/ → LTS sürümünü indir ve kur (Windows için `.msi`).

Kontrol:
```powershell
node --version
# v20.x.x veya üzeri görmelisin
npm --version
# 10.x.x veya üzeri
```

### Firebase CLI yükle
```powershell
npm install -g firebase-tools
```

Kontrol:
```powershell
firebase --version
# 13.x.x veya üzeri görmelisin
```

### Login
```powershell
firebase login
```
Tarayıcı açılır, Google hesabıyla giriş yap (Firebase projesini yarattığın hesap).

---

## 2️⃣ functions/ klasörünü hazırla

```powershell
cd "C:\Users\TUNA MUHENDISLIK\snap_nova\functions"
npm install
```

Bu, `package.json`'da listelenen Firebase SDK'larını indirir. 1-2 dakika sürer.

### Test build:
```powershell
npm run build
```

Hata olmamalı. `lib/` klasörü oluşur (derlenmiş JS).

---

## 3️⃣ Gemini API Anahtarını Firebase Secret'a Yükle

> **ÖNEMLİ:** Anahtar artık `lib/services/secrets.dart`'tan ÇIKAR ve Firebase Secret Manager'a girer. Böylece kodda asla görünmez.

```powershell
cd "C:\Users\TUNA MUHENDISLIK\snap_nova"
firebase functions:secrets:set GEMINI_API_KEY
```

`?` ile sorar: Gemini API anahtarını yapıştır → Enter. Sana onay sorar → `y`.

### Yedek anahtarı da yükle:
```powershell
firebase functions:secrets:set GEMINI_API_KEY_FALLBACK
```

Aynı şekilde yedek key'i yapıştır.

> ⚠️ Bu anahtarlar artık **sadece** Firebase Secret Manager'da saklı. Cloud Function çağrıldığında runtime'da okunur, hiçbir dosyada görünmez.

---

## 4️⃣ Function'ı Deploy Et

```powershell
firebase deploy --only functions:geminiProxy
```

3-5 dakika sürer. Çıktıda şu satırı göreceksin:
```
Function URL (geminiProxy(us-central1)):
https://us-central1-qualsar2-640f0.cloudfunctions.net/geminiProxy
```

✅ Bu URL'i kopyala. Eğer farklıysa Flutter'daki `_proxyUrl` sabitini güncelle.

### Test (terminal):
```powershell
curl -X POST https://us-central1-qualsar2-640f0.cloudfunctions.net/geminiProxy -H "Content-Type: application/json" -d "{}"
```

Beklenen yanıt:
```
{"error":"Missing or invalid Authorization header."}
```

(Yani function çalışıyor, sadece auth eksik — bu doğru.)

---

## 5️⃣ Flutter'ı Proxy Moduna Al

`lib/services/gemini_service.dart` aç. En üstte `kUseProxy` sabitini bul:

```dart
static const bool kUseProxy = false;  // ← FALSE
```

`true` yap:
```dart
static const bool kUseProxy = true;   // ← PROXY AKTİF
```

Kaydet.

---

## 6️⃣ secrets.dart'ı temizle (artık APK içinde olmayacak)

`lib/services/secrets.dart` dosyasını aç. İçeriği BOŞ bırak (key'ler artık sunucuda):

```dart
// ⚠️ Bu dosya git-ignored. Eskiden Gemini key burada idi; şimdi Firebase
// Cloud Function'da. Bu dosya artık development için bile gerekli değil.

class Secrets {
  static const gemini = '';
  static const List<String> geminiFallbacks = <String>[];
  static const openai = '';
}
```

Bu sayede APK içinde anahtar **kalmaz**.

---

## 7️⃣ Test Et

```powershell
flutter run --release
```

Uygulama açılınca bir soru sor (kamera veya yazılı). Sonuç gelmelidir.

### Sorun çıkarsa:
- **"İşlem başarısız" hatası:** Function deploy oldu mu kontrol et: `firebase functions:list`
- **401 Unauthorized:** Kullanıcı oturum açık mı? Function Firebase Auth token ister.
- **429 Rate limit:** Çok fazla istek gönderildi. Function dakikada 100 çağrı izin veriyor; gerekirse `gemini_proxy.ts`'de `RATE_LIMIT_PER_MIN` arttır.

### Logları izle:
```powershell
firebase functions:log --only geminiProxy
```

---

## 8️⃣ Geri Al (acil durum)

Eğer proxy'de bir sorun çıkarsa, anında geri al:
```dart
static const bool kUseProxy = false;  // ← FALSE'a çevir
```
Plus `secrets.dart` içine key'i geri yaz. Tek satır değişiklikle eski moda dönersin.

---

## Önemli Notlar

### Maliyet
- **Cloud Functions:** İlk 2 milyon çağrı/ay BEDAVA (Firebase Spark plan'da bile)
- **Gemini API:** Senin Google AI Studio hesabından çekiyor — aynı maliyet, sadece anahtar güvende
- Net ek maliyet: **₺0** (orta ölçek kullanıcı sayısına kadar)

### Rate Limit
Function şu anda kullanıcı başına dakikada **100 çağrı** sınırı koyuyor. Tipik kullanım için yeterli; premium kullanıcılar için kotayı arttırmak istersen `gemini_proxy.ts`:
```typescript
const RATE_LIMIT_PER_MIN = 100;  // ← bunu 500 vb. yap
```
Sonra `firebase deploy --only functions:geminiProxy` ile yeniden deploy et.

### Güvenlik Kontrolü
Bu function SADECE Firebase Auth ile giriş yapmış kullanıcılar için çalışır. Misafir / anonymous kullanıcılara çağrı izni yok. Eğer guest mode'da AI kullanım istersen, `gemini_proxy.ts`'deki `verifyIdToken` kısmını değiştirip anonymous-allow yapabilirsin (önerilmez — abuse riski).

---

## Özet — Bu Belgeden Yapacakların

1. ☐ Node.js + Firebase CLI yükle
2. ☐ `firebase login`
3. ☐ `cd functions && npm install`
4. ☐ Gemini anahtarlarını secrets'a yükle (`firebase functions:secrets:set ...`)
5. ☐ Deploy: `firebase deploy --only functions:geminiProxy`
6. ☐ Flutter'da `kUseProxy = true` yap
7. ☐ `secrets.dart`'ı boşalt
8. ☐ `flutter run --release` ile test
9. ☐ AAB build et + Play Store'a yükle (artık güvenli)

Takılırsan bana yapıştır, çözeriz.
