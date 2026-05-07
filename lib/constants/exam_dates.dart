// ═══════════════════════════════════════════════════════════════════════════════
//  exam_dates.dart — Ülke bazlı resmi sınav takvimi (merkezi sabit)
//  • Sınav Sayacı ekranı bu dosyadan beslenir.
//  • Sıralama: önce eğitim seviyesi (levelOrder), sonra tarih.
//  • Yeni yıl/sınav eklemek için sadece bu dosyayı güncelle.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

@immutable
class OfficialExam {
  /// Sınavın kısa kodu — UI'da kullanılmıyor, listede tekillik için.
  final String id;

  /// Sınavın tam adı (Örn: "YKS - TYT", "SAT", "Abitur").
  final String name;

  /// Sınav resmi tarihi (yerel saat — gösterimde TR/locale formatında).
  final DateTime date;

  /// Eğitim seviyesi sıralaması — küçükten büyüğe (1 = ilköğretim çıkışı,
  /// 2 = lise çıkışı, 3 = lisansüstü/devlet alımı).
  final int levelOrder;

  /// Kart üzerindeki vurgu rengi (yıl etiketi vb. için).
  final Color accent;

  /// Açıklama / oturum bilgisi (opsiyonel — alt satırda küçük etiket).
  final String? subtitle;

  const OfficialExam({
    required this.id,
    required this.name,
    required this.date,
    required this.levelOrder,
    required this.accent,
    this.subtitle,
  });

  String get year => date.year.toString();

  /// "2026 YKS - TYT" formatında tam başlık.
  String get fullTitle => '$year $name';
}

// ─── Ülke bazlı sınav listesi ─────────────────────────────────────────────────
// Tarihler 2026 takvimine göre — her yıl başında güncellenmeli.
// (Resmi takvim açıklanmadan önce tahmini son haftayı kullanıyoruz.)

const _trBlue = Color(0xFF2563EB);
const _trOrange = Color(0xFFFF6A00);
const _trIndigo = Color(0xFF6366F1);
const _trGreen = Color(0xFF10B981);
const _trPurple = Color(0xFF7C3AED);
const _trRose = Color(0xFFE11D48);

