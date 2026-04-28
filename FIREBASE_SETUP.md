# 🔥 Firebase Auth Kurulumu — Telefon · Google · Apple

Kod tarafı %100 hazır (`firebase_auth`, `google_sign_in`, `sign_in_with_apple`
paketleri eklendi, `AuthService` gerçek SDK çağrılarını yapıyor). Bu listede
**senin yapman gereken** kalan adımlar var. Sırayla geç:

---

## 📍 1. flutterfire configure (TEK BİR KOMUT)

```bash
# Kurulum (bir kez)
dart pub global activate flutterfire_cli

# Proje kökünde
cd "/c/Users/TUNA MUHENDISLIK/snap_nova"
flutterfire configure
```

Komut çalışınca:

- Firebase hesabınla giriş ister (browser açar)
- Mevcut proje listesini gösterir → seç (yoksa "Create new project")
- Platform seç: **android** + **ios** işaretle
- Otomatik üretir:
  - `lib/firebase_options.dart` (stub'ı geçer)
  - `android/app/google-services.json`
  - `ios/Runner/GoogleService-Info.plist`

Bu adım sonrası `flutter run` ile uygulama Firebase'e bağlı açılır.

---

## 📞 2. Telefon (SMS) — Firebase Console

🌐 https://console.firebase.google.com → projeni aç

1. **Authentication → Get started** (ilk kez ise)
2. **Sign-in method → Phone → Enable → Save**
3. **Project Settings → ⚙ → Your apps → Android app → Add fingerprint**
   - SHA-1 ve SHA-256'yı al:
     ```bash
     cd android && ./gradlew signingReport
     ```
   - Çıktıda `Variant: debug` altındaki SHA-1 + SHA-256'yı kopyala → Console'a ekle
4. **`google-services.json`'u yeniden indir** → `android/app/` altındaki eskisini değiştir
5. (Opsiyonel test) Authentication → Phone → "Phone numbers for testing" → faturasız test numarası + sabit kod ekle

---

## 🟢 3. Google Sign-In — Firebase Console

1. **Authentication → Sign-in method → Google → Enable**
2. **Project support email** seç (zorunlu)
3. **Save**
4. iOS için: `flutterfire configure` zaten `GoogleService-Info.plist`
   içine `REVERSED_CLIENT_ID`'yi ekledi — Info.plist'e otomatik
   yansır. Manuel iş yok.
5. Android için: Adım 2'deki SHA-1 zaten Google için de geçerli. Fazladan iş yok.

> **Önemli:** Google sign-in DEBUG imzasıyla SHA-1 ister. Release imzasını
> Play Console'a yüklediğinde Play Console → App signing → SHA-1'i de
> Firebase Console'a ekle (release build'de SMS/Google çalışsın diye).

---

## 🍎 4. Apple Sign-In — Apple Developer + Firebase

(Sadece iOS için gerekli; Apple Developer Program **ücretli — $99/yıl**.)

### 4a. Apple Developer Console

🌐 https://developer.apple.com/account

1. **Certificates, IDs & Profiles → Identifiers → App IDs**
2. App ID'ni seç (Bundle ID: `com.qualsar.app`)
3. **Capabilities** listesinden **Sign In with Apple** işaretle → Save
4. **Identifiers → Services IDs → +** → Yeni Service ID oluştur:
   - Identifier (örn. `com.qualsar.app.signin`)
   - Description: QuAlsar Sign In
   - **Sign In with Apple** işaretle → **Configure**:
     - Primary App ID: az önceki App ID
     - **Return URLs**: Firebase'in vereceği callback URL (5. adımda alacağız)
5. **Keys → +** → Yeni key oluştur:
   - Adı: QuAlsar Apple Auth
   - **Sign In with Apple** işaretle → Configure → Primary App ID seç
   - **Continue → Register → Download** (`AuthKey_XXXXXXXX.p8` dosyası)
   - **Key ID** ve **Team ID**'yi kaydet (sayfada görünür)

### 4b. Firebase Console — Apple provider

