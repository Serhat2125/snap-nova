# iOS FCM Push — APNs Kurulum Rehberi

iOS'ta FCM push çalışması için aşağıdaki adımlar **bir kerelik** yapılmalı.
Bu adımlar Apple Developer hesabı + Mac + Xcode gerektirir. Android için
hiçbir şey yapmana gerek yok — orada otomatik çalışıyor.

## 1. APNs Authentication Key oluştur

1. https://developer.apple.com/account → Certificates, Identifiers & Profiles
2. **Keys** sekmesi → **+** (yeni anahtar)
3. "QuAlsar APNs" gibi ad ver, **Apple Push Notifications service (APNs)** kutusunu işaretle
4. **Continue → Register → Download** (`.p8` dosyası iner)
5. **Key ID**'yi not al (örn: `ABCD1234EF`)
6. **Team ID**'yi de not al (Account → Membership → Team ID)

## 2. Firebase Console'a yükle

1. https://console.firebase.google.com/project/qualsar2-640f0/settings/cloudmessaging
2. **Apple app configuration** → iOS bundle id'yi seç
3. **APNs Authentication Key** bölümünde **Upload**:
   - `.p8` dosyasını seç
   - **Key ID** ve **Team ID**'yi gir
4. **Upload**

## 3. Xcode tarafı

`ios/Runner.xcworkspace`'i Xcode'da aç:

1. **Signing & Capabilities** → **+ Capability** → **Push Notifications**
2. **+ Capability** → **Background Modes** → **Remote notifications** kutusunu işaretle
3. **+ Capability** → **Associated Domains** → ekle:
   - `applinks:qualsar2-640f0.web.app`

## 4. apple-app-site-association dosyası

`hosting/.well-known/apple-app-site-association` dosyasında
`TEAM_ID_PLACEHOLDER` yazıyor. Bunu **Team ID** ile değiştir:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["AB12CD34EF.com.qualsar.ai"],
        "paths": ["/davet/*", "/u/*"]
      }
    ]
  }
}
```

Sonra:
```
firebase deploy --only hosting
```

## 5. Test

1. Xcode → Run on real device (simulator FCM desteklemez)
2. Bildirim izni dialog'u çıkar → izin ver
3. Konsolda `[Push] token persisted` görmeli
4. Firebase Console → Cloud Messaging → Send test message → token'ı yapıştır → Send

## Notlar

- Sandbox vs Production APNs — Firebase otomatik handle eder
- App Store Connect'te uygulama 1+ kez yüklenmeden iOS push çalışmaz
- TestFlight'ta normal davranır
- Android için **hiçbir şey** gerekmez, FCM otomatik çalışır
