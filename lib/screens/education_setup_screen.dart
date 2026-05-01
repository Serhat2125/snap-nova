import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/education_profile.dart';
import '../services/country_resolver.dart';
import '../services/gemini_service.dart';
import '../main.dart' show localeService;

/// Ana sayfadan önce çıkan eğitim profili belirleme ekranı.
/// İlk 10 uygulama açılışında gösterilir (deneme), sonra atlanır.
///
/// Akış: Ülke → Eğitim Seviyesi → (Fakülte) → Sınıf → (Alan) → Kaydet
class EducationSetupScreen extends StatefulWidget {
  final int trialEntryNumber; // 0 = deneme değil, 1-10 = N. giriş
  final VoidCallback onSaved;
  const EducationSetupScreen({
    super.key,
    this.trialEntryNumber = 0,
    required this.onSaved,
  });

  @override
  State<EducationSetupScreen> createState() => _EducationSetupScreenState();
}

class _EducationSetupScreenState extends State<EducationSetupScreen> {
  static const _brand = Color(0xFFFF5B2E);
  // Tüm metinler tam siyah
  static const _ink = Colors.black;
  static const _inkSoft = Colors.black;
  static const _inkMute = Colors.black;
  // İnce siyah çerçeve
  static const _line = Colors.black;
  // Arka plan hafif gri (beyaz sekmeyle ton farkı için)
  static const _bg = Color(0xFFFAFAFA);
  // Sekmelerin içi tam beyaz
  static const _surface = Colors.white;
  static const _accent = Color(0xFF2D5BFF);

  String? _country;
  String? _level;
  String? _grade;
  String? _track;
  String? _faculty;

