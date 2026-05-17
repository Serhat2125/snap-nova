# ─── QuAlsar ProGuard / R8 Keep Rules ─────────────────────────────────────────
# isMinifyEnabled = true ile birlikte aktif olur. Aşağıdaki kütüphaneler
# reflection / native calls kullandığı için sınıf/method isimleri korunmalı.

# ── Flutter / Dart embedding ───────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── Firebase (Auth, Firestore, Crashlytics, Analytics, App Check) ─────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName *;
}

# ── Firebase App Check (Play Integrity provider için kritik) ──────────────────
-keep class com.google.firebase.appcheck.** { *; }
-keep class com.google.android.play.core.integrity.** { *; }
-keep class com.google.android.play.integrity.** { *; }
-dontwarn com.google.firebase.appcheck.**

# ── in_app_purchase + Play Billing ────────────────────────────────────────────
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }
-keep class io.flutter.plugins.inapppurchase.** { *; }
# Crashlytics: stacktrace symbolization için
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# ── Google Play Billing (in_app_purchase) ─────────────────────────────────────
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }

# ── Google Sign-In ────────────────────────────────────────────────────────────
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ── WebView (model_viewer_plus) ───────────────────────────────────────────────
-keep class * extends android.webkit.WebViewClient
-keep class * extends android.webkit.WebChromeClient
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# ── Gson / JSON serialization (firestore çevirileri için) ─────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# ── Kotlin reflection (Hilt/coroutine olmayan minimal) ────────────────────────
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# ── App package — model sınıflarımız native plugin'lerle reflection
#    yapmıyor; ama defensive: paket kökünü koru.
-keep class com.qualsar.ai.** { *; }