final Map<String, List<OfficialExam>> _examsByCountry = {
  // ─── Türkiye ────────────────────────────────────────────────────────────
  'tr': [
    OfficialExam(
      id: 'tr_lgs_2026',
      name: 'LGS',
      subtitle: 'Liselere Geçiş Sınavı',
      date: DateTime(2026, 6, 7, 9, 30),
      levelOrder: 1,
      accent: _trGreen,
    ),
    OfficialExam(
      id: 'tr_yks_tyt_2026',
      name: 'YKS - TYT',
      subtitle: 'Temel Yeterlilik Testi',
      date: DateTime(2026, 6, 13, 10, 15),
      levelOrder: 2,
      accent: _trBlue,
    ),
    OfficialExam(
      id: 'tr_yks_ayt_2026',
      name: 'YKS - AYT',
      subtitle: 'Alan Yeterlilik Testi',
      date: DateTime(2026, 6, 14, 10, 15),
      levelOrder: 2,
      accent: _trIndigo,
    ),
    OfficialExam(
      id: 'tr_yks_ydt_2026',
      name: 'YKS - YDT',
      subtitle: 'Yabancı Dil Testi',
      date: DateTime(2026, 6, 14, 15, 45),
      levelOrder: 2,
      accent: _trPurple,
    ),
    OfficialExam(
      id: 'tr_msu_2026',
      name: 'MSÜ',
      subtitle: 'Milli Savunma Üniversitesi Askeri Öğrenci Aday Belirleme',
      date: DateTime(2026, 3, 22, 10, 15),
      levelOrder: 2,
      accent: _trRose,
    ),
    OfficialExam(
      id: 'tr_dgs_2026',
      name: 'DGS',
      subtitle: 'Dikey Geçiş Sınavı',
      date: DateTime(2026, 7, 26, 10, 15),
      levelOrder: 3,
      accent: _trOrange,
    ),
    OfficialExam(
      id: 'tr_kpss_lisans_2026',
      name: 'KPSS Lisans',
      subtitle: 'Genel Yetenek-Genel Kültür / Eğitim Bilimleri',
      date: DateTime(2026, 7, 18, 10, 15),
      levelOrder: 3,
      accent: _trBlue,
    ),
    OfficialExam(
      id: 'tr_kpss_alan_2026',
      name: 'KPSS Alan Bilgisi',
      subtitle: 'Alan Bilgisi Oturumu',
      date: DateTime(2026, 7, 19, 10, 15),
      levelOrder: 3,
      accent: _trIndigo,
    ),
    OfficialExam(
      id: 'tr_ales_1_2026',
      name: 'ALES/1',
      subtitle: 'Akademik Personel ve Lisansüstü Eğitimi Giriş Sınavı (İlkbahar)',
      date: DateTime(2026, 5, 3, 10, 15),
      levelOrder: 3,
      accent: _trGreen,
    ),
    OfficialExam(
      id: 'tr_ales_2_2026',
      name: 'ALES/2',
      subtitle: 'ALES Sonbahar Dönemi',
      date: DateTime(2026, 11, 22, 10, 15),
      levelOrder: 3,
      accent: _trPurple,
    ),
    OfficialExam(
      id: 'tr_yds_1_2026',
      name: 'YDS/1',
      subtitle: 'Yabancı Dil Bilgisi Seviye Tespit Sınavı (İlkbahar)',
      date: DateTime(2026, 4, 5, 10, 15),
      levelOrder: 3,
      accent: _trRose,
    ),
    OfficialExam(
      id: 'tr_yds_2_2026',
      name: 'YDS/2',
      subtitle: 'YDS Sonbahar Dönemi',
      date: DateTime(2026, 10, 18, 10, 15),
      levelOrder: 3,
      accent: _trOrange,
    ),
  ],

  // ─── United States ──────────────────────────────────────────────────────
  'us': [
    OfficialExam(
      id: 'us_sat_mar_2026',
      name: 'SAT (March)',
      subtitle: 'College Board — Spring',
      date: DateTime(2026, 3, 14, 8),
      levelOrder: 2,
      accent: _trBlue,
    ),
    OfficialExam(
      id: 'us_sat_may_2026',
      name: 'SAT (May)',
      subtitle: 'College Board',
      date: DateTime(2026, 5, 2, 8),
      levelOrder: 2,
      accent: _trBlue,
    ),
    OfficialExam(
      id: 'us_sat_jun_2026',
      name: 'SAT (June)',
      subtitle: 'College Board — Final spring date',
      date: DateTime(2026, 6, 6, 8),
      levelOrder: 2,
      accent: _trBlue,
    ),
    OfficialExam(
      id: 'us_act_apr_2026',
      name: 'ACT (April)',
      subtitle: 'ACT Inc.',
      date: DateTime(2026, 4, 11, 8),
      levelOrder: 2,
      accent: _trIndigo,
    ),
    OfficialExam(
      id: 'us_act_jun_2026',
      name: 'ACT (June)',
      subtitle: 'ACT Inc.',
      date: DateTime(2026, 6, 13, 8),
      levelOrder: 2,
      accent: _trIndigo,
    ),
    OfficialExam(
      id: 'us_ap_may_2026',
      name: 'AP Exams',
      subtitle: 'Advanced Placement (start of window)',
      date: DateTime(2026, 5, 4, 8),
      levelOrder: 2,
      accent: _trPurple,
    ),
  ],

  // ─── United Kingdom ─────────────────────────────────────────────────────
  'uk': [
    OfficialExam(
      id: 'uk_gcse_2026',
      name: 'GCSE',
      subtitle: 'General Certificate of Secondary Education (start)',
      date: DateTime(2026, 5, 11, 9),
      levelOrder: 1,
      accent: _trGreen,
    ),
    OfficialExam(
      id: 'uk_alevel_2026',
      name: 'A-Levels',
      subtitle: 'GCE A-Level exams (start)',
      date: DateTime(2026, 5, 11, 9),
      levelOrder: 2,
      accent: _trBlue,
    ),
  ],

  // ─── Deutschland ────────────────────────────────────────────────────────
  'de': [
    OfficialExam(
      id: 'de_abitur_2026',
      name: 'Abitur',
      subtitle: 'Allgemeine Hochschulreife (start)',
      date: DateTime(2026, 4, 20, 9),
      levelOrder: 2,
      accent: _trBlue,
    ),
    OfficialExam(
      id: 'de_msa_2026',
      name: 'MSA',
      subtitle: 'Mittlerer Schulabschluss',
      date: DateTime(2026, 5, 18, 9),
      levelOrder: 1,
      accent: _trGreen,
    ),
  ],

  // ─── France ─────────────────────────────────────────────────────────────
  'fr': [
    OfficialExam(
      id: 'fr_brevet_2026',
      name: 'Brevet (DNB)',
      subtitle: 'Diplôme national du brevet',
      date: DateTime(2026, 6, 29, 9),
      levelOrder: 1,
      accent: _trGreen,
    ),
    OfficialExam(
      id: 'fr_bac_philo_2026',
      name: 'Baccalauréat — Philosophie',
      subtitle: 'Épreuve écrite de philosophie',
      date: DateTime(2026, 6, 15, 8),
      levelOrder: 2,
      accent: _trBlue,
    ),
    OfficialExam(
      id: 'fr_bac_grandoral_2026',
      name: 'Baccalauréat — Grand Oral',
      subtitle: 'Épreuves orales (début)',
      date: DateTime(2026, 6, 22, 8),
      levelOrder: 2,
      accent: _trIndigo,
    ),
  ],
};

/// Verilen ülke koduna ait, bugünden sonraki tüm sınavları döndürür.
/// Sıralama: önce `levelOrder` (küçükten büyüğe), sonra tarih.
List<OfficialExam> upcomingExamsForCountry(String countryCode) {
  final code = countryCode.toLowerCase();
  final list = _examsByCountry[code] ?? const <OfficialExam>[];
  final now = DateTime.now();
  final upcoming = list.where((e) => e.date.isAfter(now)).toList()
    ..sort((a, b) {
      final l = a.levelOrder.compareTo(b.levelOrder);
      if (l != 0) return l;
      return a.date.compareTo(b.date);
    });
  return upcoming;
}

/// Sınav listesi olan ülkelerin kodları — UI fallback için kontrol.
List<String> get supportedExamCountries => _examsByCountry.keys.toList();
