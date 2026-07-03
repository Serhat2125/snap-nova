import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase: google-services plugin'i SADECE google-services.json varsa uygula.
// flutterfire configure çalıştırılmadıysa dosya yoktur — bu guard sayesinde
// build düşmez (uygulama Firebase olmadan açılır, AuthService içindeki
// firebaseReady flag'i false kalır → kullanıcıya net mesaj gösterilir).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// ── Release signing — key.properties'tan oku, dosya yoksa debug ile imzala ──
// Geliştirme makinesinde: android/key.properties + android/app/key.jks
// (her ikisi de .gitignore'lu). CI/CD'de bu değerler env'den enjekte edilir.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.qualsar.ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications API 26 öncesinde java.time için
        // desugaring ister. Olmadan build hata: "core library desugaring
        // to be enabled for :app".
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.qualsar.ai"
        // Firebase Auth Android için minSdk >= 23 gerektiriyor.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // ── flutter run hızlandırma ──────────────────────────────────
            // NOT: ndk.abiFilters buildType'ta defaultConfig ile BİRLEŞTİĞİ
            // için işe yaramıyor (Flutter plugin tüm ABI'ları ekliyor);
            // bu yüzden packaging dışlaması kullanılıyor.
            packaging {
                jniLibs {
                    // Vulkan validation layer (15 MB, sıkıştırmasız) —
                    // yalnızca Vulkan grafik hatası debug'ında gerekir.
                    excludes += "**/libVkLayer_khronos_validation.so"
                    // Fiziksel telefonlar arm64-v8a; x86_64/armeabi-v7a
                    // plugin .so'ları (ML Kit barhopper vb.) debug APK'yı
                    // şişiriyordu. x86_64 EMÜLATÖRDE debug çalıştıracaksan
                    // bu iki satırı geçici olarak yorum yap.
                    excludes += "lib/x86_64/**"
                    excludes += "lib/armeabi-v7a/**"
                }
            }
        }
        release {
            // key.properties varsa release imzayla, yoksa debug ile (ki
            // `flutter run --release` lokal test için çalışsın). Production
            // AAB build için key.properties + key.jks ZORUNLU.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Production: R8 minify + resource shrinking aktif → APK ~50%
            // küçülür. proguard-rules.pro içinde Firebase, Play Billing,
            // WebView, model_viewer_plus keep rules tanımlı.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Native library debug sembolleri — Flutter tooling AAB içinde
            // libflutter.so.sym/dbg ARIYOR; "NONE" verince eksik diye build'i
            // fail ediyor. SYMBOL_TABLE: küçük (~5-10 MB ekstra), Play Console
            // crash sembolleri için yeterli; FULL: ~50 MB, native stack trace
            // satır numarası gerekirse. SYMBOL_TABLE varsayılan dengesini verir.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
    }
}

flutter {
    source = "../.."
}

// Core library desugaring runtime — `isCoreLibraryDesugaringEnabled = true`
// olan compileOptions için Android'in resmi backport kütüphanesi gerekir.
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
