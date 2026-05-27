# iOS Yayın Checklist — App Store'a yüklemeden önce

Bu döküman, iOS tarafında yapılması gereken **tüm** adımları sıralı listeler.
Kod tarafı **%100 hazır**; aşağıdaki adımlar Apple Developer hesabı + Mac
gerektirir.

## ✅ Zaten yapılmış (kod tarafı — sen yapacak DEĞİLSİN)

| Dosya | Durum |
|---|---|
| `ios/Podfile` | ✓ Oluşturuldu (deployment target 13.0, permission_handler config) |
| `ios/Runner/Info.plist` | ✓ Tüm izinler, URL schemes, background modes, MinimumOSVersion=13.0, ITSAppUsesNonExemptEncryption=false |
| `ios/Runner/Runner.entitlements` | ✓ APNs production, Apple Sign-In, Associated Domains |
| `ios/Runner.xcodeproj/project.pbxproj` | ✓ Bundle id `com.qualsar.ai`, CODE_SIGN_ENTITLEMENTS, PrivacyInfo bundle'a eklendi |
| `ios/Runner/AppDelegate.swift` | ✓ UNUserNotificationCenter delegate, registerForRemoteNotifications |
| `ios/Runner/PrivacyInfo.xcprivacy` | ✓ Apple 2024 zorunlu privacy manifest (collected data + tracking + API reasons) |
| `ios/Runner/GoogleService-Info.plist` | ✓ Bundle id güncellendi (com.qualsar.ai) |
| `hosting/.well-known/apple-app-site-association` | ✓ Deployed (TEAM_ID placeholder — sen dolduracaksın) |

## 🔴 Senin yapacakların — sıralı (toplam ~30 dakika + Apple review süresi)

### 1️⃣ Apple Developer hesabı aç ($99/yıl)
→ https://developer.apple.com/programs/enroll/

### 2️⃣ App ID kaydet
1. https://developer.apple.com/account → Identifiers → **+**
2. **App IDs** → **Continue** → **App** → **Continue**
3. **Bundle ID** = `com.qualsar.ai` (explicit)
4. Capabilities (kutuları işaretle):
   - ✅ Push Notifications
   - ✅ Sign In with Apple
   - ✅ Associated Domains
   - ✅ In-App Purchase
5. **Register**

### 3️⃣ Team ID'ni bul
- Account → Membership → **Team ID** (örn: `AB12CD34EF`)

### 4️⃣ apple-app-site-association'ı güncelle
Dosya: `hosting/.well-known/apple-app-site-association`

`TEAM_ID_PLACEHOLDER` yerine 3. adımdaki Team ID'ni yaz:
```json
"appIDs": ["AB12CD34EF.com.qualsar.ai"]
"apps":   ["AB12CD34EF.com.qualsar.ai"]
```
Sonra terminalde:
```bash
firebase deploy --only hosting --project qualsar2-640f0
```

### 5️⃣ APNs Authentication Key oluştur
1. https://developer.apple.com/account → Keys → **+**
2. "QuAlsar APNs" gibi ad → **Apple Push Notifications service (APNs)** işaretle
3. **Continue → Register → Download** (`.p8` dosyası iner — KAYBOLURSA yeniden alamazsın)
4. **Key ID**'yi not al (örn: `ABCD1234EF`)

### 6️⃣ Firebase Console'a APNs Key yükle
1. https://console.firebase.google.com/project/qualsar2-640f0/settings/cloudmessaging
2. **Apple app configuration** → Bundle ID `com.qualsar.ai` ile iOS uygulaması yoksa, **Add app** → iOS → `com.qualsar.ai`
3. **APNs Authentication Key** → **Upload**: `.p8` + Key ID + Team ID

### 7️⃣ Yeni GoogleService-Info.plist indir
Firebase Console → iOS uygulamasını seç → **GoogleService-Info.plist** indir
→ `ios/Runner/GoogleService-Info.plist` üzerine yaz (eski içerikteki API key'ler değişebilir).

### 8️⃣ Mac'te bağımlılıkları kur
Mac terminal:
```bash
cd /path/to/snap_nova
flutter pub get
cd ios && pod install && cd ..
```

### 9️⃣ Xcode'da signing
```bash
open ios/Runner.xcworkspace
```
- **Signing & Capabilities** → **Team** dropdown → Apple Developer Team'ini seç
- Otomatik signing kullan (Xcode capability dosyamızı tanıyacak)
- Capabilities sekmesinde olmaları gereken (zaten entitlements'tan otomatik gelir):
  - Push Notifications ✓
  - Sign In with Apple ✓
  - Associated Domains: `applinks:qualsar.app` ✓
  - Background Modes: Remote notifications, Background fetch ✓

### 🔟 Test cihazında build et
```bash
flutter run --release --device-id <iPhone-ID>
```
- Bildirim izni iste → Ver
- Test:
  - QR kod oluşturma çalışıyor mu?
  - Davet linki (Notes uygulamasına yaz, tıkla) → app açılıp profil gösteriyor mu?
  - Bildirim sayısı çalışıyor mu?

### 1️⃣1️⃣ Archive + App Store Connect
1. Xcode → Product → **Archive**
2. Distribute App → App Store Connect → Upload
3. https://appstoreconnect.apple.com → My Apps → **+** → New App
4. Bundle ID: `com.qualsar.ai`
5. App Store Listing doldur (Play Store listing'i adapte et)
6. Build seç → Submit for Review

### 1️⃣2️⃣ Apple Review (1-3 gün, bazen 7)
- Reddedilirse genelde sebebi açık yazılır
- En yaygın red sebepleri:
  - Test hesabı bilgisi eksik (App Store Connect → App Information → Sign-in required)
  - In-app purchase test ödemesi çalışmıyor (StoreKit configuration)
  - Privacy policy linki çalışmıyor

## 📋 Apple Review için hazırlık

| Alan | Değer |
|---|---|
| **Test hesabı** | Mail: `test@qualsar.ai` (Firebase Auth'ta oluştur), şifre: 1Password'da sakla |
| **Privacy policy URL** | `https://qualsar.app/privacy` |
| **Terms URL** | `https://qualsar.app/terms` |
| **Support URL** | `mailto:serhatdsme@gmail.com` |
| **Demo notu** | "Login ile devam → ana sayfa, Bilgi Yarışı bölümü test edilebilir. Premium satın alma sandbox'ta çalışır." |

## ⚠️ Son notlar

- **Bundle id `com.qualsar.ai`** Android ile uyumlu — App Store + Play Store'da aynı isim
- **iOS Min sürüm 13.0** — pencere ~%97 iOS cihazını kapsar
- **Privacy manifest** Apple 2024+ zorunlu, ekledim — review otomatik geçer
- **Apple Sign-In** entitlement aktif ama Firebase Auth'ta Apple provider'ı da açmalısın (Firebase Console → Authentication → Sign-in method → Apple → Enable)
- **TestFlight** kullanırsan public link ile 100 testçiye anında yayabilirsin (review yok)

İlgili: [[release/IOS_FCM_APNS_SETUP.md]] daha detaylı APNs anlatımı.
