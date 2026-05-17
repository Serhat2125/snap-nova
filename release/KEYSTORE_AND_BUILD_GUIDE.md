# 🔐 Keystore + SHA-1 + AAB Build — Adım Adım

> **Bu sayfayı baştan sona, sırayla yap.** Her adımda terminale yapıştıracağın komutu olduğu gibi kopyala.

---

## 1️⃣ Keystore Üretimi (5 dakika)

### Önkoşul: Java JDK kurulu olmalı
Terminal aç ve test et:
```powershell
keytool -help
```
Eğer "tanınmıyor" hatası alırsan: Android Studio yükleyiniz, Java JDK içinde geliyor. Veya direkt JDK yüklemek için: https://adoptium.net/

### Komut: Keystore'u üret

PowerShell aç (Windows Tuşu → "powershell" yaz → enter), proje dizinine git:
```powershell
cd "C:\Users\TUNA MUHENDISLIK\snap_nova"
```

Sonra keystore üretme komutunu çalıştır:
```powershell
keytool -genkey -v -keystore android\app\key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias qualsar-release
```

### Sana soracakları sorular ve cevaplar:

| Soru | Cevap |
|---|---|
| `Enter keystore password:` | **Güçlü şifre üret** (örn: `Qualsar2026!Secure#`) → ⚠️ **NOT AL, KAYBETME** |
| `Re-enter new password:` | Aynı şifreyi tekrar yaz |
| `What is your first and last name?` | `Serhat Düşme` |
| `What is the name of your organizational unit?` | `QuAlsar` |
| `What is the name of your organization?` | `QuAlsar` |
| `What is the name of your City or Locality?` | İstanbul (veya senin şehir) |
| `What is the name of your State or Province?` | İstanbul (veya senin il) |
| `What is the two-letter country code?` | `TR` |
| `Is CN=... correct?` | `yes` |
| `Enter key password for <qualsar-release>` | **Enter'a bas** (keystore şifresi ile aynı olur) |

✅ İşlem bitti. Şimdi `android/app/key.jks` dosyası oluşmuş olmalı.

---

## 2️⃣ key.properties Dosyası Üret

### Komut:
```powershell
cd "C:\Users\TUNA MUHENDISLIK\snap_nova\android"
copy key.properties.template key.properties
```

### Şimdi `key.properties` dosyasını aç (Not Defteri ile veya VS Code):
```
C:\Users\TUNA MUHENDISLIK\snap_nova\android\key.properties
```

İçerik şöyle olmalı (4 satırı değiştir):
```
storePassword=BURAYAYAZ_KEYSTORE_SIFREN
keyPassword=BURAYAYAZ_KEYSTORE_SIFREN
keyAlias=qualsar-release
storeFile=app/key.jks
```

⚠️ `storePassword` ve `keyPassword` aynı şifredir (keystore üretirken enter'a basıp aynısını seçtiysen).

### ⚠️ YEDEKLE
- `android/app/key.jks` dosyasını → Google Drive / OneDrive'a kopyala
- Şifreleri 1Password / LastPass gibi şifre yöneticisine kaydet

**KAYBEDERSEN:** Play Store'daki uygulamayı bir daha güncelleyemezsin. Tek çare yeni uygulama yayımlamak (kullanıcılar baştan indirir).

---

## 3️⃣ SHA-1 Çıkar (Firebase için lazım — 1 dakika)

### Komut:
```powershell
keytool -list -v -keystore "C:\Users\TUNA MUHENDISLIK\snap_nova\android\app\key.jks" -alias qualsar-release
```

Şifre sorarsa keystore şifreni yaz.

### Çıktıda iki önemli satır:
```
SHA1: A1:B2:C3:D4:E5:F6:...:99
SHA256: 11:22:33:44:55:66:...:FF
```

### İkisini de kopyala ve Firebase Console'a ekle:
1. Tarayıcıdan: https://console.firebase.google.com/project/qualsar2-640f0/settings/general
2. Android app `com.qualsar.app` → "Add fingerprint" tıkla
3. **SHA1** değerini yapıştır → Save
4. Tekrar "Add fingerprint" → **SHA256** değerini yapıştır → Save
5. "Download google-services.json" → indirilen dosyayı `android/app/` klasörüne **üzerine yaz**

✅ Bu olmadan release build'te Google Sign-In çalışmaz.

---

## 4️⃣ AAB (App Bundle) Build (30 dakika ilk seferinde)

### Komut:
```powershell
cd "C:\Users\TUNA MUHENDISLIK\snap_nova"
flutter clean
flutter pub get
flutter build appbundle --release
```

İlk build uzun sürer (5-15 dk). Sonraki build'ler 1-3 dk.

### Sonuç dosyası burada:
```
C:\Users\TUNA MUHENDISLIK\snap_nova\build\app\outputs\bundle\release\app-release.aab
```

✅ Bu `.aab` dosyasını Play Console → Internal Testing → "Create new release" → "Upload bundle" ile yükleyeceksin.

### Eğer build hatası alırsan:
- "Keystore not found" → `key.properties` ve `key.jks` dosyalarının yerinde olduğunu kontrol et
- "Out of memory" → `android/gradle.properties` dosyasına ekle: `org.gradle.jvmargs=-Xmx4g`
- Başka hata → çıktıyı bana yapıştır, çözeriz

---

## 5️⃣ APK Test Build (opsiyonel, kendi telefonunda test için)

Telefonuna direkt yükleyebileceğin tek dosya APK:
```powershell
flutter build apk --release
```

Çıktı:
```
build\app\outputs\flutter-apk\app-release.apk
```

Bu dosyayı USB ile telefonuna kopyala → telefonda dosyaya tıkla → "Bilinmeyen kaynaklara izin ver" → kur.

---

## Özet — Sırayla Yapılacaklar

1. ☐ Keystore üret (`keytool -genkey ...`)
2. ☐ `key.properties` doldur
3. ☐ Keystore'u yedekle (Drive + şifre yöneticisi)
4. ☐ SHA-1 + SHA-256 al
5. ☐ Firebase Console'a SHA-1 + SHA-256 ekle
6. ☐ Yeni `google-services.json`'u indirip android/app/'e koy
7. ☐ `flutter build appbundle --release` çalıştır
8. ☐ `.aab` dosyasını Play Console Internal Testing'e yükle

Her adımda sorun olursa hata mesajını bana göster.