  @override
  void initState() {
    super.initState();
    _loadExisting();
    // Locale değişince (ülke seçiminden tetiklenir) setup ekranı da tazelensin.
    localeService.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    localeService.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadExisting() async {
    // Önceden kaydedilmiş değerleri ön-doldur (deneme turunda değişime izin verir)
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // Daha önce kullanıcı seçmiş mi?
    String? savedCountry = prefs.getString('mini_test_country');
    // Seçmemişse CountryResolver'dan en iyi tahmini al:
    //   1) IP geolocation > 2) cihaz locale.
    if (savedCountry == null) {
      final resolved = CountryResolver.instance.current ??
          localeService.detectedCountry;
      if (resolved != null && _isKnownCountryKey(resolved)) {
        savedCountry = resolved;
      }
    }
    setState(() {
      _country = savedCountry;
      final rawLevel = prefs.getString('mini_test_level');
      _level = rawLevel != null ? _levelUniversalFromLegacy(rawLevel) : null;
      _grade = prefs.getString('mini_test_grade');
      _track = prefs.getString('mini_test_track');
      _faculty = prefs.getString('mini_test_faculty');
    });
  }

  /// kAllCountries içinde tanımlı bir ülke kodu mu?
  bool _isKnownCountryKey(String key) {
    for (final c in kAllCountries) {
      if (c.key == key) return true;
    }
    return false;
  }

  String _levelUniversalFromLegacy(String raw) {
    switch (raw) {
      case 'ilkokul':
        return 'primary';
      case 'ortaokul':
        return 'middle';
      case 'lise':
        return 'high';
      case 'sinav_hazirlik':
        return 'exam_prep';
      case 'universite':
        return 'university';
      case 'yuksek_lisans':
        return 'masters';
      case 'doktora':
        return 'doctorate';
      case 'diger':
        return 'other';
      default:
        return raw;
    }
  }

  // ─────────────────── Level/Grade/Track verileri ─────────────────────────────
  // Ülkeye göre seviye etiketleri
  List<_LevelOpt> _levels() {
    switch (_country) {
      case 'tr':
        return const [
          _LevelOpt('primary', '📚', 'İlkokul'),
          _LevelOpt('middle', '🎒', 'Ortaokul'),
          // LGS Ortaokul'dan hemen sonra; seçilince exam_prep + grade=lgs
          // olarak işlenir (bkz. _pickLevel).
          _LevelOpt('lgs', '🏫', 'LGS (Liselere Geçiş Sınavı)'),
          _LevelOpt('high', '🎓', 'Lise'),
          _LevelOpt('exam_prep', '🎯', 'Sınava Hazırlık'),
          _LevelOpt('university', '🏛️', 'Üniversite'),
          _LevelOpt('masters', '📘', 'Yüksek Lisans'),
          _LevelOpt('doctorate', '🔬', 'Doktora'),
          _LevelOpt('other', '🧭', 'Diğer'),
        ];
      case 'us':
        return const [
          _LevelOpt('primary', '📚', 'Elementary School'),
          _LevelOpt('middle', '🎒', 'Middle School'),
          _LevelOpt('high', '🎓', 'High School'),
          _LevelOpt('exam_prep', '🎯', 'Test Prep'),
          _LevelOpt('university', '🏛️', 'College / University'),
          _LevelOpt('masters', '📘', "Master's Degree"),
          _LevelOpt('doctorate', '🔬', 'PhD / Doctorate'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'uk':
        return const [
          _LevelOpt('primary', '📚', 'Primary School'),
          _LevelOpt('middle', '🎒', 'Secondary (KS3)'),
          _LevelOpt('high', '🎓', 'GCSE / Sixth Form'),
          _LevelOpt('exam_prep', '🎯', 'Exam Prep'),
          _LevelOpt('university', '🏛️', 'University'),
          _LevelOpt('masters', '📘', "Master's"),
          _LevelOpt('doctorate', '🔬', 'PhD / DPhil'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'de':
        return const [
          _LevelOpt('primary', '📚', 'Grundschule'),
          _LevelOpt('middle', '🎒', 'Sekundarstufe I'),
          _LevelOpt('high', '🎓', 'Oberstufe (Gymnasium)'),
          _LevelOpt('exam_prep', '🎯', 'Prüfungsvorbereitung'),
          _LevelOpt('university', '🏛️', 'Universität'),
          _LevelOpt('masters', '📘', 'Master'),
          _LevelOpt('doctorate', '🔬', 'Promotion'),
          _LevelOpt('other', '🧭', 'Sonstige'),
        ];
      case 'fr':
        return const [
          _LevelOpt('primary', '📚', 'École primaire'),
          _LevelOpt('middle', '🎒', 'Collège'),
          _LevelOpt('high', '🎓', 'Lycée'),
          _LevelOpt('exam_prep', '🎯', 'Examens'),
          _LevelOpt('university', '🏛️', 'Université'),
          _LevelOpt('masters', '📘', 'Master'),
          _LevelOpt('doctorate', '🔬', 'Doctorat'),
          _LevelOpt('other', '🧭', 'Autre'),
        ];
      case 'jp':
        return const [
          _LevelOpt('primary', '📚', '小学校 Shōgakkō'),
          _LevelOpt('middle', '🎒', '中学校 Chūgakkō'),
          _LevelOpt('high', '🎓', '高校 Kōkō'),
          _LevelOpt('exam_prep', '🎯', '入試 Nyūshi'),
          _LevelOpt('university', '🏛️', '大学 Daigaku'),
          _LevelOpt('masters', '📘', '修士 Shūshi'),
          _LevelOpt('doctorate', '🔬', '博士 Hakase'),
          _LevelOpt('other', '🧭', 'その他'),
        ];
      case 'in':
        return const [
          _LevelOpt('primary', '📚', 'Primary / प्राथमिक'),
          _LevelOpt('middle', '🎒', 'Upper Primary / माध्यमिक'),
          _LevelOpt('high', '🎓', 'Secondary / Higher Secondary'),
          _LevelOpt('exam_prep', '🎯', 'Competitive Exams / प्रतियोगी'),
          _LevelOpt('university', '🏛️', 'University (UG) / विश्वविद्यालय'),
          _LevelOpt('masters', '📘', 'Masters (PG) / स्नातकोत्तर'),
          _LevelOpt('doctorate', '🔬', 'PhD / डॉक्टरेट'),
          _LevelOpt('other', '🧭', 'Other / अन्य'),
        ];
      // ═════ Büyük ülkeler — yerel terminoloji ═════
      case 'cn':
        return const [
          _LevelOpt('primary', '📚', '小学 Xiǎoxué'),
          _LevelOpt('middle', '🎒', '初中 Chūzhōng'),
          _LevelOpt('high', '🎓', '高中 Gāozhōng'),
          _LevelOpt('exam_prep', '🎯', '高考 Gāokǎo 备考'),
          _LevelOpt('university', '🏛️', '大学本科 Běnkē'),
          _LevelOpt('masters', '📘', '硕士 Shuòshì'),
          _LevelOpt('doctorate', '🔬', '博士 Bóshì'),
          _LevelOpt('other', '🧭', '其他'),
        ];
      case 'kr':
        return const [
          _LevelOpt('primary', '📚', '초등학교'),
          _LevelOpt('middle', '🎒', '중학교'),
          _LevelOpt('high', '🎓', '고등학교'),
          _LevelOpt('exam_prep', '🎯', '수능 준비'),
          _LevelOpt('university', '🏛️', '대학교 (학사)'),
          _LevelOpt('masters', '📘', '석사'),
          _LevelOpt('doctorate', '🔬', '박사'),
          _LevelOpt('other', '🧭', '기타'),
        ];
      case 'id':
        return const [
          _LevelOpt('primary', '📚', 'Sekolah Dasar (SD)'),
          _LevelOpt('middle', '🎒', 'SMP / MTs'),
          _LevelOpt('high', '🎓', 'SMA / SMK / MA'),
          _LevelOpt('exam_prep', '🎯', 'UTBK-SNBT / SNBP'),
          _LevelOpt('university', '🏛️', 'Sarjana (S1)'),
          _LevelOpt('masters', '📘', 'Magister (S2)'),
          _LevelOpt('doctorate', '🔬', 'Doktor (S3)'),
          _LevelOpt('other', '🧭', 'Lainnya'),
        ];
      case 'my':
        return const [
          _LevelOpt('primary', '📚', 'Sekolah Rendah'),
          _LevelOpt('middle', '🎒', 'Menengah Rendah (PT3)'),
          _LevelOpt('high', '🎓', 'Menengah Atas (SPM)'),
          _LevelOpt('exam_prep', '🎯', 'STPM / Matrikulasi'),
          _LevelOpt('university', '🏛️', 'Ijazah Sarjana Muda'),
          _LevelOpt('masters', '📘', 'Sarjana'),
          _LevelOpt('doctorate', '🔬', 'PhD / Doktor Falsafah'),
          _LevelOpt('other', '🧭', 'Lain-lain'),
        ];
      case 'ph':
        return const [
          _LevelOpt('primary', '📚', 'Elementary (K-6)'),
          _LevelOpt('middle', '🎒', 'Junior High (G7-10)'),
          _LevelOpt('high', '🎓', 'Senior High (G11-12)'),
          _LevelOpt('exam_prep', '🎯', 'College Entrance / UPCAT'),
          _LevelOpt('university', '🏛️', 'College / Bachelor'),
          _LevelOpt('masters', '📘', 'Master\'s'),
          _LevelOpt('doctorate', '🔬', 'Doctorate'),
          _LevelOpt('other', '🧭', 'Iba pa'),
        ];
      case 'th':
        return const [
          _LevelOpt('primary', '📚', 'ประถมศึกษา'),
          _LevelOpt('middle', '🎒', 'มัธยมต้น'),
          _LevelOpt('high', '🎓', 'มัธยมปลาย'),
          _LevelOpt('exam_prep', '🎯', 'TCAS / A-Level'),
          _LevelOpt('university', '🏛️', 'ปริญญาตรี'),
          _LevelOpt('masters', '📘', 'ปริญญาโท'),
          _LevelOpt('doctorate', '🔬', 'ปริญญาเอก'),
          _LevelOpt('other', '🧭', 'อื่นๆ'),
        ];
      case 'vn':
        return const [
          _LevelOpt('primary', '📚', 'Tiểu học'),
          _LevelOpt('middle', '🎒', 'Trung học cơ sở (THCS)'),
          _LevelOpt('high', '🎓', 'Trung học phổ thông (THPT)'),
          _LevelOpt('exam_prep', '🎯', 'Ôn thi THPT Quốc gia'),
          _LevelOpt('university', '🏛️', 'Đại học (Cử nhân)'),
          _LevelOpt('masters', '📘', 'Thạc sĩ'),
          _LevelOpt('doctorate', '🔬', 'Tiến sĩ'),
          _LevelOpt('other', '🧭', 'Khác'),
        ];
      case 'mm':
        return const [
          _LevelOpt('primary', '📚', 'မူလတန်း (Primary)'),
          _LevelOpt('middle', '🎒', 'အလယ်တန်း (Middle)'),
          _LevelOpt('high', '🎓', 'အထက်တန်း (High)'),
          _LevelOpt('exam_prep', '🎯', 'တက္ကသိုလ်ဝင်တန်း'),
          _LevelOpt('university', '🏛️', 'တက္ကသိုလ်'),
          _LevelOpt('masters', '📘', 'မဟာ'),
          _LevelOpt('doctorate', '🔬', 'ပါရဂူ'),
          _LevelOpt('other', '🧭', 'အခြား'),
        ];
      case 'ru':
        return const [
          _LevelOpt('primary', '📚', 'Начальная школа'),
          _LevelOpt('middle', '🎒', 'Основная школа'),
          _LevelOpt('high', '🎓', 'Старшая школа'),
          _LevelOpt('exam_prep', '🎯', 'ЕГЭ / ОГЭ подготовка'),
          _LevelOpt('university', '🏛️', 'Бакалавриат'),
          _LevelOpt('masters', '📘', 'Магистратура'),
          _LevelOpt('doctorate', '🔬', 'Аспирантура'),
          _LevelOpt('other', '🧭', 'Другое'),
        ];
      case 'ua':
        return const [
          _LevelOpt('primary', '📚', 'Початкова школа'),
          _LevelOpt('middle', '🎒', 'Базова середня'),
          _LevelOpt('high', '🎓', 'Старша школа'),
          _LevelOpt('exam_prep', '🎯', 'ЗНО / НМТ'),
          _LevelOpt('university', '🏛️', 'Бакалавр'),
          _LevelOpt('masters', '📘', 'Магістр'),
          _LevelOpt('doctorate', '🔬', 'Аспірантура'),
          _LevelOpt('other', '🧭', 'Інше'),
        ];
      case 'pl':
        return const [
          _LevelOpt('primary', '📚', 'Szkoła podstawowa'),
          _LevelOpt('middle', '🎒', 'Klasy 7-8'),
          _LevelOpt('high', '🎓', 'Liceum / Technikum'),
          _LevelOpt('exam_prep', '🎯', 'Matura'),
          _LevelOpt('university', '🏛️', 'Studia licencjackie'),
          _LevelOpt('masters', '📘', 'Studia magisterskie'),
          _LevelOpt('doctorate', '🔬', 'Doktorat'),
          _LevelOpt('other', '🧭', 'Inne'),
        ];
      case 'it':
        return const [
          _LevelOpt('primary', '📚', 'Scuola primaria'),
          _LevelOpt('middle', '🎒', 'Scuola media'),
          _LevelOpt('high', '🎓', 'Liceo / ITS'),
          _LevelOpt('exam_prep', '🎯', 'Maturità'),
          _LevelOpt('university', '🏛️', 'Laurea Triennale'),
          _LevelOpt('masters', '📘', 'Laurea Magistrale'),
          _LevelOpt('doctorate', '🔬', 'Dottorato'),
          _LevelOpt('other', '🧭', 'Altro'),
        ];
      // ═════ İspanyol Amerika ═════
      case 'mx':
      case 'co':
      case 'ar':
      case 'pe':
      case 've':
        return const [
          _LevelOpt('primary', '📚', 'Primaria'),
          _LevelOpt('middle', '🎒', 'Secundaria'),
          _LevelOpt('high', '🎓', 'Preparatoria / Bachillerato'),
          _LevelOpt('exam_prep', '🎯', 'Examen de admisión'),
          _LevelOpt('university', '🏛️', 'Universidad (Licenciatura)'),
          _LevelOpt('masters', '📘', 'Maestría'),
          _LevelOpt('doctorate', '🔬', 'Doctorado'),
          _LevelOpt('other', '🧭', 'Otro'),
        ];
      case 'es':
        return const [
          _LevelOpt('primary', '📚', 'Primaria'),
          _LevelOpt('middle', '🎒', 'ESO'),
          _LevelOpt('high', '🎓', 'Bachillerato'),
          _LevelOpt('exam_prep', '🎯', 'EvAU / EBAU (Selectividad)'),
          _LevelOpt('university', '🏛️', 'Grado Universitario'),
          _LevelOpt('masters', '📘', 'Máster'),
          _LevelOpt('doctorate', '🔬', 'Doctorado'),
          _LevelOpt('other', '🧭', 'Otro'),
        ];
      // ═════ Portekizce konuşulan ülkeler ═════
      case 'br':
        return const [
          _LevelOpt('primary', '📚', 'Ensino Fundamental I'),
          _LevelOpt('middle', '🎒', 'Ensino Fundamental II'),
          _LevelOpt('high', '🎓', 'Ensino Médio'),
          _LevelOpt('exam_prep', '🎯', 'ENEM / Vestibular'),
          _LevelOpt('university', '🏛️', 'Graduação'),
          _LevelOpt('masters', '📘', 'Mestrado'),
          _LevelOpt('doctorate', '🔬', 'Doutorado'),
          _LevelOpt('other', '🧭', 'Outro'),
        ];
      case 'ao':
      case 'mz':
        return const [
          _LevelOpt('primary', '📚', 'Ensino Primário'),
          _LevelOpt('middle', '🎒', 'Ensino Secundário'),
          _LevelOpt('high', '🎓', 'Ensino Médio'),
          _LevelOpt('exam_prep', '🎯', 'Exames de Acesso'),
          _LevelOpt('university', '🏛️', 'Licenciatura'),
          _LevelOpt('masters', '📘', 'Mestrado'),
          _LevelOpt('doctorate', '🔬', 'Doutoramento'),
          _LevelOpt('other', '🧭', 'Outro'),
        ];
      // ═════ Arap dünyası ═════
      case 'eg':
      case 'sa':
      case 'iq':
      case 'ye':
      case 'sd':
        return const [
          _LevelOpt('primary', '📚', 'الابتدائية'),
          _LevelOpt('middle', '🎒', 'الإعدادية / المتوسطة'),
          _LevelOpt('high', '🎓', 'الثانوية'),
          _LevelOpt('exam_prep', '🎯', 'اختبارات القبول'),
          _LevelOpt('university', '🏛️', 'بكالوريوس'),
          _LevelOpt('masters', '📘', 'ماجستير'),
          _LevelOpt('doctorate', '🔬', 'دكتوراه'),
          _LevelOpt('other', '🧭', 'أخرى'),
        ];
      case 'dz':
      case 'ma':
        return const [
          _LevelOpt('primary', '📚', 'Primaire / ابتدائي'),
          _LevelOpt('middle', '🎒', 'Collège / إعدادي'),
          _LevelOpt('high', '🎓', 'Lycée / ثانوي'),
          _LevelOpt('exam_prep', '🎯', 'Bac / الباكالوريا'),
          _LevelOpt('university', '🏛️', 'Licence / إجازة'),
          _LevelOpt('masters', '📘', 'Master / ماجستير'),
          _LevelOpt('doctorate', '🔬', 'Doctorat / دكتوراه'),
          _LevelOpt('other', '🧭', 'Autre / أخرى'),
        ];
      // ═════ Pakistan / Bangladesh / Nepal ═════
      case 'pk':
        return const [
          _LevelOpt('primary', '📚', 'Primary / پرائمری'),
          _LevelOpt('middle', '🎒', 'Middle / مڈل'),
          _LevelOpt('high', '🎓', 'Matric & FSc / میٹرک'),
          _LevelOpt('exam_prep', '🎯', 'Entry Tests / داخلہ'),
          _LevelOpt('university', '🏛️', 'Bachelors / بیچلرز'),
          _LevelOpt('masters', '📘', 'Masters / ماسٹرز'),
          _LevelOpt('doctorate', '🔬', 'PhD'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'bd':
        return const [
          _LevelOpt('primary', '📚', 'প্রাথমিক'),
          _LevelOpt('middle', '🎒', 'মাধ্যমিক (JSC)'),
          _LevelOpt('high', '🎓', 'SSC / HSC'),
          _LevelOpt('exam_prep', '🎯', 'ভর্তি পরীক্ষা'),
          _LevelOpt('university', '🏛️', 'অনার্স / স্নাতক'),
          _LevelOpt('masters', '📘', 'মাস্টার্স'),
          _LevelOpt('doctorate', '🔬', 'পিএইচডি'),
          _LevelOpt('other', '🧭', 'অন্যান্য'),
        ];
      case 'np':
        return const [
          _LevelOpt('primary', '📚', 'प्राथमिक (१-५)'),
          _LevelOpt('middle', '🎒', 'निम्न माध्यमिक (६-८)'),
          _LevelOpt('high', '🎓', 'SEE / +2'),
          _LevelOpt('exam_prep', '🎯', 'प्रवेश परीक्षा'),
          _LevelOpt('university', '🏛️', 'स्नातक'),
          _LevelOpt('masters', '📘', 'स्नातकोत्तर'),
          _LevelOpt('doctorate', '🔬', 'पीएचडी'),
          _LevelOpt('other', '🧭', 'अन्य'),
        ];
      // ═════ İran ═════
      case 'ir':
        return const [
          _LevelOpt('primary', '📚', 'ابتدایی'),
          _LevelOpt('middle', '🎒', 'متوسطه اول'),
          _LevelOpt('high', '🎓', 'متوسطه دوم'),
          _LevelOpt('exam_prep', '🎯', 'کنکور'),
          _LevelOpt('university', '🏛️', 'کارشناسی'),
          _LevelOpt('masters', '📘', 'کارشناسی ارشد'),
          _LevelOpt('doctorate', '🔬', 'دکترا'),
          _LevelOpt('other', '🧭', 'سایر'),
        ];
      // ═════ Anglofon Afrika ═════
      case 'ng':
      case 'gh':
      case 'ke':
      case 'ug':
      case 'tz':
      case 'za':
      case 'et':
        return const [
          _LevelOpt('primary', '📚', 'Primary School'),
          _LevelOpt('middle', '🎒', 'Junior Secondary'),
          _LevelOpt('high', '🎓', 'Senior Secondary'),
          _LevelOpt('exam_prep', '🎯', 'National Exams'),
          _LevelOpt('university', '🏛️', 'University (Bachelor)'),
          _LevelOpt('masters', '📘', 'Master\'s'),
          _LevelOpt('doctorate', '🔬', 'PhD'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'ca':
        return const [
          _LevelOpt('primary', '📚', 'Elementary / École primaire'),
          _LevelOpt('middle', '🎒', 'Middle School'),
          _LevelOpt('high', '🎓', 'High School / CEGEP (QC)'),
          _LevelOpt('exam_prep', '🎯', 'Admissions / SAT'),
          _LevelOpt('university', '🏛️', 'University (Bachelor)'),
          _LevelOpt('masters', '📘', 'Master\'s / Maîtrise'),
          _LevelOpt('doctorate', '🔬', 'PhD / Doctorat'),
          _LevelOpt('other', '🧭', 'Other / Autre'),
        ];
      // ═════ Özbekistan ═════
      case 'uz':
        return const [
          _LevelOpt('primary', '📚', 'Boshlangʻich sinflar'),
          _LevelOpt('middle', '🎒', 'Oʻrta sinflar'),
          _LevelOpt('high', '🎓', 'Akademik litsey / Kollej'),
          _LevelOpt('exam_prep', '🎯', 'DTM / Kirish imtihoni'),
          _LevelOpt('university', '🏛️', 'Bakalavr'),
          _LevelOpt('masters', '📘', 'Magistr'),
          _LevelOpt('doctorate', '🔬', 'PhD'),
          _LevelOpt('other', '🧭', 'Boshqa'),
        ];
      // ═════ DR Kongo, Madagaskar (Frankofon) ═════
      case 'cd':
      case 'mg':
        return const [
          _LevelOpt('primary', '📚', 'École primaire'),
          _LevelOpt('middle', '🎒', 'Collège'),
          _LevelOpt('high', '🎓', 'Lycée'),
          _LevelOpt('exam_prep', '🎯', 'Baccalauréat'),
          _LevelOpt('university', '🏛️', 'Licence'),
          _LevelOpt('masters', '📘', 'Master'),
          _LevelOpt('doctorate', '🔬', 'Doctorat'),
          _LevelOpt('other', '🧭', 'Autre'),
        ];
      default:
        // Ülkeye özel branş yoksa: 8 evrensel seviye (uluslararası standart
        // İngilizce etiket). Her ülkede çalışır; lokal terminoloji yok ama
        // kavramsal seviye doğru.
        return const [
          _LevelOpt('primary', '📚', 'Primary School'),
          _LevelOpt('middle', '🎒', 'Middle / Lower Secondary'),
          _LevelOpt('high', '🎓', 'High / Upper Secondary'),
          _LevelOpt('exam_prep', '🎯', 'Exam Preparation'),
          _LevelOpt('university', '🏛️', 'University (Bachelor)'),
          _LevelOpt('masters', '📘', "Master's Degree"),
          _LevelOpt('doctorate', '🔬', 'Doctorate / PhD'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
    }
  }

  /// Country-aware sınıf etiketi: sayı verilince ülkenin terminolojisine
  /// uygun "9. Sınıf" / "Grade 9" / "Year 9" / "Klasse 9" / "9年生" döner.
  /// `_country` state'i okur. _gradesForLevel içinde kullanılır.
  String _localizedGradeLabel(int n) {
    switch (_country) {
      case 'us':
      case 'ca':
      case 'au':
      case 'ph':
      case 'ng':
      case 'ke':
      case 'gh':
      case 'za':
      case 'in':
        return 'Grade $n';
      case 'uk':
      case 'ie':
        return 'Year $n';
      case 'de':
      case 'at':
        return 'Klasse $n';
      case 'fr':
      case 'be':
      case 'lu':
      case 'mc':
      case 'ch':
      case 'ma':
      case 'dz':
      case 'tn':
        return 'Classe $n';
      case 'es':
      case 'mx':
      case 'ar':
      case 'co':
      case 'pe':
      case 've':
      case 'cl':
      case 'cr':
      case 'gt':
      case 'do':
      case 'ec':
      case 'bo':
      case 'sv':
      case 'hn':
      case 'pa':
      case 'py':
      case 'uy':
        return 'Grado $n';
      case 'br':
      case 'pt':
      case 'ao':
      case 'mz':
        return 'Ano $n';
      case 'it':
        return 'Classe $n';
      case 'jp':
        return '$n年生';
      case 'cn':
      case 'tw':
      case 'hk':
        return '$n年级';
      case 'kr':
        return '$n학년';
      case 'ru':
      case 'by':
      case 'kz':
        return '$n класс';
      case 'ua':
        return '$n клас';
      case 'pl':
        return 'Klasa $n';
      case 'nl':
        return 'Groep $n';
      case 'th':
        return 'ชั้น $n';
      case 'vn':
        return 'Lớp $n';
      case 'id':
      case 'my':
        return 'Kelas $n';
      case 'eg':
      case 'sa':
      case 'iq':
      case 'jo':
      case 'ae':
      case 'kw':
      case 'qa':
      case 'lb':
      case 'sy':
      case 'ye':
      case 'ly':
        return 'الصف $n';
      case 'ir':
        return 'پایه $n';
      case 'pk':
        return 'Class $n';
      case 'bd':
        return 'শ্রেণি $n';
      case 'gr':
      case 'cy':
        return 'Τάξη $n';
      case 'tr':
      default:
        return '$n. Sınıf';
    }
  }

  List<_LevelOpt> _gradesForLevel() {
    // Country-aware sınıf etiketi yardımcısı.
    // Sayı (key) sabit (curriculum lookup için) — sadece UI etiketi yerelleşir.
    String label(int n) => _localizedGradeLabel(n);
    String hazirlikLabel() => switch (_country) {
          'us' => 'Foundation Year',
          'uk' => 'Foundation Year',
          'de' => 'Vorbereitungskurs',
          'fr' => 'Année préparatoire',
          'jp' => '予備',
          'kr' => '예비 과정',
          'cn' => '预科',
          _ => 'Hazırlık',
        };
    String mezunLabel() => switch (_country) {
          'us' || 'uk' || 'au' || 'ca' => 'Graduate',
          'de' => 'Absolvent',
          'fr' => 'Diplômé',
          'jp' => '卒業',
          'kr' => '졸업',
          'cn' => '毕业',
          _ => 'Mezun',
        };

    switch (_level) {
      case 'primary':
        return [
          _LevelOpt('1', '1️⃣', label(1)),
          _LevelOpt('2', '2️⃣', label(2)),
          _LevelOpt('3', '3️⃣', label(3)),
          _LevelOpt('4', '4️⃣', label(4)),
          _LevelOpt('5', '5️⃣', label(5)),
        ];
      case 'middle':
        return [
          _LevelOpt('5', '5️⃣', label(5)),
          _LevelOpt('6', '6️⃣', label(6)),
          _LevelOpt('7', '7️⃣', label(7)),
          _LevelOpt('8', '8️⃣', label(8)),
        ];
      case 'high':
        return [
          _LevelOpt('9', '9️⃣', label(9)),
          _LevelOpt('10', '🔟', label(10)),
          _LevelOpt('11', '1️⃣1️⃣', label(11)),
          _LevelOpt('12', '1️⃣2️⃣', label(12)),
        ];
      case 'exam_prep':
        return _examsForCountry();
      case 'university':
        return [
          _LevelOpt('hazirlik', '🔤', hazirlikLabel()),
          _LevelOpt('1', '1️⃣', label(1)),
          _LevelOpt('2', '2️⃣', label(2)),
          _LevelOpt('3', '3️⃣', label(3)),
          _LevelOpt('4', '4️⃣', label(4)),
          _LevelOpt('5', '5️⃣', label(5)),
          _LevelOpt('6', '6️⃣', label(6)),
          _LevelOpt('mezun', '🎓', mezunLabel()),
        ];
      case 'masters':
        return const [
          _LevelOpt('1donem', '1️⃣', '1. Dönem'),
          _LevelOpt('2donem', '2️⃣', '2. Dönem'),
          _LevelOpt('3donem', '3️⃣', '3. Dönem'),
          _LevelOpt('4donem', '4️⃣', '4. Dönem'),
          _LevelOpt('tez', '📝', 'Tez Aşaması'),
          _LevelOpt('mezun', '🎓', 'Mezun'),
        ];
      case 'doctorate':
        return const [
          _LevelOpt('ders', '📚', 'Ders Dönemi'),
          _LevelOpt('yeterlilik', '📋', 'Yeterlilik'),
          _LevelOpt('tez_oneri', '🧾', 'Tez Önerisi'),
          _LevelOpt('tez', '📝', 'Tez Aşaması'),
          _LevelOpt('mezun', '🎓', 'Mezun'),
        ];
      case 'other':
        return const [
          _LevelOpt('calisan', '💼', 'Çalışıyorum'),
          _LevelOpt('mezun', '🎓', 'Mezun'),
          _LevelOpt('serbest', '📖', 'Kişisel Gelişim'),
        ];
      default:
        return const [];
    }
  }

  /// Ülkeye göre filtrelenmiş sınav listesi — sadece seçilen ülkenin sınavları.
  List<_LevelOpt> _examsForCountry() {
    switch (_country) {
      case 'tr':
        // LGS bu listeden çıkarıldı — artık ana eğitim seviyesi listesinde
        // (Ortaokul'dan hemen sonra) "LGS (Liselere Geçiş Sınavı)" olarak yer alıyor.
        return const [
          _LevelOpt('yks_tyt', '🎯', 'YKS · TYT'),
          _LevelOpt('yks_ayt', '🎯', 'YKS · AYT'),
          _LevelOpt('msu', '🛡️', 'MSÜ (Milli Savunma Üniv. Sınavı)'),
          _LevelOpt('kpss', '🏛️', 'KPSS Lisans'),
          _LevelOpt('kpss_ortaogretim', '🏛️', 'KPSS Ortaöğretim'),
          _LevelOpt('dgs', '↗️', 'DGS (Dikey Geçiş Sınavı)'),
          _LevelOpt('pmyo', '👮', 'PMYO (Polis Meslek Yüksekokulu)'),
          _LevelOpt('ales', '📋', 'ALES'),
          _LevelOpt('yds', '🗣️', 'YDS / YÖKDİL'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('diger', '🧭', 'Diğer Sınav'),
        ];
      case 'us':
        return const [
          _LevelOpt('sat', '📝', 'SAT'),
          _LevelOpt('act', '📝', 'ACT'),
          _LevelOpt('ap', '🎓', 'AP Exams'),
          _LevelOpt('psat', '📝', 'PSAT'),
          _LevelOpt('gre', '🎓', 'GRE'),
          _LevelOpt('gmat', '💼', 'GMAT'),
          _LevelOpt('lsat', '⚖️', 'LSAT'),
          _LevelOpt('mcat', '🩺', 'MCAT'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'uk':
        return const [
          _LevelOpt('gcse', '📝', 'GCSE'),
          _LevelOpt('alevel', '🎓', 'A-Level'),
          _LevelOpt('ucat', '🩺', 'UCAT'),
          _LevelOpt('bmat', '🩺', 'BMAT'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'de':
        return const [
          _LevelOpt('abitur', '🎓', 'Abitur'),
          _LevelOpt('mittlere', '📝', 'Mittlere Reife'),
          _LevelOpt('testdaf', '🗣️', 'TestDaF'),
          _LevelOpt('dsh', '🗣️', 'DSH'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Sonstige'),
        ];
      case 'fr':
        return const [
          _LevelOpt('bac', '🎓', 'Baccalauréat'),
          _LevelOpt('brevet', '📝', 'Brevet'),
          _LevelOpt('delf', '🗣️', 'DELF / DALF'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Autre'),
        ];
      case 'jp':
        return const [
          _LevelOpt('kyotsu', '🎓', '共通テスト'),
          _LevelOpt('nyushi', '🎯', '個別入試'),
          _LevelOpt('jlpt', '🗣️', 'JLPT'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'その他'),
        ];
      case 'in':
        return const [
          _LevelOpt('jee_main', '⚙️', 'JEE Main'),
          _LevelOpt('jee_adv', '⚙️', 'JEE Advanced'),
          _LevelOpt('neet', '🩺', 'NEET'),
          _LevelOpt('cat', '💼', 'CAT'),
          _LevelOpt('gate', '🔧', 'GATE'),
          _LevelOpt('upsc', '🏛️', 'UPSC'),
          _LevelOpt('cuet', '🎓', 'CUET'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'cn':
        return const [
          _LevelOpt('gaokao', '🎯', '高考 Gāokǎo'),
          _LevelOpt('zhongkao', '📝', '中考 Zhōngkǎo'),
          _LevelOpt('gre', '🎓', 'GRE'),
          _LevelOpt('gmat', '💼', 'GMAT'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('hsk', '🗣️', 'HSK'),
          _LevelOpt('other', '🧭', '其他'),
        ];
      case 'kr':
        return const [
          _LevelOpt('suneung', '🎯', '수능 (CSAT)'),
          _LevelOpt('naesin', '📝', '내신'),
          _LevelOpt('toeic', '🗣️', 'TOEIC'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('topik', '🗣️', 'TOPIK'),
          _LevelOpt('other', '🧭', '기타'),
        ];
      case 'id':
        return const [
          _LevelOpt('utbk', '🎯', 'UTBK-SNBT'),
          _LevelOpt('snbp', '📝', 'SNBP'),
          _LevelOpt('un', '📋', 'UN / UTBK'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Lainnya'),
        ];
      case 'my':
        return const [
          _LevelOpt('spm', '🎓', 'SPM'),
          _LevelOpt('stpm', '📝', 'STPM'),
          _LevelOpt('pt3', '📋', 'PT3'),
          _LevelOpt('muet', '🗣️', 'MUET'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Lain-lain'),
        ];
      case 'ph':
        return const [
          _LevelOpt('upcat', '🎓', 'UPCAT'),
          _LevelOpt('acet', '📝', 'ACET'),
          _LevelOpt('dlsucet', '📝', 'DLSUCET'),
          _LevelOpt('ustet', '📝', 'USTET'),
          _LevelOpt('nmat', '💼', 'NMAT'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Iba pa'),
        ];
      case 'th':
        return const [
          _LevelOpt('tcas', '🎯', 'TCAS'),
          _LevelOpt('a_level', '📝', 'A-Level'),
          _LevelOpt('tu_star', '📝', 'TU-STAR'),
          _LevelOpt('bmat', '🩺', 'BMAT'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'อื่นๆ'),
        ];
      case 'vn':
        return const [
          _LevelOpt('thpt', '🎯', 'THPT Quốc gia'),
          _LevelOpt('dgnl', '📝', 'ĐGNL (VNU)'),
          _LevelOpt('dgtd', '⚙️', 'ĐGTD (HUST)'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('sat', '📝', 'SAT'),
          _LevelOpt('other', '🧭', 'Khác'),
        ];
      case 'mm':
        return const [
          _LevelOpt('matric', '🎓', 'Matriculation'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'အခြား'),
        ];
      case 'ru':
        return const [
          _LevelOpt('ege', '🎯', 'ЕГЭ'),
          _LevelOpt('oge', '📝', 'ОГЭ'),
          _LevelOpt('vpr', '📋', 'ВПР'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('trki', '🗣️', 'ТРКИ'),
          _LevelOpt('other', '🧭', 'Другое'),
        ];
      case 'ua':
        return const [
          _LevelOpt('zno', '🎯', 'ЗНО / НМТ'),
          _LevelOpt('dpa', '📋', 'ДПА'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Інше'),
        ];
      case 'pl':
        return const [
          _LevelOpt('matura', '🎯', 'Matura'),
          _LevelOpt('egzamin8', '📋', 'Egzamin ósmoklasisty'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('cambridge', '🗣️', 'Cambridge FCE/CAE'),
          _LevelOpt('other', '🧭', 'Inne'),
        ];
      case 'it':
        return const [
          _LevelOpt('maturita', '🎯', 'Esame di Stato (Maturità)'),
          _LevelOpt('test_medicina', '🩺', 'Test Medicina'),
          _LevelOpt('tolc', '⚙️', 'TOLC'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('cils', '🗣️', 'CILS / CELI'),
          _LevelOpt('other', '🧭', 'Altro'),
        ];
      case 'mx':
        return const [
          _LevelOpt('comipems', '🎯', 'COMIPEMS'),
          _LevelOpt('unam', '🎓', 'Examen UNAM'),
          _LevelOpt('ipn', '🎓', 'Examen IPN'),
          _LevelOpt('ceneval', '📝', 'CENEVAL EXANI-II'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Otro'),
        ];
      case 'co':
        return const [
          _LevelOpt('icfes', '🎯', 'ICFES Saber 11°'),
          _LevelOpt('saber_pro', '🎓', 'Saber Pro'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Otro'),
        ];
      case 'ar':
        return const [
          _LevelOpt('cbc', '🎯', 'CBC / Ingreso Universitario'),
          _LevelOpt('aptitud', '📝', 'Prueba de Aptitud'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Otro'),
        ];
      case 'pe':
        return const [
          _LevelOpt('admision', '🎯', 'Examen de Admisión'),
          _LevelOpt('unmsm', '🎓', 'UNMSM'),
          _LevelOpt('pucp', '🎓', 'PUCP'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Otro'),
        ];
      case 've':
        return const [
          _LevelOpt('opsu', '🎯', 'OPSU'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Otro'),
        ];
      case 'es':
        return const [
          _LevelOpt('evau', '🎯', 'EvAU / EBAU'),
          _LevelOpt('selectividad', '📝', 'Selectividad'),
          _LevelOpt('dele', '🗣️', 'DELE'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Otro'),
        ];
      case 'br':
        return const [
          _LevelOpt('enem', '🎯', 'ENEM'),
          _LevelOpt('fuvest', '🎓', 'FUVEST'),
          _LevelOpt('unicamp', '🎓', 'UNICAMP'),
          _LevelOpt('vestibular', '📝', 'Vestibular'),
          _LevelOpt('oab', '⚖️', 'OAB'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('celpe', '🗣️', 'Celpe-Bras'),
          _LevelOpt('other', '🧭', 'Outro'),
        ];
      case 'ao':
      case 'mz':
      case 'pt':
        return const [
          _LevelOpt('exame_nacional', '🎯', 'Exame Nacional'),
          _LevelOpt('acesso_uni', '📝', 'Exame de Acesso'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('celpe', '🗣️', 'Celpe-Bras / CAPLE'),
          _LevelOpt('other', '🧭', 'Outro'),
        ];
      case 'eg':
        return const [
          _LevelOpt('thanaweya', '🎯', 'الثانوية العامة'),
          _LevelOpt('azhar', '🕌', 'الثانوية الأزهرية'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'أخرى'),
        ];
      case 'sa':
        return const [
          _LevelOpt('qiyas', '🎯', 'قياس (القدرات)'),
          _LevelOpt('tahseli', '📝', 'التحصيلي'),
          _LevelOpt('step', '🗣️', 'STEP'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'أخرى'),
        ];
      case 'iq':
      case 'ye':
      case 'sd':
        return const [
          _LevelOpt('baccalaureate', '🎯', 'البكالوريا'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'أخرى'),
        ];
      case 'dz':
        return const [
          _LevelOpt('bac', '🎯', 'Baccalauréat / البكالوريا'),
          _LevelOpt('bem', '📝', 'BEM (Brevet)'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Autre / أخرى'),
        ];
      case 'ma':
        return const [
          _LevelOpt('bac', '🎯', 'Baccalauréat / الباكالوريا'),
          _LevelOpt('concours', '📝', 'Concours Grandes Écoles'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('delf', '🗣️', 'DELF / DALF'),
          _LevelOpt('other', '🧭', 'Autre'),
        ];
      case 'pk':
        return const [
          _LevelOpt('matric', '🎓', 'Matric'),
          _LevelOpt('fsc', '📝', 'FSc / FA'),
          _LevelOpt('mdcat', '🩺', 'MDCAT'),
          _LevelOpt('ecat', '⚙️', 'ECAT'),
          _LevelOpt('nts', '📋', 'NTS / NAT'),
          _LevelOpt('css', '🏛️', 'CSS'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'bd':
        return const [
          _LevelOpt('ssc', '🎓', 'SSC'),
          _LevelOpt('hsc', '🎓', 'HSC'),
          _LevelOpt('admission', '📝', 'Admission (DU / BUET)'),
          _LevelOpt('bcs', '🏛️', 'BCS'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'অন্যান্য'),
        ];
      case 'np':
        return const [
          _LevelOpt('see', '🎓', 'SEE'),
          _LevelOpt('plus2', '📝', '+2 Board'),
          _LevelOpt('entrance', '📋', 'University Entrance'),
          _LevelOpt('loksewa', '🏛️', 'Lok Sewa'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'अन्य'),
        ];
      case 'ir':
        return const [
          _LevelOpt('konkoor', '🎯', 'کنکور سراسری'),
          _LevelOpt('nezam_mohandesi', '⚙️', 'نظام مهندسی'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'سایر'),
        ];
      case 'ng':
        return const [
          _LevelOpt('waec', '🎯', 'WAEC / WASSCE'),
          _LevelOpt('neco', '📝', 'NECO'),
          _LevelOpt('jamb', '🎓', 'JAMB UTME'),
          _LevelOpt('postutme', '📋', 'Post-UTME'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'gh':
        return const [
          _LevelOpt('wassce', '🎯', 'WASSCE'),
          _LevelOpt('bece', '📝', 'BECE'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'ke':
        return const [
          _LevelOpt('kcse', '🎯', 'KCSE'),
          _LevelOpt('kcpe', '📝', 'KCPE'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Nyingine'),
        ];
      case 'ug':
        return const [
          _LevelOpt('uace', '🎯', 'UACE (A-Level)'),
          _LevelOpt('uce', '📝', 'UCE (O-Level)'),
          _LevelOpt('ple', '📋', 'PLE'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'tz':
        return const [
          _LevelOpt('acsee', '🎯', 'ACSEE (Form 6)'),
          _LevelOpt('csee', '📝', 'CSEE (Form 4)'),
          _LevelOpt('psle', '📋', 'PSLE'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Nyingine'),
        ];
      case 'za':
        return const [
          _LevelOpt('nsc', '🎯', 'NSC / Matric'),
          _LevelOpt('ieb', '📝', 'IEB'),
          _LevelOpt('nbt', '📋', 'NBT'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
      case 'et':
        return const [
          _LevelOpt('euee', '🎯', 'EUEE'),
          _LevelOpt('eslce', '📝', 'ESLCE'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'ሌላ'),
        ];
      case 'ca':
        return const [
          _LevelOpt('sat', '📝', 'SAT'),
          _LevelOpt('act', '📝', 'ACT'),
          _LevelOpt('gre', '🎓', 'GRE'),
          _LevelOpt('gmat', '💼', 'GMAT'),
          _LevelOpt('mcat', '🩺', 'MCAT'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('celpip', '🗣️', 'CELPIP'),
          _LevelOpt('tef', '🗣️', 'TEF / TCF'),
          _LevelOpt('other', '🧭', 'Other / Autre'),
        ];
      case 'uz':
        return const [
          _LevelOpt('dtm', '🎯', 'DTM'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('other', '🧭', 'Boshqa'),
        ];
      case 'cd':
      case 'mg':
        return const [
          _LevelOpt('bac', '🎯', 'Baccalauréat'),
          _LevelOpt('bepc', '📝', 'BEPC'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('delf', '🗣️', 'DELF / DALF'),
          _LevelOpt('other', '🧭', 'Autre'),
        ];
      default:
        // Universal exam set — ülkeye özel sınav listesi yoksa devreye girer.
        // Uluslararası dil + akademik standart sınavlar; "national_exam"
        // jeneriği ülkenin yerel sınavını AI'ya prompt'lamak için kullanılır.
        return const [
          _LevelOpt('national_exam', '🎯', 'National School-Leaving Exam'),
          _LevelOpt('university_entrance', '🎓', 'University Entrance Exam'),
          _LevelOpt('sat', '📝', 'SAT'),
          _LevelOpt('act', '📝', 'ACT'),
          _LevelOpt('ib', '🌐', 'IB Diploma'),
          _LevelOpt('alevel', '🎓', 'A-Level / Cambridge'),
          _LevelOpt('ielts', '🗣️', 'IELTS'),
          _LevelOpt('toefl', '🗣️', 'TOEFL'),
          _LevelOpt('duolingo', '🗣️', 'Duolingo English Test'),
          _LevelOpt('gre', '🎓', 'GRE'),
          _LevelOpt('gmat', '💼', 'GMAT'),
          _LevelOpt('other', '🧭', 'Other'),
        ];
    }
  }

  List<_LevelOpt> _tracksForLevel() {
    if (_level != 'high') return const [];
    // Ülkeye göre alan seçenekleri
    switch (_country) {
      case 'tr':
        return const [
          _LevelOpt('sayisal', '🔬', 'Sayısal'),
          _LevelOpt('sozel', '📖', 'Sözel'),
          _LevelOpt('esit_agirlik', '⚖️', 'Eşit Ağırlık'),
          _LevelOpt('dil', '🗣️', 'Dil'),
        ];
      case 'us':
        return const [
          _LevelOpt('regular', '📘', 'Regular'),
          _LevelOpt('honors', '🏅', 'Honors'),
          _LevelOpt('ap', '🎓', 'AP'),
          _LevelOpt('ib', '🌐', 'IB'),
        ];
      case 'uk':
        return const [
          _LevelOpt('sciences', '🔬', 'Sciences'),
          _LevelOpt('humanities', '📚', 'Humanities'),
          _LevelOpt('languages', '🗣️', 'Languages'),
          _LevelOpt('maths', '📐', 'Maths'),
        ];
      case 'de':
        return const [
          _LevelOpt('naturwiss', '🔬', 'Naturwissenschaften'),
          _LevelOpt('sprachen', '🗣️', 'Sprachen'),
          _LevelOpt('gesell', '👥', 'Gesellschaftswiss.'),
          _LevelOpt('kunst', '🎨', 'Kunst / Musik'),
        ];
      case 'fr':
        return const [
          _LevelOpt('general', '📚', 'Bac Général'),
          _LevelOpt('tech', '⚙️', 'Bac Technologique'),
          _LevelOpt('pro', '🔧', 'Bac Professionnel'),
        ];
      case 'jp':
        return const [
          _LevelOpt('futsu', '📚', '普通科'),
          _LevelOpt('senmon', '⚙️', '専門学科'),
        ];
      case 'in':
        return const [
          _LevelOpt('science', '🔬', 'Science'),
          _LevelOpt('commerce', '💰', 'Commerce'),
          _LevelOpt('arts', '📖', 'Arts / Humanities'),
        ];
      case 'cn':
        return const [
          _LevelOpt('lixue', '🔬', '理科 (Fen)'),
          _LevelOpt('wenxue', '📖', '文科 (Ven)'),
          _LevelOpt('zonghe', '⚖️', '综合 (Yeni Gaokao)'),
        ];
      case 'kr':
        return const [
          _LevelOpt('insa', '📖', '인문계 (İnsan Bilimleri)'),
          _LevelOpt('jayeon', '🔬', '자연계 (Fen)'),
          _LevelOpt('yesul', '🎨', '예체능 (Sanat/Spor)'),
        ];
      case 'id':
        return const [
          _LevelOpt('ipa', '🔬', 'IPA (Sayısal)'),
          _LevelOpt('ips', '📖', 'IPS (Sosyal)'),
          _LevelOpt('bahasa', '🗣️', 'Bahasa'),
          _LevelOpt('smk', '🔧', 'SMK (Vokasi)'),
        ];
      case 'my':
        return const [
          _LevelOpt('sains', '🔬', 'Aliran Sains'),
          _LevelOpt('sastera', '📖', 'Aliran Sastera'),
          _LevelOpt('perdagangan', '💰', 'Aliran Perdagangan'),
          _LevelOpt('teknikal', '🔧', 'Aliran Teknikal'),
        ];
      case 'ph':
        return const [
          _LevelOpt('stem', '🔬', 'STEM'),
          _LevelOpt('abm', '💰', 'ABM (Business)'),
          _LevelOpt('humss', '📖', 'HUMSS'),
          _LevelOpt('gas', '📚', 'GAS'),
          _LevelOpt('arts', '🎨', 'Arts & Design'),
          _LevelOpt('sports', '⚽', 'Sports Track'),
          _LevelOpt('tvl', '🔧', 'TVL'),
        ];
      case 'th':
        return const [
          _LevelOpt('wit_khanit', '🔬', 'วิทย์-คณิต'),
          _LevelOpt('silp_kham', '📖', 'ศิลป์-คำนวณ'),
          _LevelOpt('silp_phasa', '🗣️', 'ศิลป์-ภาษา'),
          _LevelOpt('silp_thurakit', '💰', 'ศิลป์-ธุรกิจ'),
        ];
      case 'vn':
        return const [
          _LevelOpt('tu_nhien', '🔬', 'Khoa học Tự nhiên'),
          _LevelOpt('xa_hoi', '📖', 'Khoa học Xã hội'),
          _LevelOpt('ngoai_ngu', '🗣️', 'Ngoại ngữ'),
        ];
      case 'mm':
        return const [
          _LevelOpt('science', '🔬', 'Science (သိပ္ပံ)'),
          _LevelOpt('arts', '📖', 'Arts (ဝိဇ္ဇာ)'),
        ];
      case 'ru':
        return const [
          _LevelOpt('estestvennyi', '🔬', 'Естественно-научный'),
          _LevelOpt('gumanitarnyi', '📖', 'Гуманитарный'),
          _LevelOpt('sociokonomicheskiy', '💰', 'Социально-экономический'),
          _LevelOpt('tekhnologicheskiy', '🔧', 'Технологический'),
        ];
      case 'ua':
        return const [
          _LevelOpt('pryrodnychyi', '🔬', 'Природничий'),
          _LevelOpt('humanitarnyi', '📖', 'Гуманітарний'),
          _LevelOpt('suspilnyi', '👥', 'Суспільно-гуманітарний'),
        ];
      case 'pl':
        return const [
          _LevelOpt('mat_fiz', '🔬', 'Mat-Fiz'),
          _LevelOpt('biol_chem', '🧬', 'Bio-Chem'),
          _LevelOpt('human', '📖', 'Humanistyczny'),
          _LevelOpt('jezyk', '🗣️', 'Językowy'),
          _LevelOpt('ekonom', '💰', 'Ekonomiczny'),
        ];
      case 'it':
        return const [
          _LevelOpt('scientifico', '🔬', 'Liceo Scientifico'),
          _LevelOpt('classico', '📖', 'Liceo Classico'),
          _LevelOpt('linguistico', '🗣️', 'Liceo Linguistico'),
          _LevelOpt('scienze_umane', '👥', 'Scienze Umane'),
          _LevelOpt('artistico', '🎨', 'Liceo Artistico'),
          _LevelOpt('tecnico', '⚙️', 'Istituto Tecnico'),
          _LevelOpt('professionale', '🔧', 'Istituto Professionale'),
        ];
      case 'mx':
      case 'co':
      case 'ar':
      case 'pe':
      case 've':
      case 'es':
        return const [
          _LevelOpt('ciencias', '🔬', 'Ciencias'),
          _LevelOpt('humanidades', '📖', 'Humanidades'),
          _LevelOpt('sociales', '👥', 'Ciencias Sociales'),
          _LevelOpt('artes', '🎨', 'Artes'),
          _LevelOpt('tecnico', '🔧', 'Técnico'),
        ];
      case 'br':
      case 'ao':
      case 'mz':
      case 'pt':
        return const [
          _LevelOpt('ciencias_natureza', '🔬', 'Ciências da Natureza'),
          _LevelOpt('humanas', '📖', 'Ciências Humanas'),
          _LevelOpt('linguagens', '🗣️', 'Linguagens'),
          _LevelOpt('matematica', '📐', 'Matemática'),
          _LevelOpt('tecnico', '🔧', 'Técnico'),
        ];
      case 'eg':
      case 'sa':
      case 'iq':
      case 'ye':
      case 'sd':
        return const [
          _LevelOpt('ilmi', '🔬', 'علمي'),
          _LevelOpt('adabi', '📖', 'أدبي'),
          _LevelOpt('riyadiat', '📐', 'رياضيات'),
          _LevelOpt('tijariya', '💰', 'تجاري'),
        ];
      case 'dz':
      case 'ma':
        return const [
          _LevelOpt('sciences', '🔬', 'Sciences / علوم'),
          _LevelOpt('lettres', '📖', 'Lettres / آداب'),
          _LevelOpt('economie', '💰', 'Économie / اقتصاد'),
          _LevelOpt('technique', '🔧', 'Technique / تقني'),
        ];
      case 'pk':
        return const [
          _LevelOpt('pre_med', '🩺', 'Pre-Medical / FSc Pre-Med'),
          _LevelOpt('pre_eng', '⚙️', 'Pre-Engineering / FSc Pre-Eng'),
          _LevelOpt('computer', '💻', 'Computer Science'),
          _LevelOpt('commerce', '💰', 'Commerce / I.Com'),
          _LevelOpt('humanities', '📖', 'Humanities / FA'),
        ];
      case 'bd':
        return const [
          _LevelOpt('vigyan', '🔬', 'বিজ্ঞান (Science)'),
          _LevelOpt('manobik', '📖', 'মানবিক (Humanities)'),
          _LevelOpt('banijya', '💰', 'ব্যবসায় শিক্ষা (Commerce)'),
        ];
      case 'np':
        return const [
          _LevelOpt('science', '🔬', 'Science / विज्ञान'),
          _LevelOpt('management', '💼', 'Management / व्यवस्थापन'),
          _LevelOpt('humanities', '📖', 'Humanities / मानविकी'),
          _LevelOpt('education', '🎓', 'Education / शिक्षा'),
        ];
      case 'ir':
        return const [
          _LevelOpt('riyazi', '📐', 'ریاضی و فیزیک'),
          _LevelOpt('tajrobi', '🧬', 'علوم تجربی'),
          _LevelOpt('ensani', '📖', 'علوم انسانی'),
          _LevelOpt('honar', '🎨', 'هنر'),
          _LevelOpt('zaban', '🗣️', 'زبان خارجه'),
        ];
      case 'ng':
      case 'gh':
      case 'ke':
      case 'ug':
      case 'tz':
      case 'za':
      case 'et':
        return const [
          _LevelOpt('sciences', '🔬', 'Sciences'),
          _LevelOpt('arts', '📖', 'Arts / Humanities'),
          _LevelOpt('commercial', '💰', 'Commercial / Business'),
          _LevelOpt('technical', '🔧', 'Technical / Vocational'),
        ];
      case 'ca':
        return const [
          _LevelOpt('general', '📘', 'General'),
          _LevelOpt('advanced', '🏅', 'Advanced / Enriched'),
          _LevelOpt('ib', '🌐', 'IB'),
          _LevelOpt('ap', '🎓', 'AP'),
        ];
      case 'uz':
        return const [
          _LevelOpt('tabiiy', '🔬', 'Tabiiy fanlar'),
          _LevelOpt('ijtimoiy', '📖', 'Ijtimoiy fanlar'),
          _LevelOpt('aniq', '📐', 'Aniq fanlar'),
        ];
      case 'cd':
      case 'mg':
        return const [
          _LevelOpt('sciences', '🔬', 'Sciences'),
          _LevelOpt('litteraire', '📖', 'Littéraire'),
          _LevelOpt('economique', '💰', 'Économique'),
          _LevelOpt('technique', '🔧', 'Technique'),
        ];
      default:
        return const [
          _LevelOpt('science', '🔬', 'Science / Sayısal'),
          _LevelOpt('humanities', '📖', 'Humanities / Sözel'),
          _LevelOpt('mixed', '⚖️', 'Mixed / Eşit Ağırlık'),
          _LevelOpt('language', '🗣️', 'Language / Dil'),
        ];
    }
  }

  bool get _needsFaculty =>
      _level == 'university' || _level == 'masters' || _level == 'doctorate';

  bool get _needsTrack => _tracksForLevel().isNotEmpty;

  bool get _canSave {
    if (_country == null || _level == null || _grade == null) return false;
    if (_needsFaculty && _faculty == null) return false;
    if (_needsTrack && _track == null) return false;
    return true;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mini_test_edu_profile_set', true);
    await prefs.setString('mini_test_country', _country!);
    await prefs.setString('mini_test_level', _level!);
    await prefs.setString('mini_test_grade', _grade!);
    if (_track != null) {
      await prefs.setString('mini_test_track', _track!);
    } else {
      await prefs.remove('mini_test_track');
    }
    if (_faculty != null) {
      await prefs.setString('mini_test_faculty', _faculty!);
    } else {
      await prefs.remove('mini_test_faculty');
    }
    // Kaydetmeden önce ülkenin dili locale'e işlendiğinden emin ol.
    // (pickCountry'de zaten yapılıyor; buraya belt-and-suspenders.)
    await localeService.setLocaleForCountry(_country!);
    await CountryResolver.instance.refresh(locale: localeService);
    // Profil cache'ini tazele — AI prompt'ları yeni müfredat bağlamını okusun.
    await EduProfile.load();
    // 131 ülkenin tamamı için AI-driven müfredat: profil değişti → cache yoksa
    // arka planda AI'dan ders + konuları çek. Static catalog'da varsa zaten
    // hızlı cevap verir; yoksa AI fetch'i yapılana kadar international fallback
    // gösterilir (UI bloklamaz — unawaited fire-and-forget).
    final p = EduProfile.current;
    if (p != null && EduProfile.aiCachedTopics(p) == null) {
      unawaited(_prefetchProfileCurriculum(p));
    }
    if (mounted) widget.onSaved();
  }

  Future<void> _prefetchProfileCurriculum(EduProfile p) async {
    try {
      final result = await GeminiService.fetchProfileCurriculum(p);
      if (result.subjects.isNotEmpty) {
        await EduProfile.saveAiSubjectCache(p, result.subjects);
      }
      if (result.topicsBySubject.isNotEmpty) {
        await EduProfile.saveAiTopicsCache(p, result.topicsBySubject);
      }
    } catch (_) {
      // Sessizce başarısız — fallback static + international.
    }
  }

  // ─────────────────── Bottom sheet pickers ──────────────────────────────────
  Future<void> _pickCountry() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CountryPickerSheet(currentCountry: _country),
    );
    if (result != null && mounted) {
      setState(() {
        if (_country != result) {
          _country = result;
          // Ülke değişince alt seçimler sıfırlanır
          _level = null;
          _grade = null;
          _track = null;
          _faculty = null;
        }
      });
      // TÜM UYGULAMA dilini bu ülkenin birincil diline çevir.
      // LocaleService.notifyListeners → LocaleInherited → MaterialApp rebuild.
      await localeService.setLocaleForCountry(result);
      // Ülke çözümleyicinin de anında güncel olması için
      await CountryResolver.instance.refresh(locale: localeService);
    }
  }

  Future<void> _pickLevel() async {
    final result = await _pickFromList(tui(_country, 'level_sheet_title'), _levels());
    if (result == null || !mounted) return;
    // LGS Ortaokul sonrası ana liste içinde gözüksün, ama kayıtta
    // exam_prep + grade=lgs olarak işlensin → curriculum lookup'ı
    // tr_exam_prep_lgs anahtarına eşleşsin, müfredat doğru çıksın.
    if (result == 'lgs') {
      setState(() {
        _level = 'exam_prep';
        _grade = 'lgs';
        _track = null;
        _faculty = null;
      });
      return;
    }
    setState(() {
      if (_level != result) {
        _level = result;
        _grade = null;
        _track = null;
        _faculty = null;
      }
    });
  }

  Future<void> _pickGrade() async {
    final result = await _pickFromList(tui(_country, 'grade_sheet_title'), _gradesForLevel());
    if (result != null && mounted) setState(() => _grade = result);
  }

  Future<void> _pickTrack() async {
    final result = await _pickFromList(tui(_country, 'track_sheet_title'), _tracksForLevel());
    if (result != null && mounted) setState(() => _track = result);
  }

  Future<void> _pickFaculty() async {
    final result = await _pickFromList(tui(_country, 'faculty_sheet_title'), _faculties, searchable: true);
    if (result != null && mounted) setState(() => _faculty = result);
  }

  Future<String?> _pickFromList(String title, List<_LevelOpt> options, {bool searchable = false}) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _OptionPickerSheet(
        title: title,
        options: options,
        searchable: searchable,
        currentCountry: _country,
      ),
    );
  }

  // Kısa fakülte listesi (detaylı liste qualsar_arena'da var; burada en yaygın olanlar)
  static const List<_LevelOpt> _faculties = [
    _LevelOpt('tip', '🩺', 'Tıp'),
    _LevelOpt('dis_hekimligi', '🦷', 'Diş Hekimliği'),
    _LevelOpt('eczacilik', '💊', 'Eczacılık'),
    _LevelOpt('veteriner', '🐾', 'Veterinerlik'),
    _LevelOpt('hukuk', '⚖️', 'Hukuk'),
    _LevelOpt('psikoloji', '🧠', 'Psikoloji'),
    _LevelOpt('bilgisayar_muh', '💻', 'Bilgisayar Mühendisliği'),
    _LevelOpt('yazilim_muh', '💾', 'Yazılım Mühendisliği'),
    _LevelOpt('elektrik_elektronik_muh', '⚡', 'Elektrik-Elektronik Müh.'),
    _LevelOpt('endustri_muh', '📊', 'Endüstri Mühendisliği'),
    _LevelOpt('makine_muh', '🔧', 'Makine Mühendisliği'),
    _LevelOpt('insaat_muh', '🏗️', 'İnşaat Mühendisliği'),
    _LevelOpt('mimarlik', '🏛️', 'Mimarlık'),
    _LevelOpt('ic_mimarlik', '🛋️', 'İç Mimarlık'),
    _LevelOpt('isletme', '📘', 'İşletme'),
    _LevelOpt('iktisat', '💰', 'İktisat / Ekonomi'),
    _LevelOpt('uluslararasi_iliskiler', '🌍', 'Uluslararası İlişkiler'),
    _LevelOpt('siyaset_bilimi', '🗳️', 'Siyaset Bilimi'),
    _LevelOpt('fizyoterapi', '🏃', 'Fizyoterapi'),
    _LevelOpt('hemsirelik', '👩‍⚕️', 'Hemşirelik'),
    _LevelOpt('beslenme', '🥗', 'Beslenme ve Diyetetik'),
    _LevelOpt('ebelik', '👶', 'Ebelik'),
    _LevelOpt('turk_dili', '📚', 'Türk Dili ve Edebiyatı'),
    _LevelOpt('ingiliz_dili', '🇬🇧', 'İngiliz Dili ve Edebiyatı'),
    _LevelOpt('matematik', '📐', 'Matematik'),
    _LevelOpt('fizik', '⚛️', 'Fizik'),
    _LevelOpt('kimya', '🧪', 'Kimya'),
    _LevelOpt('biyoloji', '🧬', 'Biyoloji'),
    _LevelOpt('tarih', '🏛️', 'Tarih'),
    _LevelOpt('cografya', '🌍', 'Coğrafya'),
    _LevelOpt('felsefe', '🤔', 'Felsefe'),
    _LevelOpt('sosyoloji', '👥', 'Sosyoloji'),
    _LevelOpt('sinif_ogretmenligi', '🎒', 'Sınıf Öğretmenliği'),
    _LevelOpt('okul_oncesi', '🧸', 'Okul Öncesi Öğretmenliği'),
    _LevelOpt('ilahiyat', '🕋', 'İlahiyat'),
    _LevelOpt('turizm', '🏨', 'Turizm'),
    _LevelOpt('gastronomi', '🍳', 'Gastronomi'),
    _LevelOpt('grafik_tasarim', '🎨', 'Grafik Tasarım'),
    _LevelOpt('muzik', '🎵', 'Müzik'),
    _LevelOpt('spor', '⚽', 'Spor Bilimleri'),
    _LevelOpt('adalet', '⚖️', 'Adalet'),
    _LevelOpt('diger', '🧭', 'Diğer Bölüm'),
  ];

  @override
  Widget build(BuildContext context) {
    Country? countryObj;
    if (_country != null) {
      for (final c in kAllCountries) {
        if (c.key == _country) {
          countryObj = c;
          break;
        }
      }
    }
    final level = _levels().firstWhere(
      (l) => l.value == _level,
      orElse: () => const _LevelOpt('', '', ''),
    );
    final grade = _gradesForLevel().firstWhere(
      (g) => g.value == _grade,
      orElse: () => const _LevelOpt('', '', ''),
    );
    final track = _tracksForLevel().firstWhere(
      (t) => t.value == _track,
      orElse: () => const _LevelOpt('', '', ''),
    );
    final faculty = _faculties.firstWhere(
      (f) => f.value == _faculty,
      orElse: () => const _LevelOpt('', '', ''),
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text('🎓', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tui(_country, 'title'),
                            style: GoogleFonts.fraunces(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.03,
                              color: Colors.black,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          tui(_country, 'subtitle'),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _inkMute,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.trialEntryNumber > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Text('🧪', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tui(_country, 'trial_text').replaceAll('{n}', '${widget.trialEntryNumber}'),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // Fields
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _field(
                    label: tui(_country, 'country_label'),
                    placeholder: tui(_country, 'country_placeholder'),
                    emoji: countryObj?.flag,
                    value: countryObj?.name,
                    onTap: _pickCountry,
                  ),
                  if (_country != null)
                    _field(
                      label: tui(_country, 'level_label'),
                      placeholder: tui(_country, 'level_placeholder'),
                      emoji: level.emoji.isEmpty ? null : level.emoji,
                      value: level.label.isEmpty ? null : level.label,
                      onTap: _pickLevel,
                    ),
                  if (_level != null && _needsFaculty)
                    _field(
                      label: tui(_country, 'faculty_label'),
                      placeholder: tui(_country, 'faculty_placeholder'),
                      emoji: faculty.emoji.isEmpty ? null : faculty.emoji,
                      value: faculty.label.isEmpty ? null : faculty.label,
                      onTap: _pickFaculty,
                    ),
                  if (_level != null && (!_needsFaculty || _faculty != null))
                    _field(
                      label: tui(_country, 'grade_label'),
                      placeholder: tui(_country, 'grade_placeholder'),
                      emoji: grade.emoji.isEmpty ? null : grade.emoji,
                      value: grade.label.isEmpty ? null : grade.label,
                      onTap: _pickGrade,
                    ),
                  if (_grade != null && _needsTrack)
                    _field(
                      label: tui(_country, 'track_label'),
                      placeholder: tui(_country, 'track_placeholder'),
                      emoji: track.emoji.isEmpty ? null : track.emoji,
                      value: track.label.isEmpty ? null : track.label,
                      onTap: _pickTrack,
                    ),
                  const SizedBox(height: 16),
                  // Bilgilendirme kutusu
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _line),
                    ),
                    child: Row(
                      children: [
                        const Text('✨', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tui(_country, 'info'),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _inkSoft,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
            // Sticky bottom action — atla yok, zorunlu
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: _primaryButton(
                label: tui(_country, 'save_button'),
                enabled: _canSave,
                onTap: _save,
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _field({
    required String label,
    required String placeholder,
    required VoidCallback onTap,
    String? value,
    String? emoji,
  }) {
    final filled = value != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _inkMute,
                letterSpacing: 0.08,
              )),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.black,
                  width: filled ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  if (emoji != null) ...[
                    Text(emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                  ] else ...[
                    Icon(Icons.expand_more_rounded, size: 20, color: _inkMute),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      value ?? placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
                        color: filled ? _ink : _inkMute,
                      ),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: filled ? _brand : _inkMute),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: enabled ? _brand : _brand.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(100),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: _brand.withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!enabled) ...[
              const Icon(Icons.lock_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                )),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ULUSLARASI UI YEREL ALTYAPISI
//  Ülkeye göre ekrandaki metinler (başlık, alt yazı, label'lar, buton vb.)
//  seçilen ülkenin resmi diline dönüşür. Her yeni dili buraya ekle.
// ═══════════════════════════════════════════════════════════════════════════════

/// Ülke → dil kodu eşlemesi.
/// Listede olmayan ülkeler 'en' (uluslararası İngilizce) kullanır.
const Map<String, String> _countryToLang = {
  'tr': 'tr',
  // İngilizce konuşulan ülkeler
  'us': 'en', 'uk': 'en', 'au': 'en', 'ca': 'en', 'nz': 'en', 'ie': 'en',
  'sg': 'en', 'za': 'en', 'hk': 'en', 'jm': 'en', 'ng': 'en', 'gh': 'en',
  'ug': 'en', 'international': 'en',
  // Hintçe (Hindistan → Hintçe; UI Hint'i yoksa İngilizce fallback)
  'in': 'hi',
  // Almanca
  'de': 'de', 'at': 'de', 'ch': 'de', 'li': 'de', 'lu': 'de',
  // Fransızca
  'fr': 'fr', 'be': 'fr', 'mc': 'fr', 'ma': 'fr', 'dz': 'fr', 'tn': 'fr',
  'cm': 'fr', 'cd': 'fr', 'mg': 'fr',
  // İspanyolca
  'es': 'es', 'mx': 'es', 'ar': 'es', 'co': 'es', 've': 'es', 'pe': 'es',
  'cl': 'es', 'ec': 'es', 'gt': 'es', 'cu': 'es', 'bo': 'es', 'do': 'es',
  'hn': 'es', 'py': 'es', 'sv': 'es', 'ni': 'es', 'cr': 'es', 'pa': 'es',
  'uy': 'es',
  // Portekizce
  'br': 'pt', 'pt': 'pt', 'ao': 'pt', 'mz': 'pt',
  // Japonca
  'jp': 'ja',
  // Rusça
  'ru': 'ru', 'by': 'ru', 'kz': 'ru', 'kg': 'ru', 'tj': 'ru', 'am': 'ru',
  // Çince
  'cn': 'zh', 'tw': 'zh',
  // Korece
  'kr': 'ko', 'kp': 'ko',
  // Arapça
  'sa': 'ar', 'ae': 'ar', 'qa': 'ar', 'kw': 'ar', 'eg': 'ar', 'jo': 'ar',
  'lb': 'ar', 'iq': 'ar', 'ye': 'ar', 'sy': 'ar', 'om': 'ar', 'bh': 'ar',
  'ly': 'ar', 'ps': 'ar', 'sd': 'ar',
  // İtalyanca
  'it': 'it', 'sm': 'it',
  // Hollandaca
  'nl': 'nl',
  // Farsça
  'ir': 'fa', 'af': 'fa',
  // Endonezce
  'id': 'id',
  // Malayca (Malezya ülke kodu 'my' — dili Malayca)
  'my': 'ms',
  // Vietnamca
  'vn': 'vi',
  // Tayca
  'th': 'th',
  // Bengalce
  'bd': 'bn',
  // Urduca (Pakistan)
  'pk': 'ur',
  // Ukraynaca
  'ua': 'ukr',
  // Lehçe
  'pl': 'pl',
  // Amharca (Etiyopya)
  'et': 'amh',
  // Burmaca/Myanmar dili
  'mm': 'bur',
  // Nepalce
  'np': 'ne',
  // Filipince
  'ph': 'fil',
  // Svahili (Kenya, Tanzanya)
  'ke': 'sw', 'tz': 'sw',
  // Özbekçe
  'uz': 'uz',
};

/// UI metin sözlüğü — dil kodu → (anahtar → metin)
const Map<String, Map<String, String>> _ui = {
  'tr': {
    'title': 'Eğitim Profilin',
    'subtitle': 'Dersler ve sorular sana özel hazırlanır',
    'country_label': 'ÜLKE',
    'country_placeholder': 'Ülke seç',
    'country_sheet_title': 'Ülke Seç',
    'country_search_hint': 'Ülke ara…',
    'level_label': 'EĞİTİM SEVİYESİ',
    'level_placeholder': 'Seviye seç',
    'level_sheet_title': 'Eğitim Seviyesi',
    'grade_label': 'SINIF',
    'grade_placeholder': 'Sınıf seç',
    'grade_sheet_title': 'Sınıf',
    'track_label': 'ALAN',
    'track_placeholder': 'Alan seç',
    'track_sheet_title': 'Alan',
    'faculty_label': 'FAKÜLTE / BÖLÜM',
    'faculty_placeholder': 'Bölüm seç',
    'faculty_sheet_title': 'Fakülte / Bölüm',
    'faculty_search_hint': 'Ara…',
    'save_button': '✓ Kaydet ve Devam Et',
    'info': 'Bu bilgilere göre QuAlsar Arena, Konu Özeti ve Sınav Soruları sayfalarında dersler ve konular otomatik çıkar.',
    'trial_text': 'Deneme sürümü · {n}/20 giriş · değiştirebilirsin',
    'no_result': 'Sonuç bulunamadı',
    'countries_count': 'ülke',
  },
  'en': {
    'title': 'Education Profile',
    'subtitle': 'Courses and questions tailored to you',
    'country_label': 'COUNTRY',
    'country_placeholder': 'Select country',
    'country_sheet_title': 'Select Country',
    'country_search_hint': 'Search country…',
    'level_label': 'EDUCATION LEVEL',
    'level_placeholder': 'Select level',
    'level_sheet_title': 'Education Level',
    'grade_label': 'GRADE',
    'grade_placeholder': 'Select grade',
    'grade_sheet_title': 'Grade',
    'track_label': 'TRACK',
    'track_placeholder': 'Select track',
    'track_sheet_title': 'Track',
    'faculty_label': 'FACULTY / MAJOR',
    'faculty_placeholder': 'Select major',
    'faculty_sheet_title': 'Faculty / Major',
    'faculty_search_hint': 'Search…',
    'save_button': '✓ Save and Continue',
    'info': 'Subjects and topics will be automatically populated across QuAlsar Arena, Topic Summary and Exam Questions based on this profile.',
    'trial_text': 'Trial · {n}/20 launches · editable',
    'no_result': 'No results',
    'countries_count': 'countries',
  },
  'de': {
    'title': 'Bildungsprofil',
    'subtitle': 'Fächer und Fragen auf dich zugeschnitten',
    'country_label': 'LAND',
    'country_placeholder': 'Land auswählen',
    'country_sheet_title': 'Land auswählen',
    'country_search_hint': 'Land suchen…',
    'level_label': 'BILDUNGSNIVEAU',
    'level_placeholder': 'Niveau auswählen',
    'level_sheet_title': 'Bildungsniveau',
    'grade_label': 'KLASSE',
    'grade_placeholder': 'Klasse auswählen',
    'grade_sheet_title': 'Klasse',
    'track_label': 'SCHWERPUNKT',
    'track_placeholder': 'Schwerpunkt auswählen',
    'track_sheet_title': 'Schwerpunkt',
    'faculty_label': 'FAKULTÄT / STUDIENGANG',
    'faculty_placeholder': 'Studiengang auswählen',
    'faculty_sheet_title': 'Fakultät / Studiengang',
    'faculty_search_hint': 'Suchen…',
    'save_button': '✓ Speichern und Fortfahren',
    'info': 'Fächer und Themen werden basierend auf deinem Profil in QuAlsar Arena automatisch vorbereitet.',
    'trial_text': 'Testversion · {n}/20 Öffnungen · änderbar',
    'no_result': 'Keine Ergebnisse',
    'countries_count': 'Länder',
  },
  'fr': {
    'title': 'Profil Éducatif',
    'subtitle': 'Cours et questions adaptés à vous',
    'country_label': 'PAYS',
    'country_placeholder': 'Choisir le pays',
    'country_sheet_title': 'Choisir le Pays',
    'country_search_hint': 'Rechercher un pays…',
    'level_label': "NIVEAU D'ÉTUDES",
    'level_placeholder': 'Choisir le niveau',
    'level_sheet_title': "Niveau d'études",
    'grade_label': 'CLASSE',
    'grade_placeholder': 'Choisir la classe',
    'grade_sheet_title': 'Classe',
    'track_label': 'FILIÈRE',
    'track_placeholder': 'Choisir la filière',
    'track_sheet_title': 'Filière',
    'faculty_label': 'FACULTÉ / MATIÈRE',
    'faculty_placeholder': 'Choisir',
    'faculty_sheet_title': 'Faculté / Matière',
    'faculty_search_hint': 'Rechercher…',
    'save_button': '✓ Enregistrer et Continuer',
    'info': 'Les matières et sujets seront automatiquement préparés selon votre profil.',
    'trial_text': "Version d'essai · {n}/20 ouvertures · modifiable",
    'no_result': 'Aucun résultat',
    'countries_count': 'pays',
  },
  'es': {
    'title': 'Perfil Educativo',
    'subtitle': 'Asignaturas y preguntas adaptadas a ti',
    'country_label': 'PAÍS',
    'country_placeholder': 'Selecciona el país',
    'country_sheet_title': 'Seleccionar País',
    'country_search_hint': 'Buscar país…',
    'level_label': 'NIVEL EDUCATIVO',
    'level_placeholder': 'Selecciona el nivel',
    'level_sheet_title': 'Nivel Educativo',
    'grade_label': 'CURSO',
    'grade_placeholder': 'Selecciona el curso',
    'grade_sheet_title': 'Curso',
    'track_label': 'MODALIDAD',
    'track_placeholder': 'Selecciona modalidad',
    'track_sheet_title': 'Modalidad',
    'faculty_label': 'FACULTAD / CARRERA',
    'faculty_placeholder': 'Selecciona carrera',
    'faculty_sheet_title': 'Facultad / Carrera',
    'faculty_search_hint': 'Buscar…',
    'save_button': '✓ Guardar y Continuar',
    'info': 'Los cursos y temas se prepararán automáticamente según tu perfil.',
    'trial_text': 'Prueba · {n}/20 inicios · editable',
    'no_result': 'Sin resultados',
    'countries_count': 'países',
  },
  'pt': {
    'title': 'Perfil Educacional',
    'subtitle': 'Disciplinas e questões personalizadas para você',
    'country_label': 'PAÍS',
    'country_placeholder': 'Selecione o país',
    'country_sheet_title': 'Selecionar País',
    'country_search_hint': 'Buscar país…',
    'level_label': 'NÍVEL EDUCACIONAL',
    'level_placeholder': 'Selecione o nível',
    'level_sheet_title': 'Nível Educacional',
    'grade_label': 'SÉRIE',
    'grade_placeholder': 'Selecione a série',
    'grade_sheet_title': 'Série',
    'track_label': 'ÁREA',
    'track_placeholder': 'Selecione a área',
    'track_sheet_title': 'Área',
    'faculty_label': 'FACULDADE / CURSO',
    'faculty_placeholder': 'Selecione o curso',
    'faculty_sheet_title': 'Faculdade / Curso',
    'faculty_search_hint': 'Buscar…',
    'save_button': '✓ Salvar e Continuar',
    'info': 'As disciplinas e os tópicos serão preparados automaticamente com base no seu perfil.',
    'trial_text': 'Versão de teste · {n}/20 aberturas · editável',
    'no_result': 'Sem resultados',
    'countries_count': 'países',
  },
  'ja': {
    'title': '教育プロフィール',
    'subtitle': 'あなたに合わせた科目と問題',
    'country_label': '国',
    'country_placeholder': '国を選択',
    'country_sheet_title': '国を選択',
    'country_search_hint': '国を検索…',
    'level_label': '教育レベル',
    'level_placeholder': 'レベルを選択',
    'level_sheet_title': '教育レベル',
    'grade_label': '学年',
    'grade_placeholder': '学年を選択',
    'grade_sheet_title': '学年',
    'track_label': 'コース',
    'track_placeholder': 'コースを選択',
    'track_sheet_title': 'コース',
    'faculty_label': '学部 / 専攻',
    'faculty_placeholder': '学部を選択',
    'faculty_sheet_title': '学部 / 専攻',
    'faculty_search_hint': '検索…',
    'save_button': '✓ 保存して続行',
    'info': 'このプロフィールに基づいて科目と問題が自動的に準備されます。',
    'trial_text': 'トライアル · {n}/20 回目 · 変更可能',
    'no_result': '結果がありません',
    'countries_count': '国',
  },
  'ru': {
    'title': 'Образовательный Профиль',
    'subtitle': 'Предметы и вопросы, подобранные для вас',
    'country_label': 'СТРАНА',
    'country_placeholder': 'Выберите страну',
    'country_sheet_title': 'Выберите Страну',
    'country_search_hint': 'Поиск страны…',
    'level_label': 'УРОВЕНЬ ОБРАЗОВАНИЯ',
    'level_placeholder': 'Выберите уровень',
    'level_sheet_title': 'Уровень Образования',
    'grade_label': 'КЛАСС',
    'grade_placeholder': 'Выберите класс',
    'grade_sheet_title': 'Класс',
    'track_label': 'НАПРАВЛЕНИЕ',
    'track_placeholder': 'Выберите направление',
    'track_sheet_title': 'Направление',
    'faculty_label': 'ФАКУЛЬТЕТ',
    'faculty_placeholder': 'Выберите факультет',
    'faculty_sheet_title': 'Факультет',
    'faculty_search_hint': 'Поиск…',
    'save_button': '✓ Сохранить и Продолжить',
    'info': 'Предметы и темы будут автоматически подобраны на основе вашего профиля.',
    'trial_text': 'Пробная версия · {n}/20 запусков · можно менять',
    'no_result': 'Ничего не найдено',
    'countries_count': 'стран',
  },
  'zh': {
    'title': '教育档案',
    'subtitle': '为您量身定制的科目和题目',
    'country_label': '国家',
    'country_placeholder': '选择国家',
    'country_sheet_title': '选择国家',
    'country_search_hint': '搜索国家…',
    'level_label': '教育水平',
    'level_placeholder': '选择水平',
    'level_sheet_title': '教育水平',
    'grade_label': '年级',
    'grade_placeholder': '选择年级',
    'grade_sheet_title': '年级',
    'track_label': '方向',
    'track_placeholder': '选择方向',
    'track_sheet_title': '方向',
    'faculty_label': '学院 / 专业',
    'faculty_placeholder': '选择专业',
    'faculty_sheet_title': '学院 / 专业',
    'faculty_search_hint': '搜索…',
    'save_button': '✓ 保存并继续',
    'info': '根据此档案,科目和主题将自动准备。',
    'trial_text': '试用版 · {n}/20 次启动 · 可编辑',
    'no_result': '无结果',
    'countries_count': '个国家',
  },
  'ko': {
    'title': '교육 프로필',
    'subtitle': '맞춤 과목과 문제',
    'country_label': '국가',
    'country_placeholder': '국가 선택',
    'country_sheet_title': '국가 선택',
    'country_search_hint': '국가 검색…',
    'level_label': '교육 수준',
    'level_placeholder': '수준 선택',
    'level_sheet_title': '교육 수준',
    'grade_label': '학년',
    'grade_placeholder': '학년 선택',
    'grade_sheet_title': '학년',
    'track_label': '계열',
    'track_placeholder': '계열 선택',
    'track_sheet_title': '계열',
    'faculty_label': '학부 / 전공',
    'faculty_placeholder': '전공 선택',
    'faculty_sheet_title': '학부 / 전공',
    'faculty_search_hint': '검색…',
    'save_button': '✓ 저장하고 계속',
    'info': '이 프로필에 따라 과목과 주제가 자동으로 준비됩니다.',
    'trial_text': '체험판 · {n}/20 회 실행 · 편집 가능',
    'no_result': '결과 없음',
    'countries_count': '개국',
  },
  'ar': {
    'title': 'الملف التعليمي',
    'subtitle': 'مواد وأسئلة مصممة لك',
    'country_label': 'الدولة',
    'country_placeholder': 'اختر الدولة',
    'country_sheet_title': 'اختر الدولة',
    'country_search_hint': 'ابحث عن دولة…',
    'level_label': 'المستوى التعليمي',
    'level_placeholder': 'اختر المستوى',
    'level_sheet_title': 'المستوى التعليمي',
    'grade_label': 'الصف',
    'grade_placeholder': 'اختر الصف',
    'grade_sheet_title': 'الصف',
    'track_label': 'المسار',
    'track_placeholder': 'اختر المسار',
    'track_sheet_title': 'المسار',
    'faculty_label': 'الكلية / التخصص',
    'faculty_placeholder': 'اختر التخصص',
    'faculty_sheet_title': 'الكلية / التخصص',
    'faculty_search_hint': 'ابحث…',
    'save_button': '✓ حفظ ومتابعة',
    'info': 'ستتم تهيئة المواد والمواضيع تلقائيًا وفقًا لملفك.',
    'trial_text': 'النسخة التجريبية · {n}/20 فتحات · قابلة للتعديل',
    'no_result': 'لا توجد نتائج',
    'countries_count': 'دولة',
  },
  'it': {
    'title': 'Profilo Educativo',
    'subtitle': 'Materie e domande su misura per te',
    'country_label': 'PAESE',
    'country_placeholder': 'Seleziona il paese',
    'country_sheet_title': 'Seleziona Paese',
    'country_search_hint': 'Cerca paese…',
    'level_label': 'LIVELLO',
    'level_placeholder': 'Seleziona livello',
    'level_sheet_title': 'Livello Educativo',
    'grade_label': 'CLASSE',
    'grade_placeholder': 'Seleziona classe',
    'grade_sheet_title': 'Classe',
    'track_label': 'INDIRIZZO',
    'track_placeholder': 'Seleziona indirizzo',
    'track_sheet_title': 'Indirizzo',
    'faculty_label': 'FACOLTÀ',
    'faculty_placeholder': 'Seleziona facoltà',
    'faculty_sheet_title': 'Facoltà',
    'faculty_search_hint': 'Cerca…',
    'save_button': '✓ Salva e Continua',
    'info': 'Materie e argomenti saranno preparati automaticamente in base al profilo.',
    'trial_text': 'Prova · {n}/20 avvii · modificabile',
    'no_result': 'Nessun risultato',
    'countries_count': 'paesi',
  },
  'nl': {
    'title': 'Onderwijsprofiel',
    'subtitle': 'Vakken en vragen op jou afgestemd',
    'country_label': 'LAND',
    'country_placeholder': 'Selecteer land',
    'country_sheet_title': 'Selecteer Land',
    'country_search_hint': 'Zoek land…',
    'level_label': 'ONDERWIJSNIVEAU',
    'level_placeholder': 'Selecteer niveau',
    'level_sheet_title': 'Onderwijsniveau',
    'grade_label': 'KLAS',
    'grade_placeholder': 'Selecteer klas',
    'grade_sheet_title': 'Klas',
    'track_label': 'RICHTING',
    'track_placeholder': 'Selecteer richting',
    'track_sheet_title': 'Richting',
    'faculty_label': 'FACULTEIT',
    'faculty_placeholder': 'Selecteer faculteit',
    'faculty_sheet_title': 'Faculteit',
    'faculty_search_hint': 'Zoeken…',
    'save_button': '✓ Opslaan en Verder',
    'info': 'Vakken en onderwerpen worden automatisch voorbereid op basis van dit profiel.',
    'trial_text': 'Proefversie · {n}/20 starts · aanpasbaar',
    'no_result': 'Geen resultaten',
    'countries_count': 'landen',
  },
  // Hintçe
  'hi': {
    'title': 'शिक्षा प्रोफ़ाइल',
    'subtitle': 'विषय और प्रश्न आपके लिए अनुकूलित',
    'country_label': 'देश',
    'country_placeholder': 'देश चुनें',
    'country_sheet_title': 'देश चुनें',
    'country_search_hint': 'देश खोजें…',
    'level_label': 'शिक्षा स्तर',
    'level_placeholder': 'स्तर चुनें',
    'level_sheet_title': 'शिक्षा स्तर',
    'grade_label': 'कक्षा',
    'grade_placeholder': 'कक्षा चुनें',
    'grade_sheet_title': 'कक्षा',
    'track_label': 'स्ट्रीम',
    'track_placeholder': 'स्ट्रीम चुनें',
    'track_sheet_title': 'स्ट्रीम',
    'faculty_label': 'संकाय / विभाग',
    'faculty_placeholder': 'विभाग चुनें',
    'faculty_sheet_title': 'संकाय / विभाग',
    'faculty_search_hint': 'खोजें…',
    'save_button': '✓ सहेजें और जारी रखें',
    'info': 'इस प्रोफ़ाइल के अनुसार विषय और विषय-वस्तु स्वचालित रूप से तैयार होंगे।',
    'trial_text': 'परीक्षण · {n}/20 लॉन्च · संपादन योग्य',
    'no_result': 'कोई परिणाम नहीं',
    'countries_count': 'देश',
  },
  // Bengalce
  'bn': {
    'title': 'শিক্ষা প্রোফাইল',
    'subtitle': 'বিষয় এবং প্রশ্ন আপনার জন্য উপযোগী',
    'country_label': 'দেশ',
    'country_placeholder': 'দেশ নির্বাচন করুন',
    'country_sheet_title': 'দেশ নির্বাচন করুন',
    'country_search_hint': 'দেশ অনুসন্ধান…',
    'level_label': 'শিক্ষা স্তর',
    'level_placeholder': 'স্তর নির্বাচন করুন',
    'level_sheet_title': 'শিক্ষা স্তর',
    'grade_label': 'শ্রেণী',
    'grade_placeholder': 'শ্রেণী নির্বাচন করুন',
    'grade_sheet_title': 'শ্রেণী',
    'track_label': 'বিভাগ',
    'track_placeholder': 'বিভাগ নির্বাচন',
    'track_sheet_title': 'বিভাগ',
    'faculty_label': 'অনুষদ / বিভাগ',
    'faculty_placeholder': 'বিভাগ নির্বাচন',
    'faculty_sheet_title': 'অনুষদ / বিভাগ',
    'faculty_search_hint': 'অনুসন্ধান…',
    'save_button': '✓ সংরক্ষণ করুন',
    'info': 'এই প্রোফাইল অনুযায়ী বিষয় ও টপিক স্বয়ংক্রিয়ভাবে তৈরি হবে।',
    'trial_text': 'ট্রায়াল · {n}/20 লঞ্চ · সম্পাদনযোগ্য',
    'no_result': 'কোনো ফলাফল নেই',
    'countries_count': 'দেশ',
  },
  // Urduca
  'ur': {
    'title': 'تعلیمی پروفائل',
    'subtitle': 'مضامین اور سوالات آپ کے لیے تیار',
    'country_label': 'ملک',
    'country_placeholder': 'ملک منتخب کریں',
    'country_sheet_title': 'ملک منتخب کریں',
    'country_search_hint': 'ملک تلاش کریں…',
    'level_label': 'تعلیمی سطح',
    'level_placeholder': 'سطح منتخب کریں',
    'level_sheet_title': 'تعلیمی سطح',
    'grade_label': 'جماعت',
    'grade_placeholder': 'جماعت منتخب کریں',
    'grade_sheet_title': 'جماعت',
    'track_label': 'شعبہ',
    'track_placeholder': 'شعبہ منتخب کریں',
    'track_sheet_title': 'شعبہ',
    'faculty_label': 'فیکلٹی / شعبہ',
    'faculty_placeholder': 'شعبہ منتخب کریں',
    'faculty_sheet_title': 'فیکلٹی / شعبہ',
    'faculty_search_hint': 'تلاش…',
    'save_button': '✓ محفوظ کریں',
    'info': 'اس پروفائل کی بنیاد پر مضامین اور موضوعات خودبخود تیار ہوں گے۔',
    'trial_text': 'آزمائشی · {n}/20 لانچ · قابلِ ترمیم',
    'no_result': 'کوئی نتیجہ نہیں',
    'countries_count': 'ممالک',
  },
  // Farsça (ایران)
  'fa': {
    'title': 'پروفایل تحصیلی',
    'subtitle': 'دروس و سؤالات متناسب با شما',
    'country_label': 'کشور',
    'country_placeholder': 'کشور را انتخاب کنید',
    'country_sheet_title': 'انتخاب کشور',
    'country_search_hint': 'جستجوی کشور…',
    'level_label': 'مقطع تحصیلی',
    'level_placeholder': 'مقطع را انتخاب کنید',
    'level_sheet_title': 'مقطع تحصیلی',
    'grade_label': 'پایه',
    'grade_placeholder': 'پایه را انتخاب کنید',
    'grade_sheet_title': 'پایه',
    'track_label': 'رشته',
    'track_placeholder': 'رشته را انتخاب کنید',
    'track_sheet_title': 'رشته',
    'faculty_label': 'دانشکده / رشته',
    'faculty_placeholder': 'رشته را انتخاب کنید',
    'faculty_sheet_title': 'دانشکده / رشته',
    'faculty_search_hint': 'جستجو…',
    'save_button': '✓ ذخیره و ادامه',
    'info': 'دروس و مباحث بر اساس این پروفایل به‌طور خودکار آماده می‌شود.',
    'trial_text': 'نسخه آزمایشی · {n}/۱۰ اجرا · قابل ویرایش',
    'no_result': 'نتیجه‌ای یافت نشد',
    'countries_count': 'کشور',
  },
  // Endonezce
  'id': {
    'title': 'Profil Pendidikan',
    'subtitle': 'Mata pelajaran dan soal disesuaikan untuk Anda',
    'country_label': 'NEGARA',
    'country_placeholder': 'Pilih negara',
    'country_sheet_title': 'Pilih Negara',
    'country_search_hint': 'Cari negara…',
    'level_label': 'JENJANG',
    'level_placeholder': 'Pilih jenjang',
    'level_sheet_title': 'Jenjang Pendidikan',
    'grade_label': 'KELAS',
    'grade_placeholder': 'Pilih kelas',
    'grade_sheet_title': 'Kelas',
    'track_label': 'JURUSAN',
    'track_placeholder': 'Pilih jurusan',
    'track_sheet_title': 'Jurusan',
    'faculty_label': 'FAKULTAS / PROGRAM STUDI',
    'faculty_placeholder': 'Pilih program',
    'faculty_sheet_title': 'Fakultas / Program',
    'faculty_search_hint': 'Cari…',
    'save_button': '✓ Simpan dan Lanjutkan',
    'info': 'Mata pelajaran dan topik akan disiapkan otomatis sesuai profil.',
    'trial_text': 'Uji coba · {n}/20 peluncuran · dapat diubah',
    'no_result': 'Tidak ada hasil',
    'countries_count': 'negara',
  },
  // Malayca (Malaysia)
  'ms': {
    'title': 'Profil Pendidikan',
    'subtitle': 'Subjek dan soalan disesuaikan untuk anda',
    'country_label': 'NEGARA',
    'country_placeholder': 'Pilih negara',
    'country_sheet_title': 'Pilih Negara',
    'country_search_hint': 'Cari negara…',
    'level_label': 'PERINGKAT',
    'level_placeholder': 'Pilih peringkat',
    'level_sheet_title': 'Peringkat Pendidikan',
    'grade_label': 'TINGKATAN',
    'grade_placeholder': 'Pilih tingkatan',
    'grade_sheet_title': 'Tingkatan',
    'track_label': 'ALIRAN',
    'track_placeholder': 'Pilih aliran',
    'track_sheet_title': 'Aliran',
    'faculty_label': 'FAKULTI / JURUSAN',
    'faculty_placeholder': 'Pilih jurusan',
    'faculty_sheet_title': 'Fakulti / Jurusan',
    'faculty_search_hint': 'Cari…',
    'save_button': '✓ Simpan dan Teruskan',
    'info': 'Subjek dan topik akan disediakan secara automatik mengikut profil ini.',
    'trial_text': 'Percubaan · {n}/20 lancar · boleh diubah',
    'no_result': 'Tiada hasil',
    'countries_count': 'negara',
  },
  // Vietnamca
  'vi': {
    'title': 'Hồ Sơ Học Tập',
    'subtitle': 'Môn học và câu hỏi được cá nhân hóa',
    'country_label': 'QUỐC GIA',
    'country_placeholder': 'Chọn quốc gia',
    'country_sheet_title': 'Chọn Quốc Gia',
    'country_search_hint': 'Tìm quốc gia…',
    'level_label': 'CẤP HỌC',
    'level_placeholder': 'Chọn cấp học',
    'level_sheet_title': 'Cấp Học',
    'grade_label': 'LỚP',
    'grade_placeholder': 'Chọn lớp',
    'grade_sheet_title': 'Lớp',
    'track_label': 'KHỐI',
    'track_placeholder': 'Chọn khối',
    'track_sheet_title': 'Khối',
    'faculty_label': 'KHOA / NGÀNH',
    'faculty_placeholder': 'Chọn ngành',
    'faculty_sheet_title': 'Khoa / Ngành',
    'faculty_search_hint': 'Tìm kiếm…',
    'save_button': '✓ Lưu và Tiếp tục',
    'info': 'Môn học và chủ đề sẽ tự động hiển thị dựa trên hồ sơ này.',
    'trial_text': 'Dùng thử · {n}/20 lượt · chỉnh sửa được',
    'no_result': 'Không có kết quả',
    'countries_count': 'quốc gia',
  },
  // Tayca
  'th': {
    'title': 'โปรไฟล์การศึกษา',
    'subtitle': 'วิชาและคำถามปรับให้เหมาะกับคุณ',
    'country_label': 'ประเทศ',
    'country_placeholder': 'เลือกประเทศ',
    'country_sheet_title': 'เลือกประเทศ',
    'country_search_hint': 'ค้นหาประเทศ…',
    'level_label': 'ระดับการศึกษา',
    'level_placeholder': 'เลือกระดับ',
    'level_sheet_title': 'ระดับการศึกษา',
    'grade_label': 'ชั้นปี',
    'grade_placeholder': 'เลือกชั้น',
    'grade_sheet_title': 'ชั้น',
    'track_label': 'สาย',
    'track_placeholder': 'เลือกสาย',
    'track_sheet_title': 'สาย',
    'faculty_label': 'คณะ / สาขา',
    'faculty_placeholder': 'เลือกสาขา',
    'faculty_sheet_title': 'คณะ / สาขา',
    'faculty_search_hint': 'ค้นหา…',
    'save_button': '✓ บันทึก',
    'info': 'วิชาและหัวข้อจะถูกจัดเตรียมโดยอัตโนมัติตามโปรไฟล์นี้',
    'trial_text': 'ทดลอง · {n}/20 ครั้ง · แก้ไขได้',
    'no_result': 'ไม่พบผลลัพธ์',
    'countries_count': 'ประเทศ',
  },
  // Lehçe
  'pl': {
    'title': 'Profil Edukacyjny',
    'subtitle': 'Przedmioty i pytania dopasowane do Ciebie',
    'country_label': 'KRAJ',
    'country_placeholder': 'Wybierz kraj',
    'country_sheet_title': 'Wybierz Kraj',
    'country_search_hint': 'Szukaj kraju…',
    'level_label': 'POZIOM',
    'level_placeholder': 'Wybierz poziom',
    'level_sheet_title': 'Poziom Edukacji',
    'grade_label': 'KLASA',
    'grade_placeholder': 'Wybierz klasę',
    'grade_sheet_title': 'Klasa',
    'track_label': 'PROFIL',
    'track_placeholder': 'Wybierz profil',
    'track_sheet_title': 'Profil',
    'faculty_label': 'WYDZIAŁ / KIERUNEK',
    'faculty_placeholder': 'Wybierz kierunek',
    'faculty_sheet_title': 'Wydział / Kierunek',
    'faculty_search_hint': 'Szukaj…',
    'save_button': '✓ Zapisz i Kontynuuj',
    'info': 'Przedmioty i tematy zostaną przygotowane automatycznie na podstawie profilu.',
    'trial_text': 'Wersja próbna · {n}/20 uruchomień · edytowalne',
    'no_result': 'Brak wyników',
    'countries_count': 'krajów',
  },
  // Ukraynaca
  'ukr': {
    'title': 'Освітній Профіль',
    'subtitle': 'Предмети та питання підібрані для тебе',
    'country_label': 'КРАЇНА',
    'country_placeholder': 'Виберіть країну',
    'country_sheet_title': 'Виберіть Країну',
    'country_search_hint': 'Пошук країни…',
    'level_label': 'РІВЕНЬ ОСВІТИ',
    'level_placeholder': 'Виберіть рівень',
    'level_sheet_title': 'Рівень Освіти',
    'grade_label': 'КЛАС',
    'grade_placeholder': 'Виберіть клас',
    'grade_sheet_title': 'Клас',
    'track_label': 'ПРОФІЛЬ',
    'track_placeholder': 'Виберіть профіль',
    'track_sheet_title': 'Профіль',
    'faculty_label': 'ФАКУЛЬТЕТ / СПЕЦІАЛЬНІСТЬ',
    'faculty_placeholder': 'Виберіть спеціальність',
    'faculty_sheet_title': 'Факультет / Спеціальність',
    'faculty_search_hint': 'Пошук…',
    'save_button': '✓ Зберегти',
    'info': 'Предмети та теми автоматично готуються на основі цього профілю.',
    'trial_text': 'Пробна · {n}/20 запусків · редаговано',
    'no_result': 'Немає результатів',
    'countries_count': 'країн',
  },
  // Filipince (Tagalog)
  'fil': {
    'title': 'Education Profile',
    'subtitle': 'Mga asignatura at tanong naka-tailor sa iyo',
    'country_label': 'BANSA',
    'country_placeholder': 'Pumili ng bansa',
    'country_sheet_title': 'Pumili ng Bansa',
    'country_search_hint': 'Hanapin ang bansa…',
    'level_label': 'ANTAS',
    'level_placeholder': 'Pumili ng antas',
    'level_sheet_title': 'Antas ng Edukasyon',
    'grade_label': 'BAITANG',
    'grade_placeholder': 'Pumili ng baitang',
    'grade_sheet_title': 'Baitang',
    'track_label': 'TRACK',
    'track_placeholder': 'Pumili ng track',
    'track_sheet_title': 'Track',
    'faculty_label': 'KOLEHIYO / KURSO',
    'faculty_placeholder': 'Pumili ng kurso',
    'faculty_sheet_title': 'Kolehiyo / Kurso',
    'faculty_search_hint': 'Maghanap…',
    'save_button': '✓ I-save at Magpatuloy',
    'info': 'Ang mga asignatura at paksa ay awtomatikong ihahanda batay sa profile.',
    'trial_text': 'Trial · {n}/20 launches · maaaring baguhin',
    'no_result': 'Walang resulta',
    'countries_count': 'bansa',
  },
  // Svahili (Kenya, Tanzanya)
  'sw': {
    'title': 'Wasifu wa Elimu',
    'subtitle': 'Masomo na maswali yameandaliwa kwa ajili yako',
    'country_label': 'NCHI',
    'country_placeholder': 'Chagua nchi',
    'country_sheet_title': 'Chagua Nchi',
    'country_search_hint': 'Tafuta nchi…',
    'level_label': 'KIWANGO CHA ELIMU',
    'level_placeholder': 'Chagua kiwango',
    'level_sheet_title': 'Kiwango cha Elimu',
    'grade_label': 'DARASA',
    'grade_placeholder': 'Chagua darasa',
    'grade_sheet_title': 'Darasa',
    'track_label': 'MKONDO',
    'track_placeholder': 'Chagua mkondo',
    'track_sheet_title': 'Mkondo',
    'faculty_label': 'KITIVO / SHAHADA',
    'faculty_placeholder': 'Chagua shahada',
    'faculty_sheet_title': 'Kitivo / Shahada',
    'faculty_search_hint': 'Tafuta…',
    'save_button': '✓ Hifadhi na Endelea',
    'info': 'Masomo na mada yataandaliwa kiotomatiki kulingana na wasifu huu.',
    'trial_text': 'Jaribio · {n}/20 uzinduzi · unaweza kuhaririwa',
    'no_result': 'Hakuna matokeo',
    'countries_count': 'nchi',
  },
  // Amharca (Etiyopya)
  'amh': {
    'title': 'የትምህርት መገለጫ',
    'subtitle': 'ትምህርቶች እና ጥያቄዎች ለእርስዎ ተዘጋጅተዋል',
    'country_label': 'ሀገር',
    'country_placeholder': 'ሀገር ይምረጡ',
    'country_sheet_title': 'ሀገር ይምረጡ',
    'country_search_hint': 'ሀገር ይፈልጉ…',
    'level_label': 'የትምህርት ደረጃ',
    'level_placeholder': 'ደረጃ ይምረጡ',
    'level_sheet_title': 'የትምህርት ደረጃ',
    'grade_label': 'ክፍል',
    'grade_placeholder': 'ክፍል ይምረጡ',
    'grade_sheet_title': 'ክፍል',
    'track_label': 'ዘርፍ',
    'track_placeholder': 'ዘርፍ ይምረጡ',
    'track_sheet_title': 'ዘርፍ',
    'faculty_label': 'ፋኩልቲ / ክፍል',
    'faculty_placeholder': 'ክፍል ይምረጡ',
    'faculty_sheet_title': 'ፋኩልቲ / ክፍል',
    'faculty_search_hint': 'ፈልግ…',
    'save_button': '✓ አስቀምጥ',
    'info': 'ትምህርቶች እና ርዕሶች በዚህ መገለጫ መሰረት በራስ ሰር ይዘጋጃሉ።',
    'trial_text': 'ሙከራ · {n}/20 ማስጀመሪያ · ሊስተካከል ይችላል',
    'no_result': 'ውጤት አልተገኘም',
    'countries_count': 'ሀገሮች',
  },
  // Burmaca
  'bur': {
    'title': 'ပညာရေး ကိုယ်ရေးအကျဉ်း',
    'subtitle': 'ဘာသာရပ်နှင့် မေးခွန်းများ သင့်အတွက် ပြင်ဆင်ပြီး',
    'country_label': 'နိုင်ငံ',
    'country_placeholder': 'နိုင်ငံ ရွေးချယ်ပါ',
    'country_sheet_title': 'နိုင်ငံ ရွေးချယ်ပါ',
    'country_search_hint': 'နိုင်ငံ ရှာ…',
    'level_label': 'ပညာရေးအဆင့်',
    'level_placeholder': 'အဆင့် ရွေးချယ်ပါ',
    'level_sheet_title': 'ပညာရေးအဆင့်',
    'grade_label': 'အတန်း',
    'grade_placeholder': 'အတန်း ရွေးချယ်ပါ',
    'grade_sheet_title': 'အတန်း',
    'track_label': 'ရပ်ဝန်း',
    'track_placeholder': 'ရပ်ဝန်း ရွေးပါ',
    'track_sheet_title': 'ရပ်ဝန်း',
    'faculty_label': 'ဌာန / အထူးပြု',
    'faculty_placeholder': 'ဘာသာရပ် ရွေးချယ်ပါ',
    'faculty_sheet_title': 'ဌာန',
    'faculty_search_hint': 'ရှာ…',
    'save_button': '✓ သိမ်း',
    'info': 'ဘာသာရပ်များနှင့် ခေါင်းစဉ်များ ကိုယ်ရေးအကျဉ်းအရ အလိုအလျောက် ပြင်ဆင်ပေးမည်။',
    'trial_text': 'စမ်းသုံးခြင်း · {n}/20 · ပြင်ဆင်နိုင်',
    'no_result': 'ရလဒ် မတွေ့ပါ',
    'countries_count': 'နိုင်ငံ',
  },
  // Nepalce
  'ne': {
    'title': 'शिक्षा प्रोफाइल',
    'subtitle': 'विषय र प्रश्नहरू तपाईंको लागि अनुकूलित',
    'country_label': 'देश',
    'country_placeholder': 'देश छान्नुहोस्',
    'country_sheet_title': 'देश छान्नुहोस्',
    'country_search_hint': 'देश खोज्नुहोस्…',
    'level_label': 'शिक्षा स्तर',
    'level_placeholder': 'स्तर छान्नुहोस्',
    'level_sheet_title': 'शिक्षा स्तर',
    'grade_label': 'कक्षा',
    'grade_placeholder': 'कक्षा छान्नुहोस्',
    'grade_sheet_title': 'कक्षा',
    'track_label': 'सङ्काय',
    'track_placeholder': 'सङ्काय छान्नुहोस्',
    'track_sheet_title': 'सङ्काय',
    'faculty_label': 'सङ्काय / विषय',
    'faculty_placeholder': 'विषय छान्नुहोस्',
    'faculty_sheet_title': 'सङ्काय',
    'faculty_search_hint': 'खोज्नुहोस्…',
    'save_button': '✓ सुरक्षित गर्नुहोस्',
    'info': 'यस प्रोफाइलका आधारमा विषयहरू स्वचालित रूपमा तयार हुनेछन्।',
    'trial_text': 'परीक्षण · {n}/20 प्रारम्भ · सम्पादन योग्य',
    'no_result': 'कुनै नतिजा छैन',
    'countries_count': 'देश',
  },
  // Özbekçe
  'uz': {
    'title': 'Taʼlim Profili',
    'subtitle': 'Fanlar va savollar siz uchun tayyorlanadi',
    'country_label': 'MAMLAKAT',
    'country_placeholder': 'Mamlakatni tanlang',
    'country_sheet_title': 'Mamlakatni Tanlang',
    'country_search_hint': 'Mamlakat qidirish…',
    'level_label': 'TAʼLIM DARAJASI',
    'level_placeholder': 'Darajani tanlang',
    'level_sheet_title': 'Taʼlim Darajasi',
    'grade_label': 'SINF',
    'grade_placeholder': 'Sinfni tanlang',
    'grade_sheet_title': 'Sinf',
    'track_label': 'YOʻNALISH',
    'track_placeholder': 'Yoʻnalish tanlang',
    'track_sheet_title': 'Yoʻnalish',
    'faculty_label': 'FAKULTET / YOʻNALISH',
    'faculty_placeholder': 'Yoʻnalish tanlang',
    'faculty_sheet_title': 'Fakultet',
    'faculty_search_hint': 'Qidirish…',
    'save_button': '✓ Saqlash va Davom Etish',
    'info': 'Fanlar va mavzular ushbu profilga asosan avtomatik tayyorlanadi.',
    'trial_text': 'Sinov · {n}/20 ishga tushirish · tahrirlash mumkin',
    'no_result': 'Natija topilmadi',
    'countries_count': 'mamlakat',
  },
};

/// Ülke kodundan UI sözlüğüne tek çağrılık erişim.
/// Öncelik: seçili ülkeden türeyen dil > aktif LocaleService dili > en > tr.
/// Böylece henüz ülke seçilmediğinde bile kullanıcının cihaz dili
/// veya IP'den türeyen dil metni sürücüye alınır.
String tui(String? country, String key) {
  String lang;
  if (country != null && _countryToLang.containsKey(country)) {
    lang = _countryToLang[country]!;
  } else {
    final active = localeService.localeCode;
    lang = _uiLocaleFromAppLocale(active);
  }
  return _ui[lang]?[key] ?? _ui['en']?[key] ?? _ui['tr']![key]!;
}

/// LocaleService'in 55-dil kodlarından `_ui` sözlüğünün anahtarlarına köprü.
/// `_ui` anahtarları `_countryToLang` ile aynı küme; bazı dil kodları
/// farklı (örn. locale 'uk' = Ukraynaca → _ui 'ukr').
String _uiLocaleFromAppLocale(String app) {
  switch (app) {
    case 'uk':
      return 'ukr';
    case 'my':
      return 'bur';
    case 'am':
      return 'amh';
    case 'tl':
      return 'fil';
    default:
      return app;
  }
}

class _LevelOpt {
  final String value;
  final String emoji;
  final String label;
  const _LevelOpt(this.value, this.emoji, this.label);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Ülke picker sheet — arama destekli tüm dünya ülkeleri listesi
// ═══════════════════════════════════════════════════════════════════════════════
class _CountryPickerSheet extends StatefulWidget {
  final String? currentCountry;
  const _CountryPickerSheet({this.currentCountry});
  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _normalize(String s) {
    const map = {
      'ş': 's', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ü': 'u', 'ç': 'c',
      'Ş': 's', 'Ğ': 'g', 'İ': 'i', 'Ö': 'o', 'Ü': 'u', 'Ç': 'c',
    };
    final sb = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  List<Country> _filtered() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return kAllCountries;
    final qn = _normalize(q);
    return kAllCountries.where((c) => _normalize(c.name).contains(qn)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _EducationSetupScreenState._bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _EducationSetupScreenState._inkMute,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text('🌍', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tui(widget.currentCountry, 'country_sheet_title'),
                        style: GoogleFonts.fraunces(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.02,
                          color: Colors.black,
                        )),
                  ),
                  Text(tui(widget.currentCountry, 'countries_count').replaceAll('{n}', '${kAllCountries.length}'),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _EducationSetupScreenState._inkMute,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _EducationSetupScreenState._surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _EducationSetupScreenState._line),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        size: 18, color: _EducationSetupScreenState._inkMute),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: tui(widget.currentCountry, 'country_search_hint'),
                          hintStyle: GoogleFonts.inter(
                            fontSize: 13,
                            color: _EducationSetupScreenState._inkMute,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    if (_searchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _searchCtrl.clear()),
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: _EducationSetupScreenState._inkMute),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(tui(widget.currentCountry, 'no_result'),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _EducationSetupScreenState._inkMute,
                            )),
                      ),
                    )
                  : ListView.separated(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => Navigator.pop(context, c.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _EducationSetupScreenState._line,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(c.flag, style: const TextStyle(fontSize: 22)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(c.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black,
                                        )),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Generic option picker sheet (seviye, sınıf, alan, fakülte için)
// ═══════════════════════════════════════════════════════════════════════════════
class _OptionPickerSheet extends StatefulWidget {
  final String title;
  final List<_LevelOpt> options;
  final bool searchable;
  final String? currentCountry;
  const _OptionPickerSheet({
    required this.title,
    required this.options,
    this.searchable = false,
    this.currentCountry,
  });

  @override
  State<_OptionPickerSheet> createState() => _OptionPickerSheetState();
}

class _OptionPickerSheetState extends State<_OptionPickerSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_LevelOpt> _filtered() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options
        .where((o) => o.label.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _EducationSetupScreenState._bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _EducationSetupScreenState._inkMute,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(widget.title,
                  style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.02,
                    color: Colors.black,
                  )),
            ),
            if (widget.searchable) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _EducationSetupScreenState._surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _EducationSetupScreenState._line),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded,
                          size: 18, color: _EducationSetupScreenState._inkMute),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            hintText: tui(widget.currentCountry, 'faculty_search_hint'),
                            hintStyle: GoogleFonts.inter(
                              fontSize: 13,
                              color: _EducationSetupScreenState._inkMute,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final o = filtered[i];
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.pop(context, o.value),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _EducationSetupScreenState._line,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(o.emoji, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(o.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  )),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
