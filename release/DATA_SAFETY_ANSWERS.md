# 📋 Play Console — Data Safety Form Cevapları

Play Console → **App content** → **Data safety**. Aşağıdaki cevapları sırayla işaretle.

> Soruları sırayla yanıtla. Bir alanı kaçırırsan Play Console submit etmene izin vermez.

---

## 1. Data collection and security

### Does your app collect or share any of the required user data types?
✅ **Yes**

### Is all of the user data collected by your app encrypted in transit?
✅ **Yes** — Tüm bağlantılar HTTPS/TLS.

### Do you provide a way for users to request that their data is deleted?
✅ **Yes** — Profil → "Hesabımı Sil" özelliği var.

### Data deletion explanation:
```
Kullanıcı uygulama içinde Profil > Hesabımı Sil yolunu izleyerek hesabını silebilir. Hesap silindiğinde Firebase Authentication kullanıcı kaydı + Firestore'daki kişisel veriler kalıcı olarak silinir.
```

---

## 2. Data types collected — Her birini ayrı ayrı yanıtla

### ✅ Personal info
| Type | Collected? | Shared? | Optional? | Purpose |
|---|---|---|---|---|
| **Name** | Yes | No | Yes | Account management |
| **Email address** | Yes | No | No | Account management, App functionality |
| **User IDs** | Yes | No | No | Account management, Analytics |

### ✅ Photos and videos
| Type | Collected? | Shared? | Optional? | Purpose |
|---|---|---|---|---|
| **Photos** | Yes | Yes (with Google Gemini) | Yes | App functionality (AI solution generation) |

**Not:** "Shared" işaretledik çünkü fotoğraflar AI işleme için Google Gemini'ye iletiliyor.

### ✅ Audio files
| Type | Collected? | Shared? | Optional? | Purpose |
|---|---|---|---|---|
| **Voice or sound recordings** | **No** | — | — | — |

**Not:** Ses cihazda metne çevriliyor (on-device speech-to-text), sunucumuza ses dosyası gönderilmiyor. **Hayır** seçeneği doğru.

### ✅ App activity
| Type | Collected? | Shared? | Optional? | Purpose |
|---|---|---|---|---|
| **App interactions** | Yes | No | No | Analytics, App functionality |
| **In-app search history** | No | — | — | — |
| **Other actions** | Yes | No | No | App functionality (study sessions, solutions used) |

### ✅ App info and performance
| Type | Collected? | Shared? | Optional? | Purpose |
|---|---|---|---|---|
| **Crash logs** | Yes | No | No | Analytics |
| **Diagnostics** | Yes | No | No | Analytics |
| **Other app performance data** | Yes | No | No | Analytics |

### ✅ Device or other IDs
| Type | Collected? | Shared? | Optional? | Purpose |
|---|---|---|---|---|
| **Device or other IDs** | Yes | No | No | Analytics, App functionality |

### ✅ Location
| Type | Collected? | Shared? | Optional? | Purpose |
|---|---|---|---|---|
| **Approximate location** | Yes | No | Yes | App functionality (Bilgi Ligi — Knowledge League rankings) |
| **Precise location** | **No** | — | — | — |

**Not:** Sadece şehir + ülke seviyesi (IP'den çözülüyor). Tam GPS YOK.

### Financial info, Health, Messages, Contacts, Calendar, Files
**Hepsi: No** (hiçbirine erişmiyoruz)

### Web browsing
**No**

---

## 3. Security practices

### Is all of the user data collected by your app encrypted in transit?
✅ **Yes**

### Do you provide a way for users to request that their data is deleted?
✅ **Yes**

### Have you committed to follow the Play Families Policy?
- Eğer hedef yaş 13+ ise: **No** (yetişkin/teen uygulaması)
- Eğer çocuklara yönelik olsaydı **Yes** olurdu

### Was your app independently validated against a global security standard?
- **No** (henüz bağımsız güvenlik denetimi yapılmadı)

---

# 🎯 Content Rating (İçerik Derecelendirme)

Play Console → **App content** → **Content rating**. Aşağıdaki sorulara göre "Hayır / Yok" işaretle:

| Soru | Cevap |
|---|---|
| Şiddet (gerçekçi veya animasyon) | ❌ Yok |
| Cinsellik / nüdite | ❌ Yok |
| Kötü dil / küfür | ❌ Yok |
| Uyuşturucu / alkol referansı | ❌ Yok |
| Kumar (gerçek para) | ❌ Yok |
| Korku / dehşet | ❌ Yok |
| Kullanıcılar birbirine mesaj atabiliyor mu? | ❌ Hayır (Bilgi Ligi'nde sadece nickname görünür, mesaj yok) |
| Kullanıcılar konum paylaşıyor mu? | ❌ Hayır (sadece şehir/ülke metni, harita yok) |
| Kullanıcılar fotoğraf/video paylaşıyor mu? | ❌ Hayır (sadece kendi sorularına çekiyor) |
| Reklamlar var mı? | ❌ Hayır (henüz reklam entegrasyonu yok) |
| Uygulama içi satın alma var mı? | ✅ Evet (Premium abonelik) |
| Kullanıcı içeriği üretiyor mu? | ❌ Hayır |
| Sosyal etkileşim özellikleri | ❌ Hayır |
| Web tarayıcı erişimi (in-app) | ⚠️ Sınırlı — model_viewer_plus WebView 3D model yükler ama kullanıcı tarayıcı kullanmaz |

**Beklenen sınıflandırma:** **PEGI 3 / Everyone (E)** — eğitim odaklı, hiçbir hassas içerik yok.

**Hedef yaş:** 13+ (Teen) — daha düşük seçersen Google Play Families Policy uyumluluğu istiyor.

---

## 📍 Target audience and content

### Target age range
✅ **13–17** ve **18+** (Teen + Adult)

> 13 altı yaş seçersen Designed for Families programına başvurman gerekir; kompleks gereksinimler var, atla.

### Does your app appeal to children?
- ⚠️ Eğitim uygulaması, çocukları cezbedebilir AMA hedef kitle 13+. 
- Cevap: **No** (yalnızca 13+ hedeflersen)

### Ads policy
- Reklamlarınız var mı: **No**
