import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  FeedbackService — Kullanıcı geri bildirimlerini Firestore'a kaydeder.
//
//  Firestore Koleksiyonu: "feedbacks"
//  Döküman Alanları:
//    isPositive      : bool     — true=👍 / false=👎
//    cozum_modu      : String   — "Adım Adım Çözüm", "Hızlı Çözüm" vb.
//    soru_ozeti      : String   — İlk 200 karakter (tam sonuç göndermiyoruz)
//    kullanici_notu  : String?  — Olumsuz geri bildirim nedeni (opsiyonel)
//    tarih           : Timestamp — Sunucu zaman damgası
//
//  Kurulum için:
//    1. Firebase Console'dan yeni proje oluştur
//    2. Android uygulaması ekle (package: com.example.snap_nova)
//    3. google-services.json dosyasını android/app/ klasörüne koy
//    4. FlutterFire CLI: flutterfire configure
//    5. main.dart'ta Firebase.initializeApp() zaten çağrılıyor
// ═══════════════════════════════════════════════════════════════════════════════

class FeedbackService {
  static final _db = FirebaseFirestore.instance;

  /// Geri bildirimi Firestore'a kaydeder.
  /// Firebase başlatılmamışsa veya bağlantı yoksa sessizce geçer —
  /// kullanıcı deneyimini kesmez.
  static Future<void> saveFeedback({
    required bool isPositive,
    required String solutionMode,
    required String questionSummary,
    String? userReason,
  }) async {
    try {
      await _db.collection('feedbacks').add({
        'isPositive'     : isPositive,
        'cozum_modu'     : solutionMode,
        'soru_ozeti'     : questionSummary.length > 200
            ? '${questionSummary.substring(0, 200)}…'
            : questionSummary,
        'kullanici_notu' : userReason,
        'tarih'          : FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Sessizce yok say — Firebase henüz kurulmamış veya ağ hatası
    }
  }
}