1. **Authentication → Sign-in method → Apple → Enable**
2. **Services ID**: 4a/4'teki Service ID identifier
3. **Apple Team ID**: Apple Dev hesabındaki Team ID (üstte göründü)
4. **Key ID**: 4a/5'teki Key ID
5. **Private key**: indirdiğin `.p8` dosyasının içeriğini yapıştır
6. **Save** — Console sana bir **callback URL** verir → Apple Service ID'nin "Return URLs" kısmına ekle (4a/4 adımına geri dön)

### 4c. Xcode — Capability

1. `ios/Runner.xcworkspace`'i Xcode'da aç
2. Sol panelden **Runner** projesini → **Runner** target'ı seç
3. **Signing & Capabilities** sekmesi
4. Sol üstte **+ Capability** → "Sign In with Apple" → çift tıkla
5. (Otomatik) `Runner.entitlements` dosyası oluşturulur — biz zaten ekledik
6. Bundle ID, Team aynı (App ID ile)
7. Kaydet → **Product → Clean Build Folder** → tekrar build

---

## 🚀 5. Çalıştır

```bash
flutter clean
flutter pub get

# Android
flutter run

# iOS (Mac gerekli)
cd ios && pod install && cd ..
flutter run
```

---

## ✅ Test sırası

1. Uygulama aç → onboarding sayfa 1 (auth)
2. **Google ile devam et** → Google sheet açılır → hesap seç → otomatik geçer
3. **Apple ile devam et** (sadece iOS) → Apple sheet açılır → Face ID/şifre → geçer
4. **Telefon numarası ile devam et** → numara gir → "Kod Gönder" → SMS → 6 haneli kodu yaz → otomatik doğrulanır
5. Hepsinde başarılı giriş sonrası uygulama otomatik **Eğitim Seviyeni Belirle** sayfasına geçer

---

## 🐛 Hata Karşılığı Sözlük

| Hata | Sebep | Çözüm |
|------|-------|-------|
| `[core/no-app] No Firebase App` | flutterfire configure çalıştırılmadı | Adım 1 |
| `app-not-authorized` | SHA-1 yanlış / google-services.json eski | Adım 2.3-2.4 |
| `billing-not-enabled` | Phone Auth Blaze plan ister (production) | Firebase Console → Upgrade plan, OR Test numarası kullan (Adım 2.5) |
| iOS reCAPTCHA görünüyor | APNs yüklenmemiş | Apple Dev → APNs Auth Key → Firebase Console → Cloud Messaging |
| Apple sheet açılmıyor | Capability eksik | Adım 4c |
| `INVALID_TOKEN` (Apple) | Service ID / Return URL eşleşmiyor | Adım 4a/4 ↔ 4b |
| `invalid-verification-code` | Kullanıcı yanlış kod yazdı | Tekrar gönder |

---

## 📋 Kod tarafında ZATEN yapılmış olanlar

- ✅ `pubspec.yaml`: `firebase_auth`, `google_sign_in`, `sign_in_with_apple`
- ✅ `lib/firebase_options.dart`: stub (flutterfire configure ile gerçeği üretilir)
- ✅ `lib/main.dart`: `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` + readiness flag
- ✅ `lib/services/auth_service.dart`:
  - Telefon: `FirebaseAuth.verifyPhoneNumber` + `signInWithCredential`
  - Google: `GoogleSignIn().signIn()` → `GoogleAuthProvider.credential` → Firebase
  - Apple: `SignInWithApple.getAppleIDCredential` → `OAuthProvider('apple.com')` → Firebase
- ✅ `android/app/build.gradle.kts`: Google Services plugin koşullu, `minSdk = 23`, `multiDexEnabled = true`
- ✅ `android/settings.gradle.kts`: plugin sürümü deklare edildi
- ✅ `ios/Runner/Runner.entitlements`: `com.apple.developer.applesignin` eklendi
- ✅ UI: yapılandırma yoksa AlertDialog, kullanıcı iptalinde sessiz dön
