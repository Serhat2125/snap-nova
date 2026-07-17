// ⚠️ ŞABLON DOSYA — bu dosyayı secrets.dart olarak kopyala ve kendi
// anahtarlarını yaz. secrets.dart git-ignored, bu dosya commit edilir.
//
// Yeni makinede kurulum:
//   1) Bu dosyayı secrets.dart olarak kopyala
//   2) Aşağıdaki placeholder'ları gerçek anahtarlarınla değiştir
//   3) secrets.dart dosyası ASLA commit edilmez (.gitignore'da tanımlı)

class Secrets {
  /// Google Gemini API key — aistudio.google.com üzerinden alınır.
  static const gemini = 'YOUR_GEMINI_API_KEY_HERE';

  /// Kota/limit dolunca sırayla denenecek yedek Gemini anahtarları.
  /// Boş bırakılabilir; gerçek anahtarlarını secrets.dart'ta doldur.
  static const List<String> geminiFallbacks = [];

  /// OpenAI API key (Gemini kotası dolunca fallback). Boş bırakılabilir.
  static const openai = '';
}
