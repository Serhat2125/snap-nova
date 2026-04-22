import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/runtime_translator.dart';
import '../services/education_profile.dart';
import '../services/gemini_service.dart';
import '../services/duelo_matchmaking_service.dart';
import '../widgets/qualsar_numeric_loader.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  QuAlsar Arena — Premium soru çözme ve sıralama arenası
//  Akış: Kurulum (ilk giriş) → Anasayfa → Sihirbaz → Yükleme → Quiz → Sonuç → Paylaş
//  Premium: Ülke & Dünya sıralaması, rozet sistemi, sınırsız test, özel kartlar
// ═══════════════════════════════════════════════════════════════════════════════

class _Palette {
  static const bg = Color(0xFFFAF7F2);
  static const ink = Color(0xFF0E0E10);
  static const inkSoft = Color(0xFF47474D);
  static const inkMute = Color(0xFF8B8B93);
  static const line = Color(0xFFE8E3DA);
  static const surface = Colors.white;
  static const brand = Color(0xFFFF5B2E);
  static const brandDeep = Color(0xFFE63E0F);
  static const accent = Color(0xFF2D5BFF);
  static const success = Color(0xFF10B981);
  static const error = Color(0xFFEF4444);
  static const warn = Color(0xFFF59E0B);
  static const math = Color(0xFF2D5BFF);
  static const physics = Color(0xFF8B5CF6);
  static const chem = Color(0xFF10B981);
  static const bio = Color(0xFFF59E0B);
  static const turkish = Color(0xFFEF4444);
  static const history = Color(0xFFA16207);
  static const geo = Color(0xFF0891B2);
  static const lit = Color(0xFFDB2777);
}

TextStyle _serif({double size = 16, FontWeight weight = FontWeight.w600, Color? color, double letterSpacing = -0.02, double? height}) {
  return GoogleFonts.fraunces(
    fontSize: size,
    fontWeight: weight,
    color: color ?? _Palette.ink,
    letterSpacing: letterSpacing,
    height: height,
  );
}

TextStyle _sans({double size = 14, FontWeight weight = FontWeight.w500, Color? color, double letterSpacing = -0.01, double? height}) {
  return GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    color: color ?? _Palette.ink,
    letterSpacing: letterSpacing,
    height: height,
  );
}

TextStyle _mono({double size = 12, FontWeight weight = FontWeight.w600, Color? color}) {
  return GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: weight,
    color: color ?? _Palette.ink,
  );
}

// ───────────────────────────────────────────────────────────────────────────────
//  Entry point — önce eğitim profili kontrolü; yoksa kurulum modalı açılır
// ───────────────────────────────────────────────────────────────────────────────
const _kPrefsEduProfileSet = 'mini_test_edu_profile_set';
const _kPrefsLevel = 'mini_test_level';
const _kPrefsGrade = 'mini_test_grade';
const _kPrefsTrack = 'mini_test_track';
const _kPrefsFaculty = 'mini_test_faculty';
const _kPrefsCountry = 'mini_test_country';
const _kPrefsOpenCount = 'qualsar_arena_open_count';
const _kPrefsQP = 'qualsar_arena_qp';
const _kPrefsMastery = 'qualsar_arena_mastery'; // json: {subjectKey|topic: 0-100}
const _kPrefsStreak = 'qualsar_arena_streak';
const _kPrefsLastPlay = 'qualsar_arena_last_play';
const _kPrefsPowerUps = 'qualsar_arena_powerups'; // json: {fiftyFifty: N, ...}
// Deneme süresi: ilk 10 giriş boyunca kurulum modalı her seferde gösterilir
const _kTrialEntries = 10;

// ═══════════════════════════════════════════════════════════════════════════════
//  ARENA STATE — QP, ustalık, power-up'lar, lig bilgisi
//  Modül düzeyinde; uygulama açık kaldığı sürece anlık erişim sağlar
// ═══════════════════════════════════════════════════════════════════════════════
class _ArenaStateStore {
  int qp = 0;
  int streak = 0;
  String? lastPlayDate; // YYYY-MM-DD
  // subjectKey|topic -> mastery percent (0-100)
  final Map<String, int> mastery = {};
  // Power-up envanteri
  int powerFiftyFifty = 3;
  int powerFreeze = 2;
  int powerSkip = 1;
  int powerDoublePoints = 1;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    qp = p.getInt(_kPrefsQP) ?? 120; // yeni kullanıcıya hoşgeldin bonusu
    streak = p.getInt(_kPrefsStreak) ?? 0;
    lastPlayDate = p.getString(_kPrefsLastPlay);
    mastery.clear();
    final mStr = p.getString(_kPrefsMastery);
    if (mStr != null && mStr.isNotEmpty) {
      try {
        final parsed = jsonDecode(mStr) as Map<String, dynamic>;
        parsed.forEach((k, v) {
          mastery[k] = (v as num).toInt();
        });
      } catch (_) {}
    }
    final pu = p.getString(_kPrefsPowerUps);
    if (pu != null && pu.isNotEmpty) {
      try {
        final m = jsonDecode(pu) as Map<String, dynamic>;
        powerFiftyFifty = (m['fiftyFifty'] as num?)?.toInt() ?? 3;
        powerFreeze = (m['freeze'] as num?)?.toInt() ?? 2;
        powerSkip = (m['skip'] as num?)?.toInt() ?? 1;
        powerDoublePoints = (m['double'] as num?)?.toInt() ?? 1;
      } catch (_) {}
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kPrefsQP, qp);
    await p.setInt(_kPrefsStreak, streak);
    if (lastPlayDate != null) await p.setString(_kPrefsLastPlay, lastPlayDate!);
    await p.setString(_kPrefsMastery, jsonEncode(mastery));
    await p.setString(
      _kPrefsPowerUps,
      jsonEncode({
        'fiftyFifty': powerFiftyFifty,
        'freeze': powerFreeze,
        'skip': powerSkip,
        'double': powerDoublePoints,
      }),
    );
  }

  // Testi bitirince çağır: skoru hesapla, QP ekle, ustalıkları güncelle, streak işle
  Future<void> onQuizCompleted({
    required List<_QuizQuestion> questions,
    required Map<int, int> answers,
    required int comboMax,
    required bool doublePoints,
  }) async {
    int correct = 0;
    final topicCorrects = <String, _Pair>{}; // "subjectKey|topic" -> Pair(correct,total)
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final isCorrect = answers[i] == q.correctIndex;
      if (isCorrect) correct++;
      final key = '${q.subjectKey}|${q.topic}';
      final pair = topicCorrects.putIfAbsent(key, () => _Pair(0, 0));
      pair.total += 1;
      if (isCorrect) pair.correct += 1;
    }

    // Ustalık güncelle: 70% ağırlık eski, 30% ağırlık yeni performans
    topicCorrects.forEach((key, p) {
      if (p.total == 0) return;
      final perf = ((p.correct / p.total) * 100).round();
      final prev = mastery[key] ?? 40; // default baseline
      final next = (prev * 0.7 + perf * 0.3).round().clamp(0, 100);
      mastery[key] = next;
    });

    // QP hesapla: temel (doğru*15) + combo bonus (5*combo) + bitirme bonus (20)
    int gained = correct * 15 + comboMax * 5 + 20;
    if (doublePoints) gained *= 2;
    qp += gained;

    // Streak işlemi
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (lastPlayDate == today) {
      // aynı gün, streak aynı kalır
    } else if (lastPlayDate != null) {
      final last = DateTime.tryParse(lastPlayDate!);
      if (last != null) {
        final diff = now.difference(last).inDays;
        if (diff == 1) {
          streak += 1;
        } else if (diff > 1) {
          streak = 1; // break
        }
      } else {
        streak = 1;
      }
    } else {
      streak = 1;
    }
    lastPlayDate = today;

    await save();
  }

  int get league {
    // QP'ye göre lig endeksi: 0=Bronz ... 5=Efsanevi
    if (qp < 200) return 0;
    if (qp < 600) return 1;
    if (qp < 1500) return 2;
    if (qp < 3500) return 3;
    if (qp < 7500) return 4;
    return 5;
  }

  int get masteryAverage {
    if (mastery.isEmpty) return 0;
    final sum = mastery.values.fold<int>(0, (a, b) => a + b);
    return (sum / mastery.length).round();
  }
}

class _Pair {
  int correct;
  int total;
  _Pair(this.correct, this.total);
}

// Global singleton — sayfa geçişlerinde değer korunur
final _arenaState = _ArenaStateStore();

class _LeagueInfo {
  final String name;
  final String emoji;
  final Color color;
  const _LeagueInfo(this.name, this.emoji, this.color);
}

const List<_LeagueInfo> _leagues = [
  _LeagueInfo('Bronz', '🥉', Color(0xFFCD7F32)),
  _LeagueInfo('Gümüş', '🥈', Color(0xFFBFC1C2)),
  _LeagueInfo('Altın', '🥇', Color(0xFFFFB800)),
  _LeagueInfo('Platin', '💠', Color(0xFF22D3EE)),
  _LeagueInfo('Elmas', '💎', Color(0xFF60A5FA)),
  _LeagueInfo('Efsanevi', '👑', Color(0xFFA855F7)),
];

class QuAlsarArenaScreen extends StatefulWidget {
  const QuAlsarArenaScreen({super.key});

  @override
  State<QuAlsarArenaScreen> createState() => _QuAlsarArenaScreenState();
}

class _QuAlsarArenaScreenState extends State<QuAlsarArenaScreen> {
  bool _loaded = false;
  bool _hasProfile = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();

    // Arena durumunu yükle (QP, ustalık, streak, power-up)
    await _arenaState.load();

    // Giriş sayısını artır (max 999 tut, gereksiz büyümesin)
    final prevCount = prefs.getInt(_kPrefsOpenCount) ?? 0;
    final newCount = prevCount >= 999 ? 999 : prevCount + 1;
    await prefs.setInt(_kPrefsOpenCount, newCount);

    final saved = prefs.getBool(_kPrefsEduProfileSet) ?? false;
    final inTrial = newCount <= _kTrialEntries;

    // Varsa kayıtlı profili önce uygula (arka planda anasayfa hazır olsun)
    Map<String, String?>? prefill;
    if (saved) {
      final country = prefs.getString(_kPrefsCountry);
      final level = prefs.getString(_kPrefsLevel);
      final grade = prefs.getString(_kPrefsGrade);
      final track = prefs.getString(_kPrefsTrack);
      final faculty = prefs.getString(_kPrefsFaculty);
      if (level != null && grade != null) {
        _applyProfile(country: country, level: level, grade: grade, track: track, faculty: faculty);
        prefill = {
          'country': country,
          'level': level,
          'grade': grade,
          'track': track,
          'faculty': faculty,
        };
      }
    }

    // Profil kayıtlı VE deneme süresi bitmiş → direkt ana ekran
    if (saved && !inTrial && prefill != null) {
      if (mounted) {
        setState(() {
          _hasProfile = true;
          _loaded = true;
        });
      }
      return;
    }

    // Aksi halde modal göster (ya profil yok, ya da deneme süresi devam ediyor)
    if (mounted) setState(() => _loaded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final result = await showDialog<Map<String, String?>>(
        context: context,
        barrierDismissible: saved, // kayıtlı profil varsa dışa tıklayarak kapanabilir
        builder: (_) => _EducationSetupDialog(
          initial: prefill,
          trialEntryNumber: inTrial ? newCount : 0,
        ),
      );
      if (result == null) {
        // Dialog iptal edildi
        if (saved) {
          // Kayıtlı profil zaten uygulandı → anasayfaya geç
          if (mounted) setState(() => _hasProfile = true);
        } else {
          // Profil yok + dialog kapatıldı → çık
          if (mounted) Navigator.of(context).pop();
        }
        return;
      }
      final country = result['country'];
      final level = result['level']!;
      final grade = result['grade']!;
      final track = result['track'];
      final faculty = result['faculty'];
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kPrefsEduProfileSet, true);
      await p.setString(_kPrefsLevel, level);
      await p.setString(_kPrefsGrade, grade);
      if (country != null) await p.setString(_kPrefsCountry, country);
      if (track != null) {
        await p.setString(_kPrefsTrack, track);
      } else {
        await p.remove(_kPrefsTrack);
      }
      if (faculty != null) {
        await p.setString(_kPrefsFaculty, faculty);
      } else {
        await p.remove(_kPrefsFaculty);
      }
      _applyProfile(country: country, level: level, grade: grade, track: track, faculty: faculty);
      if (mounted) setState(() => _hasProfile = true);
    });
  }

  void _applyProfile({
    String? country,
    required String level,
    required String grade,
    String? track,
    String? faculty,
  }) {
    _currentGrade = _formatGradeLabel(level: level, grade: grade, track: track, faculty: faculty);
    _currentLevel = level;
    _currentFaculty = faculty;
    if (country != null) {
      _currentCountryKey = country;
      final c = _findCountry(country);
      _currentCountry = c.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: _Palette.bg),
      child: !_loaded || !_hasProfile
          ? const Scaffold(backgroundColor: _Palette.bg, body: SizedBox.shrink())
          : const _ArenaHome(),
    );
  }
}

String _formatGradeLabel({required String level, required String grade, String? track, String? faculty}) {
  // Ülkeye göre dinamik etiket üretimi
  final lvl = _findLevel(_currentCountryKey, level);
  String gradeLabel = grade;
  if (lvl != null) {
    for (final g in lvl.grades) {
      if (g.value == grade) {
        gradeLabel = g.label;
        break;
      }
    }
  }
  final levelLabel = lvl?.label ?? level;

  // Legacy Türkiye anahtarlarını da destekle
  final universalKey = lvl?.universalKey ?? level;
  switch (universalKey) {
    case 'primary':
    case 'ilkokul':
      return '$levelLabel · $gradeLabel';
    case 'middle':
    case 'ortaokul':
      return '$levelLabel · $gradeLabel';
    case 'high':
    case 'lise':
      final trackLabel = _trackLabels[track] ?? '';
      return trackLabel.isEmpty
          ? '$levelLabel · $gradeLabel'
          : '$levelLabel · $gradeLabel · $trackLabel';
    case 'exam_prep':
    case 'sinav_hazirlik':
      return gradeLabel.isNotEmpty ? '$gradeLabel Hazırlığı' : 'Sınav Hazırlığı';
    case 'university':
    case 'universite':
      final f = _facultyLabels[faculty] ?? levelLabel;
      return '$f · $gradeLabel';
    case 'masters':
    case 'yuksek_lisans':
      final f = _facultyLabels[faculty] ?? 'Lisansüstü';
      return '$f · $levelLabel · $gradeLabel';
    case 'doctorate':
    case 'doktora':
      final f = _facultyLabels[faculty] ?? 'Doktora';
      return '$f · $levelLabel · $gradeLabel';
    case 'other':
    case 'diger':
      return gradeLabel;
    default:
      return '$levelLabel · $gradeLabel';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ÜLKE BAZLI EĞİTİM SİSTEMLERİ
//  Her ülkenin kendi seviye adları, sınıfları, alan tercihleri ve dersleri var.
//  MEB, Common Core, National Curriculum, KMK, Monbushō gibi resmi sistemler baz alındı.
// ═══════════════════════════════════════════════════════════════════════════════
class _EduCountry {
  final String key;
  final String name;
  final String flag;
  final List<_EduLevel> levels;
  const _EduCountry({required this.key, required this.name, required this.flag, required this.levels});
}

class _EduLevel {
  final String universalKey; // primary | middle | high | exam_prep | university | masters | doctorate | other
  final String emoji;
  final String label;
  final List<_GradeOpt> grades;
  final List<_PickerOption>? tracks;
  final bool needsFaculty;
  const _EduLevel({
    required this.universalKey,
    required this.emoji,
    required this.label,
    required this.grades,
    this.tracks,
    this.needsFaculty = false,
  });
}

class _GradeOpt {
  final String value;
  final String emoji;
  final String label;
  const _GradeOpt(this.value, this.emoji, this.label);
}

// Ortak hazır liste — sık kullanılan sınıf sayıları
const _gradesK5 = [
  _GradeOpt('K', '🎒', 'Kindergarten'),
  _GradeOpt('1', '1️⃣', 'Grade 1'),
  _GradeOpt('2', '2️⃣', 'Grade 2'),
  _GradeOpt('3', '3️⃣', 'Grade 3'),
  _GradeOpt('4', '4️⃣', 'Grade 4'),
  _GradeOpt('5', '5️⃣', 'Grade 5'),
];
const _gradesTr14 = [
  _GradeOpt('1', '1️⃣', '1. Sınıf'),
  _GradeOpt('2', '2️⃣', '2. Sınıf'),
  _GradeOpt('3', '3️⃣', '3. Sınıf'),
  _GradeOpt('4', '4️⃣', '4. Sınıf'),
];
const _tracksTr = [
  _PickerOption('sayisal', '🔬', 'Sayısal'),
  _PickerOption('sozel', '📖', 'Sözel'),
  _PickerOption('esit_agirlik', '⚖️', 'Eşit Ağırlık'),
  _PickerOption('dil', '🗣️', 'Dil'),
];
const _tracksUs = [
  _PickerOption('regular', '📘', 'Regular'),
  _PickerOption('honors', '🏅', 'Honors'),
  _PickerOption('ap', '🎓', 'AP / Advanced Placement'),
  _PickerOption('ib', '🌐', 'IB (International)'),
];
const _tracksUk = [
  _PickerOption('sciences', '🔬', 'Sciences'),
  _PickerOption('humanities', '📚', 'Humanities'),
  _PickerOption('languages', '🗣️', 'Languages'),
  _PickerOption('maths', '📐', 'Maths / Further Maths'),
];
const _tracksDe = [
  _PickerOption('naturwiss', '🔬', 'Naturwissenschaften (Fen)'),
  _PickerOption('sprachen', '🗣️', 'Sprachen (Dil)'),
  _PickerOption('gesell', '👥', 'Gesellschaftswiss. (Sosyal)'),
  _PickerOption('kunst', '🎨', 'Kunst / Musik'),
];
const _tracksFr = [
  _PickerOption('general', '📚', 'Bac Général'),
  _PickerOption('tech', '⚙️', 'Bac Technologique'),
  _PickerOption('pro', '🔧', 'Bac Professionnel'),
];
const _tracksJp = [
  _PickerOption('futsu', '📚', '普通科 Futsū (Genel)'),
  _PickerOption('senmon', '⚙️', '専門学科 Specialized'),
];
const _tracksIn = [
  _PickerOption('science', '🔬', 'Science (PCM/PCB)'),
  _PickerOption('commerce', '💰', 'Commerce'),
  _PickerOption('arts', '📖', 'Arts / Humanities'),
];

// Üniversite ve yukarı sınıflar (ortak)
const _gradesUniv = [
  _GradeOpt('hazirlik', '🔤', 'Hazırlık'),
  _GradeOpt('1', '1️⃣', '1. Sınıf'),
  _GradeOpt('2', '2️⃣', '2. Sınıf'),
  _GradeOpt('3', '3️⃣', '3. Sınıf'),
  _GradeOpt('4', '4️⃣', '4. Sınıf'),
  _GradeOpt('5', '5️⃣', '5. Sınıf'),
  _GradeOpt('6', '6️⃣', '6. Sınıf'),
  _GradeOpt('mezun', '🎓', 'Mezun'),
];
const _gradesMasters = [
  _GradeOpt('1donem', '1️⃣', '1. Dönem'),
  _GradeOpt('2donem', '2️⃣', '2. Dönem'),
  _GradeOpt('3donem', '3️⃣', '3. Dönem'),
  _GradeOpt('4donem', '4️⃣', '4. Dönem'),
  _GradeOpt('tez', '📝', 'Tez Aşaması'),
  _GradeOpt('mezun', '🎓', 'Mezun'),
];
const _gradesDoct = [
  _GradeOpt('ders', '📚', 'Ders Dönemi'),
  _GradeOpt('yeterlilik', '📋', 'Yeterlilik'),
  _GradeOpt('tez_oneri', '🧾', 'Tez Önerisi'),
  _GradeOpt('tez', '📝', 'Tez Aşaması'),
  _GradeOpt('mezun', '🎓', 'Mezun'),
];
const _gradesOther = [
  _GradeOpt('calisan', '💼', 'Çalışıyorum'),
  _GradeOpt('mezun', '🎓', 'Mezun'),
  _GradeOpt('serbest', '📖', 'Kişisel Gelişim'),
];

// Sınav hazırlık seçenekleri (ülkeye göre değişir)
const _examsTr = [
  _GradeOpt('lgs', '🏫', 'LGS'),
  _GradeOpt('yks_tyt', '🎯', 'YKS · TYT'),
  _GradeOpt('yks_ayt', '🎯', 'YKS · AYT'),
  _GradeOpt('yks_ydt', '🗣️', 'YKS · YDT'),
  _GradeOpt('kpss', '🏛️', 'KPSS'),
  _GradeOpt('ales', '📊', 'ALES'),
  _GradeOpt('dgs', '🔁', 'DGS'),
  _GradeOpt('yds', '🗣️', 'YDS / YÖKDİL'),
];
const _examsUs = [
  _GradeOpt('sat', '📝', 'SAT'),
  _GradeOpt('act', '📝', 'ACT'),
  _GradeOpt('ap', '🎓', 'AP Exams'),
  _GradeOpt('gre', '🧪', 'GRE'),
  _GradeOpt('gmat', '💼', 'GMAT'),
  _GradeOpt('mcat', '🩺', 'MCAT'),
  _GradeOpt('lsat', '⚖️', 'LSAT'),
  _GradeOpt('toefl', '🗣️', 'TOEFL'),
];
const _examsUk = [
  _GradeOpt('gcse', '📝', 'GCSE'),
  _GradeOpt('alevel', '🎓', 'A-Level'),
  _GradeOpt('ucat', '🩺', 'UCAT'),
  _GradeOpt('bmat', '🩺', 'BMAT'),
  _GradeOpt('ielts', '🗣️', 'IELTS'),
];
const _examsDe = [
  _GradeOpt('abitur', '🎓', 'Abitur'),
  _GradeOpt('mittlere_reife', '📝', 'Mittlere Reife'),
  _GradeOpt('testdaf', '🗣️', 'TestDaF'),
];
const _examsFr = [
  _GradeOpt('brevet', '📝', 'Brevet'),
  _GradeOpt('bac', '🎓', 'Baccalauréat'),
];
const _examsJp = [
  _GradeOpt('kotogakko_nyushi', '🏫', '高校入試'),
  _GradeOpt('daigaku_nyushi', '🎓', '大学入試 (共通テスト)'),
];
const _examsIn = [
  _GradeOpt('cbse10', '📝', 'CBSE Class 10 Board'),
  _GradeOpt('cbse12', '🎓', 'CBSE Class 12 Board'),
  _GradeOpt('jee', '⚙️', 'JEE Main/Advanced'),
  _GradeOpt('neet', '🩺', 'NEET'),
  _GradeOpt('upsc', '🏛️', 'UPSC'),
  _GradeOpt('gate', '📊', 'GATE'),
];

// Her ülkenin eğitim yapısı — levels listesi
final List<_EduCountry> _worldCountries = [
  _EduCountry(
    key: 'tr',
    name: 'Türkiye',
    flag: '🇹🇷',
    levels: [
      _EduLevel(
        universalKey: 'primary',
        emoji: '📚',
        label: 'İlkokul'.tr(),
        grades: _gradesTr14,
      ),
      _EduLevel(
        universalKey: 'middle',
        emoji: '🎒',
        label: 'Ortaokul',
        grades: [
          _GradeOpt('5', '5️⃣', '5. Sınıf'),
          _GradeOpt('6', '6️⃣', '6. Sınıf'),
          _GradeOpt('7', '7️⃣', '7. Sınıf'),
          _GradeOpt('8', '8️⃣', '8. Sınıf'),
        ],
      ),
      _EduLevel(
        universalKey: 'high',
        emoji: '🎓',
        label: 'Lise',
        grades: [
          _GradeOpt('9', '9️⃣', '9. Sınıf'),
          _GradeOpt('10', '🔟', '10. Sınıf'),
          _GradeOpt('11', '1️⃣1️⃣', '11. Sınıf'),
          _GradeOpt('12', '1️⃣2️⃣', '12. Sınıf'),
        ],
        tracks: _tracksTr,
      ),
      _EduLevel(
        universalKey: 'exam_prep',
        emoji: '🎯',
        label: 'Sınava Hazırlık'.tr(),
        grades: _examsTr,
      ),
      _EduLevel(
        universalKey: 'university',
        emoji: '🏛️',
        label: 'Üniversite'.tr(),
        grades: _gradesUniv,
        needsFaculty: true,
      ),
      _EduLevel(
        universalKey: 'masters',
        emoji: '📘',
        label: 'Yüksek Lisans'.tr(),
        grades: _gradesMasters,
        needsFaculty: true,
      ),
      _EduLevel(
        universalKey: 'doctorate',
        emoji: '🔬',
        label: 'Doktora',
        grades: _gradesDoct,
        needsFaculty: true,
      ),
      _EduLevel(
        universalKey: 'other',
        emoji: '🧭',
        label: 'Diğer'.tr(),
        grades: _gradesOther,
      ),
    ],
  ),
  _EduCountry(
    key: 'us',
    name: 'ABD',
    flag: '🇺🇸',
    levels: [
      _EduLevel(
        universalKey: 'primary',
        emoji: '📚',
        label: 'Elementary School',
        grades: _gradesK5,
      ),
      _EduLevel(
        universalKey: 'middle',
        emoji: '🎒',
        label: 'Middle School',
        grades: const [
          _GradeOpt('6', '6️⃣', 'Grade 6'),
          _GradeOpt('7', '7️⃣', 'Grade 7'),
          _GradeOpt('8', '8️⃣', 'Grade 8'),
        ],
      ),
      _EduLevel(
        universalKey: 'high',
        emoji: '🎓',
        label: 'High School',
        grades: const [
          _GradeOpt('9', '9️⃣', 'Freshman (9)'),
          _GradeOpt('10', '🔟', 'Sophomore (10)'),
          _GradeOpt('11', '1️⃣1️⃣', 'Junior (11)'),
          _GradeOpt('12', '1️⃣2️⃣', 'Senior (12)'),
        ],
        tracks: _tracksUs,
      ),
      _EduLevel(
        universalKey: 'exam_prep',
        emoji: '🎯',
        label: 'Test Prep',
        grades: _examsUs,
      ),
      _EduLevel(
        universalKey: 'university',
        emoji: '🏛️',
        label: 'College / University',
        grades: const [
          _GradeOpt('freshman', '1️⃣', 'Freshman'),
          _GradeOpt('sophomore', '2️⃣', 'Sophomore'),
          _GradeOpt('junior', '3️⃣', 'Junior'),
          _GradeOpt('senior', '4️⃣', 'Senior'),
          _GradeOpt('graduate', '🎓', 'Graduate'),
        ],
        needsFaculty: true,
      ),
      _EduLevel(universalKey: 'masters', emoji: '📘', label: "Master's Degree", grades: _gradesMasters, needsFaculty: true),
      _EduLevel(universalKey: 'doctorate', emoji: '🔬', label: 'PhD / Doctorate', grades: _gradesDoct, needsFaculty: true),
      _EduLevel(universalKey: 'other', emoji: '🧭', label: 'Other', grades: _gradesOther),
    ],
  ),
  _EduCountry(
    key: 'uk',
    name: 'Birleşik Krallık',
    flag: '🇬🇧',
    levels: [
      _EduLevel(
        universalKey: 'primary',
        emoji: '📚',
        label: 'Primary School',
        grades: const [
          _GradeOpt('1', '1️⃣', 'Year 1'),
          _GradeOpt('2', '2️⃣', 'Year 2'),
          _GradeOpt('3', '3️⃣', 'Year 3'),
          _GradeOpt('4', '4️⃣', 'Year 4'),
          _GradeOpt('5', '5️⃣', 'Year 5'),
          _GradeOpt('6', '6️⃣', 'Year 6'),
        ],
      ),
      _EduLevel(
        universalKey: 'middle',
        emoji: '🎒',
        label: 'Secondary (KS3)',
        grades: const [
          _GradeOpt('7', '7️⃣', 'Year 7'),
          _GradeOpt('8', '8️⃣', 'Year 8'),
          _GradeOpt('9', '9️⃣', 'Year 9'),
        ],
      ),
      _EduLevel(
        universalKey: 'high',
        emoji: '🎓',
        label: 'GCSE / Sixth Form',
        grades: const [
          _GradeOpt('10', '🔟', 'Year 10 (GCSE)'),
          _GradeOpt('11', '1️⃣1️⃣', 'Year 11 (GCSE)'),
          _GradeOpt('12', '1️⃣2️⃣', 'Year 12 (AS Level)'),
          _GradeOpt('13', '1️⃣3️⃣', 'Year 13 (A-Level)'),
        ],
        tracks: _tracksUk,
      ),
      _EduLevel(universalKey: 'exam_prep', emoji: '🎯', label: 'Exam Prep', grades: _examsUk),
      _EduLevel(
        universalKey: 'university',
        emoji: '🏛️',
        label: 'University',
        grades: const [
          _GradeOpt('1', '1️⃣', '1st Year'),
          _GradeOpt('2', '2️⃣', '2nd Year'),
          _GradeOpt('3', '3️⃣', '3rd Year'),
          _GradeOpt('4', '4️⃣', '4th Year'),
          _GradeOpt('graduate', '🎓', 'Graduate'),
        ],
        needsFaculty: true,
      ),
      _EduLevel(universalKey: 'masters', emoji: '📘', label: "Master's", grades: _gradesMasters, needsFaculty: true),
      _EduLevel(universalKey: 'doctorate', emoji: '🔬', label: 'PhD / DPhil', grades: _gradesDoct, needsFaculty: true),
      _EduLevel(universalKey: 'other', emoji: '🧭', label: 'Other', grades: _gradesOther),
    ],
  ),
  _EduCountry(
    key: 'de',
    name: 'Almanya',
    flag: '🇩🇪',
    levels: [
      _EduLevel(
        universalKey: 'primary',
        emoji: '📚',
        label: 'Grundschule',
        grades: const [
          _GradeOpt('1', '1️⃣', 'Klasse 1'),
          _GradeOpt('2', '2️⃣', 'Klasse 2'),
          _GradeOpt('3', '3️⃣', 'Klasse 3'),
          _GradeOpt('4', '4️⃣', 'Klasse 4'),
        ],
      ),
      _EduLevel(
        universalKey: 'middle',
        emoji: '🎒',
        label: 'Sekundarstufe I',
        grades: const [
          _GradeOpt('5', '5️⃣', 'Klasse 5'),
          _GradeOpt('6', '6️⃣', 'Klasse 6'),
          _GradeOpt('7', '7️⃣', 'Klasse 7'),
          _GradeOpt('8', '8️⃣', 'Klasse 8'),
          _GradeOpt('9', '9️⃣', 'Klasse 9'),
          _GradeOpt('10', '🔟', 'Klasse 10'),
        ],
      ),
      _EduLevel(
        universalKey: 'high',
        emoji: '🎓',
        label: 'Oberstufe (Gymnasium)',
        grades: const [
          _GradeOpt('11', '1️⃣1️⃣', 'Klasse 11'),
          _GradeOpt('12', '1️⃣2️⃣', 'Klasse 12'),
          _GradeOpt('13', '1️⃣3️⃣', 'Klasse 13'),
        ],
        tracks: _tracksDe,
      ),
      _EduLevel(universalKey: 'exam_prep', emoji: '🎯', label: 'Prüfungsvorbereitung'.tr(), grades: _examsDe),
      _EduLevel(
        universalKey: 'university',
        emoji: '🏛️',
        label: 'Universität'.tr(),
        grades: const [
          _GradeOpt('1', '1️⃣', 'Semester 1-2'),
          _GradeOpt('2', '2️⃣', 'Semester 3-4'),
          _GradeOpt('3', '3️⃣', 'Semester 5-6'),
          _GradeOpt('bachelor', '🎓', 'Bachelor Mezun'),
        ],
        needsFaculty: true,
      ),
      _EduLevel(universalKey: 'masters', emoji: '📘', label: 'Master', grades: _gradesMasters, needsFaculty: true),
      _EduLevel(universalKey: 'doctorate', emoji: '🔬', label: 'Promotion (PhD)', grades: _gradesDoct, needsFaculty: true),
      _EduLevel(universalKey: 'other', emoji: '🧭', label: 'Sonstige', grades: _gradesOther),
    ],
  ),
  _EduCountry(
    key: 'fr',
    name: 'Fransa',
    flag: '🇫🇷',
    levels: [
      _EduLevel(
        universalKey: 'primary',
        emoji: '📚',
        label: 'École primaire'.tr(),
        grades: const [
          _GradeOpt('cp', '1️⃣', 'CP'),
          _GradeOpt('ce1', '2️⃣', 'CE1'),
          _GradeOpt('ce2', '3️⃣', 'CE2'),
          _GradeOpt('cm1', '4️⃣', 'CM1'),
          _GradeOpt('cm2', '5️⃣', 'CM2'),
        ],
      ),
      _EduLevel(
        universalKey: 'middle',
        emoji: '🎒',
        label: 'Collège'.tr(),
        grades: const [
          _GradeOpt('6e', '6️⃣', 'Sixième'),
          _GradeOpt('5e', '5️⃣', 'Cinquième'),
          _GradeOpt('4e', '4️⃣', 'Quatrième'),
          _GradeOpt('3e', '3️⃣', 'Troisième'),
        ],
      ),
      _EduLevel(
        universalKey: 'high',
        emoji: '🎓',
        label: 'Lycée'.tr(),
        grades: const [
          _GradeOpt('2nde', '2️⃣', 'Seconde'),
          _GradeOpt('1ere', '1️⃣', 'Première'),
          _GradeOpt('term', 'Ⓣ', 'Terminale'),
        ],
        tracks: _tracksFr,
      ),
      _EduLevel(universalKey: 'exam_prep', emoji: '🎯', label: 'Examens', grades: _examsFr),
      _EduLevel(
        universalKey: 'university',
        emoji: '🏛️',
        label: 'Université'.tr(),
        grades: const [
          _GradeOpt('l1', '1️⃣', 'Licence 1'),
          _GradeOpt('l2', '2️⃣', 'Licence 2'),
          _GradeOpt('l3', '3️⃣', 'Licence 3'),
          _GradeOpt('m1', '4️⃣', 'Master 1'),
          _GradeOpt('m2', '5️⃣', 'Master 2'),
          _GradeOpt('mezun', '🎓', 'Diplômé'),
        ],
        needsFaculty: true,
      ),
      _EduLevel(universalKey: 'masters', emoji: '📘', label: 'Master', grades: _gradesMasters, needsFaculty: true),
      _EduLevel(universalKey: 'doctorate', emoji: '🔬', label: 'Doctorat', grades: _gradesDoct, needsFaculty: true),
      _EduLevel(universalKey: 'other', emoji: '🧭', label: 'Autre', grades: _gradesOther),
    ],
  ),
  _EduCountry(
    key: 'jp',
    name: 'Japonya',
    flag: '🇯🇵',
    levels: [
      _EduLevel(
        universalKey: 'primary',
        emoji: '📚',
        label: '小学校 Shōgakkō'.tr(),
        grades: const [
          _GradeOpt('1', '1️⃣', '1年生 (1)'),
          _GradeOpt('2', '2️⃣', '2年生'),
          _GradeOpt('3', '3️⃣', '3年生'),
          _GradeOpt('4', '4️⃣', '4年生'),
          _GradeOpt('5', '5️⃣', '5年生'),
          _GradeOpt('6', '6️⃣', '6年生'),
        ],
      ),
      _EduLevel(
        universalKey: 'middle',
        emoji: '🎒',
        label: '中学校 Chūgakkō'.tr(),
        grades: const [
          _GradeOpt('1', '1️⃣', '1年生'),
          _GradeOpt('2', '2️⃣', '2年生'),
          _GradeOpt('3', '3️⃣', '3年生'),
        ],
      ),
      _EduLevel(
        universalKey: 'high',
        emoji: '🎓',
        label: '高校 Kōkō'.tr(),
        grades: const [
          _GradeOpt('1', '1️⃣', '1年生'),
          _GradeOpt('2', '2️⃣', '2年生'),
          _GradeOpt('3', '3️⃣', '3年生'),
        ],
        tracks: _tracksJp,
      ),
      _EduLevel(universalKey: 'exam_prep', emoji: '🎯', label: '入試 Nyūshi'.tr(), grades: _examsJp),
      _EduLevel(
        universalKey: 'university',
        emoji: '🏛️',
        label: '大学 Daigaku'.tr(),
        grades: const [
          _GradeOpt('1', '1️⃣', '1年生'),
          _GradeOpt('2', '2️⃣', '2年生'),
          _GradeOpt('3', '3️⃣', '3年生'),
          _GradeOpt('4', '4️⃣', '4年生'),
          _GradeOpt('mezun', '🎓', '卒業'),
        ],
        needsFaculty: true,
      ),
      _EduLevel(universalKey: 'masters', emoji: '📘', label: '修士 Shūshi'.tr(), grades: _gradesMasters, needsFaculty: true),
      _EduLevel(universalKey: 'doctorate', emoji: '🔬', label: '博士 Hakase', grades: _gradesDoct, needsFaculty: true),
      _EduLevel(universalKey: 'other', emoji: '🧭', label: 'その他'.tr(), grades: _gradesOther),
    ],
  ),
  _EduCountry(
    key: 'in',
    name: 'Hindistan',
    flag: '🇮🇳',
    levels: [
      _EduLevel(
        universalKey: 'primary',
        emoji: '📚',
        label: 'Primary',
        grades: const [
          _GradeOpt('1', '1️⃣', 'Class 1'),
          _GradeOpt('2', '2️⃣', 'Class 2'),
          _GradeOpt('3', '3️⃣', 'Class 3'),
          _GradeOpt('4', '4️⃣', 'Class 4'),
          _GradeOpt('5', '5️⃣', 'Class 5'),
        ],
      ),
      _EduLevel(
        universalKey: 'middle',
        emoji: '🎒',
        label: 'Upper Primary',
        grades: const [
          _GradeOpt('6', '6️⃣', 'Class 6'),
          _GradeOpt('7', '7️⃣', 'Class 7'),
          _GradeOpt('8', '8️⃣', 'Class 8'),
        ],
      ),
      _EduLevel(
        universalKey: 'high',
        emoji: '🎓',
        label: 'Secondary / Higher',
        grades: const [
          _GradeOpt('9', '9️⃣', 'Class 9'),
          _GradeOpt('10', '🔟', 'Class 10 (Board)'),
          _GradeOpt('11', '1️⃣1️⃣', 'Class 11'),
          _GradeOpt('12', '1️⃣2️⃣', 'Class 12 (Board)'),
        ],
        tracks: _tracksIn,
      ),
      _EduLevel(universalKey: 'exam_prep', emoji: '🎯', label: 'Competitive Exams', grades: _examsIn),
      _EduLevel(
        universalKey: 'university',
        emoji: '🏛️',
        label: 'University (UG)',
        grades: const [
          _GradeOpt('1', '1️⃣', 'Year 1'),
          _GradeOpt('2', '2️⃣', 'Year 2'),
          _GradeOpt('3', '3️⃣', 'Year 3'),
          _GradeOpt('4', '4️⃣', 'Year 4'),
          _GradeOpt('graduate', '🎓', 'Graduate'),
        ],
        needsFaculty: true,
      ),
      _EduLevel(universalKey: 'masters', emoji: '📘', label: 'Masters (PG)', grades: _gradesMasters, needsFaculty: true),
      _EduLevel(universalKey: 'doctorate', emoji: '🔬', label: 'PhD', grades: _gradesDoct, needsFaculty: true),
      _EduLevel(universalKey: 'other', emoji: '🧭', label: 'Other', grades: _gradesOther),
    ],
  ),
  _EduCountry(
    key: 'international',
    name: 'Diğer / Uluslararası',
    flag: '🌐',
    levels: [
      _EduLevel(universalKey: 'primary', emoji: '📚', label: 'Primary / İlkokul'.tr(), grades: _gradesK5),
      _EduLevel(
        universalKey: 'middle',
        emoji: '🎒',
        label: 'Middle / Ortaokul',
        grades: const [
          _GradeOpt('6', '6️⃣', 'Grade 6'),
          _GradeOpt('7', '7️⃣', 'Grade 7'),
          _GradeOpt('8', '8️⃣', 'Grade 8'),
        ],
      ),
      _EduLevel(
        universalKey: 'high',
        emoji: '🎓',
        label: 'High / Lise',
        grades: const [
          _GradeOpt('9', '9️⃣', 'Grade 9'),
          _GradeOpt('10', '🔟', 'Grade 10'),
          _GradeOpt('11', '1️⃣1️⃣', 'Grade 11'),
          _GradeOpt('12', '1️⃣2️⃣', 'Grade 12'),
        ],
        tracks: const [
          _PickerOption('science', '🔬', 'Science / Sayısal'),
          _PickerOption('humanities', '📖', 'Humanities / Sözel'),
          _PickerOption('mixed', '⚖️', 'Mixed / Eşit Ağırlık'),
          _PickerOption('language', '🗣️', 'Language / Dil'),
        ],
      ),
      _EduLevel(universalKey: 'university', emoji: '🏛️', label: 'University / Üniversite'.tr(), grades: _gradesUniv, needsFaculty: true),
      _EduLevel(universalKey: 'masters', emoji: '📘', label: "Master's / Yüksek Lisans", grades: _gradesMasters, needsFaculty: true),
      _EduLevel(universalKey: 'doctorate', emoji: '🔬', label: 'Doctorate / Doktora', grades: _gradesDoct, needsFaculty: true),
      _EduLevel(universalKey: 'other', emoji: '🧭', label: 'Other / Diğer'.tr(), grades: _gradesOther),
    ],
  ),
];

// Ülkeye göre dersler - her ülkenin kendine özgü zorunlu dersleri var
// (Ortak evrensel dersler + ülkenin milli dili/tarihi/dini vb.)
final Map<String, Map<String, List<String>>> _countrySubjects = {
  // Türkiye: mevcut _gradeSubjectKeys kullanır (detaylı müfredat)
  'us': {
    'primary': ['math', 'turkish', 'sanat_muzik', 'beden', 'ingilizce'],
    'middle': ['math', 'physics', 'bio', 'history', 'geo', 'ingilizce', 'beden', 'sanat_muzik'],
    'high': ['math', 'physics', 'chem', 'bio', 'history', 'geo', 'lit', 'ingilizce', 'beden', 'sanat_muzik', 'psikoloji_dersi'],
    'university': ['math', 'physics', 'chem', 'bio', 'history', 'geo', 'lit', 'felsefe', 'psikoloji_dersi'],
  },
  'uk': {
    'primary': ['math', 'turkish', 'sanat_muzik', 'beden'],
    'middle': ['math', 'physics', 'bio', 'chem', 'history', 'geo', 'ingilizce', 'beden', 'sanat_muzik', 'din_kultur'],
    'high': ['math', 'physics', 'chem', 'bio', 'history', 'geo', 'lit', 'felsefe', 'ingilizce', 'beden', 'sanat_muzik', 'ikinci_dil', 'psikoloji_dersi'],
    'university': ['math', 'physics', 'chem', 'bio', 'history', 'lit', 'felsefe'],
  },
  'de': {
    'primary': ['math', 'turkish', 'sanat_muzik', 'beden', 'ingilizce'],
    'middle': ['math', 'physics', 'bio', 'chem', 'history', 'geo', 'ingilizce', 'beden', 'sanat_muzik', 'din_kultur', 'ikinci_dil'],
    'high': ['math', 'physics', 'chem', 'bio', 'history', 'geo', 'lit', 'felsefe', 'ingilizce', 'beden', 'sanat_muzik', 'ikinci_dil', 'psikoloji_dersi', 'sosyoloji'],
    'university': ['math', 'physics', 'chem', 'bio', 'history', 'lit', 'felsefe'],
  },
  'fr': {
    'primary': ['math', 'turkish', 'sanat_muzik', 'beden'],
    'middle': ['math', 'physics', 'bio', 'history', 'geo', 'ingilizce', 'ikinci_dil', 'beden', 'sanat_muzik'],
    'high': ['math', 'physics', 'chem', 'bio', 'history', 'geo', 'lit', 'felsefe', 'ingilizce', 'ikinci_dil', 'beden', 'sanat_muzik'],
    'university': ['math', 'physics', 'chem', 'bio', 'history', 'lit', 'felsefe'],
  },
  'jp': {
    'primary': ['math', 'turkish', 'sanat_muzik', 'beden'],
    'middle': ['math', 'physics', 'bio', 'history', 'geo', 'ingilizce', 'beden', 'sanat_muzik'],
    'high': ['math', 'physics', 'chem', 'bio', 'history', 'geo', 'lit', 'ingilizce', 'beden', 'sanat_muzik'],
    'university': ['math', 'physics', 'chem', 'bio', 'history', 'lit', 'felsefe'],
  },
  'in': {
    'primary': ['math', 'turkish', 'sanat_muzik', 'beden', 'ingilizce'],
    'middle': ['math', 'physics', 'bio', 'chem', 'history', 'geo', 'ingilizce', 'beden', 'sanat_muzik'],
    'high': ['math', 'physics', 'chem', 'bio', 'history', 'geo', 'lit', 'ingilizce', 'beden', 'sanat_muzik'],
    'university': ['math', 'physics', 'chem', 'bio', 'history', 'lit', 'felsefe'],
  },
  'international': {
    'primary': ['math', 'turkish', 'sanat_muzik', 'beden', 'ingilizce'],
    'middle': ['math', 'physics', 'bio', 'history', 'geo', 'ingilizce', 'beden', 'sanat_muzik'],
    'high': ['math', 'physics', 'chem', 'bio', 'history', 'geo', 'lit', 'ingilizce', 'felsefe', 'beden', 'sanat_muzik'],
    'university': ['math', 'physics', 'chem', 'bio', 'history', 'lit', 'felsefe'],
  },
};

_EduCountry _findCountry(String key) {
  for (final c in _worldCountries) {
    if (c.key == key) return c;
  }
  return _worldCountries.last; // international fallback
}

_EduLevel? _findLevel(String countryKey, String universalKey) {
  final country = _findCountry(countryKey);
  for (final l in country.levels) {
    if (l.universalKey == universalKey) return l;
  }
  return null;
}

const Map<String, String> _trackLabels = {
  'sayisal': 'Sayısal',
  'sozel': 'Sözel',
  'esit_agirlik': 'Eşit Ağırlık',
  'dil': 'Dil',
};

// Türkiye YÖK bölümleri — popülerliğe göre sıralı (üstte en çok tercih edilenler)
const List<_PickerOption> _allDepartments = [
  // ─── Sağlık (en çok tercih edilen grup)
  _PickerOption('tip', '🩺', 'Tıp'),
  _PickerOption('dis_hekimligi', '🦷', 'Diş Hekimliği'),
  _PickerOption('eczacilik', '💊', 'Eczacılık'),
  _PickerOption('veteriner', '🐾', 'Veterinerlik'),
  _PickerOption('hukuk', '⚖️', 'Hukuk'),
  _PickerOption('psikoloji', '🧠', 'Psikoloji'),
  _PickerOption('rehberlik', '🧭', 'Rehberlik ve Psikolojik Danışmanlık'),
  // ─── Mühendislik (en popüler)
  _PickerOption('bilgisayar_muh', '💻', 'Bilgisayar Mühendisliği'),
  _PickerOption('yazilim_muh', '💾', 'Yazılım Mühendisliği'),
  _PickerOption('elektrik_elektronik_muh', '⚡', 'Elektrik-Elektronik Mühendisliği'),
  _PickerOption('endustri_muh', '📊', 'Endüstri Mühendisliği'),
  _PickerOption('makine_muh', '🔧', 'Makine Mühendisliği'),
  _PickerOption('insaat_muh', '🏗️', 'İnşaat Mühendisliği'),
  _PickerOption('mekatronik_muh', '🛠️', 'Mekatronik Mühendisliği'),
  _PickerOption('biyomedikal_muh', '🧬', 'Biyomedikal Mühendisliği'),
  _PickerOption('havacilik_muh', '✈️', 'Havacılık ve Uzay Mühendisliği'),
  _PickerOption('otomotiv_muh', '🚗', 'Otomotiv Mühendisliği'),
  _PickerOption('elektronik_haberlesme_muh', '📡', 'Elektronik ve Haberleşme Mühendisliği'),
  _PickerOption('kimya_muh', '⚗️', 'Kimya Mühendisliği'),
  _PickerOption('gida_muh', '🍞', 'Gıda Mühendisliği'),
  _PickerOption('cevre_muh', '🌳', 'Çevre Mühendisliği'),
  _PickerOption('maden_muh', '⛏️', 'Maden Mühendisliği'),
  _PickerOption('jeoloji_muh', '⛰️', 'Jeoloji Mühendisliği'),
  _PickerOption('petrol_muh', '🛢️', 'Petrol ve Doğalgaz Mühendisliği'),
  _PickerOption('tekstil_muh', '👕', 'Tekstil Mühendisliği'),
  _PickerOption('gemi_muh', '⛵', 'Gemi İnşaatı ve Gemi Makineleri Müh.'),
  _PickerOption('harita_muh', '🗺️', 'Harita Mühendisliği (Geomatik)'),
  _PickerOption('metalurji_muh', '🔩', 'Metalurji ve Malzeme Mühendisliği'),
  _PickerOption('orman_muh', '🌲', 'Orman Mühendisliği'),
  _PickerOption('ziraat_muh', '🌾', 'Ziraat Mühendisliği'),
  // ─── Mimarlık / Tasarım
  _PickerOption('mimarlik', '🏛️', 'Mimarlık'),
  _PickerOption('ic_mimarlik', '🛋️', 'İç Mimarlık'),
  _PickerOption('sehir_planlama', '🏙️', 'Şehir ve Bölge Planlama'),
  _PickerOption('peyzaj_mimarligi', '🌿', 'Peyzaj Mimarlığı'),
  _PickerOption('endustri_tasarim', '🏭', 'Endüstri Ürünleri Tasarımı'),
  // ─── Sağlık Bilimleri (Tıp dışı)
  _PickerOption('fizyoterapi', '🏃', 'Fizyoterapi ve Rehabilitasyon'),
  _PickerOption('hemsirelik', '👩‍⚕️', 'Hemşirelik'),
  _PickerOption('beslenme_diyetetik', '🥗', 'Beslenme ve Diyetetik'),
  _PickerOption('ebelik', '👶', 'Ebelik'),
  _PickerOption('odyoloji', '👂', 'Odyoloji'),
  _PickerOption('cocuk_gelisimi', '🧸', 'Çocuk Gelişimi'),
  _PickerOption('sosyal_hizmet', '🤝', 'Sosyal Hizmet'),
  _PickerOption('dil_konusma_terapisi', '🗣️', 'Dil ve Konuşma Terapisi'),
  // ─── İktisadi / İdari / Sosyal
  _PickerOption('isletme', '📘', 'İşletme'),
  _PickerOption('iktisat', '💰', 'İktisat / Ekonomi'),
  _PickerOption('uluslararasi_iliskiler', '🌍', 'Uluslararası İlişkiler'),
  _PickerOption('siyaset_bilimi', '🗳️', 'Siyaset Bilimi'),
  _PickerOption('kamu_yonetimi', '🏛️', 'Kamu Yönetimi'),
  _PickerOption('bankacilik_finans', '🏦', 'Bankacılık ve Finans'),
  _PickerOption('uluslararasi_ticaret', '🚚', 'Uluslararası Ticaret ve Lojistik'),
  _PickerOption('ekonometri', '📈', 'Ekonometri'),
  _PickerOption('istatistik', '📉', 'İstatistik'),
  _PickerOption('aktuerya', '💹', 'Aktüerya'),
  _PickerOption('sigortacilik', '🛡️', 'Sigortacılık'),
  // ─── İletişim / Medya / Sanat
  _PickerOption('gazetecilik', '📰', 'Gazetecilik'),
  _PickerOption('halkla_iliskiler', '🎤', 'Halkla İlişkiler ve Tanıtım'),
  _PickerOption('reklamcilik', '📢', 'Reklamcılık'),
  _PickerOption('radyo_tv_sinema', '📺', 'Radyo, TV ve Sinema'),
  _PickerOption('gorsel_iletisim', '🖼️', 'Görsel İletişim Tasarımı'),
  _PickerOption('grafik_tasarim', '🎨', 'Grafik Tasarım'),
  _PickerOption('fotograf', '📸', 'Fotoğraf'),
  _PickerOption('moda_tasarim', '👗', 'Moda Tasarımı'),
  _PickerOption('sinema_tv', '🎥', 'Sinema ve Televizyon'),
  _PickerOption('tiyatro', '🎭', 'Tiyatro / Sahne Sanatları'),
  _PickerOption('muzik', '🎵', 'Müzik'),
  _PickerOption('muzikoloji', '🎹', 'Müzikoloji'),
  _PickerOption('resim', '🖌️', 'Resim'),
  _PickerOption('heykel', '🗿', 'Heykel'),
  _PickerOption('seramik', '🏺', 'Seramik'),
  // ─── Fen / Edebiyat
  _PickerOption('matematik', '📐', 'Matematik'),
  _PickerOption('fizik', '⚛️', 'Fizik'),
  _PickerOption('kimya', '🧪', 'Kimya'),
  _PickerOption('biyoloji', '🧬', 'Biyoloji'),
  _PickerOption('turk_dili_edebiyat', '📚', 'Türk Dili ve Edebiyatı'),
  _PickerOption('ingiliz_dili_edebiyat', '🇬🇧', 'İngiliz Dili ve Edebiyatı'),
  _PickerOption('alman_dili_edebiyat', '🇩🇪', 'Alman Dili ve Edebiyatı'),
  _PickerOption('fransiz_dili_edebiyat', '🇫🇷', 'Fransız Dili ve Edebiyatı'),
  _PickerOption('arap_dili_edebiyat', '🕌', 'Arap Dili ve Edebiyatı'),
  _PickerOption('mutercim_tercumanlik', '🌐', 'Mütercim-Tercümanlık'),
  _PickerOption('tarih', '🏛️', 'Tarih'),
  _PickerOption('cografya', '🌍', 'Coğrafya'),
  _PickerOption('felsefe', '🤔', 'Felsefe'),
  _PickerOption('sosyoloji', '👥', 'Sosyoloji'),
  _PickerOption('arkeoloji', '🏺', 'Arkeoloji'),
  _PickerOption('sanat_tarihi', '🖼️', 'Sanat Tarihi'),
  _PickerOption('antropoloji', '🧍', 'Antropoloji'),
  // ─── Eğitim / Öğretmenlik
  _PickerOption('sinif_ogretmenligi', '🎒', 'Sınıf Öğretmenliği'),
  _PickerOption('okul_oncesi', '🧸', 'Okul Öncesi Öğretmenliği'),
  _PickerOption('ozel_egitim', '📕', 'Özel Eğitim Öğretmenliği'),
  _PickerOption('turkce_ogretmen', '🖋️', 'Türkçe Öğretmenliği'),
  _PickerOption('matematik_ogretmen', '📗', 'Matematik Öğretmenliği'),
  _PickerOption('fen_bilgisi_ogretmen', '🔬', 'Fen Bilgisi Öğretmenliği'),
  _PickerOption('sosyal_bilgiler_ogretmen', '🌏', 'Sosyal Bilgiler Öğretmenliği'),
  _PickerOption('ingilizce_ogretmen', '🔤', 'İngilizce Öğretmenliği'),
  _PickerOption('din_kulturu_ogretmen', '📿', 'Din Kültürü Öğretmenliği'),
  _PickerOption('beden_egitimi_ogretmen', '🏃', 'Beden Eğitimi Öğretmenliği'),
  // ─── Din / İlahiyat
  _PickerOption('ilahiyat', '🕋', 'İlahiyat'),
  // ─── Turizm / Spor
  _PickerOption('turizm_isletmeciligi', '🏨', 'Turizm İşletmeciliği'),
  _PickerOption('gastronomi', '🍳', 'Gastronomi ve Mutfak Sanatları'),
  _PickerOption('otel_yoneticiligi', '🏖️', 'Otel Yöneticiliği'),
  _PickerOption('antrenorluk', '🏋️', 'Antrenörlük Eğitimi'),
  _PickerOption('spor_yoneticiligi', '🏊', 'Spor Yöneticiliği'),
  // ─── Denizcilik
  _PickerOption('denizcilik_isletme', '🌊', 'Deniz Ulaştırma İşletme Müh.'),
  _PickerOption('guverte', '⚓', 'Güverte'),
  // ─── Hukuk / İdari
  _PickerOption('adalet', '⚖️', 'Adalet MYO'),
  // ─── Diğer
  _PickerOption('diger', '🧭', 'Diğer Bölüm'),
];

final Map<String, String> _facultyLabels = {
  for (final d in _allDepartments) d.value: d.label,
};

// ═══════════════════════════════════════════════════════════════════════════════
//  EĞİTİM KURULUM DIALOG — ilk girişte açılır, kaydet → bir daha çıkmaz
// ═══════════════════════════════════════════════════════════════════════════════
class _EducationSetupDialog extends StatefulWidget {
  final Map<String, String?>? initial;
  final int trialEntryNumber; // 0 = deneme değil, 1-10 = N. giriş
  const _EducationSetupDialog({this.initial, this.trialEntryNumber = 0});

  @override
  State<_EducationSetupDialog> createState() => _EducationSetupDialogState();
}

class _EducationSetupDialogState extends State<_EducationSetupDialog> {
  String _country = 'tr';
  String? _level; // universal key: primary | middle | high | exam_prep | university | masters | doctorate | other
  String? _grade;
  String? _track;
  String? _faculty;

  String? _openPicker; // 'country' | 'level' | 'grade' | 'track' | 'faculty'

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _country = init['country'] ?? 'tr';
      // Eski kayıtlardaki (Türkiye'ye özgü) level keys → universal
      _level = _legacyLevelToUniversal(init['level']);
      _grade = init['grade'];
      _track = init['track'];
      _faculty = init['faculty'];
    }
  }

  // Eski Türkiye spesifik anahtarları universal key'lere çevir
  String? _legacyLevelToUniversal(String? legacy) {
    switch (legacy) {
      case 'ilkokul': return 'primary';
      case 'ortaokul': return 'middle';
      case 'lise': return 'high';
      case 'sinav_hazirlik': return 'exam_prep';
      case 'universite': return 'university';
      case 'yuksek_lisans': return 'masters';
      case 'doktora': return 'doctorate';
      case 'diger': return 'other';
      default: return legacy; // zaten universal ise geç
    }
  }

  List<_PickerOption> _countries() {
    return [
      for (final c in _worldCountries) _PickerOption(c.key, c.flag, c.name),
    ];
  }

  _EduCountry get _eduCountry => _findCountry(_country);

  List<_PickerOption> _levels() {
    return [
      for (final l in _eduCountry.levels) _PickerOption(l.universalKey, l.emoji, l.label),
    ];
  }

  List<_PickerOption> _gradeOptions() {
    final l = _findLevel(_country, _level ?? '');
    if (l == null) return const [];
    return [
      for (final g in l.grades) _PickerOption(g.value, g.emoji, g.label),
    ];
  }

  List<_PickerOption> _tracks() {
    final l = _findLevel(_country, _level ?? '');
    return l?.tracks ?? const [];
  }

  final List<_PickerOption> _faculties = _allDepartments;

  bool get _needsFaculty {
    final l = _findLevel(_country, _level ?? '');
    return l?.needsFaculty ?? false;
  }

  bool get _needsTrack {
    final l = _findLevel(_country, _level ?? '');
    return (l?.tracks ?? const []).isNotEmpty;
  }

  bool get _canSave {
    if (_level == null || _grade == null) return false;
    if (_needsTrack && _track == null) return false;
    if (_needsFaculty && _faculty == null) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _Palette.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('🎓'.tr(), style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Eğitim seviyeni seç',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _serif(size: 18, weight: FontWeight.w700, letterSpacing: -0.02),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Sana uygun dersler ve konular otomatik olarak hazırlanır.',
                style: _sans(size: 11, color: _Palette.inkMute, height: 1.3),
              ),
              if (widget.trialEntryNumber > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _Palette.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _Palette.accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🧪'.tr(), style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Deneme sürümü · ${widget.trialEntryNumber}/10 giriş',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sans(size: 11, weight: FontWeight.w700, color: _Palette.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Ülke seçici (en üstte, eğitim sistemini belirler)
              _ExpandablePicker(
                label: 'ÜLKEN'.tr(),
                placeholder: 'Ülkeni seç',
                options: _countries(),
                selectedValue: _country,
                expanded: _openPicker == 'country',
                listMaxHeight: 280,
                onExpand: () => setState(() => _openPicker = _openPicker == 'country' ? null : 'country'),
                onSelect: (v) {
                  setState(() {
                    if (_country != v) {
                      _country = v;
                      // Ülke değişince alt seçimleri sıfırla (sistem farklı)
                      _level = null;
                      _grade = null;
                      _track = null;
                      _faculty = null;
                    }
                    _openPicker = null;
                  });
                },
              ),
              const SizedBox(height: 10),
              // Seviye seçici — ülkeye göre (İlkokul/Elementary/Grundschule vb.)
              _ExpandablePicker(
                label: 'EĞİTİM SEVİYESİ'.tr(),
                placeholder: 'Seviyeni seç',
                options: _levels(),
                selectedValue: _level,
                expanded: _openPicker == 'level',
                onExpand: () => setState(() => _openPicker = _openPicker == 'level' ? null : 'level'),
                onSelect: (v) {
                  setState(() {
                    if (_level != v) {
                      _level = v;
                      _grade = null;
                      _track = null;
                      _faculty = null;
                    }
                    _openPicker = null;
                  });
                },
              ),
              // Fakülte/Bölüm seçici — Üniversite, Yüksek Lisans, Doktora için
              if (_needsFaculty) ...[
                const SizedBox(height: 10),
                _ExpandablePicker(
                  label: _level == 'university' ? 'FAKÜLTEN / BÖLÜMÜN' : 'PROGRAM ALANI',
                  placeholder: _level == 'university' ? 'Bölümünü seç' : 'Program alanını seç',
                  options: _faculties,
                  selectedValue: _faculty,
                  expanded: _openPicker == 'faculty',
                  listMaxHeight: 360,
                  searchable: true,
                  searchPlaceholder: 'Bölüm ara…',
                  onExpand: () => setState(() => _openPicker = _openPicker == 'faculty' ? null : 'faculty'),
                  onSelect: (v) => setState(() {
                    _faculty = v;
                    _openPicker = null;
                  }),
                ),
              ],
              // Sınıf/Dönem seçici — ülkeye göre (örn. Grade 10, Year 11, Klasse 10)
              if (_level != null && (!_needsFaculty || _faculty != null)) ...[
                const SizedBox(height: 10),
                _ExpandablePicker(
                  label: 'SINIFIN',
                  placeholder: 'Sınıfını seç',
                  options: _gradeOptions(),
                  selectedValue: _grade,
                  expanded: _openPicker == 'grade',
                  onExpand: () => setState(() => _openPicker = _openPicker == 'grade' ? null : 'grade'),
                  onSelect: (v) => setState(() {
                    _grade = v;
                    _openPicker = null;
                  }),
                ),
              ],
              // Alan/Track seçici — ülkeye göre (Sayısal/Sözel vs. AP/Honors vs. Leistungskurse)
              if (_needsTrack && _grade != null) ...[
                const SizedBox(height: 10),
                _ExpandablePicker(
                  label: 'ALANIN',
                  placeholder: 'Alanını seç',
                  options: _tracks(),
                  selectedValue: _track,
                  expanded: _openPicker == 'track',
                  onExpand: () => setState(() => _openPicker = _openPicker == 'track' ? null : 'track'),
                  onSelect: (v) => setState(() {
                    _track = v;
                    _openPicker = null;
                  }),
                ),
              ],

              const SizedBox(height: 18),
              _PrimaryButton(
                label: '✓ Kaydet ve Başla'.tr(),
                brand: true,
                onTap: _canSave
                    ? () {
                        Navigator.of(context).pop(<String, String?>{
                          'country': _country,
                          'level': _level!,
                          'grade': _grade!,
                          'track': _track,
                          'faculty': _faculty,
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Vazgeç'.tr(),
                      style: _sans(size: 12, weight: FontWeight.w600, color: _Palette.inkMute)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerOption {
  final String value;
  final String emoji;
  final String label;
  const _PickerOption(this.value, this.emoji, this.label);
}

class _ExpandablePicker extends StatefulWidget {
  final String label;
  final String placeholder;
  final List<_PickerOption> options;
  final String? selectedValue;
  final bool expanded;
  final VoidCallback onExpand;
  final ValueChanged<String> onSelect;
  /// null = doğal yükseklik (tüm seçenekler görünür).
  /// değer verilirse liste bu yükseklikle sınırlı olur ve iç scroll oluşur.
  final double? listMaxHeight;
  /// true ise liste üstünde arama kutusu gösterilir.
  final bool searchable;
  final String searchPlaceholder;
  const _ExpandablePicker({
    required this.label,
    required this.placeholder,
    required this.options,
    required this.selectedValue,
    required this.expanded,
    required this.onExpand,
    required this.onSelect,
    this.listMaxHeight,
    this.searchable = false,
    this.searchPlaceholder = 'Ara…',
  });

  @override
  State<_ExpandablePicker> createState() => _ExpandablePickerState();
}

class _ExpandablePickerState extends State<_ExpandablePicker> {
  final _searchCtrl = TextEditingController();

  @override
  void didUpdateWidget(covariant _ExpandablePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Picker kapandığında aramayı sıfırla
    if (oldWidget.expanded && !widget.expanded) {
      _searchCtrl.clear();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  _PickerOption? _findSelected() {
    if (widget.selectedValue == null) return null;
    for (final o in widget.options) {
      if (o.value == widget.selectedValue) return o;
    }
    return null;
  }

  List<_PickerOption> _filteredOptions() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options.where((o) {
      final label = _stripDiacritics(o.label.toLowerCase());
      final query = _stripDiacritics(q);
      return label.contains(query);
    }).toList();
  }

  // Türkçe karakter normalizasyonu (ş → s, ğ → g, ...) — arama için
  String _stripDiacritics(String s) {
    const map = {
      'ş': 's', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ü': 'u', 'ç': 'c',
      'Ş': 's', 'Ğ': 'g', 'İ': 'i', 'Ö': 'o', 'Ü': 'u', 'Ç': 'c',
    };
    final sb = StringBuffer();
    for (final ch in s.split('')) {
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final sel = _findSelected();
    final filtered = _filteredOptions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: widget.onExpand,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _Palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.expanded ? _Palette.brand : _Palette.line,
                width: widget.expanded ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                if (sel != null)
                  Text(sel.emoji, style: const TextStyle(fontSize: 18))
                else
                  Icon(Icons.expand_more_rounded, size: 18, color: _Palette.inkMute),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sel?.label ?? widget.placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(
                      size: 14,
                      weight: sel != null ? FontWeight.w700 : FontWeight.w500,
                      color: sel != null ? _Palette.ink : _Palette.inkMute,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: widget.expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: widget.expanded ? _Palette.brand : _Palette.inkMute),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: widget.expanded
              ? Container(
                  margin: const EdgeInsets.only(top: 6),
                  constraints: widget.listMaxHeight != null
                      ? BoxConstraints(maxHeight: widget.listMaxHeight!)
                      : null,
                  decoration: BoxDecoration(
                    color: _Palette.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _Palette.line),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.searchable) _buildSearchField(),
                      Flexible(
                        child: filtered.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('🔍'.tr(), style: TextStyle(fontSize: 18)),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Sonuç bulunamadı',
                                      style: _sans(size: 13, color: _Palette.inkMute),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: widget.listMaxHeight != null
                                    ? const ClampingScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    Divider(height: 1, color: _Palette.line.withValues(alpha: 0.5)),
                                itemBuilder: (_, i) {
                                  final o = filtered[i];
                                  final isSel = o.value == widget.selectedValue;
                                  return InkWell(
                                    onTap: () => widget.onSelect(o.value),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(
                                        children: [
                                          Text(o.emoji, style: const TextStyle(fontSize: 18)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              o.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: _sans(
                                                size: 14,
                                                weight: isSel ? FontWeight.w700 : FontWeight.w500,
                                                color: isSel ? _Palette.brand : _Palette.ink,
                                              ),
                                            ),
                                          ),
                                          if (isSel)
                                            const Icon(Icons.check_rounded, size: 18, color: _Palette.brand),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _Palette.line.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _Palette.bg,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.search_rounded, size: 16, color: _Palette.inkMute),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              style: _sans(size: 13, weight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: widget.searchPlaceholder,
                hintStyle: _sans(size: 13, color: _Palette.inkMute),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _searchCtrl.clear()),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: _Palette.inkMute),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  HOME
// ═══════════════════════════════════════════════════════════════════════════════
class _ArenaHome extends StatefulWidget {
  const _ArenaHome();

  @override
  State<_ArenaHome> createState() => _ArenaHomeState();
}

class _ArenaHomeState extends State<_ArenaHome> {
  // Kişinin kütüphanesindeki görünür dersler (başlangıçta tüm 8 ders)
  late List<String> _visibleSubjectKeys;
  // Seçili dersler
  final Set<String> _selectedSubjects = {};
  // Kişinin gerçekten test oluşturduğu dersler (swap mantığı için)
  final Set<String> _createdQuestionSubjects = {};
  // Görünür liste üst sınır — bu sınıra ulaşıldığında swap devreye girer
  static const int _visibleLimit = 10;

  @override
  void initState() {
    super.initState();
    _visibleSubjectKeys = _subjectsForGrade().map((s) => s.key).toList();
  }

  Future<void> _toggleSelect(String key) async {
    // Dil dersleri için önce dil seçici aç (seçili değilse veya dil atanmamışsa)
    if (_isLanguagePickerSubject(key) && !_selectedSubjects.contains(key)) {
      final lang = await _showLanguagePickerSheet(context);
      if (lang == null) return;
      _chosenLanguage[key] = lang;
    }
    setState(() {
      if (_selectedSubjects.contains(key)) {
        _selectedSubjects.remove(key);
      } else {
        _selectedSubjects.add(key);
      }
    });
  }

  Future<void> _confirmRemove(_Subject subject) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Bu dersi kaldır?'.tr(), style: _serif(size: 18, weight: FontWeight.w600)),
        content: Text(
          '${subject.emoji} ${subject.name} kütüphanenden kaldırılacak. İstediğin zaman tekrar ekleyebilirsin.',
          style: _sans(size: 13, color: _Palette.inkSoft, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Vazgeç'.tr(), style: _sans(size: 13, weight: FontWeight.w600, color: _Palette.inkMute)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Kaldır'.tr(), style: _sans(size: 13, weight: FontWeight.w700, color: _Palette.error)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _visibleSubjectKeys.remove(subject.key);
        _selectedSubjects.remove(subject.key);
      });
    }
  }

  Future<void> _addSubjectSheet() async {
    final available = _allSubjects.where((s) => !_visibleSubjectKeys.contains(s.key)).toList();
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddSubjectSheet(available: available),
    );
    if (result != null) {
      setState(() {
        _visibleSubjectKeys.add(result);
      });
    }
  }

  void _openWizardWithSelection() {
    if (_selectedSubjects.isEmpty) return;
    // Kullanıcı bu derslerden soru/test oluşturma akışına girdi →
    // "soru oluşturulmuş" setine ekle. Bu sayede gelecekteki
    // Diğer Dersler swap'ında bu dersler kaldırılmaz.
    _createdQuestionSubjects.addAll(_selectedSubjects);
    final cfg = _WizardConfig()..selectedSubjects = _selectedSubjects.toSet();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _CreateWizard(cfg: cfg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    _CircleBtn(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_Palette.brand, Color(0xFFFF8F4C)],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text('A', style: _sans(size: 16, weight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('QuAlsar Arena',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _serif(size: 19, weight: FontWeight.w700, letterSpacing: -0.03)),
                          const SizedBox(height: 1),
                          Text('Merhaba Ahmet, yarış başlasın!'.tr(), style: _sans(size: 12, color: _Palette.inkMute)),
                        ],
                      ),
                    ),
                    _BellButton(onTap: () => _showNotificationsSheet(context)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildSubjectsCard(),
              const SizedBox(height: 14),
              const _DueloCard(),
              const SizedBox(height: 18),
              const _FriendsSection(),
              const SizedBox(height: 18),
              const _MasterySection(),
              _BadgesSectionTitle(
                onInfoTap: () => _showBadgesInfoSheet(context),
                onRankingsTap: () => _showRankingsSheet(context),
              ),
              const _BadgesScroll(),
              const SizedBox(height: 16),
              const _WrappedCard(),
              const SizedBox(height: 18),
              // QP / Seri / Lig en alta
              const _StatsRow(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _Palette.line),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Hangi dersten soru çözmek istersin?',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _serif(size: 17, weight: FontWeight.w600, letterSpacing: -0.02, height: 1.25),
                ),
              ),
              if (_selectedSubjects.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _Palette.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${_selectedSubjects.length} seçili',
                    style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.brand),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _Palette.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🎓'.tr(), style: TextStyle(fontSize: 10)),
                    const SizedBox(width: 4),
                    Text(
                      _currentGrade,
                      style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'seviyesine göre dersler ve konular hazır.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(size: 11, color: _Palette.inkMute),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSubjectsGrid(),
          const SizedBox(height: 14),
          _PrimaryButton(
            label: 'Devam Et',
            brand: true,
            trailingIcon: Icons.arrow_forward_rounded,
            onTap: _selectedSubjects.isEmpty ? null : _openWizardWithSelection,
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectsGrid() {
    final visible = _allSubjects.where((s) => _visibleSubjectKeys.contains(s.key)).toList();
    final top10 = visible.take(8).toList();
    final hasMore = visible.length > 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.0,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final s in top10)
              _MiniSubjectTile(
                subject: s,
                selected: _selectedSubjects.contains(s.key),
                onTap: () => _toggleSelect(s.key),
                onLongPress: () => _confirmRemove(s),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _OtherSubjectsButton(
                onTap: _showOtherSubjectsSheet,
                highlight: hasMore || _hasHiddenSubjects(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AddSubjectInlineButton(onTap: _addSubjectSheet),
            ),
          ],
        ),
      ],
    );
  }

  bool _hasHiddenSubjects() {
    return _allSubjects.any((s) => !_visibleSubjectKeys.contains(s.key));
  }

  Future<void> _showOtherSubjectsSheet() async {
    final visible = _allSubjects.where((s) => _visibleSubjectKeys.contains(s.key)).toList();
    final overflowList = visible.skip(8).toList();
    final hidden = _allSubjects.where((s) => !_visibleSubjectKeys.contains(s.key)).toList();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => _OtherSubjectsSheet(
        overflow: overflowList,
        hidden: hidden,
        selectedKeys: _selectedSubjects,
        usedKeys: _createdQuestionSubjects,
        onToggleSelect: (key) => _toggleSelect(key),
        onAddToVisible: (key) {
          // Otomatik swap: görünür sınırı aşılmışsa, kullanılmamış bir
          // dersi Diğer Dersler'e kaydır.
          setState(() {
            if (!_visibleSubjectKeys.contains(key)) {
              _visibleSubjectKeys.add(key);
              if (_visibleSubjectKeys.length > _visibleLimit) {
                // Yeni eklenen hariç, kullanılmamış (soru oluşturulmamış)
                // ilk dersi kaldır.
                final victim = _visibleSubjectKeys.firstWhere(
                  (k) =>
                      k != key &&
                      !_createdQuestionSubjects.contains(k),
                  orElse: () => '',
                );
                if (victim.isNotEmpty) {
                  _visibleSubjectKeys.remove(victim);
                  _selectedSubjects.remove(victim);
                }
              }
            }
          });
          // Sheet'i kapat ki kullanıcı hemen ana sayfada görsün
          Navigator.of(sheetCtx).pop();
        },
        onRemoveFromVisible: (key) {
          setState(() {
            _visibleSubjectKeys.remove(key);
            _selectedSubjects.remove(key);
          });
        },
      ),
    );
    if (mounted) setState(() {});
  }
}

class _MiniSubjectTile extends StatelessWidget {
  final _Subject subject;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _MiniSubjectTile({
    required this.subject,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected ? _Palette.bg : _Palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _Palette.ink : _Palette.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isLanguagePickerSubject(subject.key) && _chosenLanguage[subject.key] != null
                          ? _chosenLanguage[subject.key]!.emoji
                          : subject.emoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLanguagePickerSubject(subject.key) && _chosenLanguage[subject.key] != null
                          ? _chosenLanguage[subject.key]!.label
                          : subject.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(size: 11, weight: FontWeight.w600, height: 1.15),
                    ),
                  ],
                ),
              ),
            ),
            if (selected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _Palette.ink,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Diğer Dersler butonu — 10 dersin altında solda
class _OtherSubjectsButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool highlight;
  const _OtherSubjectsButton({required this.onTap, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Palette.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('📚'.tr(), style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Diğer Dersler',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(size: 12, weight: FontWeight.w700),
              ),
            ),
            if (highlight) ...[
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _Palette.brand,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Ders Ekle satır-içi buton — 10 dersin altında sağda
class _AddSubjectInlineButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSubjectInlineButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _Palette.brand.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Palette.brand.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, size: 16, color: _Palette.brand),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Ders Ekle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(size: 12, weight: FontWeight.w700, color: _Palette.brand),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Diğer Dersler sheet — görünür sınırı aşanlar + gizlenenler
class _OtherSubjectsSheet extends StatefulWidget {
  final List<_Subject> overflow; // görünür listenin 10+'si
  final List<_Subject> hidden; // tamamen gizlenmişler
  final Set<String> selectedKeys;
  final Set<String> usedKeys; // soru oluşturulmuş dersler
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<String> onAddToVisible;
  final ValueChanged<String> onRemoveFromVisible;

  const _OtherSubjectsSheet({
    required this.overflow,
    required this.hidden,
    required this.selectedKeys,
    required this.usedKeys,
    required this.onToggleSelect,
    required this.onAddToVisible,
    required this.onRemoveFromVisible,
  });

  @override
  State<_OtherSubjectsSheet> createState() => _OtherSubjectsSheetState();
}

class _OtherSubjectsSheetState extends State<_OtherSubjectsSheet> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Diğer Dersler'.tr(),
                style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
            const SizedBox(height: 4),
            Text(
              'Başlangıçta gösterilmeyen dersler. Tıkla seç, basılı tut kaldır, + ile ana listene al.',
              style: _sans(size: 12, color: _Palette.inkMute, height: 1.4),
            ),
            if (widget.overflow.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('KÜTÜPHANENDE'.tr(),
                  style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
              const SizedBox(height: 8),
              for (final s in widget.overflow)
                _otherRow(
                  s,
                  isVisible: true,
                  isSelected: widget.selectedKeys.contains(s.key),
                ),
            ],
            if (widget.hidden.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('EKLENMEMİŞ DERSLER'.tr(),
                  style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
              const SizedBox(height: 8),
              for (final s in widget.hidden)
                _otherRow(
                  s,
                  isVisible: false,
                  isSelected: false,
                ),
            ],
            if (widget.overflow.isEmpty && widget.hidden.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('Tüm dersler ana listende görünüyor 🎉'.tr(),
                      style: _sans(size: 13, color: _Palette.inkMute)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _otherRow(_Subject s, {required bool isVisible, required bool isSelected}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        // Görünür satırda tek tıkla seç / gizliyse tek tıkla ana sayfaya ekle.
        onTap: isVisible
            ? () {
                widget.onToggleSelect(s.key);
                setState(() {});
              }
            : () {
                // Otomatik ekleme — swap ana ekranda olur, sheet kapanır.
                widget.onAddToVisible(s.key);
              },
        onLongPress: isVisible
            ? () {
                widget.onRemoveFromVisible(s.key);
                setState(() {});
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _Palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? _Palette.ink : _Palette.line,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(s.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(size: 14, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      isVisible
                          ? (isSelected
                              ? '✓ Seçili · basılı tut: kaldır'.tr()
                              : 'Tıkla: seç · basılı tut: kaldır'.tr())
                          : 'Tıkla: ana sayfaya ekle'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(size: 10, color: _Palette.inkMute),
                    ),
                  ],
                ),
              ),
              if (!isVisible)
                const Icon(Icons.north_east_rounded,
                    size: 18, color: _Palette.ink)
              else if (isSelected)
                const Icon(Icons.check_rounded,
                    size: 18, color: _Palette.ink),
            ],
          ),
        ),
      ),
    );
  }
}


class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: _Palette.brand.withValues(alpha: 0.4), radius: 14, dashWidth: 5, dashSpace: 4, strokeWidth: 1.5),
      child: Container(
        padding: const EdgeInsets.all(6),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashSpace;
  final double strokeWidth;
  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashSpace,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final extract = metric.extractPath(distance, distance + dashWidth);
        canvas.drawPath(extract, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  YENİ DERS EKLE SHEET — mevcut listeden seç veya kendi dersini yaz
// ═══════════════════════════════════════════════════════════════════════════════
class _AddSubjectSheet extends StatefulWidget {
  final List<_Subject> available;
  const _AddSubjectSheet({required this.available});

  @override
  State<_AddSubjectSheet> createState() => _AddSubjectSheetState();
}

class _AddSubjectSheetState extends State<_AddSubjectSheet> {
  final _ctrl = TextEditingController();
  String _selectedEmoji = '📘';
  final List<String> _emojiChoices = const ['📘', '📗', '📕', '📙', '🎨', '🎵', '🌐', '⚙️', '🧩', '🗂️'];
  final List<Color> _colorPalette = const [
    Color(0xFF2D5BFF),
    Color(0xFF10B981),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFFDB2777),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _slugify(String name) {
    final lower = name.toLowerCase().trim();
    final cleaned = lower.replaceAll(RegExp(r'[^a-zA-ZğüşıöçĞÜŞİÖÇ0-9]+'), '_');
    return 'custom_${cleaned}_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _properCase(String name) {
    // "matemAtik" → "Matematik"; ilk harf büyük, kalanı olduğu gibi
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    final parts = trimmed.split(RegExp(r'\s+'));
    return parts
        .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
  }

  void _saveCustom() {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) return;
    final name = _properCase(raw);
    final color = _colorPalette[_allSubjects.length % _colorPalette.length];
    final key = _slugify(raw);
    final newSubject = _Subject(key, _selectedEmoji, name, 0, color, const []);
    _allSubjects.add(newSubject);
    Navigator.of(context).pop(key);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Yeni Bir Ders Ekle',
                style: _serif(size: 20, weight: FontWeight.w600, letterSpacing: -0.02)),
            const SizedBox(height: 4),
            Text('Hazır listeden seç ya da kendi ders adını yaz.'.tr(),
                style: _sans(size: 12, color: _Palette.inkMute)),
            const SizedBox(height: 18),

            // Kendi dersini yaz
            Text('KENDİN YAZ'.tr(),
                style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
            const SizedBox(height: 8),
            Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    final picked = await showModalBottomSheet<String>(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _EmojiPickerSheet(choices: _emojiChoices, selected: _selectedEmoji),
                    );
                    if (picked != null) setState(() => _selectedEmoji = picked);
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _Palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _Palette.line),
                    ),
                    alignment: Alignment.center,
                    child: Text(_selectedEmoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 24,
                    style: _sans(size: 14, weight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Örn: Felsefe'.tr(),
                      hintStyle: _sans(size: 13, color: _Palette.inkMute),
                      filled: true,
                      fillColor: _Palette.surface,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _Palette.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _Palette.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _Palette.brand, width: 1.5),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _saveCustom(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _PrimaryButton(
              label: 'Kaydet',
              brand: true,
              onTap: _ctrl.text.trim().isEmpty ? null : _saveCustom,
            ),

            if (widget.available.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('HAZIR LİSTE'.tr(),
                  style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
              const SizedBox(height: 8),
              for (final s in widget.available)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, s.key),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _Palette.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _Palette.line),
                    ),
                    child: Row(
                      children: [
                        Text(s.emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _sans(size: 14, weight: FontWeight.w600)),
                        ),
                        Icon(Icons.add_rounded, size: 20, color: s.color),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmojiPickerSheet extends StatelessWidget {
  final List<String> choices;
  final String selected;
  const _EmojiPickerSheet({required this.choices, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: _Palette.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Bir ikon seç'.tr(),
              style: _serif(size: 18, weight: FontWeight.w600, letterSpacing: -0.02)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final e in choices)
                GestureDetector(
                  onTap: () => Navigator.pop(context, e),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _Palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: e == selected ? _Palette.ink : _Palette.line,
                        width: e == selected ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(e, style: const TextStyle(fontSize: 24)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _BellButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _Palette.surface,
              border: Border.all(color: _Palette.line),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.notifications_none_rounded, size: 20, color: _Palette.ink),
          ),
          Positioned(
            top: 8,
            right: 10,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: _Palette.brand,
                shape: BoxShape.circle,
                border: Border.all(color: _Palette.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Bildirimler sheet — tıklayınca açılır
void _showNotificationsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('🔔'.tr(), style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Bildirimler',
                      style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _Palette.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text('3 yeni',
                      style: _sans(size: 10, weight: FontWeight.w800, color: _Palette.brand)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _notifItem('🏆', '@deniz.k seni haftalık sıralamada geçti', '12 dk önce', true),
            _notifItem('🎯', 'Yeni yarışma daveti — @elif_m', '1 saat önce', true),
            _notifItem('🔥', 'Serini koru! Bugün hiç test çözmedin', '3 saat önce', true),
            _notifItem('🎁', 'Haftalık Wrapped kartın hazır', 'Dün'),
            _notifItem('👑', '1 hafta önce Bilgi Ustası rozeti kazandın', '1 hafta önce'),
            _notifItem("🎯", "Türev'de 3 test üst üste %90+ yaptın", '2 hafta önce'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _Palette.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _Palette.line),
              ),
              child: Row(
                children: [
                  const Text('⚙️', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bildirim tercihlerini ayarlar menüsünden belirleyebilirsin.',
                      style: _sans(size: 11, color: _Palette.inkSoft, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _notifItem(String emoji, String text, String time, [bool unread = false]) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unread ? _Palette.brand.withValues(alpha: 0.06) : _Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unread ? _Palette.brand.withValues(alpha: 0.3) : _Palette.line,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _Palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _Palette.line),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(size: 13, weight: FontWeight.w600, height: 1.3)),
                const SizedBox(height: 2),
                Text(time, style: _sans(size: 10, color: _Palette.inkMute)),
              ],
            ),
          ),
          if (unread) ...[
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: _Palette.brand,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _Palette.surface,
          border: Border.all(color: _Palette.line),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: _Palette.ink),
      ),
    );
  }
}


class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    final league = _leagues[_arenaState.league];
    final stats = [
      (
        '${_arenaState.qp}',
        'QP',
        '⚡',
        _Palette.warn,
      ),
      (
        '${_arenaState.streak}',
        'Günlük Seri',
        '🔥',
        _Palette.brand,
      ),
      (
        league.name,
        'Lig',
        league.emoji,
        league.color,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (int i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: _Palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Palette.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(stats[i].$3, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            stats[i].$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _serif(
                              size: 20,
                              weight: FontWeight.w800,
                              letterSpacing: -0.03,
                              height: 1,
                              color: stats[i].$4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stats[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(size: 10, weight: FontWeight.w600, color: _Palette.inkMute),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════════
//  DÜELLO — 1v1 mock ekran (gerçek matchmaking backend'e kalacak)
// ═══════════════════════════════════════════════════════════════════════════════
class _DueloCard extends StatelessWidget {
  const _DueloCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DueloLobbyScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _Palette.ink,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: _Palette.ink.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFB800), Color(0xFFFF5B2E)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text('🏆'.tr(), style: TextStyle(fontSize: 34)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('Bilgi Yarışı'.tr(),
                            style: _sans(size: 16, weight: FontWeight.w800, color: Colors.white, letterSpacing: -0.01)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _Palette.error,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text('CANLI',
                                  style: _sans(size: 8, weight: FontWeight.w800, color: Colors.white, letterSpacing: 0.1)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ülkende ve dünyada kendi seviyendeki öğrencilerle canlı bilgi yarışına katıl. Aynı soruları aynı anda çöz, kim daha hızlı?',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(size: 12, color: Colors.white.withValues(alpha: 0.78), height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// Dünya çapında düello için evrensel dersler — çoğu ülkede ortak müfredat
// Yalnızca Türkçe dili/edebiyatı ve Türkiye tarihi dile/kültüre bağımlı olduğu için dahil değil.
final List<_Subject> _globalDueloSubjects = [
  // Temel bilimler
  const _Subject('math', '📐', 'Matematik', 8, _Palette.math, [
    'Cebir', 'Geometri', 'Sayılar', 'Olasılık', 'Trigonometri', 'Fonksiyonlar', 'Türev', 'İntegral',
  ]),
  const _Subject('physics', '⚛️', 'Fizik', 6, _Palette.physics, [
    'Kuvvet ve Hareket', 'Enerji', 'Elektrik', 'Optik', 'Dalgalar', 'Modern Fizik',
  ]),
  const _Subject('chem', '🧪', 'Kimya', 5, _Palette.chem, [
    'Atom', 'Periyodik Sistem', 'Kimyasal Bağlar', 'Tepkimeler', 'Asit-Baz',
  ]),
  const _Subject('bio', '🧬', 'Biyoloji', 5, _Palette.bio, [
    'Hücre', 'Genetik', 'Evrim', 'Ekoloji', 'İnsan Fizyolojisi',
  ]),
  // Sosyal bilimler (evrensel)
  const _Subject('philosophy', '🤔', 'Felsefe', 5, Color(0xFF7C3AED), [
    'Ahlak Felsefesi', 'Bilgi Felsefesi', 'Varlık Felsefesi', 'Mantık', 'Politik Felsefe',
  ]),
  const _Subject('world_history', '📜', 'Dünya Tarihi', 6, Color(0xFFA16207), [
    'Antik Çağ', 'Orta Çağ', 'Rönesans', 'Sanayi Devrimi', 'Dünya Savaşları', 'Soğuk Savaş',
  ]),
  const _Subject('world_geo', '🌍', 'Dünya Coğrafyası', 5, Color(0xFF0891B2), [
    'Kıtalar ve Okyanuslar', 'Haritalar', 'İklimler', 'Bayraklar ve Başkentler', 'Doğal Afetler',
  ]),
  // Diller
  const _Subject('english', '🇬🇧', 'İngilizce', 6, Color(0xFF2563EB), [
    'Grammar', 'Vocabulary', 'Reading', 'Writing', 'Listening', 'Idioms',
  ]),
  const _Subject('other_langs', '🗣️', 'Diğer Diller', 4, Color(0xFF1D4ED8), [
    'İspanyolca', 'Fransızca', 'Almanca', 'Çince', 'Arapça',
  ]),
  // Sanat & kültür
  const _Subject('music', '🎵', 'Müzik', 5, Color(0xFFDB2777), [
    'Notalar', 'Enstrümanlar', 'Müzik Tarihi', 'Teori', 'Klasik Besteciler',
  ]),
  const _Subject('visual_arts', '🎨', 'Görsel Sanatlar & Resim', 5, Color(0xFFEC4899), [
    'Renk Teorisi', 'Sanat Akımları', 'Ünlü Eserler', 'Kompozisyon', 'Sanat Tarihi',
  ]),
  // Teknik
  const _Subject('tech_cs', '💻', 'Teknoloji & Bilgisayar', 5, Color(0xFF0F766E), [
    'Donanım', 'Yazılım', 'İnternet', 'Ağlar', 'Siber Güvenlik',
  ]),
  const _Subject('coding', '⌨️', 'Kodlama & Yazılım', 6, Color(0xFF4F46E5), [
    'Algoritmalar', 'Değişkenler', 'Döngüler', 'Veri Yapıları', 'Web', 'Python',
  ]),
  // Yaşamsal beceriler
  const _Subject('citizenship', '🏛️', 'Vatandaşlık', 4, Color(0xFF0369A1), [
    'İnsan Hakları', 'Demokrasi', 'Anayasal Haklar', 'Küresel Vatandaşlık',
  ]),
  const _Subject('ethics', '⚖️', 'Ahlak', 4, Color(0xFF7C2D12), [
    'Değerler', 'Etik İlkeler', 'Erdemler', 'Ahlaki İkilemler',
  ]),
  const _Subject('pe', '⚽', 'Beden Eğitimi', 4, _Palette.success, [
    'Spor Kuralları', 'Olimpiyatlar', 'Sağlıklı Yaşam', 'Anatomi',
  ]),
  const _Subject('finance', '💰', 'Finans Okuryazarlığı', 5, Color(0xFFFFB800), [
    'Bütçe', 'Yatırım', 'Kredi', 'Tasarruf', 'Ekonomi Temelleri',
  ]),
  const _Subject('entrepreneur', '🚀', 'Girişimcilik', 5, Color(0xFFEF4444), [
    'İş Planı', 'Pazarlama', 'Liderlik', 'İnovasyon', 'Ünlü Girişimciler',
  ]),
  const _Subject('media_lit', '📰', 'Medya Okuryazarlığı', 4, Color(0xFF8B5CF6), [
    'Haber Analizi', 'Sosyal Medya', 'Dezenformasyon', 'Reklamcılık',
  ]),
  const _Subject('psychology', '🧠', 'Psikoloji', 5, Color(0xFFDB2777), [
    'Duygular', 'Stres Yönetimi', 'Kişilik', 'Bilişsel Çarpıtmalar', 'Uyku',
  ]),
  const _Subject('life_skills', '🎯', 'Yaşam Becerileri', 4, Color(0xFFF59E0B), [
    'Zaman Yönetimi', 'İletişim', 'Karar Verme', 'Problem Çözme',
  ]),
];

// Kullanıcının eklediği özel dünya dersleri (oturum boyu korunur)
final List<_Subject> _customWorldSubjects = [];

// Dünyada en çok konuşulan 20 dil — ikinci yabancı dil / diğer diller picker'ı
const List<_PickerOption> _topLanguages = [
  _PickerOption('en', '🇬🇧', 'İngilizce'),
  _PickerOption('zh', '🇨🇳', 'Çince (Mandarin)'),
  _PickerOption('hi', '🇮🇳', 'Hintçe'),
  _PickerOption('es', '🇪🇸', 'İspanyolca'),
  _PickerOption('fr', '🇫🇷', 'Fransızca'),
  _PickerOption('ar', '🇸🇦', 'Arapça'),
  _PickerOption('bn', '🇧🇩', 'Bengalce'),
  _PickerOption('ru', '🇷🇺', 'Rusça'),
  _PickerOption('pt', '🇵🇹', 'Portekizce'),
  _PickerOption('ur', '🇵🇰', 'Urduca'),
  _PickerOption('id', '🇮🇩', 'Endonezce'),
  _PickerOption('de', '🇩🇪', 'Almanca'),
  _PickerOption('ja', '🇯🇵', 'Japonca'),
  _PickerOption('tr', '🇹🇷', 'Türkçe'),
  _PickerOption('ko', '🇰🇷', 'Korece'),
  _PickerOption('it', '🇮🇹', 'İtalyanca'),
  _PickerOption('vi', '🇻🇳', 'Vietnamca'),
  _PickerOption('fa', '🇮🇷', 'Farsça'),
  _PickerOption('th', '🇹🇭', 'Tayca'),
  _PickerOption('nl', '🇳🇱', 'Hollandaca'),
];

// Dil dersleri için kullanıcının seçimi (subject key → seçilen dil)
// Anasayfa ve düelloda ortak kullanılır
final Map<String, _PickerOption> _chosenLanguage = {};

// Bu subject key'leri tıklanınca dil seçici açar
bool _isLanguagePickerSubject(String key) =>
    key == 'ikinci_dil' || key == 'other_langs';

Future<_PickerOption?> _showLanguagePickerSheet(BuildContext context) {
  return showModalBottomSheet<_PickerOption>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _Palette.inkMute,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('🗣️'.tr(), style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Hangi Dil?',
                      style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Dünyada en çok konuşulan 20 dil arasından seç. Seçtiğin dil bu derste gözükecek.',
              style: _sans(size: 12, color: _Palette.inkMute, height: 1.4),
            ),
            const SizedBox(height: 16),
            for (final lang in _topLanguages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, lang),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _Palette.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _Palette.line),
                    ),
                    child: Row(
                      children: [
                        Text(lang.emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(lang.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _sans(size: 14, weight: FontWeight.w600)),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 18, color: _Palette.inkMute),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// Fakülteye göre eklenen evrensel dersler (üniversite/YL/doktora için)
// Bu derslerin içerikleri dünyada ortak müfredattır.
final Map<String, List<_Subject>> _facultyGlobalSubjects = {
  'insaat_muh': [
    _Subject('statik', '⚖️', 'Statik', 5, Color(0xFF0F766E), ['Denge', 'Mesnet Tepkileri', 'Kafes Sistemler', 'Kesit Tesirleri', 'Sürtünme']),
    _Subject('mukavemet', '💪', 'Mukavemet', 5, Color(0xFF0891B2), ['Gerilme-Şekil Değiştirme', 'Eğilme', 'Kesme', 'Burulma', 'Eksenel Yükleme']),
    _Subject('dinamik', '🎯', 'Dinamik', 4, Color(0xFF2563EB), ['Kinematik', 'Kinetik', 'İş-Enerji', 'Momentum', 'Titreşim']),
    _Subject('betonarme', '🧱', 'Betonarme', 4, Color(0xFFA16207), ['Kiriş Tasarımı', 'Kolon Tasarımı', 'Döşeme', 'Temel']),
    _Subject('akiskanlar', '💧', 'Akışkanlar Mekaniği', 4, Color(0xFF0EA5E9), ['Hidrostatik', 'Bernoulli', 'Kanal Akımı', 'Pompa ve Türbin']),
  ],
  'bilgisayar_muh': [
    _Subject('algoritma', '🧮', 'Algoritmalar', 6, Color(0xFF4F46E5), ['Sıralama', 'Arama', 'Böl-Fethet', 'Dinamik Programlama', 'Greedy', 'Grafik Algoritmaları']),
    _Subject('veri_yapi', '📊', 'Veri Yapıları', 6, Color(0xFF7C3AED), ['Dizi', 'Liste', 'Yığın', 'Kuyruk', 'Ağaçlar', 'Hash Tablolar']),
    _Subject('os', '⚙️', 'İşletim Sistemleri', 5, Color(0xFF0F766E), ['Süreç Yönetimi', 'Bellek Yönetimi', 'Dosya Sistemleri', 'Senkronizasyon', 'Deadlock']),
    _Subject('networks', '🌐', 'Bilgisayar Ağları', 5, Color(0xFF0891B2), ['OSI Katmanları', 'TCP/IP', 'Yönlendirme', 'HTTP', 'Güvenlik']),
    _Subject('db', '💽', 'Veritabanları', 5, Color(0xFFDB2777), ['SQL', 'İlişkisel Model', 'Normalizasyon', 'İndeksleme', 'NoSQL']),
    _Subject('ai', '🤖', 'Yapay Zeka', 5, Color(0xFFEC4899), ['Arama Algoritmaları', 'Makine Öğrenmesi', 'Derin Öğrenme', 'NLP', 'Görüntü İşleme']),
  ],
  'yazilim_muh': [
    _Subject('algoritma', '🧮', 'Algoritmalar', 6, Color(0xFF4F46E5), ['Sıralama', 'Arama', 'Dinamik Programlama', 'Greedy', 'Grafik']),
    _Subject('veri_yapi', '📊', 'Veri Yapıları', 6, Color(0xFF7C3AED), ['Dizi', 'Liste', 'Ağaçlar', 'Hash', 'Heap']),
    _Subject('oop', '🧩', 'Nesne Yönelimli Prog.', 5, Color(0xFF0F766E), ['Sınıf ve Nesne', 'Kalıtım', 'Polimorfizm', 'Encapsulation', 'Design Patterns']),
    _Subject('db', '💽', 'Veritabanları', 5, Color(0xFFDB2777), ['SQL', 'ORM', 'NoSQL', 'Transaction', 'İndeksleme']),
    _Subject('software_eng', '🏗️', 'Yazılım Mühendisliği', 4, Color(0xFF2563EB), ['Agile/Scrum', 'Test', 'CI/CD', 'Mimari']),
  ],
  'elektrik_elektronik_muh': [
    _Subject('devre', '⚡', 'Devre Teorisi', 5, Color(0xFFFF5B2E), ['Kirchhoff Yasaları', 'Thevenin', 'RLC', 'AC/DC', 'Filtreler']),
    _Subject('sinyal', '📡', 'Sinyal İşleme', 5, Color(0xFF8B5CF6), ['Fourier', 'Laplace', 'Z-Dönüşümü', 'Filtreler', 'FFT']),
    _Subject('dijital', '💻', 'Dijital Elektronik', 4, Color(0xFF0891B2), ['Boolean', 'Karnaugh', 'Flip-Flop', 'Sayısal Tasarım']),
    _Subject('control', '🎛️', 'Kontrol Sistemleri', 4, Color(0xFF10B981), ['Transfer Fonksiyonu', 'Kök-Yer Eğrisi', 'Bode', 'PID']),
    _Subject('elektromag', '🧲', 'Elektromanyetik', 4, Color(0xFF6366F1), ['Maxwell Denklemleri', 'Dalga', 'Antenler']),
  ],
  'makine_muh': [
    _Subject('makina_elem', '🔩', 'Makina Elemanları', 5, Color(0xFF78350F), ['Dişli', 'Yatak', 'Civata', 'Kaynak', 'Yay']),
    _Subject('mukavemet', '💪', 'Mukavemet', 5, Color(0xFF0891B2), ['Eğilme', 'Kesme', 'Burulma', 'Gerilme']),
    _Subject('termodinamik', '🌡️', 'Termodinamik', 5, Color(0xFFEF4444), ['1. Yasa', '2. Yasa', 'Çevrimler', 'Buhar']),
    _Subject('akiskanlar', '💧', 'Akışkanlar Mekaniği', 4, Color(0xFF0EA5E9), ['Hidrostatik', 'Bernoulli', 'Türbülans']),
    _Subject('malzeme', '🔬', 'Malzeme Bilimi', 4, Color(0xFF7C3AED), ['Metaller', 'Polimerler', 'Kompozitler', 'Faz Diyagramları']),
  ],
  'endustri_muh': [
    _Subject('or', '📊', 'Yöneylem Araştırması', 5, Color(0xFF2563EB), ['Doğrusal Programlama', 'Simpleks', 'Ağ Analizi', 'Dinamik Programlama']),
    _Subject('stat', '📉', 'Mühendislik İstatistiği', 5, Color(0xFF7C3AED), ['Olasılık', 'Dağılımlar', 'Hipotez Testi', 'Regresyon']),
    _Subject('uretim', '🏭', 'Üretim Sistemleri', 4, Color(0xFF0F766E), ['Yalın Üretim', 'JIT', 'Kalite Kontrol', 'Planlama']),
    _Subject('muhendislik_ekonomi', '💰', 'Mühendislik Ekonomisi', 4, Color(0xFFFFB800), ['Nakit Akışı', 'Geri Ödeme', 'IRR', 'NPV']),
  ],
  'tip': [
    _Subject('anatomi', '🦴', 'Anatomi', 6, Color(0xFFB91C1C), ['İskelet', 'Kas', 'Sinir', 'Damar', 'İç Organlar', 'Baş-Boyun']),
    _Subject('fizyoloji', '💓', 'Fizyoloji', 6, Color(0xFFEF4444), ['Kardiyovasküler', 'Solunum', 'Sindirim', 'Boşaltım', 'Sinir', 'Endokrin']),
    _Subject('biyokimya', '🧪', 'Biyokimya', 5, Color(0xFF10B981), ['Proteinler', 'Karbonhidrat', 'Lipid', 'Metabolizma', 'Enzimler']),
    _Subject('farmakoloji', '💊', 'Farmakoloji', 5, Color(0xFFDB2777), ['Farmakokinetik', 'Farmakodinamik', 'İlaç Grupları', 'Yan Etkiler']),
    _Subject('mikrobiyoloji', '🔬', 'Mikrobiyoloji', 4, Color(0xFF7C3AED), ['Bakteri', 'Virüs', 'Mantar', 'Antibiyotikler']),
    _Subject('patoloji', '🏥', 'Patoloji', 4, Color(0xFFF59E0B), ['Hücre Hasarı', 'İnflamasyon', 'Neoplazi', 'Enfeksiyon']),
  ],
  'dis_hekimligi': [
    _Subject('dis_anatomi', '🦷', 'Diş Anatomisi', 4, Color(0xFF0891B2), ['Süt Dişler', 'Daimi Dişler', 'Morfoloji', 'Gelişim']),
    _Subject('oral_patoloji', '🔬', 'Oral Patoloji', 3, Color(0xFF7C3AED), ['Lezyonlar', 'Tümörler', 'Enfeksiyonlar']),
    _Subject('biyokimya', '🧪', 'Biyokimya', 4, Color(0xFF10B981), ['Proteinler', 'Metabolizma', 'Enzimler']),
  ],
  'eczacilik': [
    _Subject('farmakoloji', '💊', 'Farmakoloji', 5, Color(0xFFDB2777), ['Farmakokinetik', 'Farmakodinamik', 'İlaç Grupları']),
    _Subject('farma_kimya', '⚗️', 'Farmasötik Kimya', 5, Color(0xFF10B981), ['Organik Sentez', 'İlaç Dizaynı', 'Yapı-Aktivite']),
    _Subject('biyokimya', '🧪', 'Biyokimya', 4, Color(0xFF8B5CF6), ['Proteinler', 'Metabolizma', 'Enzimler']),
  ],
  'hukuk': [
    _Subject('uluslar_hukuk', '🌐', 'Uluslararası Hukuk', 4, Color(0xFF2563EB), ['BM Sistemi', 'İnsan Hakları', 'Deniz Hukuku', 'Diplomatik Hukuk']),
    _Subject('roma_hukuku', '🏛️', 'Roma Hukuku', 3, Color(0xFFA16207), ['Kişiler Hukuku', 'Eşya Hukuku', 'Sözleşme', 'Tazminat']),
    _Subject('hukuk_felsefesi', '⚖️', 'Hukuk Felsefesi', 3, Color(0xFF7C2D12), ['Adalet', 'Doğal Hukuk', 'Pozitif Hukuk', 'Etik']),
  ],
  'isletme': [
    _Subject('finans', '💰', 'Finans', 5, Color(0xFFFFB800), ['Zaman Değeri', 'Yatırım Analizi', 'Risk', 'Portföy', 'Türev']),
    _Subject('pazarlama', '📣', 'Pazarlama', 4, Color(0xFFEC4899), ['4P', 'Segmentasyon', 'Tüketici Davranışı', 'Marka']),
    _Subject('ik', '👥', 'İnsan Kaynakları', 4, Color(0xFF10B981), ['İşe Alım', 'Eğitim', 'Performans', 'Ücret']),
    _Subject('mikro', '📈', 'Mikroekonomi', 4, Color(0xFF2563EB), ['Arz-Talep', 'Elastikiyet', 'Üretim', 'Piyasa Yapıları']),
    _Subject('makro', '📊', 'Makroekonomi', 4, Color(0xFF8B5CF6), ['GSYİH', 'Enflasyon', 'İşsizlik', 'Para Politikası']),
  ],
  'iktisat': [
    _Subject('mikro', '📈', 'Mikroekonomi', 5, Color(0xFF2563EB), ['Arz-Talep', 'Elastikiyet', 'Piyasa', 'Rekabet']),
    _Subject('makro', '📊', 'Makroekonomi', 5, Color(0xFF8B5CF6), ['GSYİH', 'Enflasyon', 'İşsizlik', 'Para Politikası']),
    _Subject('uluslar_ekonomi', '💱', 'Uluslararası Ekonomi', 4, Color(0xFFDB2777), ['Ticaret', 'Döviz', 'Ödemeler Dengesi']),
    _Subject('ekonometri', '📉', 'Ekonometri', 4, Color(0xFF0F766E), ['Regresyon', 'Zaman Serileri', 'Panel Veri']),
  ],
  'psikoloji': [
    _Subject('bilissel_psi', '🧠', 'Bilişsel Psikoloji', 4, Color(0xFF7C3AED), ['Hafıza', 'Dikkat', 'Algı', 'Problem Çözme']),
    _Subject('gelisim_psi', '👶', 'Gelişim Psikolojisi', 4, Color(0xFFEC4899), ['Piaget', 'Erikson', 'Bağlanma', 'Ergenlik']),
    _Subject('sosyal_psi', '👥', 'Sosyal Psikoloji', 4, Color(0xFFFF5B2E), ['Tutumlar', 'Uyum', 'Önyargı', 'Grup Dinamiği']),
    _Subject('klinik_psi', '🏥', 'Klinik Psikoloji', 4, Color(0xFFEF4444), ['Tanı', 'DSM', 'CBT', 'Psikoterapi']),
  ],
  'mimarlik': [
    _Subject('yapi', '🏢', 'Yapı Bilgisi', 4, Color(0xFF0F766E), ['Malzeme', 'Strüktür', 'Detay', 'Sürdürülebilirlik']),
    _Subject('mimarlik_tarihi', '🏛️', 'Mimarlık Tarihi', 5, Color(0xFFA16207), ['Antik', 'Orta Çağ', 'Rönesans', 'Modern', 'Postmodern']),
    _Subject('tasarim', '✏️', 'Mimari Tasarım', 4, Color(0xFFDB2777), ['Kompozisyon', 'Mekan', 'Oran', 'Konsept']),
  ],
};

// Herhangi bir listede arayarak ders adını/rengini getirir (crash'leri önler)
_Subject _findSubjectByKey(String key) {
  for (final s in _allSubjects) {
    if (s.key == key) return s;
  }
  for (final s in _globalDueloSubjects) {
    if (s.key == key) return s;
  }
  for (final s in _customWorldSubjects) {
    if (s.key == key) return s;
  }
  for (final list in _facultyGlobalSubjects.values) {
    for (final s in list) {
      if (s.key == key) return s;
    }
  }
  return _allSubjects.first;
}

// Kullanıcının profiline göre dünya dersleri (baz + fakülte + özel)
List<_Subject> _worldSubjectsForUser() {
  final out = <_Subject>[..._globalDueloSubjects];
  final fac = _currentFaculty;
  if (fac != null) {
    final extra = _facultyGlobalSubjects[fac];
    if (extra != null) out.addAll(extra);
  }
  out.addAll(_customWorldSubjects);
  return out;
}

// Dünya opponent havuzu — çeşitli ülkeler
const List<_DueloOpponent> _worldOpponents = [
  _DueloOpponent('hiroki_k', 'H', '🇯🇵', 'Japonya', 2458),
  _DueloOpponent('lukas_m', 'L', '🇩🇪', 'Almanya', 2210),
  _DueloOpponent('priya_s', 'P', '🇮🇳', 'Hindistan', 1980),
  _DueloOpponent('alex_j', 'A', '🇺🇸', 'ABD', 1845),
  _DueloOpponent('giulia_r', 'G', '🇮🇹', 'İtalya', 1672),
  _DueloOpponent('chloe_l', 'C', '🇫🇷', 'Fransa', 1550),
  _DueloOpponent('noah_v', 'N', '🇳🇱', 'Hollanda', 1490),
  _DueloOpponent('sofia_g', 'S', '🇪🇸', 'İspanya', 1420),
  _DueloOpponent('diego_m', 'D', '🇲🇽', 'Meksika', 1380),
  _DueloOpponent('jisoo_p', 'J', '🇰🇷', 'Kore', 1820),
];

// Ülke (Türkiye) havuzu
const List<_DueloOpponent> _countryOpponents = [
  _DueloOpponent('zeynep_y', 'Z', '🇹🇷', 'Türkiye', 1680),
  _DueloOpponent('deniz.k', 'D', '🇹🇷', 'Türkiye', 1540),
  _DueloOpponent('arda_2010', 'A', '🇹🇷', 'Türkiye', 1420),
  _DueloOpponent('mert_demir', 'M', '🇹🇷', 'Türkiye', 1310),
  _DueloOpponent('elif_m', 'E', '🇹🇷', 'Türkiye', 1250),
  _DueloOpponent('sema45', 'S', '🇹🇷', 'Türkiye', 1190),
  _DueloOpponent('kaan.ak', 'K', '🇹🇷', 'Türkiye', 1140),
  _DueloOpponent('bahar_c', 'B', '🇹🇷', 'Türkiye', 1080),
];

class _DueloOpponent {
  final String username;
  final String avatar;
  final String flag;
  final String country;
  final int elo;
  const _DueloOpponent(this.username, this.avatar, this.flag, this.country, this.elo);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _DueloRecord + _DueloRecordStore — her yarıştan sonra sonuç kartını
//  yerel olarak kaydeder; lobi ekranında liste halinde görünür.
// ═══════════════════════════════════════════════════════════════════════════════
class _DueloRecord {
  final String id;
  final DateTime createdAt;
  final String subjectName;
  final String topicName;
  final String scope;
  final int totalQuestions;
  // Ben
  final String myName;
  final String myCountry;
  final String myFlag;
  final int myCorrect;
  final int myWrong;
  final int myEmpty;
  final int myElapsed;
  // Rakip
  final String opponentName;
  final String opponentCountry;
  final String opponentFlag;
  final int opponentElo;
  final int opponentCorrect;
  final int opponentWrong;
  final int opponentEmpty;
  final int opponentElapsed;
  // Sorular + benim cevaplarım (yanlışları görebilmek için)
  final List<Map<String, dynamic>> questionsJson;
  final Map<int, int> myAnswers;

  _DueloRecord({
    required this.id,
    required this.createdAt,
    required this.subjectName,
    required this.topicName,
    required this.scope,
    required this.totalQuestions,
    required this.myName,
    required this.myCountry,
    required this.myFlag,
    required this.myCorrect,
    required this.myWrong,
    required this.myEmpty,
    required this.myElapsed,
    required this.opponentName,
    required this.opponentCountry,
    required this.opponentFlag,
    required this.opponentElo,
    required this.opponentCorrect,
    required this.opponentWrong,
    required this.opponentEmpty,
    required this.opponentElapsed,
    required this.questionsJson,
    required this.myAnswers,
  });

  int get winner {
    if (myCorrect > opponentCorrect) return 1;
    if (opponentCorrect > myCorrect) return -1;
    if (myElapsed < opponentElapsed) return 1;
    if (opponentElapsed < myElapsed) return -1;
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'subjectName': subjectName,
        'topicName': topicName,
        'scope': scope,
        'totalQuestions': totalQuestions,
        'myName': myName,
        'myCountry': myCountry,
        'myFlag': myFlag,
        'myCorrect': myCorrect,
        'myWrong': myWrong,
        'myEmpty': myEmpty,
        'myElapsed': myElapsed,
        'opponentName': opponentName,
        'opponentCountry': opponentCountry,
        'opponentFlag': opponentFlag,
        'opponentElo': opponentElo,
        'opponentCorrect': opponentCorrect,
        'opponentWrong': opponentWrong,
        'opponentEmpty': opponentEmpty,
        'opponentElapsed': opponentElapsed,
        'questionsJson': questionsJson,
        'myAnswers':
            myAnswers.map((k, v) => MapEntry(k.toString(), v)),
      };

  factory _DueloRecord.fromJson(Map<String, dynamic> j) {
    final qs = (j['questionsJson'] as List?) ?? const [];
    final ans = (j['myAnswers'] as Map?) ?? const {};
    final parsedAns = <int, int>{};
    ans.forEach((k, v) {
      final ki = int.tryParse(k.toString());
      if (ki != null && v is num) parsedAns[ki] = v.toInt();
    });
    return _DueloRecord(
      id: j['id'].toString(),
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      subjectName: (j['subjectName'] ?? '').toString(),
      topicName: (j['topicName'] ?? '').toString(),
      scope: (j['scope'] ?? 'world').toString(),
      totalQuestions: (j['totalQuestions'] as num?)?.toInt() ?? 0,
      myName: (j['myName'] ?? '').toString(),
      myCountry: (j['myCountry'] ?? '').toString(),
      myFlag: (j['myFlag'] ?? '🏳️').toString(),
      myCorrect: (j['myCorrect'] as num?)?.toInt() ?? 0,
      myWrong: (j['myWrong'] as num?)?.toInt() ?? 0,
      myEmpty: (j['myEmpty'] as num?)?.toInt() ?? 0,
      myElapsed: (j['myElapsed'] as num?)?.toInt() ?? 0,
      opponentName: (j['opponentName'] ?? '').toString(),
      opponentCountry: (j['opponentCountry'] ?? '').toString(),
      opponentFlag: (j['opponentFlag'] ?? '🏳️').toString(),
      opponentElo: (j['opponentElo'] as num?)?.toInt() ?? 1000,
      opponentCorrect: (j['opponentCorrect'] as num?)?.toInt() ?? 0,
      opponentWrong: (j['opponentWrong'] as num?)?.toInt() ?? 0,
      opponentEmpty: (j['opponentEmpty'] as num?)?.toInt() ?? 0,
      opponentElapsed: (j['opponentElapsed'] as num?)?.toInt() ?? 0,
      questionsJson:
          qs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      myAnswers: parsedAns,
    );
  }
}

class _DueloRecordStore {
  static const _key = 'duelo_records_v1';

  static Future<List<_DueloRecord>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? const [];
      final out = <_DueloRecord>[];
      for (final s in list) {
        try {
          out.add(_DueloRecord.fromJson(
              jsonDecode(s) as Map<String, dynamic>));
        } catch (_) {}
      }
      // En yeni başa
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(_DueloRecord r) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = [...(prefs.getStringList(_key) ?? const <String>[])];
      list.add(jsonEncode(r.toJson()));
      // En fazla 30 kayıt — eski temizlik.
      if (list.length > 30) {
        list.removeRange(0, list.length - 30);
      }
      await prefs.setStringList(_key, list);
    } catch (_) {}
  }

  static Future<void> delete(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = [...(prefs.getStringList(_key) ?? const <String>[])];
      list.removeWhere((s) {
        try {
          final j = jsonDecode(s) as Map<String, dynamic>;
          return j['id']?.toString() == id;
        } catch (_) {
          return false;
        }
      });
      await prefs.setStringList(_key, list);
    } catch (_) {}
  }
}

// _QuizQuestion ↔ JSON dönüşümü (kayıt için).
Map<String, dynamic> _quizQuestionToJson(_QuizQuestion q) => {
      'subjectKey': q.subjectKey,
      'subjectName': q.subjectName,
      'subjectEmoji': q.subjectEmoji,
      'subjectColor': q.subjectColor.toARGB32(),
      'topic': q.topic,
      'text': q.text,
      'formula': q.formula,
      'options': q.options,
      'correctIndex': q.correctIndex,
      'hint': q.hint,
      'explanation': q.explanation,
      'difficulty': q.difficulty,
    };

_QuizQuestion _quizQuestionFromJson(Map<String, dynamic> j) => _QuizQuestion(
      subjectKey: (j['subjectKey'] ?? '').toString(),
      subjectName: (j['subjectName'] ?? '').toString(),
      subjectEmoji: (j['subjectEmoji'] ?? '📚').toString(),
      subjectColor: Color((j['subjectColor'] as num?)?.toInt() ?? 0xFF000000),
      topic: (j['topic'] ?? '').toString(),
      text: (j['text'] ?? '').toString(),
      formula: j['formula']?.toString(),
      options: ((j['options'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      correctIndex: (j['correctIndex'] as num?)?.toInt() ?? 0,
      hint: (j['hint'] ?? '').toString(),
      explanation: (j['explanation'] ?? '').toString(),
      difficulty: (j['difficulty'] ?? 'medium').toString(),
    );

// ═══════════════════════════════════════════════════════════════════════════════
//  _DueloRecordsPage — "Kayıtlı Yarışlar" tam sayfa listesi.
//  En son yarış başta, her kart tam boyut, taşma yok, tarih + skor
//  + rakip + CTA'lar (paylaş / yanlışlar) dahil.
// ═══════════════════════════════════════════════════════════════════════════════
class _DueloRecordsPage extends StatefulWidget {
  final String scopeFilter; // 'world' | 'country' | '' (hepsi)
  final void Function(_DueloRecord record, bool friendMode) onShare;
  final void Function(_DueloRecord record) onOpenMistakes;
  const _DueloRecordsPage({
    required this.onShare,
    required this.onOpenMistakes,
    this.scopeFilter = '',
  });

  @override
  State<_DueloRecordsPage> createState() => _DueloRecordsPageState();
}


class _DueloRecordsPageState extends State<_DueloRecordsPage> {
  List<_DueloRecord> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _DueloRecordStore.loadAll();
    if (!mounted) return;
    final filtered = widget.scopeFilter.isEmpty
        ? list
        : list.where((r) => r.scope == widget.scopeFilter).toList();
    setState(() => _items = filtered);
  }

  Future<void> _delete(_DueloRecord r) async {
    await _DueloRecordStore.delete(r.id);
    await _load();
  }

  void _rematchFromRecord(BuildContext ctx, _DueloRecord r) {
    // Aynı ders+konu ile yeni bir lobi aç — kullanıcı istediğinde direkt
    // "Rakip Bul" diyebilir.
    Navigator.of(ctx).pushReplacement(
      MaterialPageRoute(builder: (_) => const DueloLobbyScreen()),
    );
  }

  // Karta dokununca kayıttan orijinal sonuç ekranını (testi ilk bitirdiğinde
  // gördüğü ekranı) aynen yeniden aç.
  void _openResultScreen(_DueloRecord r) {
    final qs =
        r.questionsJson.map(_quizQuestionFromJson).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DueloResultsScreen(
          subjectName: r.subjectName,
          topicName: r.topicName,
          totalQuestions: r.totalQuestions,
          scope: r.scope,
          questions: qs,
          myAnswers: r.myAnswers,
          myName: r.myName,
          myCountry: r.myCountry,
          myFlag: r.myFlag,
          myCorrect: r.myCorrect,
          myWrong: r.myWrong,
          myEmpty: r.myEmpty,
          myElapsed: r.myElapsed,
          opponentName: r.opponentName,
          opponentCountry: r.opponentCountry,
          opponentFlag: r.opponentFlag,
          opponentElo: r.opponentElo,
          opponentCorrect: r.opponentCorrect,
          opponentWrong: r.opponentWrong,
          opponentEmpty: r.opponentEmpty,
          opponentElapsed: r.opponentElapsed,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(_DueloRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🗑️', style: TextStyle(fontSize: 32)),
              const SizedBox(height: 10),
              Text(
                'Kaydı Sil'.tr(),
                style: _serif(
                    size: 18, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                r.topicName.isEmpty
                    ? (r.subjectName.isEmpty
                        ? 'Bu yarış kaydı silinsin mi?'.tr()
                        : '${r.subjectName} ${"silinsin mi?".tr()}')
                    : '${r.subjectName} · ${r.topicName} ${"silinsin mi?".tr()}',
                textAlign: TextAlign.center,
                style: _sans(
                    size: 13,
                    weight: FontWeight.w500,
                    color: _Palette.inkSoft,
                    height: 1.4),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          Navigator.of(dialogCtx).pop(false),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: _Palette.surface,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: _Palette.line),
                        ),
                        alignment: Alignment.center,
                        child: Text('Vazgeç'.tr(),
                            style: _sans(
                                size: 13, weight: FontWeight.w800)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(dialogCtx).pop(true),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: _Palette.error,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        alignment: Alignment.center,
                        child: Text('Sil'.tr(),
                            style: _sans(
                                size: 13,
                                weight: FontWeight.w900,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await _delete(r);
  }

  String _pageTitle() {
    switch (widget.scopeFilter) {
      case 'world':
        return 'Dünya Çapında Yarışlarım'.tr();
      case 'country':
        return 'Ülke Çapında Yarışlarım'.tr();
      default:
        return 'Kayıtlı Yarışlarım'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      appBar: AppBar(
        backgroundColor: _Palette.bg,
        elevation: 0,
        foregroundColor: _Palette.ink,
        title: Text(
          _pageTitle(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _serif(
              size: 18, weight: FontWeight.w700, letterSpacing: -0.01),
        ),
      ),
      body: _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🏁', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 10),
                    Text(
                      'Henüz kayıtlı yarışın yok.'.tr(),
                      textAlign: TextAlign.center,
                      style: _sans(
                          size: 14,
                          weight: FontWeight.w700,
                          color: _Palette.inkSoft),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final r = _items[i];
                return _DueloRecordFullCard(
                  record: r,
                  onTap: () => _openResultScreen(r),
                  onOpenMistakes: () => widget.onOpenMistakes(r),
                  onRematch: () => _rematchFromRecord(context, r),
                  onShareSocial: () => widget.onShare(r, false),
                  onShareFriend: () => widget.onShare(r, true),
                  onLongPress: () => _confirmDelete(r),
                );
              },
            ),
    );
  }
}

// Tam boyut kayıt kartı — liste sayfasında kullanılır. Taşma yok.
// Tap → orijinal sonuç ekranı; long press → sil.
class _DueloRecordFullCard extends StatelessWidget {
  final _DueloRecord record;
  final VoidCallback onTap;
  final VoidCallback onOpenMistakes;
  final VoidCallback onRematch;
  final VoidCallback onShareSocial;
  final VoidCallback onShareFriend;
  final VoidCallback onLongPress;
  const _DueloRecordFullCard({
    required this.record,
    required this.onTap,
    required this.onOpenMistakes,
    required this.onRematch,
    required this.onShareSocial,
    required this.onShareFriend,
    required this.onLongPress,
  });

  String _fmtFullDate(DateTime d) {
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}  ·  $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final win = record.winner;
    final label = win == 1
        ? 'Kazandın'.tr()
        : (win == 0 ? 'Berabere'.tr() : 'Kaybettin'.tr());
    final accent = win == 1
        ? _Palette.success
        : (win == 0 ? _Palette.ink : _Palette.error);
    final scopeTxt = record.scope == 'world'
        ? '🌍 ${"Dünya".tr()}'
        : '🇹🇷 ${"Ülke".tr()}';
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: accent.withValues(alpha: 0.55), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst satır: kazanma durumu + kapsam + tarih
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(label,
                    style: _sans(
                        size: 10,
                        weight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.3)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _Palette.surface,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: _Palette.line),
                ),
                child: Text(scopeTxt,
                    style: _sans(
                        size: 10,
                        weight: FontWeight.w800,
                        color: _Palette.ink)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Ders + Konu
          Text(
            record.subjectName.isEmpty
                ? 'Yarış'.tr()
                : record.subjectName,
            style: _serif(
                size: 18,
                weight: FontWeight.w800,
                letterSpacing: -0.02,
                color: _Palette.ink),
          ),
          if (record.topicName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              record.topicName,
              style: _sans(
                  size: 13,
                  weight: FontWeight.w600,
                  color: _Palette.inkMute),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.event_rounded,
                  size: 13, color: _Palette.inkMute),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _fmtFullDate(record.createdAt),
                  style: _sans(
                      size: 11,
                      weight: FontWeight.w700,
                      color: _Palette.inkMute),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Skor özeti — yan yana iki pill
          Row(
            children: [
              Expanded(
                child: _scoreBox(
                  label: 'Sen'.tr(),
                  flag: record.myFlag,
                  name: '@${record.myName}',
                  country: record.myCountry,
                  score:
                      '${record.myCorrect}/${record.totalQuestions}',
                  isWinner: win == 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _scoreBox(
                  label: 'Rakip'.tr(),
                  flag: record.opponentFlag,
                  name: '@${record.opponentName}',
                  country: record.opponentCountry,
                  score:
                      '${record.opponentCorrect}/${record.totalQuestions}',
                  isWinner: win == -1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Aksiyon butonları — 2x2 grid.
          // Üst satır: [Yeniden Yarış] [Yanlışlarım]
          // Alt satır: [Sosyal medyada paylaş] [Arkadaşınla paylaş]
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.replay_rounded,
                  label: 'Yeniden Yarış'.tr(),
                  color: _Palette.brand,
                  onTap: onRematch,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _actionBtn(
                  icon: Icons.auto_stories_rounded,
                  label: 'Yanlışlarım'.tr(),
                  onTap: onOpenMistakes,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.ios_share_rounded,
                  label: 'Sosyal medyada paylaş'.tr(),
                  onTap: onShareSocial,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _actionBtn(
                  icon: Icons.send_rounded,
                  label: 'Arkadaşınla paylaş'.tr(),
                  onTap: onShareFriend,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Uzun basınca sil'.tr(),
              style: _sans(
                  size: 9,
                  weight: FontWeight.w700,
                  color: _Palette.inkMute,
                  letterSpacing: 0.3),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _scoreBox({
    required String label,
    required String flag,
    required String name,
    required String country,
    required String score,
    required bool isWinner,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: isWinner
            ? _Palette.success.withValues(alpha: 0.08)
            : _Palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isWinner
                ? _Palette.success
                : _Palette.line,
            width: isWinner ? 1.4 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(label.toUpperCase(),
                  style: _sans(
                      size: 9,
                      weight: FontWeight.w900,
                      color: _Palette.inkMute,
                      letterSpacing: 0.5)),
              if (isWinner) ...[
                const SizedBox(width: 4),
                const Text('🏆', style: TextStyle(fontSize: 10)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  country,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(
                      size: 12,
                      weight: FontWeight.w800,
                      color: _Palette.ink),
                ),
              ),
            ],
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sans(
                size: 11,
                weight: FontWeight.w700,
                color: _Palette.inkMute),
          ),
          const SizedBox(height: 6),
          Text(
            score,
            style: _serif(
                size: 20,
                weight: FontWeight.w900,
                letterSpacing: -0.02,
                color: isWinner ? _Palette.success : _Palette.ink),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    final fg = color ?? _Palette.ink;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: fg.withValues(alpha: 0.5), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(
                    size: 11, weight: FontWeight.w800, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DueloLobbyScreen extends StatefulWidget {
  const DueloLobbyScreen({super.key});
  @override
  State<DueloLobbyScreen> createState() => _DueloLobbyScreenState();
}

class _DueloLobbyScreenState extends State<DueloLobbyScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  Timer? _matchTimer;
  bool _matching = false;
  String _scope = 'world'; // world | country
  String? _selectedSubject;
  String? _selectedTopic;
  bool _showOtherSheet = false;
  bool _draggingFromSheet = false;
  List<_DueloRecord> _records = const [];

  // ── Renk özelleştirme state'i ──────────────────────────────────────
  // Kullanıcı sağ üstteki palet butonundan açar; hedefi (arka plan veya
  // ders çerçeveleri) seçip renge basarak uygular ya da rengi sürükleyip
  // istediği kareye/arka plana bırakarak da uygular.
  bool _showColorPicker = false;
  String _colorMode = 'frame'; // 'frame' | 'text'
  String _colorTarget = 'bg'; // 'bg' | 'subjects'
  Color? _pageBgOverride;
  final Map<String, Color> _subjectColors = {};
  final Map<String, Color> _subjectTextColors = {};

  static const _colorPalette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  static const _duelBgColorKey = 'duelo_bg_color';
  static const _duelTileColorsKey = 'duelo_tile_colors';
  static const _duelTileTextColorsKey = 'duelo_tile_text_colors';
  static const _duelOrderKey = 'duelo_subject_order';

  // Scope bazlı ders sırası (sürükle-bırak ile değişir).
  final Map<String, List<String>> _customOrder = {
    'world': const [],
    'country': const [],
  };

  Future<void> _loadDuelOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_duelOrderKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      m.forEach((k, v) {
        if (v is List) {
          _customOrder[k] = v.map((e) => e.toString()).toList();
        }
      });
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveDuelOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _duelOrderKey,
        jsonEncode(_customOrder),
      );
    } catch (_) {}
  }

  // _availableSubjects sonucunu mevcut scope için kayıtlı sıraya göre
  // yeniden düzenler.
  List<_Subject> _orderedSubjects(List<_Subject> base) {
    final order = _customOrder[_scope] ?? const <String>[];
    if (order.isEmpty) return base;
    final byKey = {for (final s in base) s.key: s};
    final out = <_Subject>[];
    for (final k in order) {
      final s = byKey.remove(k);
      if (s != null) out.add(s);
    }
    out.addAll(byKey.values);
    return out;
  }

  void _swapDuelSubjects(String draggedKey, String targetKey) {
    if (draggedKey == targetKey) return;
    final current = _orderedSubjects(_availableSubjects())
        .map((s) => s.key)
        .toList();
    final from = current.indexOf(draggedKey);
    final to = current.indexOf(targetKey);
    if (from < 0 || to < 0) return;
    final tmp = current[from];
    current[from] = current[to];
    current[to] = tmp;
    setState(() => _customOrder[_scope] = current);
    _saveDuelOrder();
  }

  Future<void> _loadDuelColorPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bgInt = prefs.getInt(_duelBgColorKey);
      final tilesRaw = prefs.getString(_duelTileColorsKey);
      final tilesTextRaw = prefs.getString(_duelTileTextColorsKey);
      if (!mounted) return;
      setState(() {
        if (bgInt != null) _pageBgOverride = Color(bgInt);
        if (tilesRaw != null && tilesRaw.isNotEmpty) {
          try {
            final m = jsonDecode(tilesRaw) as Map<String, dynamic>;
            _subjectColors.clear();
            m.forEach((k, v) {
              if (v is num) _subjectColors[k] = Color(v.toInt());
            });
          } catch (_) {}
        }
        if (tilesTextRaw != null && tilesTextRaw.isNotEmpty) {
          try {
            final m = jsonDecode(tilesTextRaw) as Map<String, dynamic>;
            _subjectTextColors.clear();
            m.forEach((k, v) {
              if (v is num) _subjectTextColors[k] = Color(v.toInt());
            });
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  Future<void> _saveDuelColorPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pageBgOverride == null) {
        await prefs.remove(_duelBgColorKey);
      } else {
        await prefs.setInt(
            _duelBgColorKey, _pageBgOverride!.toARGB32());
      }
      if (_subjectColors.isEmpty) {
        await prefs.remove(_duelTileColorsKey);
      } else {
        final json = jsonEncode(_subjectColors
            .map((k, v) => MapEntry(k, v.toARGB32())));
        await prefs.setString(_duelTileColorsKey, json);
      }
      if (_subjectTextColors.isEmpty) {
        await prefs.remove(_duelTileTextColorsKey);
      } else {
        final json = jsonEncode(_subjectTextColors
            .map((k, v) => MapEntry(k, v.toARGB32())));
        await prefs.setString(_duelTileTextColorsKey, json);
      }
    } catch (_) {}
  }

  void _applyColorTo(String target, Color c) {
    setState(() {
      if (_colorMode == 'text') {
        // Yazı modu — dersler üzerindeki metin rengine uygulanır.
        for (final s in _availableSubjects()) {
          _subjectTextColors[s.key] = c;
        }
      } else if (target == 'bg') {
        _pageBgOverride = c;
      } else {
        // Tüm görünür dersleri boyanmış say.
        for (final s in _availableSubjects()) {
          _subjectColors[s.key] = c;
        }
      }
    });
    _saveDuelColorPrefs();
  }

  void _applyColorToSubject(String subjectKey, Color c) {
    setState(() {
      if (_colorMode == 'text') {
        _subjectTextColors[subjectKey] = c;
      } else {
        _subjectColors[subjectKey] = c;
      }
    });
    _saveDuelColorPrefs();
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _loadRecords();
    _loadDuelColorPrefs();
    _loadDuelOrder();
  }

  Future<void> _loadRecords() async {
    final list = await _DueloRecordStore.loadAll();
    if (!mounted) return;
    setState(() => _records = list);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _matchTimer?.cancel();
    super.dispose();
  }

  List<_Subject> _availableSubjects() {
    if (_scope == 'world') {
      // Baz evrensel + fakülteye göre eklenen + kullanıcının eklediği
      return _worldSubjectsForUser();
    }
    // Ülke modu: kullanıcının seviyesindeki tüm dersler
    return _subjectsForGrade();
  }

  List<String> _availableTopics() {
    if (_selectedSubject == null) return [];
    // Dünya modunda: ders listesinden konu çek
    if (_scope == 'world') {
      final subj = _findSubjectByKey(_selectedSubject!);
      return subj.topics;
    }
    // Ülke modu: önce müfredat, yoksa soru bankası, yoksa ders.topics
    final curric = _topicsForGrade(_selectedSubject!);
    if (curric.isNotEmpty) return curric;
    final bank = _questionBank[_selectedSubject!];
    if (bank != null) return bank.keys.toList();
    return _findSubjectByKey(_selectedSubject!).topics;
  }

  bool get _canStart => _selectedSubject != null && _selectedTopic != null;

  // Kullanıcı için sabit bir deviceId tabanlı userId. SharedPreferences'tan
  // cache'lenir; yoksa random UUID-benzeri oluşturulur.
  Future<String?> _currentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('duelo_user_id');
      if (id == null || id.isEmpty) {
        id = 'u${DateTime.now().millisecondsSinceEpoch}'
            '${math.Random().nextInt(99999)}';
        await prefs.setString('duelo_user_id', id);
      }
      return id;
    } catch (_) {
      return null;
    }
  }

  String _userFlag() {
    const map = {
      'tr': '🇹🇷', 'us': '🇺🇸', 'uk': '🇬🇧', 'de': '🇩🇪', 'fr': '🇫🇷',
      'jp': '🇯🇵', 'cn': '🇨🇳', 'kr': '🇰🇷', 'in': '🇮🇳', 'ru': '🇷🇺',
      'br': '🇧🇷', 'mx': '🇲🇽', 'es': '🇪🇸', 'it': '🇮🇹', 'pl': '🇵🇱',
      'ua': '🇺🇦',
    };
    final code = EduProfile.current?.country ?? 'tr';
    return map[code] ?? '🏳️';
  }

  // Dev modu: kısa delay sonrası her zaman null (= mock rakibe düş).
  Future<DueloMatchResult?> _fakeMatchmakingDelay() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return null;
  }

  // Prod: gerçek Firebase matchmaking akışı. Şu an dev modda çağrılmıyor;
  // yayına alırken _findMatch içinde bu fonksiyona geçiş yapın.
  // ignore: unused_element
  Future<DueloMatchResult?> _runRealMatchmaking({
    required String subjectKey,
    String? topic,
  }) async {
    final profile = EduProfile.current;
    final userId = await _currentUserId();
    if (userId == null || profile == null) return null;
    final criteria = DueloMatchCriteria(
      userId: userId,
      username: _currentUsername,
      flag: _userFlag(),
      country: _userCountryName(),
      level: profile.level,
      grade: profile.grade,
      track: profile.track,
      scope: _scope,
      subjectKey: subjectKey,
      topic: topic,
      elo: 1000,
    );
    return DueloMatchmakingService.findMatch(
      criteria,
      timeout: const Duration(seconds: 12),
    );
  }

  Future<void> _findMatch() async {
    if (!_canStart) return;
    setState(() => _matching = true);

    final subjectKey = _selectedSubject!;
    final topic = _selectedTopic;
    final subjectObj = _findSubjectByKey(subjectKey);
    final rng = math.Random();

    const targetCount = 5;
    const minProceedCount = 3; // <3 soru varsa oyunu hiç başlatma

    // Takipli ID tabanlı tekrar bloklama — aynı soru tekrar eklenmesin.
    final seen = <String>{};
    List<_QuizQuestion> picks = <_QuizQuestion>[];
    void addUnique(Iterable<_QuizQuestion> qs) {
      for (final q in qs) {
        final k = '${q.subjectKey}|${q.topic}|${q.text}';
        if (seen.add(k)) picks.add(q);
      }
    }

    // 1) Bank'ten SEÇİLEN konu için topla.
    final bank = _questionBank[subjectKey];
    if (bank != null) {
      if (topic != null && bank[topic] != null) {
        addUnique(List.of(bank[topic]!)..shuffle(rng));
      } else if (topic == null) {
        final all = <_QuizQuestion>[];
        for (final list in bank.values) {
          all.addAll(list);
        }
        all.shuffle(rng);
        addUnique(all);
      }
    }

    // 2) Eksikse AI ile strict (aynı) konu üret.
    if (picks.length < targetCount) {
      final need = targetCount - picks.length;
      try {
        final aiQs = await _generateAiQuestions(
          subject: subjectObj,
          topic: topic,
          count: need,
        );
        addUnique(aiQs);
      } catch (e) {
        debugPrint('[Duelo] AI soru üretimi başarısız (1): $e');
      }
    }

    // 3) "Rakip Aranıyor" animasyonu (dev modda 2 sn).
    final DueloMatchResult? match = await _fakeMatchmakingDelay();
    // Prod için:
    //   match = await _runRealMatchmaking(
    //     subjectKey: subjectKey, topic: topic);
    if (!mounted) return;

    // 4) Hâlâ eksikse: AYNI DERSİN diğer konularından doldur (subject
    //    fallback — çapraz-ders hâlâ yok).
    if (picks.length < targetCount && bank != null && topic != null) {
      final extras = <_QuizQuestion>[];
      for (final entry in bank.entries) {
        if (entry.key == topic) continue;
        extras.addAll(entry.value);
      }
      extras.shuffle(rng);
      addUnique(extras);
    }

    // 5) Hâlâ eksikse: AI ile aynı ders, topic'i null bırakıp genel üret.
    if (picks.length < targetCount) {
      final need = targetCount - picks.length;
      try {
        final aiQs = await _generateAiQuestions(
          subject: subjectObj,
          topic: null, // ders geneli
          count: need,
        );
        addUnique(aiQs);
      } catch (e) {
        debugPrint('[Duelo] AI soru üretimi başarısız (2): $e');
      }
    }
    if (!mounted) return;

    // 6) En az minProceedCount varsa oyunu başlat, yetiyorsa targetCount'a
    //    kırp. Aksi halde net hata ver.
    if (picks.length < minProceedCount) {
      setState(() => _matching = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Bu konu için şu an yeterli soru üretilemedi. Lütfen birazdan tekrar dene.'
                .tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (picks.length > targetCount) {
      picks = picks.take(targetCount).toList();
    }
    // picks.length artık [3, 5] aralığında — oyun başlayacak.

    // 5) Rakip seç: gerçek varsa gerçek, yoksa mock.
    final cfg = _WizardConfig()
      ..count = picks.length
      ..selectedSubjects = {subjectKey}
      ..timeMode = 'race';

    String oppName;
    String oppAvatar;
    String oppFlag;
    String oppCountry;
    int oppElo;
    if (match != null) {
      oppName = match.opponentUsername;
      oppAvatar = oppName.isEmpty ? '?' : oppName[0].toUpperCase();
      oppFlag = match.opponentFlag;
      oppCountry = match.opponentCountry;
      oppElo = match.opponentElo;
      debugPrint('[Duelo] GERÇEK rakip: @$oppName ($oppCountry)');
    } else {
      final pool =
          _scope == 'world' ? _worldOpponents : _countryOpponents;
      final opp = pool[rng.nextInt(pool.length)];
      oppName = opp.username;
      oppAvatar = opp.avatar;
      oppFlag = opp.flag;
      oppCountry = opp.country;
      oppElo = opp.elo;
      debugPrint('[Duelo] Mock rakip (gerçek bulunamadı): @$oppName');
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _DueloQuizScreen(
          cfg: cfg,
          questions: picks,
          opponentName: oppName,
          opponentAvatar: oppAvatar,
          opponentFlag: oppFlag,
          opponentCountry: oppCountry,
          opponentElo: oppElo,
          subjectName: subjectObj.name,
          topicName: topic,
          scope: _scope,
        ),
      ),
    );
  }

  // AI ile düello sorularını üret. Strict subject+topic — başka dersten
  // soru üretmesi yasak. Başarısız olursa boş liste döner.
  Future<List<_QuizQuestion>> _generateAiQuestions({
    required _Subject subject,
    required String? topic,
    required int count,
  }) async {
    final String topicLabel = topic ??
        (subject.topics.isNotEmpty ? subject.topics.first : subject.name);
    final prompt = '''
[DÜELLO SORU ÜRETİMİ — $count SORU · JSON]
Ders: ${subject.name}
Konu: $topicLabel

GÖREVİN: TAM OLARAK $count soru üret. SADECE "$topicLabel" konusu
için ve sadece "${subject.name}" dersi kapsamında sorular yaz.
BAŞKA DERSTEN (matematik, tarih, vb.) soru ÜRETME.

SADECE geçerli bir JSON array döndür — başka metin, markdown fence,
emoji başlık yok.

Format:
[
  {
    "q": "soru metni — kısa ve net, en fazla 15 kelime",
    "opts": {"A": "...", "B": "...", "C": "...", "D": "..."},
    "ans": "B",
    "hint": "tek cümle yol gösterici ipucu",
    "sol": "2-3 cümle çözüm",
    "d": "medium"
  }
]

KURALLAR:
• TAM $count soru.
• "opts" her zaman 4 şık: A, B, C, D.
• "ans" şık harfi: "A" | "B" | "C" | "D".
• Türkçe yaz. Dolar işareti yok; LaTeX \\( ... \\).
• Markdown yıldız (**) veya başlık (#) YAZMA.
• "Sonuç:" / "Püf Nokta:" yazma.
• Çıktın tek başına geçerli bir JSON array olmalı.
''';
    final raw = await GeminiService.solveHomework(
      question: prompt,
      solutionType: 'TestSorulari',
      subject: subject.name,
    );
    return _parseAiDueloQuestions(raw, subject, topic ?? topicLabel);
  }

  List<_QuizQuestion> _parseAiDueloQuestions(
      String raw, _Subject subject, String topic) {
    var s = raw.trim();
    // Markdown fence temizle
    if (s.startsWith('```')) {
      final firstNl = s.indexOf('\n');
      if (firstNl > -1) s = s.substring(firstNl + 1);
      final lastFence = s.lastIndexOf('```');
      if (lastFence > -1) s = s.substring(0, lastFence);
      s = s.trim();
    }
    final start = s.indexOf('[');
    final end = s.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    try {
      final decoded = jsonDecode(s.substring(start, end + 1));
      if (decoded is! List) return const [];
      final out = <_QuizQuestion>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final j = Map<String, dynamic>.from(item);
        final q = (j['q'] ?? '').toString().trim();
        final opts = j['opts'];
        final ans = (j['ans'] ?? '').toString().trim().toUpperCase();
        if (q.isEmpty || opts is! Map) continue;
        final keys = ['A', 'B', 'C', 'D', 'E'];
        final options = <String>[];
        int correctIdx = -1;
        for (int i = 0; i < keys.length; i++) {
          final v = opts[keys[i]];
          if (v == null) continue;
          options.add(v.toString());
          if (keys[i] == ans) correctIdx = options.length - 1;
        }
        if (options.length < 3 || correctIdx < 0) continue;
        out.add(_QuizQuestion(
          subjectKey: subject.key,
          subjectName: subject.name,
          subjectEmoji: subject.emoji,
          subjectColor: subject.color,
          topic: topic,
          text: q,
          options: options,
          correctIndex: correctIdx,
          hint: (j['hint'] ?? '').toString(),
          explanation: (j['sol'] ?? '').toString(),
          difficulty: (j['d'] ?? 'medium').toString(),
        ));
      }
      return out;
    } catch (e) {
      debugPrint('[Duelo] JSON parse hatası: $e');
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_matching) return _buildMatchingOverlay();
    final subjects = _orderedSubjects(_availableSubjects());
    return Scaffold(
      backgroundColor: _pageBgOverride ?? _Palette.bg,
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  _CircleBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bilgi Yarışı'.tr(),
                            style: _serif(size: 20, weight: FontWeight.w700, letterSpacing: -0.02)),
                        Text(_currentGrade,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _sans(size: 11, color: _Palette.inkMute)),
                      ],
                    ),
                  ),
                  // Renk özelleştirme — diğer sayfalardaki gibi renkli
                  // "Renk Seç" pill.
                  GestureDetector(
                    onTap: () => setState(
                        () => _showColorPicker = !_showColorPicker),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFF6A00),
                            Color(0xFFDB2777),
                            Color(0xFF7C3AED),
                            Color(0xFF2563EB),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showColorPicker
                                ? Icons.close_rounded
                                : Icons.palette_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showColorPicker
                                ? 'Kapat'.tr()
                                : 'Renk Seç'.tr(),
                            style: _sans(
                              size: 12,
                              weight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_showColorPicker) _buildColorPickerPanel(),
            Expanded(
              child: DragTarget<Color>(
                onAcceptWithDetails: (d) {
                  // Bırakma noktası herhangi bir ders tile'ına değse
                  // tile kendi DragTarget'ında yakalamıştı zaten; buraya
                  // düşme arkaplana bırakma anlamına gelir.
                  setState(() => _pageBgOverride = d.data);
                },
                builder: (context, cand, rej) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  children: [
                    // Kapsam seçici (Dünya / Ülkem)
                    _buildScopeTabs(),
                  const SizedBox(height: 6),
                  Text(
                    _scope == 'world'
                        ? '🌍 Dünyadan aynı seviyede (${_currentLevel == 'universite' && _currentFaculty != null ? _facultyLabels[_currentFaculty] : _currentGrade}) bir rakiple karşılaşırsın. Her iki taraf aynı evrensel dersi/konuyu seçer.'
                        : '🇹🇷 Ülkendeki aynı seviyede bir rakiple karşılaşırsın. Tüm derslerden yarışabilirsin.',
                    style: _sans(size: 11, color: _Palette.inkMute, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  // Ders seçimi
                  Text('HANGİ DERSTE YARIŞACAKSIN?'.tr(),
                      style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
                  const SizedBox(height: 10),
                  _buildSubjectGrid(subjects),
                  // Kayıtlı yarış kartları — diğer dersler / yeni ders ekle
                  // satırının hemen altında duruyor.
                  _buildRecordsSection(),
                  // Seçili konu varsa alt önizleme rozeti (rahat bakılsın).
                  if (_selectedTopic != null) ...[
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _Palette.ink,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_rounded,
                                size: 12, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              _selectedTopic!,
                              style: _sans(
                                  size: 11,
                                  weight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            // Alt CTA — sadece ders + konu seçiliyse gösterilir
            if (_canStart)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: _PrimaryButton(
                  label: '🏆 Rakip Bul'.tr(),
                  brand: true,
                  onTap: _findMatch,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 20),
                  decoration: BoxDecoration(
                    color: _Palette.line.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _selectedSubject == null
                        ? 'Önce bir ders seç'
                        : 'Şimdi bir konu seç',
                    style: _sans(size: 14, weight: FontWeight.w600, color: _Palette.inkMute),
                  ),
                ),
              ),
          ],
        ),
      ),
          if (_showOtherSheet) _buildOtherSheetOverlay(),
        ],
      ),
    );
  }

  Widget _buildScopeTabs() {
    final tabs = [
      ('world', '🌍', 'Dünya Çapında'),
      ('country', '🇹🇷', 'Ülke Çapında'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _Palette.line.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final t in tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _scope = t.$1;
                  _selectedSubject = null;
                  _selectedTopic = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _scope == t.$1 ? _Palette.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _scope == t.$1
                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t.$2, style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          t.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sans(
                            size: 12,
                            weight: FontWeight.w800,
                            color: _scope == t.$1 ? _Palette.ink : _Palette.inkMute,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubjectGrid(List<_Subject> subjects) {
    if (subjects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Palette.line),
        ),
        child: Row(
          children: [
            Text('🤷'.tr(), style: TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Bu modda uygun ders yok',
                  style: _sans(size: 12, color: _Palette.inkMute)),
            ),
          ],
        ),
      );
    }
    // İlk 8 ders görünür (2x4); kullanıcı "Diğer Dersler"e basınca alttan
    // yarım sayfa sheet açılır.
    final visible = subjects.take(8).toList();
    final hasMore = subjects.length > 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.0,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final s in visible) _subjectTile(s),
          ],
        ),
        const SizedBox(height: 10),
        // Altta yan yana: Diğer Dersler (varsa) + Yeni Bir Ders Ekle
        Row(
          children: [
            Expanded(
              child: hasMore
                  ? _wideActionButton(
                      icon: Icons.keyboard_arrow_down_rounded,
                      label: 'Diğer Dersler'.tr(),
                      onTap: _openOtherSubjectsSheet,
                      filled: false,
                    )
                  : const SizedBox.shrink(),
            ),
            if (hasMore) const SizedBox(width: 8),
            Expanded(
              child: _wideActionButton(
                icon: Icons.add_rounded,
                label: 'Yeni Bir Ders Ekle'.tr(),
                onTap: _addCustomSubject,
                filled: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 8'in üstündeki dersleri listeleyen yarım sayfa sheet.
  void _openOtherSubjectsSheet() {
    final subjects = _orderedSubjects(_availableSubjects());
    final overflow = subjects.skip(8).toList();
    if (overflow.isEmpty) return;
    setState(() => _showOtherSheet = true);
  }

  void _closeOtherSheet() {
    if (_showOtherSheet) {
      setState(() {
        _showOtherSheet = false;
        _draggingFromSheet = false;
      });
    }
  }

  // Overlay sheet — modal değil, arka plandaki top-8 grid tıklanabilir kalır.
  Widget _buildOtherSheetOverlay() {
    final subjects = _orderedSubjects(_availableSubjects());
    final overflow = subjects.skip(8).toList();
    if (overflow.isEmpty) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final sheetHeight = mq.size.height * 0.55;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedOpacity(
            opacity: _draggingFromSheet ? 0.30 : 1.0,
            duration: const Duration(milliseconds: 180),
            // Material sarmalı: Text widget'larındaki sarı debug alt
            // çizgilerini önler (Material context sağlar).
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                height: sheetHeight,
                decoration: const BoxDecoration(
                  color: Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 30),
                        Expanded(
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _closeOtherSheet,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                  color: Colors.black12),
                            ),
                            child: const Icon(Icons.close_rounded,
                                size: 16, color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Başlık + sağ üstte soluk ipucu
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'Diğer Dersler'.tr(),
                            style: _sans(
                                size: 18,
                                weight: FontWeight.w800,
                                color: _Palette.ink),
                          ),
                        ),
                        ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 130),
                          child: Opacity(
                            opacity: 0.85,
                            child: Text(
                              'Derslere basılı tut,\nsürükle, yerini değiştir'
                                  .tr(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
                              style: _sans(
                                size: 9,
                                weight: FontWeight.w600,
                                color: _Palette.ink,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 4,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.0,
                        children: [
                          for (final s in overflow)
                            _DueloOverflowSubjectTile(
                              subject: s,
                              customColor: _subjectColors[s.key],
                              customTextColor: _subjectTextColors[s.key],
                              onTap: () {
                                _closeOtherSheet();
                                _onSubjectTap(s);
                              },
                              onDragStarted: () {
                                setState(() =>
                                    _draggingFromSheet = true);
                              },
                              onDragEnd: () {
                                setState(() =>
                                    _draggingFromSheet = false);
                              },
                              onAcceptSwap: (draggedKey) =>
                                  _swapDuelSubjects(draggedKey, s.key),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _wideActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: filled
              ? _Palette.brand.withValues(alpha: 0.1)
              : _Palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: filled ? _Palette.brand : _Palette.line,
            width: filled ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: filled ? _Palette.brand : _Palette.ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(
                  size: 12,
                  weight: FontWeight.w800,
                  color: filled ? _Palette.brand : _Palette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSubjectTap(_Subject s) async {
    // Renk özelleştirme modu aktifken ders seçimi pasif — konular açılmaz,
    // sadece boyama / drag-drop yapılır.
    if (_showColorPicker) return;
    // Dil dersi seçilirse önce dil picker'ı aç
    if (_isLanguagePickerSubject(s.key) && _selectedSubject != s.key) {
      final lang = await _showLanguagePickerSheet(context);
      if (lang == null) return;
      _chosenLanguage[s.key] = lang;
    }
    // Aynı ders tekrar tıklandıysa temizle.
    if (_selectedSubject == s.key) {
      setState(() {
        _selectedSubject = null;
        _selectedTopic = null;
      });
      return;
    }
    setState(() {
      _selectedSubject = s.key;
      _selectedTopic = null;
    });
    // Ortaya küçük bir pencere (dialog) aç — konuları burada göster.
    final topics = _availableTopics();
    if (topics.isEmpty) return;
    final picked = await _showTopicsDialog(
      subjectName: s.name,
      topics: topics,
    );
    if (picked != null && mounted) {
      setState(() => _selectedTopic = picked);
    }
  }

  Future<String?> _showTopicsDialog({
    required String subjectName,
    required List<String> topics,
  }) async {
    // Arka planı hafif bulanıklaştırılmış (blur) dialog — sadece konular
    // netçe seçilebilsin, geri plan puslu kalsın.
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.2),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, a1, a2) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              maxWidth: 360,
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Konu Seç'.tr(),
                          style: _serif(
                              size: 18,
                              weight: FontWeight.w700,
                              letterSpacing: -0.01),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subjectName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sans(
                              size: 12,
                              weight: FontWeight.w600,
                              color: _Palette.inkMute),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _Palette.surface,
                        border: Border.all(color: _Palette.line),
                      ),
                      child: const Icon(Icons.close_rounded, size: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in topics)
                        GestureDetector(
                          onTap: () => Navigator.of(ctx).pop(t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F1EA),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              t,
                              style: _sans(
                                  size: 12.5,
                                  weight: FontWeight.w600,
                                  color: _Palette.ink),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  // Ders tile'ı — hem seçim hem renk özelleştirme DragTarget'ı.
  Widget _subjectTile(_Subject s) {
    final custom = _subjectColors[s.key];
    final selected = _selectedSubject == s.key;
    final baseColor = selected ? _Palette.bg : _Palette.surface;
    final bgColor = custom ?? baseColor;
    final darkBg = (() {
      final l = (0.299 * bgColor.r + 0.587 * bgColor.g + 0.114 * bgColor.b);
      return l < 0.55;
    })();
    final customText = _subjectTextColors[s.key];
    final fg = customText ?? (darkBg ? Colors.white : _Palette.ink);

    Widget tile(bool hovering) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hovering
                ? const Color(0xFFFF6A00)
                : (selected ? _Palette.ink : _Palette.line),
            width: hovering ? 2.4 : (selected ? 2 : 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isLanguagePickerSubject(s.key) &&
                        _chosenLanguage[s.key] != null
                    ? _chosenLanguage[s.key]!.emoji
                    : s.emoji,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 4),
              Text(
                _isLanguagePickerSubject(s.key) &&
                        _chosenLanguage[s.key] != null
                    ? _chosenLanguage[s.key]!.label
                    : s.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _sans(
                    size: 11,
                    weight: FontWeight.w600,
                    height: 1.15,
                    color: fg),
              ),
            ],
          ),
        ),
      );
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != s.key,
      onAcceptWithDetails: (d) => _swapDuelSubjects(d.data, s.key),
      builder: (ctx, swapCand, _) {
        return DragTarget<Color>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (d) => _applyColorToSubject(s.key, d.data),
          builder: (ctx2, colorCand, _) {
            final hovering = swapCand.isNotEmpty || colorCand.isNotEmpty;
            return LongPressDraggable<String>(
              data: s.key,
              onDragStarted: () {
                // Diğer dersler sheet'i açıksa sürüklemede sade görünüm — kapansın.
                if (_showOtherSheet) {
                  setState(() => _showOtherSheet = false);
                }
              },
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: tile(false),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: tile(false),
              ),
              child: GestureDetector(
                onTap: _showColorPicker ? null : () => _onSubjectTap(s),
                child: tile(hovering),
              ),
            );
          },
        );
      },
    );
  }

  // Üstten açılan renk paneli — target seçici + sürüklenebilir renk şeridi.
  Widget _buildColorPickerPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.ink, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded,
                  size: 16, color: _Palette.ink),
              const SizedBox(width: 6),
              Text(
                'Renk'.tr(),
                style: _sans(
                    size: 13,
                    weight: FontWeight.w900,
                    color: _Palette.ink),
              ),
              const SizedBox(width: 10),
              Expanded(child: _modeToggle()),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _pageBgOverride = null;
                    _subjectColors.clear();
                    _subjectTextColors.clear();
                  });
                  _saveDuelColorPrefs();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _Palette.surface,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: _Palette.line),
                  ),
                  child: Text(
                    'Sıfırla'.tr(),
                    style: _sans(
                        size: 10,
                        weight: FontWeight.w800,
                        color: _Palette.inkMute),
                  ),
                ),
              ),
            ],
          ),
          // Hedef chip'leri — "Arka plan / Ders Çerçeveleri". Tam genişlikte
          // tek satır; altındaki açıklama yazısı ve palet "Arka plan"
          // çerçevesinin sol kenarıyla aynı hizadan başlar.
          const SizedBox(height: 8),
          _targetToggle(),
          const SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin kareye veya arka plana bırak.'.tr(),
            style: _sans(
                size: 10,
                weight: FontWeight.w600,
                color: _Palette.inkMute,
                height: 1.3),
          ),
          const SizedBox(height: 8),
          // Çift sıra, yatay kaydırılır renk paleti.
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _colorPalette.length,
              itemBuilder: (_, i) => _draggableColor(_colorPalette[i]),
            ),
          ),
        ],
      ),
    );
  }

  // Yazı / Çerçeve mod seçici — Renk başlığının altında iki küçük kutu.
  Widget _modeToggle() {
    Widget box(String id, IconData icon, String label) {
      final active = _colorMode == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorMode = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(
                vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFFFF6A00).withValues(alpha: 0.12)
                  : _Palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? const Color(0xFFFF6A00) : _Palette.ink,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 13,
                    color: active
                        ? const Color(0xFFFF6A00)
                        : _Palette.ink),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(
                      size: 11,
                      weight: FontWeight.w800,
                      color: active
                          ? const Color(0xFFFF6A00)
                          : _Palette.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        box('text', Icons.text_fields_rounded, 'Yazı'.tr()),
        const SizedBox(width: 8),
        box('frame', Icons.crop_square_rounded, 'Çerçeve'.tr()),
      ],
    );
  }

  Widget _targetToggle() {
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = id),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFFFF6A00).withValues(alpha: 0.12)
                  : _Palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    active ? const Color(0xFFFF6A00) : _Palette.line,
                width: active ? 1.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _sans(
                  size: 10.5,
                  weight: FontWeight.w800,
                  color: active
                      ? const Color(0xFFFF6A00)
                      : _Palette.ink),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('bg', 'Arka plan'.tr()),
        const SizedBox(width: 6),
        chip('subjects', 'Ders Çerçeveleri'.tr()),
      ],
    );
  }

  Widget _draggableColor(Color c) {
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: _colorDot(c, faded: true),
      child: GestureDetector(
        onTap: () => _applyColorTo(_colorTarget, c),
        child: _colorDot(c),
      ),
    );
  }

  Widget _colorDot(Color c, {bool faded = false}) {
    return Opacity(
      opacity: faded ? 0.3 : 1.0,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black26, width: 1),
        ),
      ),
    );
  }

  Future<void> _addCustomSubject() async {
    final existing = [..._globalDueloSubjects, ..._customWorldSubjects]
        .map((s) => s.key)
        .toList();
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddDueloSubjectSheet(existingKeys: existing),
    );
    if (result != null) {
      // Yeni ders eklenmiş; hemen seç
      setState(() {
        _selectedSubject = result;
        _selectedTopic = null;
      });
    }
  }

  // ignore: unused_element
  Widget _buildTopicChips(List<String> topics) {
    if (topics.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Palette.line),
        ),
        child: Row(
          children: [
            Text('🤷'.tr(), style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Bu ders için hazır konu yok.',
                style: _sans(size: 12, color: _Palette.inkMute),
              ),
            ),
          ],
        ),
      );
    }
    // Chip'ler beyaz zeminli bir çerçeve içinde sunuluyor.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Palette.line),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in topics)
            GestureDetector(
              onTap: () => setState(() {
                _selectedTopic = (_selectedTopic == t) ? null : t;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _selectedTopic == t
                      ? _Palette.ink
                      : const Color(0xFFF5F1EA),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedTopic == t)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.check_rounded,
                            size: 12, color: Colors.white),
                      ),
                    Text(
                      t,
                      style: _sans(
                        size: 12,
                        weight: FontWeight.w500,
                        color: _selectedTopic == t
                            ? Colors.white
                            : _Palette.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Kayıtlı yarışlarım — grid'in hemen altında iki ayrı sekme ─────
  //  1) Dünya Çapında Yarışlarım
  //  2) Ülke Çapında Yarışlarım
  //  Kayıtlar scope'una göre ilgili sekmeye otomatik dağılır.
  Widget _buildRecordsSection() {
    if (_records.isEmpty) return const SizedBox.shrink();
    final worldCount =
        _records.where((r) => r.scope == 'world').length;
    final countryCount =
        _records.where((r) => r.scope == 'country').length;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          if (worldCount > 0)
            _recordsTab(
              icon: '🌍',
              title: 'Dünya Çapında Yarışlarım'.tr(),
              count: worldCount,
              onTap: () => _openRecordsPage(scope: 'world'),
            ),
          if (worldCount > 0 && countryCount > 0)
            const SizedBox(height: 8),
          if (countryCount > 0)
            _recordsTab(
              icon: '🇹🇷',
              title: 'Ülke Çapında Yarışlarım'.tr(),
              count: countryCount,
              onTap: () => _openRecordsPage(scope: 'country'),
            ),
        ],
      ),
    );
  }

  Widget _recordsTab({
    required String icon,
    required String title,
    required int count,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Palette.line, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _Palette.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(
                        size: 14,
                        weight: FontWeight.w800,
                        color: _Palette.ink),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$count ${"kayıt".tr()}',
                    style: _sans(
                        size: 11,
                        weight: FontWeight.w600,
                        color: _Palette.inkMute),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: _Palette.inkMute, size: 22),
          ],
        ),
      ),
    );
  }

  Future<void> _openRecordsPage({required String scope}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _DueloRecordsPage(
          scopeFilter: scope,
          onShare: (r, friendMode) =>
              _shareRecord(r, friendMode: friendMode),
          onOpenMistakes: _openRecordMistakes,
        ),
      ),
    );
    await _loadRecords();
  }

  void _shareRecord(_DueloRecord r, {required bool friendMode}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DueloShareModePage(
          caption:
              'QuAlsar uygulamasını indir — sen de istediğin derste, '
              'istediğin konuda, dünyada veya ülkende yarış!\nqualsar.app',
          subjectName: r.subjectName,
          topicName: r.topicName,
          totalQuestions: r.totalQuestions,
          scope: r.scope,
          myName: r.myName,
          myCountry: r.myCountry,
          myFlag: r.myFlag,
          myCorrect: r.myCorrect,
          myWrong: r.myWrong,
          myEmpty: r.myEmpty,
          myElapsed: r.myElapsed,
          opponentName: r.opponentName,
          opponentCountry: r.opponentCountry,
          opponentFlag: r.opponentFlag,
          opponentElo: r.opponentElo,
          opponentCorrect: r.opponentCorrect,
          opponentWrong: r.opponentWrong,
          opponentEmpty: r.opponentEmpty,
          opponentElapsed: r.opponentElapsed,
          winner: r.winner,
          friendMode: friendMode,
        ),
      ),
    );
  }

  void _openRecordMistakes(_DueloRecord r) {
    final qs = r.questionsJson.map(_quizQuestionFromJson).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DueloMistakesScreen(
          questions: qs,
          answers: r.myAnswers,
        ),
      ),
    );
  }

  Widget _buildMatchingOverlay() {
    // Dünya: "Dünyada Rakip Aranıyor"
    // Ülke: "<Ülke>de Rakip Aranıyor" (örn. Türkiye'de)
    final country = _userCountryName();
    final label = _scope == 'world'
        ? 'Dünyada Rakip Aranıyor'
        : '${country}de Rakip Aranıyor';
    // Seçili derse göre loader varyantı — sayısal dersler formül akışı,
    // sözel/sosyal dersler harf + kelime akışı gösterir.
    final variant = _isNumericSubjectKey(_selectedSubject)
        ? QuAlsarLoaderVariant.numeric
        : QuAlsarLoaderVariant.verbal;
    return Scaffold(
      backgroundColor: Colors.white,
      body: QuAlsarNumericLoader(
        primaryText: label.tr(),
        staticLabel: true,
        variant: variant,
      ),
    );
  }

  // Matematik, geometri, fizik, kimya, biyoloji gibi dersler sayısal.
  // Diğerleri (tarih, edebiyat, coğrafya, felsefe, yabancı dil...) sözel.
  bool _isNumericSubjectKey(String? key) {
    if (key == null) return true;
    const numeric = <String>{
      'math', 'matematik',
      'geometry', 'geometri',
      'physics', 'fizik',
      'chem', 'chemistry', 'kimya',
      'bio', 'biology', 'biyoloji',
      'stats', 'istatistik',
      'informatics', 'bilisim',
    };
    return numeric.contains(key.toLowerCase());
  }

  /// Cihazdan veya kullanıcı profilinden ülke adı — Türkçe hal ekine uygun.
  String _userCountryName() {
    // EduProfile.current içindeki ülke kodu ise ad eşlemesini çıkar.
    final code = EduProfile.current?.country ?? 'tr';
    const tr = {
      'tr': 'Türkiye',
      'us': 'ABD',
      'uk': 'Birleşik Krallık',
      'de': 'Almanya',
      'fr': 'Fransa',
      'jp': 'Japonya',
      'cn': 'Çin',
      'kr': 'Kore',
      'in': 'Hindistan',
      'ru': 'Rusya',
      'br': 'Brezilya',
      'mx': 'Meksika',
      'es': 'İspanya',
      'it': 'İtalya',
      'pl': 'Polonya',
      'ua': 'Ukrayna',
      'eg': 'Mısır',
      'sa': 'Suudi Arabistan',
      'ir': 'İran',
      'id': 'Endonezya',
      'vn': 'Vietnam',
      'th': 'Tayland',
      'my': 'Malezya',
      'ph': 'Filipinler',
      'pk': 'Pakistan',
      'bd': 'Bangladeş',
      'ng': 'Nijerya',
      'za': 'Güney Afrika',
      'ca': 'Kanada',
      'au': 'Avustralya',
    };
    return tr[code] ?? 'Ülken';
  }
}

// Düello için kullanıcı tarafından eklenen özel ders sheet'i
class _AddDueloSubjectSheet extends StatefulWidget {
  final List<String> existingKeys;
  const _AddDueloSubjectSheet({required this.existingKeys});

  @override
  State<_AddDueloSubjectSheet> createState() => _AddDueloSubjectSheetState();
}

class _AddDueloSubjectSheetState extends State<_AddDueloSubjectSheet> {
  final _nameCtrl = TextEditingController();
  final _topicsCtrl = TextEditingController();
  String _selectedEmoji = '📘';
  final List<String> _emojiChoices = const [
    '📘', '📗', '📕', '🧪', '🔭', '🎨', '🎵', '🌐', '⚙️', '🧠', '💡', '🏋️', '🎭', '🗺️', '🌟',
  ];
  final List<Color> _colorPalette = const [
    Color(0xFF2563EB), Color(0xFF10B981), Color(0xFFEF4444),
    Color(0xFF8B5CF6), Color(0xFFF59E0B), Color(0xFFDB2777),
    Color(0xFF0F766E), Color(0xFFFFB800),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _topicsCtrl.dispose();
    super.dispose();
  }

  String _properCase(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    final parts = trimmed.split(RegExp(r'\s+'));
    return parts
        .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
  }

  String _slugify(String name) {
    final lower = name.toLowerCase().trim();
    final cleaned = lower.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return 'custom_${cleaned}_${DateTime.now().millisecondsSinceEpoch}';
  }

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty;

  void _save() {
    final name = _properCase(_nameCtrl.text);
    final topicsRaw = _topicsCtrl.text.trim();
    final topics = topicsRaw.isEmpty
        ? <String>[]
        : topicsRaw
            .split(RegExp(r'[,\n]'))
            .map((t) => _properCase(t))
            .where((t) => t.isNotEmpty)
            .toList();
    final color = _colorPalette[_customWorldSubjects.length % _colorPalette.length];
    final key = _slugify(_nameCtrl.text);
    final subj = _Subject(key, _selectedEmoji, name, topics.length, color, topics);
    _customWorldSubjects.add(subj);
    Navigator.of(context).pop(key);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => Container(
          decoration: const BoxDecoration(
            color: _Palette.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('➕'.tr(), style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Yeni Ders Ekle',
                        style: _serif(size: 20, weight: FontWeight.w600, letterSpacing: -0.02)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Kendi konun için ders oluştur — düelloda seçmek için listende görünecek.',
                style: _sans(size: 12, color: _Palette.inkMute, height: 1.4),
              ),
              const SizedBox(height: 18),
              // İkon + ad
              Text('DERS ADI',
                  style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
              const SizedBox(height: 8),
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickEmoji,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _Palette.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _Palette.line),
                      ),
                      alignment: Alignment.center,
                      child: Text(_selectedEmoji, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 28,
                      style: _sans(size: 14, weight: FontWeight.w600),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Örn: Astronomi'.tr(),
                        hintStyle: _sans(size: 13, color: _Palette.inkMute),
                        filled: true,
                        fillColor: _Palette.surface,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: _Palette.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: _Palette.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: _Palette.brand, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text('KONULAR',
                      style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
                  const SizedBox(width: 6),
                  Text('(opsiyonel, virgülle ayır)'.tr(),
                      style: _sans(size: 9, color: _Palette.inkMute)),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _topicsCtrl,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: _sans(size: 13),
                decoration: InputDecoration(
                  hintText: 'Örn: Gezegenler, Yıldızlar, Galaksiler'.tr(),
                  hintStyle: _sans(size: 12, color: _Palette.inkMute),
                  filled: true,
                  fillColor: _Palette.surface,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _Palette.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _Palette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _Palette.brand, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _PrimaryButton(
                label: '✓ Ekle'.tr(),
                brand: true,
                onTap: _canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickEmoji() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Bir ikon seç'.tr(),
                style: _serif(size: 18, weight: FontWeight.w600, letterSpacing: -0.02)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in _emojiChoices)
                  GestureDetector(
                    onTap: () => Navigator.pop(context, e),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _Palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: e == _selectedEmoji ? _Palette.ink : _Palette.line,
                          width: e == _selectedEmoji ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _selectedEmoji = picked);
  }
}

class _DueloQuizScreen extends StatefulWidget {
  final _WizardConfig cfg;
  final List<_QuizQuestion> questions;
  final String opponentName;
  final String opponentAvatar;
  final String opponentFlag;
  final String opponentCountry;
  final int opponentElo;
  final String? subjectName;
  final String? topicName;
  final String scope; // 'world' | 'country'
  const _DueloQuizScreen({
    required this.cfg,
    required this.questions,
    required this.opponentName,
    required this.opponentAvatar,
    required this.opponentFlag,
    required this.opponentCountry,
    required this.opponentElo,
    this.subjectName,
    this.topicName,
    this.scope = 'world',
  });

  @override
  State<_DueloQuizScreen> createState() => _DueloQuizScreenState();
}

class _DueloQuizScreenState extends State<_DueloQuizScreen> {
  int _opponentProgress = 0; // rakibin çözdüğü soru sayısı (sahte)
  Timer? _opponentTimer;
  int _mySolved = 0; // benim cevapladığım soru sayısı

  // Bitiş durumları — iki taraf bitene kadar sonuç ekranı gösterilmez.
  bool _iFinished = false;
  bool _opponentFinished = false;
  int _opponentElapsed = 0; // opponent'ın toplam çözme süresi (sim)
  int _opponentCorrect = 0; // opponent'ın doğru sayısı (sim)
  // Benim tarafımın snapshot'ı (answers/hints/combo ileri kullanım için)
  int _myElapsed = 0;
  int _myCorrect = 0;
  int _myAnswered = 0; // cevap verilen soru sayısı (doğru + yanlış)
  Map<int, int> _myAnswers = {}; // q index → şık index

  // Bekleme ekranı göstermek için.
  bool _waitingForOpponent = false;

  @override
  void initState() {
    super.initState();
    _scheduleOpponent();
  }

  void _scheduleOpponent() {
    // Rakip ortalama 8-14 sn'de cevap verir
    final rng = math.Random();
    _opponentTimer =
        Timer(Duration(milliseconds: 8000 + rng.nextInt(6000)), () {
      if (!mounted) return;
      setState(() {
        _opponentProgress++;
        _opponentElapsed += 10; // ortalama olarak 10 sn/soru (simülasyon)
      });
      if (_opponentProgress < widget.questions.length) {
        _scheduleOpponent();
      } else {
        _onOpponentFinished();
      }
    });
  }

  void _onOpponentFinished() {
    // Opponent skoru — ELO'ya göre ortalama doğruluk (%55-90)
    final rng = math.Random();
    final baseAcc = 0.55 + (widget.opponentElo.clamp(1000, 2000) - 1000) /
            1000 *
            0.35; // 1000 → 0.55, 2000 → 0.90
    int correct = 0;
    for (int i = 0; i < widget.questions.length; i++) {
      if (rng.nextDouble() < baseAcc) correct++;
    }
    setState(() {
      _opponentFinished = true;
      _opponentCorrect = correct;
    });
    _tryShowResults();
  }

  void _onMyFinished({
    required int elapsedSeconds,
    required Map<int, int> answers,
    required int correctCount,
    required int hintsUsed,
    required int comboMax,
  }) {
    // answers.length = cevaplanan soru sayısı (boş bırakılan dahil değil).
    setState(() {
      _iFinished = true;
      _myElapsed = elapsedSeconds;
      _myCorrect = correctCount;
      _myAnswered = answers.length;
      _myAnswers = Map<int, int>.from(answers);
      _waitingForOpponent = !_opponentFinished;
    });
    // hintsUsed, comboMax şu an kullanılmıyor; signature korundu.
    _tryShowResults();
  }

  Future<bool> _confirmFinishEarly() async {
    // Rakip hala devam ediyorsa kullanıcıya uyarı dialog'u.
    if (_opponentFinished) return true;
    final remaining =
        widget.questions.length - _opponentProgress;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⏳', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 10),
              Text(
                'Rakip Hâlâ Çözüyor'.tr(),
                style: _serif(
                    size: 18, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '@${widget.opponentName} cevaplamaya devam ediyor '
                        '($remaining ${"soru kaldı".tr()}). '
                        'Bitirirsen beklemeye geçersin.'
                    .tr(),
                textAlign: TextAlign.center,
                style: _sans(
                    size: 13,
                    weight: FontWeight.w500,
                    color: _Palette.inkSoft,
                    height: 1.45),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFED7AA),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Geri Dön'.tr(),
                          style: _sans(
                              size: 13,
                              weight: FontWeight.w800,
                              color: const Color(0xFFC2410C)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 13),
                        decoration: BoxDecoration(
                          color: _Palette.ink,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Yine de Bitir'.tr(),
                          style: _sans(
                              size: 13,
                              weight: FontWeight.w900,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return ok == true;
  }

  void _tryShowResults() {
    if (!_iFinished || !_opponentFinished) return;
    // Küçük gecikme — "bekliyor" animasyonundan hemen sonra geçiş.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final total = widget.questions.length;
      final myWrong = (_myAnswered - _myCorrect).clamp(0, total);
      final myEmpty = (total - _myAnswered).clamp(0, total);
      final oppWrong = (total - _opponentCorrect).clamp(0, total);
      // Rakip simülasyonu tüm soruları cevaplıyor sayılır → empty = 0.

      // Lobide gösterilmek üzere yerel kayıt — best-effort.
      _DueloRecordStore.save(_DueloRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        subjectName: widget.subjectName ?? '',
        topicName: widget.topicName ?? '',
        scope: widget.scope,
        totalQuestions: total,
        myName: _currentUsername,
        myCountry: _userCountryName(),
        myFlag: '🇹🇷',
        myCorrect: _myCorrect,
        myWrong: myWrong,
        myEmpty: myEmpty,
        myElapsed: _myElapsed,
        opponentName: widget.opponentName,
        opponentCountry: widget.opponentCountry,
        opponentFlag: widget.opponentFlag,
        opponentElo: widget.opponentElo,
        opponentCorrect: _opponentCorrect,
        opponentWrong: oppWrong,
        opponentEmpty: 0,
        opponentElapsed: _opponentElapsed,
        questionsJson:
            widget.questions.map(_quizQuestionToJson).toList(),
        myAnswers: Map<int, int>.from(_myAnswers),
      ));

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => _DueloResultsScreen(
            subjectName: widget.subjectName ?? '',
            topicName: widget.topicName ?? '',
            totalQuestions: total,
            scope: widget.scope,
            questions: widget.questions,
            myAnswers: _myAnswers,
            myName: _currentUsername,
            myCountry: _userCountryName(),
            myFlag: '🇹🇷',
            myCorrect: _myCorrect,
            myWrong: myWrong,
            myEmpty: myEmpty,
            myElapsed: _myElapsed,
            opponentName: widget.opponentName,
            opponentCountry: widget.opponentCountry,
            opponentFlag: widget.opponentFlag,
            opponentElo: widget.opponentElo,
            opponentCorrect: _opponentCorrect,
            opponentWrong: oppWrong,
            opponentEmpty: 0,
            opponentElapsed: _opponentElapsed,
          ),
        ),
      );
    });
  }

  // Kullanıcının mevcut ülke adını — _DueloLobbyScreenState.userCountryName
  // burada private, yeniden küçük helper: EduProfile'dan basit eşleme.
  String _userCountryName() {
    final code = EduProfile.current?.country ?? 'tr';
    const tr = {
      'tr': 'Türkiye', 'us': 'ABD', 'uk': 'Birleşik Krallık',
      'de': 'Almanya', 'fr': 'Fransa', 'jp': 'Japonya', 'cn': 'Çin',
      'kr': 'Kore', 'in': 'Hindistan', 'ru': 'Rusya', 'br': 'Brezilya',
      'mx': 'Meksika', 'es': 'İspanya', 'it': 'İtalya', 'pl': 'Polonya',
      'ua': 'Ukrayna',
    };
    return tr[code] ?? 'Türkiye';
  }

  @override
  void dispose() {
    _opponentTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ═══ Üst başlık bloğu — Dünya/Ülke rozeti + Ders + Konu ═══
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Dünya/Ülke rozeti — büyük pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: widget.scope == 'world'
                              ? _Palette.accent.withValues(alpha: 0.14)
                              : _Palette.brand.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: widget.scope == 'world'
                                ? _Palette.accent
                                : _Palette.brand,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.scope == 'world' ? '🌍' : '🇹🇷',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.scope == 'world'
                                  ? 'Dünya'.tr()
                                  : 'Ülke'.tr(),
                              style: _sans(
                                size: 15,
                                weight: FontWeight.w900,
                                color: widget.scope == 'world'
                                    ? _Palette.accent
                                    : _Palette.brand,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Ders + Konu — tek satırda yan yana, aynı hizada.
                      if (widget.subjectName != null)
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.subjectName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _serif(
                                    size: 17,
                                    weight: FontWeight.w800,
                                    letterSpacing: -0.02,
                                    color: _Palette.ink,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              if (widget.topicName != null) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                  child: Text(
                                    '·',
                                    style: _sans(
                                      size: 17,
                                      weight: FontWeight.w700,
                                      color: _Palette.inkMute,
                                    ),
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    widget.topicName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _serif(
                                      size: 17,
                                      weight: FontWeight.w600,
                                      letterSpacing: -0.02,
                                      color: _Palette.inkSoft,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // İnce ayırıcı — başlık ile rakip kutusu arası
                  Container(
                    height: 1,
                    color: _Palette.line,
                  ),
                  const SizedBox(height: 10),
                  // Rakibin ülkesi satırı (dünya modunda belirgin)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: _Palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _Palette.line),
                    ),
                    child: Row(
                      children: [
                        Text(widget.opponentFlag,
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: _sans(
                                  size: 14,
                                  weight: FontWeight.w600,
                                  color: _Palette.inkSoft),
                              children: [
                                TextSpan(
                                  text: 'Rakibin: '.tr(),
                                  style: _sans(
                                      size: 14,
                                      weight: FontWeight.w700,
                                      color: _Palette.inkSoft),
                                ),
                                TextSpan(
                                  text: widget.opponentCountry,
                                  style: _sans(
                                      size: 14,
                                      weight: FontWeight.w900,
                                      color: _Palette.ink),
                                ),
                                const TextSpan(text: '\'dan '),
                                TextSpan(
                                  text: '@${widget.opponentName}',
                                  style: _sans(
                                      size: 14,
                                      weight: FontWeight.w800,
                                      color: _Palette.brand),
                                ),
                                TextSpan(
                                  text: ' · ${widget.opponentElo} ELO',
                                  style: _sans(
                                      size: 12,
                                      weight: FontWeight.w600,
                                      color: _Palette.inkMute),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // VS satırı — simetrik: sol avatar, ortada VS, sağ avatar
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _DueloAvatar(
                        name: _currentUsername,
                        avatar: 'A',
                        progress: _mySolved / widget.questions.length,
                        color: _Palette.brand,
                        flag: '🇹🇷',
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _Palette.surface,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: _Palette.line),
                        ),
                        child: Text(
                          'VS',
                          style: _serif(
                              size: 14,
                              weight: FontWeight.w800,
                              color: _Palette.inkMute),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _DueloAvatar(
                        name: widget.opponentName,
                        avatar: widget.opponentAvatar,
                        progress:
                            _opponentProgress / widget.questions.length,
                        color: _Palette.accent,
                        flag: widget.opponentFlag,
                        mirror: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                _QuizScreen(
                  cfg: widget.cfg,
                  questions: widget.questions,
                  onProgress: (idx) {
                    if (mounted) setState(() => _mySolved = idx);
                  },
                  onBeforeFinish: _confirmFinishEarly,
                  onFinish: ({
                    required elapsedSeconds,
                    required answers,
                    required correctCount,
                    required hintsUsed,
                    required comboMax,
                  }) {
                    _onMyFinished(
                      elapsedSeconds: elapsedSeconds,
                      answers: answers,
                      correctCount: correctCount,
                      hintsUsed: hintsUsed,
                      comboMax: comboMax,
                    );
                  },
                ),
                if (_waitingForOpponent)
                  _DueloWaitingOverlay(
                    opponentName: widget.opponentName,
                    opponentFlag: widget.opponentFlag,
                    opponentCountry: widget.opponentCountry,
                    opponentProgress: _opponentProgress,
                    total: widget.questions.length,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _DueloWaitingOverlay — ben bitirdim, rakip hala çözüyor
// ═══════════════════════════════════════════════════════════════════════════════
class _DueloWaitingOverlay extends StatelessWidget {
  final String opponentName;
  final String opponentFlag;
  final String opponentCountry;
  final int opponentProgress;
  final int total;
  const _DueloWaitingOverlay({
    required this.opponentName,
    required this.opponentFlag,
    required this.opponentCountry,
    required this.opponentProgress,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = total - opponentProgress;
    return Container(
      color: Colors.white.withValues(alpha: 0.96),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⏳', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 18),
            Text(
              'Rakibini Bekliyoruz'.tr(),
              style: _serif(
                size: 24,
                weight: FontWeight.w700,
                letterSpacing: -0.02,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: _sans(
                    size: 14,
                    weight: FontWeight.w500,
                    color: _Palette.inkSoft,
                    height: 1.5),
                children: [
                  TextSpan(text: '$opponentFlag '),
                  TextSpan(
                      text: '@$opponentName',
                      style: _sans(
                          size: 14,
                          weight: FontWeight.w800,
                          color: _Palette.brand)),
                  TextSpan(text: ' · $opponentCountry\n'),
                  TextSpan(text: 'henüz testi bitirmedi. '.tr()),
                  TextSpan(
                      text: '$remaining ${"soru kaldı".tr()}.',
                      style: _sans(
                          size: 14,
                          weight: FontWeight.w700,
                          color: _Palette.ink)),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : opponentProgress / total,
                  minHeight: 6,
                  backgroundColor: _Palette.line,
                  valueColor:
                      const AlwaysStoppedAnimation(_Palette.accent),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$opponentProgress / $total',
              style: _sans(
                  size: 12,
                  weight: FontWeight.w700,
                  color: _Palette.inkMute),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _DueloResultsScreen — iki taraf da bitince çıkan karşılaştırma ekranı
// ═══════════════════════════════════════════════════════════════════════════════
class _DueloResultsScreen extends StatelessWidget {
  final String subjectName;
  final String topicName;
  final int totalQuestions;
  final String scope; // world | country
  final List<_QuizQuestion> questions;
  final Map<int, int> myAnswers;
  // Ben
  final String myName;
  final String myCountry;
  final String myFlag;
  final int myCorrect;
  final int myWrong;
  final int myEmpty;
  final int myElapsed;
  // Rakip
  final String opponentName;
  final String opponentCountry;
  final String opponentFlag;
  final int opponentElo;
  final int opponentCorrect;
  final int opponentWrong;
  final int opponentEmpty;
  final int opponentElapsed;

  const _DueloResultsScreen({
    required this.subjectName,
    required this.topicName,
    required this.totalQuestions,
    required this.scope,
    required this.questions,
    required this.myAnswers,
    required this.myName,
    required this.myCountry,
    required this.myFlag,
    required this.myCorrect,
    required this.myWrong,
    required this.myEmpty,
    required this.myElapsed,
    required this.opponentName,
    required this.opponentCountry,
    required this.opponentFlag,
    required this.opponentElo,
    required this.opponentCorrect,
    required this.opponentWrong,
    required this.opponentEmpty,
    required this.opponentElapsed,
  });

  // Kazanan kararı: önce doğru sayısı, eşitse daha hızlı olan (az süre).
  int get _winner {
    if (myCorrect > opponentCorrect) return 1;
    if (opponentCorrect > myCorrect) return -1;
    if (myElapsed < opponentElapsed) return 1;
    if (opponentElapsed < myElapsed) return -1;
    return 0;
  }

  String _fmtTime(int s) {
    if (s <= 0) return '0 sn';
    final m = s ~/ 60;
    final r = s % 60;
    if (m == 0) return '$r sn';
    return "$m:${r.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final win = _winner;
    return Scaffold(
      backgroundColor: _Palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Üst bar: kapat butonu SAĞ üstte, tek pop ────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Spacer(),
                  _CircleBtn(
                    icon: Icons.close_rounded,
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              ),
            ),
            // ── Gövde scroll ──────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  children: [
                    // ── Kartların üstünde ORTALANMIŞ header:
                    //    [Dünya/Ülke rozeti]  [Ders: X]  [Konu: Y]
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: scope == 'world'
                                ? _Palette.accent.withValues(alpha: 0.12)
                                : _Palette.brand.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: scope == 'world'
                                  ? _Palette.accent
                                  : _Palette.brand,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(scope == 'world' ? '🌍' : '🇹🇷',
                                  style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 5),
                              Text(
                                scope == 'world'
                                    ? 'Dünya'.tr()
                                    : 'Ülke'.tr(),
                                style: _sans(
                                    size: 12,
                                    weight: FontWeight.w900,
                                    color: scope == 'world'
                                        ? _Palette.accent
                                        : _Palette.brand,
                                    letterSpacing: 0.3),
                              ),
                            ],
                          ),
                        ),
                        if (subjectName.isNotEmpty)
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${"Ders".tr()}: ',
                                  style: _sans(
                                      size: 13,
                                      weight: FontWeight.w700,
                                      color: _Palette.inkMute),
                                ),
                                TextSpan(
                                  text: subjectName,
                                  style: _sans(
                                      size: 13,
                                      weight: FontWeight.w900,
                                      color: _Palette.ink),
                                ),
                              ],
                            ),
                          ),
                        if (topicName.isNotEmpty)
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${"Konu".tr()}: ',
                                  style: _sans(
                                      size: 13,
                                      weight: FontWeight.w700,
                                      color: _Palette.inkMute),
                                ),
                                TextSpan(
                                  text: topicName,
                                  style: _sans(
                                      size: 13,
                                      weight: FontWeight.w900,
                                      color: _Palette.ink),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ── Skor kartı karşılaştırması (soru/doğru/yanlış/boş/süre içerir) ──
                    Builder(builder: (_) {
                      // Doğru sayıları eşitse hız belirleyici olmuş demektir.
                      final tiedOnCorrect =
                          myCorrect == opponentCorrect && myCorrect > 0;
                      final int mySpeedAdv = (tiedOnCorrect &&
                              myElapsed < opponentElapsed)
                          ? (opponentElapsed - myElapsed)
                          : 0;
                      final int oppSpeedAdv = (tiedOnCorrect &&
                              opponentElapsed < myElapsed)
                          ? (myElapsed - opponentElapsed)
                          : 0;
                      // ELO hesaplaması — standart K=32 Elo formülü.
                      // win → 1, tie → 0.5, loss → 0
                      const int myElo = 1000; // kullanıcı ELO takibi yok,
                                             //  baz 1000 kullanılıyor.
                      final double myScore = win == 1
                          ? 1.0
                          : (win == 0 ? 0.5 : 0.0);
                      final double myExpected = 1 /
                          (1 +
                              math.pow(10,
                                  (opponentElo - myElo) / 400.0));
                      final int myDelta =
                          (32 * (myScore - myExpected)).round();
                      final int oppDelta = -myDelta;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _DueloPlayerCard(
                              isWinner: win == 1,
                              isTie: win == 0,
                              name: myName,
                              country: myCountry,
                              flag: myFlag,
                              eloText: 'sen',
                              correct: myCorrect,
                              wrong: myWrong,
                              empty: myEmpty,
                              total: totalQuestions,
                              elapsed: _fmtTime(myElapsed),
                              color: _Palette.brand,
                              speedAdvantageSeconds: mySpeedAdv,
                              eloDelta: myDelta,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DueloPlayerCard(
                              isWinner: win == -1,
                              isTie: win == 0,
                              name: opponentName,
                              country: opponentCountry,
                              flag: opponentFlag,
                              eloText: '$opponentElo ELO',
                              correct: opponentCorrect,
                              wrong: opponentWrong,
                              empty: opponentEmpty,
                              total: totalQuestions,
                              elapsed: _fmtTime(opponentElapsed),
                              color: _Palette.accent,
                              speedAdvantageSeconds: oppSpeedAdv,
                              eloDelta: oppDelta,
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
            // ── Alt CTA'lar: 3 stacked buton ─────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Üst satır: iki ayrı buton yan yana.
                  Row(
                    children: [
                      Expanded(
                        child: _bottomAction(
                          icon: Icons.search_rounded,
                          label: 'Yeni Rakip Bul'.tr(),
                          filled: false,
                          onTap: () => _newOpponent(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _bottomAction(
                          icon: Icons.sports_mma_rounded,
                          label: 'Rövanş İste'.tr(),
                          filled: true,
                          onTap: () => _requestRematch(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _bottomAction(
                    icon: Icons.ios_share_rounded,
                    label: 'Sosyal medyada paylaş'.tr(),
                    filled: false,
                    onTap: () =>
                        _openShareMode(context, friendMode: false),
                  ),
                  const SizedBox(height: 8),
                  _bottomAction(
                    icon: Icons.send_rounded,
                    label: 'Arkadaşınla paylaş'.tr(),
                    filled: false,
                    onTap: () =>
                        _openShareMode(context, friendMode: true),
                  ),
                  const SizedBox(height: 8),
                  _bottomAction(
                    icon: Icons.auto_stories_rounded,
                    label: 'Yanlış yaptığın sorulara bak'.tr(),
                    filled: false,
                    onTap: () => _openMistakes(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomAction({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        decoration: BoxDecoration(
          color: filled ? _Palette.ink : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: filled ? _Palette.ink : _Palette.line,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: filled ? Colors.white : _Palette.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: _sans(
                    size: 13,
                    weight: FontWeight.w800,
                    color: filled ? Colors.white : _Palette.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shareCaption() {
    // Paylaşım mesajı: kazanç/kayıp detayı veya skor karşılaştırması yok.
    // Sadece sade bir davet — sonucun görseli zaten kartta.
    return 'QuAlsar uygulamasını indir — sen de istediğin derste, '
        'istediğin konuda, dünyada veya ülkende yarış!\nqualsar.app';
  }

  void _openShareMode(BuildContext context, {required bool friendMode}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DueloShareModePage(
          caption: _shareCaption(),
          subjectName: subjectName,
          topicName: topicName,
          totalQuestions: totalQuestions,
          scope: scope,
          myName: myName,
          myCountry: myCountry,
          myFlag: myFlag,
          myCorrect: myCorrect,
          myWrong: myWrong,
          myEmpty: myEmpty,
          myElapsed: myElapsed,
          opponentName: opponentName,
          opponentCountry: opponentCountry,
          opponentFlag: opponentFlag,
          opponentElo: opponentElo,
          opponentCorrect: opponentCorrect,
          opponentWrong: opponentWrong,
          opponentEmpty: opponentEmpty,
          opponentElapsed: opponentElapsed,
          winner: _winner,
          friendMode: friendMode,
        ),
      ),
    );
  }

  void _openMistakes(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DueloMistakesScreen(
          questions: questions,
          answers: myAnswers,
        ),
      ),
    );
  }

  // Yeni rakibe git — sonuç ekranını kapatıp taze bir lobi aç.
  void _newOpponent(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DueloLobbyScreen()),
    );
  }

  // Rövanş iste — aynı rakibe bildirim (Firestore üzerinden). Şu an dev
  // modunda olduğumuz için kullanıcıya "istek gönderildi" teyidi gösterip
  // lobi ekranına yönlendiriyoruz. Backend açılınca push notification da
  // eklenir.
  Future<void> _requestRematch(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // Best-effort: opponent'a Firestore "rematch_requests" koleksiyonuna doc
    // yaz. Hata olursa sessiz geç.
    try {
      // ignore: avoid_dynamic_calls
      await DueloMatchmakingService.requestRematch(
        opponentUsername: opponentName,
        subjectName: subjectName,
        topicName: topicName,
      );
    } catch (_) {}
    messenger.showSnackBar(SnackBar(
      content: Text(
          '@$opponentName kullanıcısına rövanş isteği gönderildi.'.tr()),
      behavior: SnackBarBehavior.floating,
    ));
    if (!context.mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DueloLobbyScreen()),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _DueloMistakesScreen — kullanıcının yanlış + boş sorularının çözümü
// ═══════════════════════════════════════════════════════════════════════════════
class _DueloMistakesScreen extends StatelessWidget {
  final List<_QuizQuestion> questions;
  final Map<int, int> answers;
  const _DueloMistakesScreen(
      {required this.questions, required this.answers});

  @override
  Widget build(BuildContext context) {
    final wrongIdx = <int>[];
    for (int i = 0; i < questions.length; i++) {
      final a = answers[i];
      if (a == null || a != questions[i].correctIndex) wrongIdx.add(i);
    }
    return Scaffold(
      backgroundColor: _Palette.bg,
      appBar: AppBar(
        backgroundColor: _Palette.bg,
        elevation: 0,
        foregroundColor: _Palette.ink,
        title: Text(
          'Yanlışlarım'.tr(),
          style: _serif(
              size: 16,
              weight: FontWeight.w800,
              letterSpacing: -0.01),
        ),
      ),
      body: wrongIdx.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🎉', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 10),
                    Text(
                      'Hiç yanlışın yok, tebrikler!'.tr(),
                      textAlign: TextAlign.center,
                      style: _sans(
                          size: 14,
                          weight: FontWeight.w700,
                          color: _Palette.inkSoft),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              itemCount: wrongIdx.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final idx = wrongIdx[i];
                final q = questions[idx];
                final picked = answers[idx];
                final isEmpty = picked == null;
                final correctLetter =
                    String.fromCharCode(65 + q.correctIndex);
                final pickedLetter = isEmpty
                    ? '—'
                    : String.fromCharCode(65 + picked);
                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _Palette.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isEmpty
                                  ? _Palette.inkMute
                                  : _Palette.error,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '${"Soru".tr()} ${idx + 1}',
                              style: _sans(
                                  size: 10,
                                  weight: FontWeight.w900,
                                  color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isEmpty
                                ? '${"Boş".tr()} · ${"Doğru".tr()}: $correctLetter'
                                : 'Senin: $pickedLetter · ${"Doğru".tr()}: $correctLetter',
                            style: _sans(
                                size: 11,
                                weight: FontWeight.w700,
                                color: _Palette.inkMute),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        q.text,
                        style: _serif(
                            size: 14,
                            weight: FontWeight.w600,
                            height: 1.35),
                      ),
                      if (q.explanation.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                            height: 1,
                            color: _Palette.line),
                        const SizedBox(height: 10),
                        Text(
                          'Çözüm'.tr(),
                          style: _sans(
                              size: 11,
                              weight: FontWeight.w900,
                              color: _Palette.inkMute,
                              letterSpacing: 0.3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          q.explanation,
                          style: _sans(
                              size: 13,
                              weight: FontWeight.w500,
                              color: _Palette.ink,
                              height: 1.5),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _DueloPlayerCard extends StatelessWidget {
  final bool isWinner;
  final bool isTie;
  final String name;
  final String country;
  final String flag;
  final String eloText;
  final int correct;
  final int wrong;
  final int empty;
  final int total;
  final String elapsed;
  final Color color;
  // Doğru sayıları eşitken hız kazandırdıysa pozitif saniye farkı
  // (0 veya negatif ise hız avantajı gösterilmez). Kaybeden tarafta da
  // opponent hızlıysa gösterilecek.
  final int speedAdvantageSeconds;
  // Bu maç sonrası ELO değişimi. 0 ise gösterilmez, pozitif → yeşil +N,
  // negatif → kırmızı N pill'i ELO yazısının yanında çıkar.
  final int eloDelta;
  const _DueloPlayerCard({
    required this.isWinner,
    required this.isTie,
    required this.name,
    required this.country,
    required this.flag,
    required this.eloText,
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.total,
    required this.elapsed,
    required this.color,
    this.speedAdvantageSeconds = 0,
    this.eloDelta = 0,
  });

  static const Color _goldTop = Color(0xFFFFD24D);
  static const Color _goldMid = Color(0xFFF5B301);
  static const Color _goldDeep = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) {
    // Her iki kart aynı boyda — çerçeve kalınlığı eş. Kazanan sadece
    // altın kenar rengi + rozet + bayrak konfetisi ile ayırt ediliyor.
    final borderColor = isWinner
        ? _goldMid
        : (isTie ? _Palette.ink : _Palette.line);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        children: [
          if (isWinner)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_goldTop, _goldMid, _goldDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: _goldMid.withValues(alpha: 0.5),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(
                    'KAZANAN'.tr(),
                    style: _sans(
                        size: 10,
                        weight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.1),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 21),
          const SizedBox(height: 6),
          // Kimlik bloğu — bayrak (kazananın yanlarında konfeti).
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isWinner)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('🎉', style: TextStyle(fontSize: 20)),
                ),
              Text(flag, style: const TextStyle(fontSize: 34)),
              if (isWinner)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('🎊', style: TextStyle(fontSize: 20)),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            country,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _sans(
                size: 13.5,
                weight: FontWeight.w800,
                color: _Palette.ink,
                letterSpacing: 0.1),
          ),
          const SizedBox(height: 1),
          Text(
            '@$name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _sans(
                size: 13,
                weight: FontWeight.w700,
                color: _Palette.inkMute),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _Palette.surface,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  eloText,
                  style: _sans(
                      size: 10,
                      weight: FontWeight.w800,
                      color: _Palette.inkMute,
                      letterSpacing: 0.2),
                ),
              ),
              if (eloDelta != 0) ...[
                const SizedBox(width: 4),
                _DeltaPill(delta: eloDelta),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // ══ Donut grafik (ortalanmış) + altında stat tablosu ══
          _StatsDonutBlock(
            correct: correct,
            wrong: wrong,
            empty: empty,
            total: total,
            elapsed: elapsed,
            speedAdvantageSeconds: speedAdvantageSeconds,
            isWinner: isWinner,
          ),
        ],
      ),
    );
  }
}

// Donut grafik (ortalanmış, kullanıcı adı altında) + altında ince çerçeveli
// stat kutusu (soru, doğru, yanlış, boş, süre).
// ELO değişimi mini pill — pozitifte yeşil, negatifte kırmızı, ok ikonlu.
class _DeltaPill extends StatelessWidget {
  final int delta;
  const _DeltaPill({required this.delta});

  @override
  Widget build(BuildContext context) {
    final positive = delta > 0;
    final zero = delta == 0;
    final color = zero
        ? _Palette.inkMute
        : (positive
            ? const Color(0xFF059669)
            : const Color(0xFFDC2626));
    final label = zero
        ? '0'
        : (positive ? '+$delta' : '$delta');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
            color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsDonutBlock extends StatelessWidget {
  final int correct;
  final int wrong;
  final int empty;
  final int total;
  final String elapsed;
  final int speedAdvantageSeconds;
  final bool isWinner;
  const _StatsDonutBlock({
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.total,
    required this.elapsed,
    this.speedAdvantageSeconds = 0,
    this.isWinner = false,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF059669);
    const red = Color(0xFFDC2626);
    const gray = Color(0xFF6B7280);

    int pctOf(int n) => total == 0 ? 0 : ((n * 100) / total).round();
    final pct = pctOf(correct);

    final sections = <PieChartSectionData>[];
    void addSlice(int v, Color c) {
      if (v <= 0) return;
      sections.add(PieChartSectionData(
        value: v.toDouble(),
        color: c,
        radius: 14,
        showTitle: false,
      ));
    }

    addSlice(correct, green);
    addSlice(wrong, red);
    addSlice(empty, gray);
    if (sections.isEmpty) {
      sections.add(PieChartSectionData(
        value: 1,
        color: gray.withValues(alpha: 0.3),
        radius: 14,
        showTitle: false,
      ));
    }

    return Column(
      children: [
        // ── Ortalanmış donut grafik ─────────────────────────────
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 24,
                  sectionsSpace: 2,
                  startDegreeOffset: -90,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '%$pct',
                    style: _serif(
                        size: 16,
                        weight: FontWeight.w900,
                        letterSpacing: -0.02,
                        color: _Palette.ink),
                  ),
                  Text(
                    'Başarı'.tr(),
                    style: _sans(
                        size: 7,
                        weight: FontWeight.w800,
                        color: _Palette.inkMute,
                        letterSpacing: 0.6),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // ── Altta küçük çerçeveli stat kutusu ────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F1EA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _Palette.line.withValues(alpha: 0.7), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _statRow(
                  Icons.check_rounded, 'Doğru'.tr(), '$correct', green),
              _statRow(
                  Icons.close_rounded, 'Yanlış'.tr(), '$wrong', red),
              if (empty > 0)
                _statRow(
                    Icons.remove_rounded, 'Boş'.tr(), '$empty', gray),
              _timeRow(),
            ],
          ),
        ),
      ],
    );
  }

  // Süre satırı — hız avantajı varsa altın rozet + "X sn daha hızlı".
  Widget _timeRow() {
    final int diff = speedAdvantageSeconds.abs();
    // Sadece eşit doğru ve bu taraf kazanan + >0 diff iken vurgu belirgin.
    final bool highlight = isWinner && diff > 0;
    final Color color = highlight ? const Color(0xFFB45309) : _Palette.ink;
    final Color bg = highlight
        ? const Color(0xFFFFD24D).withValues(alpha: 0.22)
        : Colors.transparent;
    return Container(
      padding: highlight
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 0, vertical: 3),
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.timer_rounded, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                'Süre'.tr(),
                style: _sans(
                    size: 12.5,
                    weight: FontWeight.w800,
                    color: color),
              ),
              const Spacer(),
              Text(
                elapsed,
                style: _sans(
                    size: 13.5,
                    weight: FontWeight.w900,
                    color: color),
              ),
            ],
          ),
          if (highlight) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(Icons.bolt_rounded,
                    size: 12, color: Color(0xFFB45309)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$diff ${"sn daha hızlı".tr()}',
                    style: _sans(
                        size: 10.5,
                        weight: FontWeight.w800,
                        color: const Color(0xFFB45309),
                        letterSpacing: 0.1),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statRow(
      IconData icon, String label, String value, Color valueColor) {
    // Etiket + değer aynı renkte, biraz daha büyük fontlarla.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: valueColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: _sans(
                size: 12.5,
                weight: FontWeight.w800,
                color: valueColor),
          ),
          const Spacer(),
          Text(
            value,
            style: _sans(
                size: 13.5,
                weight: FontWeight.w900,
                color: valueColor),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _DueloShareModePage — paylaşım modu: iki oyuncu karşılaştırma kartı,
//  her biri donut grafik içerir; altında QR kod ve renk seçici.
// ═══════════════════════════════════════════════════════════════════════════════
class _DueloShareModePage extends StatefulWidget {
  final String caption;
  final String subjectName;
  final String topicName;
  final int totalQuestions;
  final String scope;
  final String myName;
  final String myCountry;
  final String myFlag;
  final int myCorrect;
  final int myWrong;
  final int myEmpty;
  final int myElapsed;
  final String opponentName;
  final String opponentCountry;
  final String opponentFlag;
  final int opponentElo;
  final int opponentCorrect;
  final int opponentWrong;
  final int opponentEmpty;
  final int opponentElapsed;
  final int winner; // 1=ben, -1=rakip, 0=berabere
  final bool friendMode;

  const _DueloShareModePage({
    required this.caption,
    required this.subjectName,
    required this.topicName,
    required this.totalQuestions,
    required this.scope,
    required this.myName,
    required this.myCountry,
    required this.myFlag,
    required this.myCorrect,
    required this.myWrong,
    required this.myEmpty,
    required this.myElapsed,
    required this.opponentName,
    required this.opponentCountry,
    required this.opponentFlag,
    required this.opponentElo,
    required this.opponentCorrect,
    required this.opponentWrong,
    required this.opponentEmpty,
    required this.opponentElapsed,
    required this.winner,
    required this.friendMode,
  });

  @override
  State<_DueloShareModePage> createState() => _DueloShareModePageState();
}

class _DueloShareModePageState extends State<_DueloShareModePage> {
  // Test paylaşım modundaki 10 renk paleti — tek kaynağı tutarlı tutuyor.
  static const _palette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF4B5563),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFEF3C7),
    Color(0xFFFBBF24),
    Color(0xFFD97706),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFF047857),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFF1E40AF),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFF4C1D95),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  // Hangi çerçevenin rengi değiştirilsin — 'card' (büyük), 'me' (kendi),
  // 'opp' (rakip).
  String _target = 'card';
  Color _bg = Colors.white;
  Color _myBoxBg = Colors.white;
  Color _oppBoxBg = Colors.white;
  bool _sharing = false;
  final GlobalKey _shotKey = GlobalKey();

  Color _currentTargetColor() {
    switch (_target) {
      case 'me':
        return _myBoxBg;
      case 'opp':
        return _oppBoxBg;
      default:
        return _bg;
    }
  }

  void _applyColor(Color c) {
    setState(() {
      switch (_target) {
        case 'me':
          _myBoxBg = c;
          break;
        case 'opp':
          _oppBoxBg = c;
          break;
        default:
          _bg = c;
      }
    });
  }

  String _targetLabel() {
    switch (_target) {
      case 'me':
        return 'Kendi Çerçeven'.tr();
      case 'opp':
        return 'Rakip Çerçeve'.tr();
      default:
        return 'Büyük Çerçeve'.tr();
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    Rect? origin;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _shotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Kart hazır değil.');
      if (boundary.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('PNG dönüşümü başarısız.');
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/qualsar_duelo_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'qualsar_duelo.png')],
        text: widget.caption,
        subject: 'QuAlsar Bilgi Yarışı',
        sharePositionOrigin: origin,
      );
    } catch (e, st) {
      debugPrint('[DueloShare] hata: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Paylaşılamadı: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  bool get _isBgDark {
    final l = (0.299 * _bg.r + 0.587 * _bg.g + 0.114 * _bg.b);
    return l < 0.6;
  }

  @override
  Widget build(BuildContext context) {
    const pageBg = _Palette.bg;
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: _Palette.ink,
        centerTitle: true,
        title: Text(
          widget.friendMode
              ? 'Arkadaşınla paylaş'.tr()
              : 'Sosyal medyada paylaş'.tr(),
          style: _sans(size: 14, weight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(context).size.width * 0.92,
                      ),
                      child: RepaintBoundary(
                        key: _shotKey,
                        child: _DueloShareCard(
                          bgColor: _bg,
                          myBoxBg: _myBoxBg,
                          oppBoxBg: _oppBoxBg,
                          isBgDark: _isBgDark,
                          scope: widget.scope,
                          subjectName: widget.subjectName,
                          topicName: widget.topicName,
                          totalQuestions: widget.totalQuestions,
                          winner: widget.winner,
                          myName: widget.myName,
                          myCountry: widget.myCountry,
                          myFlag: widget.myFlag,
                          myCorrect: widget.myCorrect,
                          myWrong: widget.myWrong,
                          myEmpty: widget.myEmpty,
                          myElapsed: widget.myElapsed,
                          opponentName: widget.opponentName,
                          opponentCountry: widget.opponentCountry,
                          opponentFlag: widget.opponentFlag,
                          opponentElo: widget.opponentElo,
                          opponentCorrect: widget.opponentCorrect,
                          opponentWrong: widget.opponentWrong,
                          opponentEmpty: widget.opponentEmpty,
                          opponentElapsed: widget.opponentElapsed,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(child: _colorPickerButton()),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _sharing ? null : _share,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: _sharing
                        ? Colors.black38
                        : const Color(0xFFFF6A00),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_sharing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(Icons.ios_share_rounded,
                            color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _sharing
                            ? 'Hazırlanıyor…'.tr()
                            : 'Paylaş'.tr(),
                        style: _sans(
                            size: 14,
                            weight: FontWeight.w900,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorPickerButton() {
    return GestureDetector(
      onTap: _openColorSheet,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _Palette.ink, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: _currentTargetColor(),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black26, width: 1),
              ),
            ),
            const SizedBox(width: 9),
            const Icon(Icons.palette_rounded,
                size: 15, color: _Palette.ink),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Kart Rengini Seç'.tr(),
                  style: _sans(
                      size: 12.5,
                      weight: FontWeight.w900,
                      color: _Palette.ink),
                ),
                Text(
                  _targetLabel(),
                  style: _sans(
                      size: 9.5,
                      weight: FontWeight.w700,
                      color: const Color(0xFFFF6A00),
                      letterSpacing: 0.2),
                ),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_drop_down_rounded,
                size: 20, color: _Palette.ink),
          ],
        ),
      ),
    );
  }

  Future<void> _openColorSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        // Sheet kendi state'ini tutsun ki target değişince anında
        // güncellensin; picking renge basınca parent state'e yansıtıp kapanır.
        return StatefulBuilder(builder: (ctx, setSheetState) {
          void pickTarget(String t) {
            setState(() => _target = t);
            setSheetState(() {});
          }

          return SafeArea(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Başlık satırı: sol "Kart Rengini Seç", sağda TAMAMLA
                  // butonu — renk seçimleri sheet kapanmadan yapılabilir,
                  // kullanıcı "Tamamla" dediğinde sheet kapanır.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.palette_rounded,
                          size: 18, color: _Palette.ink),
                      const SizedBox(width: 8),
                      Text(
                        'Kart Rengini Seç'.tr(),
                        style: _sans(
                            size: 15,
                            weight: FontWeight.w900,
                            color: _Palette.ink),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(sheetCtx).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6A00),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_rounded,
                                  size: 14, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                'Tamamla'.tr(),
                                style: _sans(
                                    size: 12,
                                    weight: FontWeight.w900,
                                    color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _targetSegment(pickTarget),
                  const SizedBox(height: 14),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 6,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.0,
                    children: [
                      for (final c in _palette)
                        _sheetSwatch(c, onPick: () {
                          // Sheet KAPANMIYOR — kullanıcı istediği kadar
                          // farklı hedef + renk deneyebilsin. Kapatma
                          // sadece üstteki "Tamamla" butonu ile.
                          _applyColor(c);
                          setSheetState(() {});
                        }),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _targetSegment(void Function(String) pick) {
    // 3 pill — hangi çerçevenin rengi değiştirilecek?
    Widget chip({
      required String id,
      required IconData icon,
      required String label,
    }) {
      final active = _target == id;
      final previewColor = id == 'card'
          ? _bg
          : (id == 'me' ? _myBoxBg : _oppBoxBg);
      return Expanded(
        child: GestureDetector(
          onTap: () => pick(id),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFFFF6A00).withValues(alpha: 0.12)
                  : _Palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    active ? const Color(0xFFFF6A00) : _Palette.line,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: 14,
                        color: active
                            ? const Color(0xFFFF6A00)
                            : _Palette.ink),
                    const SizedBox(width: 5),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: previewColor,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                            color: Colors.black26, width: 0.8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _sans(
                      size: 10.5,
                      weight: FontWeight.w800,
                      color: active
                          ? const Color(0xFFFF6A00)
                          : _Palette.ink),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(
          id: 'card',
          icon: Icons.crop_square_rounded,
          label: 'Büyük Çerçeve'.tr(),
        ),
        const SizedBox(width: 8),
        chip(
          id: 'me',
          icon: Icons.person_rounded,
          label: 'Kendi Çerçeven'.tr(),
        ),
        const SizedBox(width: 8),
        chip(
          id: 'opp',
          icon: Icons.people_rounded,
          label: 'Rakip Çerçeve'.tr(),
        ),
      ],
    );
  }

  Widget _sheetSwatch(Color c, {required VoidCallback onPick}) {
    final selected = _bg == c;
    final lum = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
    final dark = lum < 0.6;
    return GestureDetector(
      onTap: onPick,
      child: Container(
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF6A00)
                : Colors.black26,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Center(
                child: Icon(Icons.check_rounded,
                    size: 20,
                    color: dark ? Colors.white : Colors.black),
              )
            : null,
      ),
    );
  }
}

// Paylaşılacak kart — başlık + iki oyuncu kutusu (her biri donut grafikli)
// + alt marka ve QR kod.
class _DueloShareCard extends StatelessWidget {
  final Color bgColor;
  final Color myBoxBg;
  final Color oppBoxBg;
  final bool isBgDark;
  final String scope;
  final String subjectName;
  final String topicName;
  final int totalQuestions;
  final int winner;
  final String myName;
  final String myCountry;
  final String myFlag;
  final int myCorrect;
  final int myWrong;
  final int myEmpty;
  final int myElapsed;
  final String opponentName;
  final String opponentCountry;
  final String opponentFlag;
  final int opponentElo;
  final int opponentCorrect;
  final int opponentWrong;
  final int opponentEmpty;
  final int opponentElapsed;

  const _DueloShareCard({
    required this.bgColor,
    required this.myBoxBg,
    required this.oppBoxBg,
    required this.isBgDark,
    required this.scope,
    required this.subjectName,
    required this.topicName,
    required this.totalQuestions,
    required this.winner,
    required this.myName,
    required this.myCountry,
    required this.myFlag,
    required this.myCorrect,
    required this.myWrong,
    required this.myEmpty,
    required this.myElapsed,
    required this.opponentName,
    required this.opponentCountry,
    required this.opponentFlag,
    required this.opponentElo,
    required this.opponentCorrect,
    required this.opponentWrong,
    required this.opponentEmpty,
    required this.opponentElapsed,
  });

  Color get _ink => isBgDark ? Colors.white : _Palette.ink;
  Color get _inkMute =>
      isBgDark ? Colors.white70 : _Palette.inkMute;

  String _fmtTime(int s) {
    if (s <= 0) return '0 sn';
    final m = s ~/ 60;
    final r = s % 60;
    if (m == 0) return '$r sn';
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: isBgDark ? Colors.white24 : Colors.black,
            width: 1.2),
      ),
      child: Column(
        children: [
          // ── QuAlsar marka başlığı ──────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('✦',
                  style: TextStyle(
                      color: isBgDark
                          ? Colors.white
                          : const Color(0xFFC8102E),
                      fontSize: 12)),
              const SizedBox(width: 8),
              Text(
                'QuAlsar',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: isBgDark
                      ? Colors.white
                      : const Color(0xFFC8102E),
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(width: 8),
              Text('✦',
                  style: TextStyle(
                      color: isBgDark
                          ? Colors.white
                          : const Color(0xFFC8102E),
                      fontSize: 12)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Bilgi Yarışı'.tr().toUpperCase(),
            style: _sans(
                size: 10,
                weight: FontWeight.w800,
                color: _inkMute,
                letterSpacing: 1.6),
          ),
          const SizedBox(height: 10),
          // ── Header: scope + ders + konu ────────────────────────
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip(scope == 'world' ? '🌍 ${"Dünya".tr()}' : '🇹🇷 ${"Ülke".tr()}'),
              if (subjectName.isNotEmpty)
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${"Ders".tr()}: ',
                      style: _sans(
                          size: 12,
                          weight: FontWeight.w700,
                          color: _inkMute)),
                  TextSpan(
                      text: subjectName,
                      style: _sans(
                          size: 12,
                          weight: FontWeight.w900,
                          color: _ink)),
                ])),
              if (topicName.isNotEmpty)
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${"Konu".tr()}: ',
                      style: _sans(
                          size: 12,
                          weight: FontWeight.w700,
                          color: _inkMute)),
                  TextSpan(
                      text: topicName,
                      style: _sans(
                          size: 12,
                          weight: FontWeight.w900,
                          color: _ink)),
                ])),
            ],
          ),
          const SizedBox(height: 14),
          // ── İki oyuncu kutusu, her biri donut + stats ──────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DueloShareUserBox(
                  isWinner: winner == 1,
                  isTie: winner == 0,
                  name: myName,
                  country: myCountry,
                  flag: myFlag,
                  eloText: 'sen',
                  correct: myCorrect,
                  wrong: myWrong,
                  empty: myEmpty,
                  total: totalQuestions,
                  elapsed: _fmtTime(myElapsed),
                  isBgDark: isBgDark,
                  accent: const Color(0xFFFF6A00),
                  boxBg: myBoxBg,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DueloShareUserBox(
                  isWinner: winner == -1,
                  isTie: winner == 0,
                  name: opponentName,
                  country: opponentCountry,
                  flag: opponentFlag,
                  eloText: '$opponentElo ELO',
                  correct: opponentCorrect,
                  wrong: opponentWrong,
                  empty: opponentEmpty,
                  total: totalQuestions,
                  elapsed: _fmtTime(opponentElapsed),
                  isBgDark: isBgDark,
                  accent: const Color(0xFF2563EB),
                  boxBg: oppBoxBg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── Footer: marka (sol) + "Uygulamayı indir" + QR (sağ) ─
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QuAlsar ile çözüldü'.tr(),
                      style: _sans(
                          size: 11,
                          weight: FontWeight.w700,
                          color: _ink,
                          letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'qualsar.app',
                      style: _sans(
                          size: 12,
                          weight: FontWeight.w900,
                          color: isBgDark
                              ? Colors.white
                              : const Color(0xFFC8102E),
                          letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Uygulamayı indir'.tr(),
                      style: _sans(
                          size: 10,
                          weight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.black12, width: 1),
                      ),
                      child: QrImageView(
                        data: 'https://qualsar.app',
                        version: QrVersions.auto,
                        size: 54,
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isBgDark ? Colors.white : Colors.black)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
            color: (isBgDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: _sans(
            size: 11, weight: FontWeight.w900, color: _ink),
      ),
    );
  }
}

// Tek oyuncu kutusu — donut grafik + sayısal özet.
class _DueloShareUserBox extends StatelessWidget {
  final bool isWinner;
  final bool isTie;
  final String name;
  final String country;
  final String flag;
  final String eloText;
  final int correct;
  final int wrong;
  final int empty;
  final int total;
  final String elapsed;
  final bool isBgDark;
  final Color accent;
  // Kutunun iç zemini — kullanıcı renk seçici ile değiştirebilir.
  final Color boxBg;

  const _DueloShareUserBox({
    required this.isWinner,
    required this.isTie,
    required this.name,
    required this.country,
    required this.flag,
    required this.eloText,
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.total,
    required this.elapsed,
    required this.isBgDark,
    required this.accent,
    required this.boxBg,
  });

  bool get _darkBox {
    final l = (0.299 * boxBg.r + 0.587 * boxBg.g + 0.114 * boxBg.b);
    return l < 0.6;
  }

  Color get _boxInk => _darkBox ? Colors.white : _Palette.ink;
  Color get _boxInkMute => _darkBox ? Colors.white70 : _Palette.inkMute;

  int _pct() => total == 0 ? 0 : ((correct * 100) / total).round();

  @override
  Widget build(BuildContext context) {
    final borderCol = isWinner
        ? accent
        : (isBgDark ? Colors.white24 : Colors.black12);
    final borderW = isWinner ? 2.0 : 1.0;

    const green = Color(0xFF059669);
    const red = Color(0xFFDC2626);
    const gray = Color(0xFF9CA3AF);

    // Dilim açıları orantılı; iç kısımda label gösterilmiyor (küçük donut).
    final sections = <PieChartSectionData>[];
    void addSlice(int v, Color c) {
      if (v <= 0) return;
      sections.add(PieChartSectionData(
        value: v.toDouble(),
        color: c,
        radius: 12,
        showTitle: false,
      ));
    }

    addSlice(correct, green);
    addSlice(wrong, red);
    addSlice(empty, gray);
    if (sections.isEmpty) {
      sections.add(PieChartSectionData(
        value: 1,
        color: gray.withValues(alpha: 0.3),
        radius: 12,
        showTitle: false,
      ));
    }

    final pct = _pct();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol, width: borderW),
      ),
      child: Column(
        children: [
          if (isWinner)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text('🏆 Kazanan'.tr(),
                  style: _sans(
                      size: 8,
                      weight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5)),
            )
          else
            const SizedBox(height: 14),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isWinner)
                const Padding(
                  padding: EdgeInsets.only(right: 5),
                  child: Text('🎉', style: TextStyle(fontSize: 17)),
                ),
              Text(flag, style: const TextStyle(fontSize: 30)),
              if (isWinner)
                const Padding(
                  padding: EdgeInsets.only(left: 5),
                  child: Text('🎊', style: TextStyle(fontSize: 17)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            country,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _sans(
                size: 12.5,
                weight: FontWeight.w800,
                color: _boxInk),
          ),
          Text(
            '@$name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _sans(
                size: 12,
                weight: FontWeight.w700,
                color: _boxInkMute),
          ),
          const SizedBox(height: 6),
          // ══ Ortalanmış donut — kullanıcı adının altında ═════════
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 20,
                    sectionsSpace: 2,
                    startDegreeOffset: -90,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '%$pct',
                      style: _serif(
                          size: 13,
                          weight: FontWeight.w900,
                          letterSpacing: -0.02,
                          color: _boxInk),
                    ),
                    Text(
                      'Başarı'.tr(),
                      style: _sans(
                          size: 6.5,
                          weight: FontWeight.w800,
                          color: _boxInkMute,
                          letterSpacing: 0.6),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ══ Küçük çerçeveli stat kutusu — etiket ve değer eş renk ══
          Container(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
            decoration: BoxDecoration(
              color: _darkBox
                  ? Colors.white.withValues(alpha: 0.12)
                  : const Color(0xFFF5F1EA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (_darkBox ? Colors.white : Colors.black)
                    .withValues(alpha: 0.14),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sbStat('Doğru'.tr(), '$correct', green),
                _sbStat('Yanlış'.tr(), '$wrong', red),
                if (empty > 0) _sbStat('Boş'.tr(), '$empty', gray),
                _sbStat('Süre'.tr(), elapsed, _boxInk),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _darkBox
                  ? Colors.white.withValues(alpha: 0.16)
                  : _Palette.surface,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              eloText,
              style: _sans(
                  size: 8.5,
                  weight: FontWeight.w800,
                  color: _boxInkMute),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sbStat(String label, String value, Color valueColor) {
    // Etiket ve değer aynı renkte, biraz büyütüldü.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: _sans(
                size: 11,
                weight: FontWeight.w800,
                color: valueColor),
          ),
          const Spacer(),
          Text(value,
              style: _sans(
                  size: 12,
                  weight: FontWeight.w900,
                  color: valueColor)),
        ],
      ),
    );
  }
}

class _DueloAvatar extends StatelessWidget {
  final String name;
  final String avatar;
  final double progress;
  final Color color;
  final String flag;
  // true → sağ tarafa konumlanır: avatar/flag sağda, isim soldan ellipsis.
  // Simetri için VS'in sağındaki avatar bu modda çalışır.
  final bool mirror;
  const _DueloAvatar({
    required this.name,
    required this.avatar,
    required this.progress,
    required this.color,
    required this.flag,
    this.mirror = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatarCircle = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      alignment: Alignment.center,
      child: Text(avatar,
          style: _sans(size: 11, weight: FontWeight.w800, color: Colors.white)),
    );
    final flagText = Text(flag, style: const TextStyle(fontSize: 11));
    final nameText = Flexible(
      child: Text(
        '@$name',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: mirror ? TextAlign.right : TextAlign.left,
        style: _sans(size: 11, weight: FontWeight.w700),
      ),
    );

    final children = mirror
        ? <Widget>[
            nameText,
            const SizedBox(width: 4),
            flagText,
            const SizedBox(width: 6),
            avatarCircle,
          ]
        : <Widget>[
            avatarCircle,
            const SizedBox(width: 6),
            flagText,
            const SizedBox(width: 4),
            nameText,
          ];

    return Expanded(
      child: Column(
        crossAxisAlignment:
            mirror ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                mirror ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: children,
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: _Palette.line,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ARKADAŞLAR — mock feed (gerçek backend sonrası dolacak)
// ═══════════════════════════════════════════════════════════════════════════════
class _FriendsSection extends StatelessWidget {
  const _FriendsSection();

  @override
  Widget build(BuildContext context) {
    final feed = const [
      ('deniz.k', 'D', '🇹🇷', 'Matematik testinde %95 yaptı', '12 dk önce', '🎯'),
      ('lukas_m', 'L', '🇩🇪', 'Günlük meydan okumayı bitirdi', '1 saat önce', '🌍'),
      ('zeynep_y', 'Z', '🇹🇷', '7 gün streak yaptı', '3 saat önce', '🔥'),
      ('priya_s', 'P', '🇮🇳', 'Efsanevi lige yükseldi', '5 saat önce', '👑'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Text('Arkadaşların'.tr(),
                  style: _serif(size: 20, weight: FontWeight.w600, letterSpacing: -0.02)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showFriendsInfoSheet(context),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _Palette.brand.withValues(alpha: 0.12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.question_mark_rounded, size: 13, color: _Palette.brand),
                ),
              ),
            ],
          ),
        ),
        // Büyük turuncu, yatayda geniş "Arkadaş Ekle" butonu
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: GestureDetector(
            onTap: () => _showAddFriendSheet(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_Palette.brand, _Palette.brandDeep],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _Palette.brand.withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.person_add_rounded, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Arkadaş Ekle'.tr(),
                            style: _sans(size: 15, weight: FontWeight.w800, color: Colors.white, letterSpacing: -0.01)),
                        const SizedBox(height: 2),
                        Text('QR, rehber veya davet linkiyle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _sans(size: 11, color: Colors.white.withValues(alpha: 0.88))),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                ],
              ),
            ),
          ),
        ),
        for (int i = 0; i < feed.length; i++)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, i == feed.length - 1 ? 0 : 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _Palette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _Palette.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _avatarColors[feed[i].$1.hashCode.abs() % _avatarColors.length],
                    ),
                    alignment: Alignment.center,
                    child: Text(feed[i].$2,
                        style: _sans(size: 13, weight: FontWeight.w800, color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(feed[i].$3, style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text('@${feed[i].$1}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _sans(size: 12, weight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(feed[i].$4,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _sans(size: 11, color: _Palette.inkSoft)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(feed[i].$6, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 4),
                  Text(feed[i].$5.split(' ').first,
                      style: _sans(size: 10, color: _Palette.inkMute)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

void _showFriendsInfoSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Container(
      decoration: const BoxDecoration(
        color: _Palette.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('👥'.tr(), style: TextStyle(fontSize: 26)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Arkadaşlar Nasıl Çalışır?'.tr(),
                    style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _Palette.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _Palette.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Text('💬'.tr(), style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mesajlaşma yok — sadece birlikte öğrenme ve yarışma.',
                    style: _sans(size: 12, color: _Palette.accent, weight: FontWeight.w700, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _friendsRule('🏆', 'Bilgi yarışı yap', 'Arkadaşını yarışmaya davet et, aynı 5 soruyu aynı anda çözün. Kim daha hızlı?'),
          _friendsRule('📊', 'Karşılaştır', 'Ders-ders kim daha iyi? QP, seri, lig karşılaştırması profilde.'),
          _friendsRule('📰', 'Aktivite feed\'i', 'Arkadaşın test çözdüğünde, lig atladığında, rozet kazandığında anasayfada görürsün.'),
          _friendsRule('🏆', 'Arkadaş sıralaması', 'Sıralama sayfasında "Arkadaşlar" sekmesi → sadece eklediklerin.'),
          _friendsRule('🎁', 'Davet = ödül', 'Arkadaş ekle, kabul ederse ikiniz de +50 QP kazanın.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _Palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _Palette.line),
            ),
            child: Row(
              children: [
                Text('🔒'.tr(), style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sadece eklediğin kişiler seni görür. Kullanıcı adın profilinde gizli de olabilir.',
                    style: _sans(size: 11, color: _Palette.inkSoft, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _friendsRule(String emoji, String title, String desc) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _Palette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _Palette.line),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _sans(size: 13, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(desc, style: _sans(size: 12, color: _Palette.inkSoft, height: 1.35)),
            ],
          ),
        ),
      ],
    ),
  );
}

void _showAddFriendSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _AddFriendSheet(),
  );
}

class _AddFriendSheet extends StatefulWidget {
  const _AddFriendSheet();
  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
  final _searchCtrl = TextEditingController();

  static const _suggestions = [
    ('elifm', 'E', '🇹🇷', 'Lise 10', 'Tanıdığın 3 kişi ekledi'),
    ('arda_2010', 'A', '🇹🇷', 'Lise 10', 'Aynı sınıf'),
    ('kaan.ak', 'K', '🇹🇷', 'Lise 10', 'Haftalık sıralamada yakın'),
    ('bahar_c', 'B', '🇹🇷', 'Lise 10', 'Aynı bölümden'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<dynamic> _filteredSuggestions() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _suggestions;
    return _suggestions.where((s) => s.$1.toLowerCase().contains(q)).toList();
  }

  void _sendRequest(BuildContext context, String username) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text('📨'.tr(), style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text('@$username\'a istek gönderildi')),
          ],
        ),
        backgroundColor: _Palette.ink,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final suggestions = _filteredSuggestions();
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => Container(
          decoration: const BoxDecoration(
            color: _Palette.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _Palette.inkMute,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Arkadaş Ekle'.tr(),
                  style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
              const SizedBox(height: 4),
              Text(
                'Birini ekle → düello yapabilirsiniz, karşılaştırabilirsiniz. Mesajlaşma yok.',
                style: _sans(size: 12, color: _Palette.inkMute, height: 1.4),
              ),
              const SizedBox(height: 16),
              // Arama
              _buildSearchField(),
              const SizedBox(height: 18),
              // Hızlı yöntemler
              Text('HIZLI YÖNTEMLER'.tr(),
                  style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _QuickMethod(
                      emoji: '📲',
                      label: 'QR Kod',
                      sub: 'Göster / tara',
                      onTap: () => _showQRSheet(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickMethod(
                      emoji: '🔗',
                      label: 'Davet Linki',
                      sub: 'Paylaş',
                      onTap: () async {
                        final link = 'https://qualsar.app/davet/$_currentUsername';
                        await Share.share(
                          'QuAlsar Arena\'da benimle yarış! 🏆\n'
                          '@$_currentUsername davet ediyor · kabul edince ikimiz de +50 QP kazanırız.\n\n'
                          '$link',
                          subject: 'QuAlsar Arena daveti',
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickMethod(
                      emoji: '📞',
                      label: 'Rehber',
                      sub: 'Kontaktları tara',
                      onTap: () {
                        Navigator.pop(context);
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => const _ContactsSheet(),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              // Öneriler
              Text(_searchCtrl.text.isEmpty ? 'ÖNERİLEN KİŞİLER' : 'ARAMA SONUÇLARI',
                  style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
              const SizedBox(height: 10),
              if (suggestions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _Palette.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _Palette.line),
                  ),
                  child: Row(
                    children: [
                      Text('🔍'.tr(), style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Kullanıcı bulunamadı. Davet linki gönderebilirsin.'.tr(),
                            style: _sans(size: 12, color: _Palette.inkMute)),
                      ),
                    ],
                  ),
                )
              else
                for (final s in suggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SuggestionRow(
                      username: s.$1 as String,
                      avatar: s.$2 as String,
                      flag: s.$3 as String,
                      grade: s.$4 as String,
                      reason: s.$5 as String,
                      onAdd: () => _sendRequest(context, s.$1 as String),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Palette.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: _Palette.inkMute),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: _sans(size: 14, weight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: '@kullanıcı adı ara'.tr(),
                hintStyle: _sans(size: 13, color: _Palette.inkMute),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _searchCtrl.clear()),
              child: Icon(Icons.close_rounded, size: 16, color: _Palette.inkMute),
            ),
        ],
      ),
    );
  }

  void _showQRSheet(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
            ),
            const SizedBox(height: 18),
            Text('Senin QR Kodun',
                style: _serif(size: 20, weight: FontWeight.w600, letterSpacing: -0.02)),
            const SizedBox(height: 4),
            Text('Arkadaşın okutsun, ekleme isteği gelsin'.tr(),
                style: _sans(size: 11, color: _Palette.inkMute)),
            const SizedBox(height: 18),
            Container(
              width: 200,
              height: 200,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _Palette.line),
              ),
              child: CustomPaint(painter: _QrPainter()),
            ),
            const SizedBox(height: 14),
            Text('@$_currentUsername',
                style: _sans(size: 16, weight: FontWeight.w800)),
            const SizedBox(height: 18),
            _PrimaryButton(
              label: '📷 Arkadaşının QR Kodunu Tara'.tr(),
              brand: true,
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => _QrScanDialog(),
                );
              },
            ),
            const SizedBox(height: 8),
            _SecondaryButton(
              label: '🔗 QR Yerine Linki Paylaş'.tr(),
              onTap: () async {
                final nav = Navigator.of(context);
                final link = 'https://qualsar.app/davet/$_currentUsername';
                final shareText = "QuAlsar Arena'da benimle yarış! 🏆\n"
                    '@$_currentUsername davet ediyor · $link';
                await Share.share(shareText);
                if (nav.mounted) nav.pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Basit QR görselleştirici (gerçek QR kod paketi ile değiştirilebilir)
// Rehberden arkadaş ekleme sheet'i (mock veriyle; gerçek sürüm flutter_contacts)
class _ContactsSheet extends StatefulWidget {
  const _ContactsSheet();
  @override
  State<_ContactsSheet> createState() => _ContactsSheetState();
}

class _ContactsSheetState extends State<_ContactsSheet> {
  bool _permissionAsked = false;
  bool _permissionGranted = false;
  final _searchCtrl = TextEditingController();

  // Mock rehber verisi — gerçek sürümde flutter_contacts paketinden gelir
  static const _contacts = [
    ('Deniz Kaya', '+90 532 *** 4412', true, '@deniz.k'),
    ('Elif Yıldız', '+90 533 *** 7891', true, '@elif_m'),
    ('Arda Çelik', '+90 541 *** 2033', true, '@arda_2010'),
    ('Mehmet Aksu', '+90 532 *** 5566', false, null),
    ('Fatma Öz', '+90 555 *** 8899', false, null),
    ('Burak Şen', '+90 505 *** 1234', true, '@burak.s'),
    ('Ayşe Korkut', '+90 542 *** 9900', false, null),
    ('Kaan Akdağ', '+90 532 *** 3322', true, '@kaan.ak'),
    ('Zehra Bulut', '+90 538 *** 6677', false, null),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestPermission() async {
    // Gerçek sürüm: permission_handler ile Permission.contacts.request()
    setState(() => _permissionAsked = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _permissionGranted = true);
  }

  List<dynamic> _filtered() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts.where((c) => c.$1.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _permissionGranted ? _buildContactList(scroll) : _buildPermissionPrompt(),
      ),
    );
  }

  Widget _buildPermissionPrompt() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _Palette.brand.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text('📞'.tr(), style: TextStyle(fontSize: 40)),
          ),
          const SizedBox(height: 18),
          Text('Rehbere Erişim'.tr(),
              style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Telefon rehberini tarayarak QuAlsar\'ı kullanan arkadaşlarını bulalım. '
              'Eşleşme sadece telefon numarası hash\'i ile yapılır, numara sunucuya gönderilmez.',
              textAlign: TextAlign.center,
              style: _sans(size: 13, color: _Palette.inkSoft, height: 1.5),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _Palette.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _Palette.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Text('🔒'.tr(), style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kayıt olurken verdiğin telefonunu kullanır. Kimseye gösterilmez.',
                    style: _sans(size: 11, color: _Palette.accent, weight: FontWeight.w700, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _PrimaryButton(
            label: _permissionAsked ? 'İzin isteniyor…' : '✓ İzin Ver ve Tara',
            brand: true,
            onTap: _permissionAsked ? null : _requestPermission,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Vazgeç'.tr(),
                style: _sans(size: 12, weight: FontWeight.w600, color: _Palette.inkMute)),
          ),
        ],
      ),
    );
  }

  Widget _buildContactList(ScrollController scroll) {
    final filtered = _filtered();
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 16),
        Text('Rehberden Ekle',
            style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
        const SizedBox(height: 4),
        Text('QuAlsar kullanan kontaktların burada. Kullanmayanlar davet edilebilir.'.tr(),
            style: _sans(size: 12, color: _Palette.inkMute, height: 1.4)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _Palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _Palette.line),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 18, color: _Palette.inkMute),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: _sans(size: 14, weight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'Kontakt ara',
                    hintStyle: _sans(size: 13, color: _Palette.inkMute),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_searchCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _searchCtrl.clear()),
                  child: const Icon(Icons.close_rounded, size: 16, color: _Palette.inkMute),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final c in filtered)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ContactRow(
              name: c.$1 as String,
              phone: c.$2 as String,
              onQuAlsar: c.$3 as bool,
              username: c.$4 as String?,
              onAction: () {
                final onApp = c.$3 as bool;
                Navigator.pop(context);
                if (onApp) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${c.$4}\'a arkadaş isteği gönderildi 📨'),
                      backgroundColor: _Palette.ink,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else {
                  Share.share(
                    'Merhaba ${c.$1}! QuAlsar Arena\'da yarışalım mı? 🏆\n'
                    'https://qualsar.app/davet/$_currentUsername',
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  final String name;
  final String phone;
  final bool onQuAlsar;
  final String? username;
  final VoidCallback onAction;
  const _ContactRow({
    required this.name,
    required this.phone,
    required this.onQuAlsar,
    required this.username,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final color = _avatarColors[name.hashCode.abs() % _avatarColors.length];
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Palette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onQuAlsar ? color : _Palette.inkMute,
            ),
            alignment: Alignment.center,
            child: Text(initial,
                style: _sans(size: 14, weight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sans(size: 13, weight: FontWeight.w700)),
                    ),
                    if (onQuAlsar) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _Palette.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🏆'.tr(), style: TextStyle(fontSize: 9)),
                            const SizedBox(width: 3),
                            Text('QuAlsar',
                                style: _sans(size: 9, weight: FontWeight.w800, color: _Palette.success)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  onQuAlsar && username != null ? username! : phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(size: 11, color: _Palette.inkMute),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: onQuAlsar ? _Palette.brand : _Palette.ink,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(onQuAlsar ? Icons.person_add_rounded : Icons.send_rounded, size: 11, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(onQuAlsar ? 'Ekle' : 'Davet',
                      style: _sans(size: 11, weight: FontWeight.w800, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Basit QR tarayıcı mock (gerçek sürümde mobile_scanner paketi)
class _QrScanDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('📷'.tr(), style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text('QR Kod Tara',
                    style: _sans(size: 16, weight: FontWeight.w700, color: Colors.white)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Text('Kameraya izin ver',
                          style: _sans(size: 13, color: Colors.white.withValues(alpha: 0.6))),
                    ),
                    // Köşe işaretleri
                    Positioned(top: 12, left: 12, child: _corner(topLeft: true)),
                    Positioned(top: 12, right: 12, child: _corner(topRight: true)),
                    Positioned(bottom: 12, left: 12, child: _corner(bottomLeft: true)),
                    Positioned(bottom: 12, right: 12, child: _corner(bottomRight: true)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Arkadaşının QR kodunu bu çerçeveye hizala',
              textAlign: TextAlign.center,
              style: _sans(size: 12, color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 14),
            _PrimaryButton(
              label: 'Kamerayı Aç'.tr(),
              brand: true,
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Kamera izni istenecek · gerçek sürümde mobile_scanner ile açılır'.tr()),
                    backgroundColor: _Palette.ink,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _corner({
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        border: Border(
          top: (topLeft || topRight) ? const BorderSide(color: _Palette.brand, width: 3) : BorderSide.none,
          bottom: (bottomLeft || bottomRight) ? const BorderSide(color: _Palette.brand, width: 3) : BorderSide.none,
          left: (topLeft || bottomLeft) ? const BorderSide(color: _Palette.brand, width: 3) : BorderSide.none,
          right: (topRight || bottomRight) ? const BorderSide(color: _Palette.brand, width: 3) : BorderSide.none,
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _Palette.ink;
    const cells = 15;
    final cellSize = size.width / cells;
    final rng = math.Random(42);
    // 3 köşe işareti
    void corner(int x, int y) {
      canvas.drawRect(
        Rect.fromLTWH(x * cellSize, y * cellSize, 4 * cellSize, 4 * cellSize),
        paint,
      );
      canvas.drawRect(
        Rect.fromLTWH((x + 1) * cellSize, (y + 1) * cellSize, 2 * cellSize, 2 * cellSize),
        Paint()..color = Colors.white,
      );
    }
    corner(0, 0);
    corner(cells - 4, 0);
    corner(0, cells - 4);
    // Rastgele noktalar
    for (int y = 0; y < cells; y++) {
      for (int x = 0; x < cells; x++) {
        if ((x < 5 && y < 5) || (x >= cells - 5 && y < 5) || (x < 5 && y >= cells - 5)) continue;
        if (rng.nextDouble() < 0.45) {
          canvas.drawRect(
            Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _QuickMethod extends StatelessWidget {
  final String emoji;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _QuickMethod({required this.emoji, required this.label, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Palette.line),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(size: 11, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _sans(size: 9, color: _Palette.inkMute)),
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final String username;
  final String avatar;
  final String flag;
  final String grade;
  final String reason;
  final VoidCallback onAdd;
  const _SuggestionRow({
    required this.username,
    required this.avatar,
    required this.flag,
    required this.grade,
    required this.reason,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final color = _avatarColors[username.hashCode.abs() % _avatarColors.length];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Palette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            alignment: Alignment.center,
            child: Text(avatar,
                style: _sans(size: 14, weight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(flag, style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sans(size: 13, weight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                    Text('· $grade',
                        style: _sans(size: 10, color: _Palette.inkMute)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(size: 11, color: _Palette.inkMute)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _Palette.brand,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_add_rounded, size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text('Ekle',
                      style: _sans(size: 11, weight: FontWeight.w800, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ARENA WRAPPED — haftalık otomatik özet kartı (Spotify Wrapped tarzı)
// ═══════════════════════════════════════════════════════════════════════════════
class _WrappedCard extends StatelessWidget {
  const _WrappedCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => const _WrappedSheet(),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFF2D5BFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEC4899).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Text('🎁'.tr(), style: TextStyle(fontSize: 32)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Arena Wrapped',
                        style: _serif(size: 18, weight: FontWeight.w800, color: Colors.white, letterSpacing: -0.02)),
                    const SizedBox(height: 2),
                    Text('Bu haftanın özetini gör ve paylaş'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(size: 12, color: Colors.white.withValues(alpha: 0.88))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _WrappedSheet extends StatelessWidget {
  const _WrappedSheet();

  @override
  Widget build(BuildContext context) {
    // Ustalıktan en iyi konu, toplam QP vb.
    final masteryEntries = _arenaState.mastery.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topTopic = masteryEntries.isNotEmpty
        ? masteryEntries.first.key.split('|').last
        : 'Henüz test yok';

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 18),
            // Ana Wrapped kartı (paylaşılabilir)
            Center(
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFF2D5BFF)],
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('QuAlsar',
                            style: _serif(size: 18, weight: FontWeight.w800, color: Colors.white)),
                        const Spacer(),
                        Text('🎁'.tr(), style: TextStyle(fontSize: 20)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('Bu Haftan',
                        style: _sans(size: 11, weight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.75), letterSpacing: 0.06)),
                    const SizedBox(height: 20),
                    _wrappedStat('⚡', '${_arenaState.qp} QP', 'Toplam skor'),
                    const SizedBox(height: 12),
                    _wrappedStat('🔥', '${_arenaState.streak} gün', 'Aktif seri'),
                    const SizedBox(height: 12),
                    _wrappedStat('👑', topTopic, 'En ustalaştığın konu'),
                    const SizedBox(height: 12),
                    _wrappedStat('🏆', _leagues[_arenaState.league].name, 'Aktif lig'),
                    const SizedBox(height: 18),
                    Text('Sıra sende! @$_currentUsername · qualsar.app'.tr(),
                        style: _sans(size: 11, weight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _PrimaryButton(
              label: '📤 Paylaş'.tr(),
              brand: true,
              onTap: () {
                Share.share(
                  "🎁 QuAlsar Arena Wrapped — Bu hafta:\n"
                  "⚡ ${_arenaState.qp} QP · 🔥 ${_arenaState.streak} gün seri\n"
                  "👑 En iyi konum: $topTopic\n"
                  "🏆 ${_leagues[_arenaState.league].name} Ligi\n\n"
                  "Sen de dene! qualsar.app",
                );
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrappedStat(String emoji, String value, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _serif(size: 20, weight: FontWeight.w800, color: Colors.white, letterSpacing: -0.02, height: 1.1)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(size: 11, color: Colors.white.withValues(alpha: 0.75))),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MASTERY — Konu Ustası sistemi (her konu 0-100 ustalık oranı)
// ═══════════════════════════════════════════════════════════════════════════════
class _MasterySection extends StatelessWidget {
  const _MasterySection();

  @override
  Widget build(BuildContext context) {
    // Ustalık haritasından top 5 konu + en düşük 2 konu çıkar
    final entries = _arenaState.mastery.entries.toList();
    if (entries.isEmpty) {
      return _emptyMastery(context);
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    final weakest = entries.length > 3
        ? entries.reversed.take(2).toList()
        : <MapEntry<String, int>>[];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _Palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('📈'.tr(), style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Konu Ustalığın'.tr(),
                      style: _serif(size: 17, weight: FontWeight.w600, letterSpacing: -0.02)),
                ),
                Text('Ort. %${_arenaState.masteryAverage}',
                    style: _sans(size: 12, weight: FontWeight.w700, color: _Palette.accent)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Her doğru cevap ustalığını artırır, uzun süre çözmezsen azalır.',
              style: _sans(size: 11, color: _Palette.inkMute),
            ),
            const SizedBox(height: 12),
            for (final e in top) _masteryRow(e.key, e.value, false),
            if (weakest.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(color: _Palette.line.withValues(alpha: 0.6), height: 1),
              const SizedBox(height: 10),
              Text('⚠️ EN ZAYIF KONULAR',
                  style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.error, letterSpacing: 0.06)),
              const SizedBox(height: 6),
              for (final e in weakest) _masteryRow(e.key, e.value, true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyMastery(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _Palette.line, style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            Text('📈'.tr(), style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Konu Ustalığı'.tr(),
                      style: _sans(size: 13, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('İlk testini çöz, konu ustalığın burada görünsün.'.tr(),
                      style: _sans(size: 11, color: _Palette.inkMute)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _masteryRow(String key, int pct, bool isWeak) {
    final parts = key.split('|');
    final subjectKey = parts.first;
    final topic = parts.length > 1 ? parts.last : parts.first;
    final subj = _allSubjects.firstWhere(
      (s) => s.key == subjectKey,
      orElse: () => _allSubjects.first,
    );
    final Color barColor;
    final String level;
    if (pct >= 90) {
      barColor = _Palette.success;
      level = '👑 Usta';
    } else if (pct >= 70) {
      barColor = _Palette.brand;
      level = '🔥 İleri';
    } else if (pct >= 40) {
      barColor = _Palette.warn;
      level = '📖 Orta';
    } else {
      barColor = _Palette.error;
      level = '🌱 Başlangıç';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(subj.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              topic,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _sans(
                size: 12,
                weight: FontWeight.w600,
                color: isWeak ? _Palette.error : _Palette.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 6,
                backgroundColor: _Palette.line,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '%$pct',
              textAlign: TextAlign.right,
              style: _sans(size: 11, weight: FontWeight.w700, color: barColor),
            ),
          ),
          const SizedBox(width: 4),
          Text(level.split(' ').first, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BADGES — kurallar + etkileşim
// ═══════════════════════════════════════════════════════════════════════════════
class _BadgeInfo {
  final String emoji;
  final String name;
  final String rule;
  final String earnedStatus; // "Dün", "3 gün önce", "Kilitli" vb.
  final bool unlocked;
  const _BadgeInfo({
    required this.emoji,
    required this.name,
    required this.rule,
    required this.earnedStatus,
    required this.unlocked,
  });
}

const List<_BadgeInfo> _allBadges = [
  _BadgeInfo(
    emoji: '🔥',
    name: 'Ateşli',
    rule: '7 gün üst üste Mini Test çöz. Seri devam ettikçe alev büyür.',
    earnedStatus: 'Dün kazandın',
    unlocked: true,
  ),
  _BadgeInfo(
    emoji: '🎯',
    name: 'Sniper',
    rule: 'Bir testte hiç yanlış yapmadan tüm soruları doğru cevapla.',
    earnedStatus: '3 gün önce',
    unlocked: true,
  ),
  _BadgeInfo(
    emoji: '🏆',
    name: 'Bilgi Ustası',
    rule: 'Toplam 10 test tamamla. Sonuçların ortalaması %70+ olmalı.',
    earnedStatus: '1 hafta önce',
    unlocked: true,
  ),
  _BadgeInfo(
    emoji: '👑',
    name: 'Efsane',
    rule: 'Toplam 50 test tamamla. Hangi dersle olursa olsun devam et.',
    earnedStatus: 'Kilitli',
    unlocked: false,
  ),
  _BadgeInfo(
    emoji: '🌈',
    name: 'Çok Yönlü',
    rule: '5 farklı derste en az 1 test çöz. Çeşitlilik kazandırır.',
    earnedStatus: 'Kilitli',
    unlocked: false,
  ),
  _BadgeInfo(
    emoji: '⚡',
    name: 'Hız Şampiyonu',
    rule: '"Yarış" süre modunda bir testi bitir.',
    earnedStatus: 'Kilitli',
    unlocked: false,
  ),
  _BadgeInfo(
    emoji: '🎴',
    name: 'Kart Koleksiyoncusu',
    rule: '10 farklı konudan bilgi kartı oluştur.',
    earnedStatus: 'Kilitli',
    unlocked: false,
  ),
];

class _BadgesSectionTitle extends StatelessWidget {
  final VoidCallback onInfoTap;
  final VoidCallback onRankingsTap;
  const _BadgesSectionTitle({required this.onInfoTap, required this.onRankingsTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
      child: Row(
        children: [
          Text('Rozetlerim', style: _serif(size: 20, weight: FontWeight.w600, letterSpacing: -0.02)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onInfoTap,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _Palette.brand.withValues(alpha: 0.12),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.question_mark_rounded, size: 13, color: _Palette.brand),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onRankingsTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _Palette.ink,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🏆'.tr(), style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 5),
                  Text('Sıralama'.tr(),
                      style: _sans(size: 12, weight: FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showBadgesInfoSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        child: ListView(
          controller: scroll,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Rozetler Nasıl Çalışır?'.tr(),
                style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
            const SizedBox(height: 6),
            Text(
              'Rozetler çalışma alışkanlıklarını ödüllendirir. Her rozet farklı bir hedefi temsil eder; tamamlayınca otomatik kilitlenir açılır.',
              style: _sans(size: 13, color: _Palette.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 18),
            for (final b in _allBadges) ...[
              _BadgeRuleCard(badge: b),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    ),
  );
}

void _showSingleBadgeSheet(BuildContext context, _BadgeInfo badge) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Container(
      decoration: const BoxDecoration(
        color: _Palette.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
          ),
          const SizedBox(height: 18),
          Text(badge.emoji, style: TextStyle(fontSize: 68, color: badge.unlocked ? null : Colors.grey)),
          const SizedBox(height: 10),
          Text(badge.name, style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badge.unlocked
                  ? _Palette.success.withValues(alpha: 0.12)
                  : _Palette.line,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              badge.unlocked ? '✓ Kazanıldı · ${badge.earnedStatus}' : '🔒 Henüz kazanılmadı',
              style: _sans(
                size: 11,
                weight: FontWeight.w700,
                color: badge.unlocked ? _Palette.success : _Palette.inkMute,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _Palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _Palette.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NASIL KAZANILIR?',
                    style: _sans(size: 10, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
                const SizedBox(height: 6),
                Text(badge.rule, style: _sans(size: 14, color: _Palette.ink, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SIRALAMA — haftalık / aylık / tüm zamanlar
// ═══════════════════════════════════════════════════════════════════════════════
class _RankEntry {
  final int rank;
  final String username;
  final String? avatar; // tek harf (baş harf)
  final int tests;
  final int successPct;
  final bool isCurrentUser;
  final String countryFlag; // 🌍 sekmesinde gösterilir
  const _RankEntry({
    required this.rank,
    required this.username,
    this.avatar,
    required this.tests,
    required this.successPct,
    this.isCurrentUser = false,
    this.countryFlag = '🇹🇷',
  });
}

// Sahte veri: gerçek sistemde backend'ten gelecek
final Map<String, List<_RankEntry>> _rankingsData = {
  'weekly': [
    _RankEntry(rank: 1, username: 'zeynep_y', avatar: 'Z', tests: 32, successPct: 96),
    _RankEntry(rank: 2, username: 'deniz.k', avatar: 'D', tests: 29, successPct: 94),
    _RankEntry(rank: 3, username: 'arda_2010', avatar: 'A', tests: 27, successPct: 92),
    _RankEntry(rank: 4, username: 'elifm', avatar: 'E', tests: 24, successPct: 89),
    _RankEntry(rank: 5, username: 'mert_demir', avatar: 'M', tests: 22, successPct: 88),
    _RankEntry(rank: 6, username: 'sema45', avatar: 'S', tests: 20, successPct: 87),
    _RankEntry(rank: 7, username: 'kaan.ak', avatar: 'K', tests: 19, successPct: 86),
    _RankEntry(rank: 8, username: 'ahmet', avatar: 'A', tests: 18, successPct: 82, isCurrentUser: true),
    _RankEntry(rank: 9, username: 'bahar_c', avatar: 'B', tests: 17, successPct: 82),
    _RankEntry(rank: 10, username: 'onur07', avatar: 'O', tests: 16, successPct: 80),
  ],
  'monthly': [
    _RankEntry(rank: 1, username: 'deniz.k', avatar: 'D', tests: 112, successPct: 93),
    _RankEntry(rank: 2, username: 'zeynep_y', avatar: 'Z', tests: 108, successPct: 92),
    _RankEntry(rank: 3, username: 'arda_2010', avatar: 'A', tests: 98, successPct: 90),
    _RankEntry(rank: 4, username: 'mert_demir', avatar: 'M', tests: 85, successPct: 88),
    _RankEntry(rank: 5, username: 'elifm', avatar: 'E', tests: 81, successPct: 87),
    _RankEntry(rank: 6, username: 'kaan.ak', avatar: 'K', tests: 76, successPct: 85),
    _RankEntry(rank: 7, username: 'sema45', avatar: 'S', tests: 74, successPct: 85),
    _RankEntry(rank: 8, username: 'bahar_c', avatar: 'B', tests: 69, successPct: 84),
    _RankEntry(rank: 9, username: 'onur07', avatar: 'O', tests: 65, successPct: 82),
    _RankEntry(rank: 10, username: 'ecrin_t', avatar: 'E', tests: 61, successPct: 81),
    _RankEntry(rank: 14, username: 'ahmet', avatar: 'A', tests: 47, successPct: 82, isCurrentUser: true),
  ],
  'alltime': [
    _RankEntry(rank: 1, username: 'ismail_g', avatar: 'İ', tests: 1842, successPct: 94),
    _RankEntry(rank: 2, username: 'deniz.k', avatar: 'D', tests: 1620, successPct: 92),
    _RankEntry(rank: 3, username: 'zeynep_y', avatar: 'Z', tests: 1503, successPct: 91),
    _RankEntry(rank: 4, username: 'asli_92', avatar: 'A', tests: 1411, successPct: 90),
    _RankEntry(rank: 5, username: 'burak.s', avatar: 'B', tests: 1280, successPct: 88),
    _RankEntry(rank: 6, username: 'arda_2010', avatar: 'A', tests: 1195, successPct: 87),
    _RankEntry(rank: 7, username: 'mert_demir', avatar: 'M', tests: 1080, successPct: 86),
    _RankEntry(rank: 8, username: 'elifm', avatar: 'E', tests: 985, successPct: 86),
    _RankEntry(rank: 9, username: 'sema45', avatar: 'S', tests: 890, successPct: 85),
    _RankEntry(rank: 10, username: 'kaan.ak', avatar: 'K', tests: 820, successPct: 84),
    _RankEntry(rank: 247, username: 'ahmet', avatar: 'A', tests: 47, successPct: 82, isCurrentUser: true),
  ],
  // 🌍 Dünya sıralaması: ülke-bağımsız, başarı% + log(test sayısı) formülü
  // Gerçek sistemde backend'ten pre-computed leaderboard çekilir
  'world': [
    _RankEntry(rank: 1, username: 'hiroki.k', avatar: 'H', tests: 3210, successPct: 97, countryFlag: '🇯🇵'),
    _RankEntry(rank: 2, username: 'jisoo_p', avatar: 'J', tests: 2980, successPct: 96, countryFlag: '🇰🇷'),
    _RankEntry(rank: 3, username: 'lukas_m', avatar: 'L', tests: 2754, successPct: 95, countryFlag: '🇩🇪'),
    _RankEntry(rank: 4, username: 'alex_j', avatar: 'A', tests: 2612, successPct: 94, countryFlag: '🇺🇸'),
    _RankEntry(rank: 5, username: 'priya_s', avatar: 'P', tests: 2488, successPct: 94, countryFlag: '🇮🇳'),
    _RankEntry(rank: 6, username: 'giulia_r', avatar: 'G', tests: 2310, successPct: 93, countryFlag: '🇮🇹'),
    _RankEntry(rank: 7, username: 'emma_w', avatar: 'E', tests: 2205, successPct: 92, countryFlag: '🇬🇧'),
    _RankEntry(rank: 8, username: 'ismail_g', avatar: 'İ', tests: 1842, successPct: 94, countryFlag: '🇹🇷'),
    _RankEntry(rank: 9, username: 'bruno_s', avatar: 'B', tests: 1788, successPct: 91, countryFlag: '🇧🇷'),
    _RankEntry(rank: 10, username: 'diego_m', avatar: 'D', tests: 1702, successPct: 90, countryFlag: '🇲🇽'),
    _RankEntry(rank: 11, username: 'mikhail_v', avatar: 'M', tests: 1634, successPct: 90, countryFlag: '🇷🇺'),
    _RankEntry(rank: 12, username: 'chloe_l', avatar: 'C', tests: 1560, successPct: 89, countryFlag: '🇫🇷'),
    _RankEntry(rank: 13, username: 'noah_v', avatar: 'N', tests: 1498, successPct: 89, countryFlag: '🇳🇱'),
    _RankEntry(rank: 14, username: 'sofia_g', avatar: 'S', tests: 1445, successPct: 88, countryFlag: '🇪🇸'),
    _RankEntry(rank: 15, username: 'deniz.k', avatar: 'D', tests: 1620, successPct: 92, countryFlag: '🇹🇷'),
    _RankEntry(rank: 4827, username: 'ahmet', avatar: 'A', tests: 47, successPct: 82, isCurrentUser: true, countryFlag: '🇹🇷'),
  ],
};

void _showRankingsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _RankingsSheet(),
  );
}

class _RankingsSheet extends StatefulWidget {
  const _RankingsSheet();

  @override
  State<_RankingsSheet> createState() => _RankingsSheetState();
}

class _RankingsSheetState extends State<_RankingsSheet> {
  String _period = 'weekly';

  String _countryFlag(String country) {
    if (country == 'Türkiye') return '🇹🇷';
    if (country == 'Almanya') return '🇩🇪';
    return '🌍';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _rankingsData[_period] ?? const <_RankEntry>[];
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('🏆'.tr(), style: TextStyle(fontSize: 26)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Arena Sıralaması'.tr(),
                      style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  _period == 'world' ? '🌍' : _countryFlag(_currentCountry),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 6),
                Text(
                  _period == 'world' ? 'Dünya geneli' : _currentCountry,
                  style: _sans(size: 13, weight: FontWeight.w600, color: _Palette.inkSoft),
                ),
                if (_period != 'world') ...[
                  const SizedBox(width: 6),
                  Text('·', style: _sans(size: 13, color: _Palette.inkMute)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('$_currentGrade öğrencileri'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(size: 12, color: _Palette.inkMute)),
                  ),
                ] else ...[
                  const SizedBox(width: 6),
                  Text('·', style: _sans(size: 13, color: _Palette.inkMute)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('Tüm ülkeler, tüm seviyeler'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(size: 12, color: _Palette.inkMute)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _RankTabBar(
              current: _period,
              onChanged: (p) => setState(() => _period = p),
            ),
            const SizedBox(height: 14),
            for (int i = 0; i < entries.length; i++) ...[
              // Şu anki kullanıcı 10. sıradan sonra geliyorsa araya ayraç koy
              if (i > 0 && entries[i].rank - entries[i - 1].rank > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: _Palette.line, thickness: 1)),
                      const SizedBox(width: 8),
                      Text('⋯',
                          style: _sans(size: 14, color: _Palette.inkMute, weight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Expanded(child: Divider(color: _Palette.line, thickness: 1)),
                    ],
                  ),
                ),
              _RankRow(entry: entries[i], showFlag: _period == 'world'),
              if (i != entries.length - 1) const SizedBox(height: 8),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _Palette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _Palette.line),
              ),
              child: Row(
                children: [
                  const Text('ℹ️', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _period == 'world'
                          ? 'Dünya sıralaması müfredattan bağımsızdır: başarı oranı ve aktivite skorundan hesaplanır. Ülkeler ve sınıflar karışık yarışır.'
                          : 'Sıralama çözdüğün test sayısı ve başarı oranından hesaplanır. Her test bir sonraki puanlamana dahil olur.',
                      style: _sans(size: 12, color: _Palette.inkSoft, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankTabBar extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _RankTabBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tabs = const [
      ('weekly', '📅', 'Hafta'),
      ('monthly', '🗓️', 'Ay'),
      ('alltime', '🏅', 'Tümü'),
      ('world', '🌍', 'Dünya'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _Palette.line.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(tab.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: current == tab.$1 ? _Palette.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: current == tab.$1
                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(tab.$2, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          tab.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sans(
                            size: 11,
                            weight: FontWeight.w700,
                            color: current == tab.$1 ? _Palette.ink : _Palette.inkMute,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final _RankEntry entry;
  final bool showFlag;
  const _RankRow({required this.entry, this.showFlag = false});

  String _rankEmoji() {
    switch (entry.rank) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = entry.isCurrentUser;
    final rankEmoji = _rankEmoji();
    final hasMedal = rankEmoji.isNotEmpty;
    final avatarColor = _avatarColors[entry.username.hashCode.abs() % _avatarColors.length];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? _Palette.brand.withValues(alpha: 0.08)
            : _Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? _Palette.brand : _Palette.line,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Sıra + madalya
          SizedBox(
            width: 42,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasMedal) Text(rankEmoji, style: const TextStyle(fontSize: 18)),
                if (!hasMedal)
                  Text(
                    '#${entry.rank}',
                    style: _sans(
                      size: 13,
                      weight: FontWeight.w800,
                      color: highlighted ? _Palette.brand : _Palette.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Avatar (ülke bayrağı rozeti ile dünya modunda)
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [avatarColor, avatarColor.withValues(alpha: 0.7)],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.avatar ?? entry.username.substring(0, 1).toUpperCase(),
                  style: _sans(size: 14, weight: FontWeight.w800, color: Colors.white),
                ),
              ),
              if (showFlag)
                Positioned(
                  right: -4,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: _Palette.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: _Palette.line, width: 0.5),
                    ),
                    child: Text(entry.countryFlag, style: const TextStyle(fontSize: 11)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          // İsim + test sayısı
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '@${entry.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(
                          size: 13,
                          weight: FontWeight.w700,
                          color: highlighted ? _Palette.brand : _Palette.ink,
                        ),
                      ),
                    ),
                    if (highlighted) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _Palette.brand,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text('SEN',
                            style: _sans(
                              size: 9,
                              weight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.06,
                            )),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.tests} test · %${entry.successPct} başarı',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(size: 11, color: _Palette.inkMute),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Skor/puan göstergesi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: highlighted ? _Palette.brand : _Palette.ink,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '%${entry.successPct}',
              style: _sans(size: 12, weight: FontWeight.w800, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

const List<Color> _avatarColors = [
  Color(0xFFFF5B2E),
  Color(0xFF2D5BFF),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
];

class _BadgeRuleCard extends StatelessWidget {
  final _BadgeInfo badge;
  const _BadgeRuleCard({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: badge.unlocked ? 1 : 0.4,
            child: Text(badge.emoji, style: const TextStyle(fontSize: 32)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        badge.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(size: 14, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (!badge.unlocked)
                      Icon(Icons.lock_outline_rounded, size: 13, color: _Palette.inkMute),
                  ],
                ),
                const SizedBox(height: 2),
                Text(badge.rule,
                    style: _sans(size: 12, color: _Palette.inkSoft, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgesScroll extends StatelessWidget {
  const _BadgesScroll();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _allBadges.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final b = _allBadges[i];
          return GestureDetector(
            onTap: () => _showSingleBadgeSheet(context, b),
            child: Opacity(
              opacity: b.unlocked ? 1 : 0.5,
              child: Container(
                width: 104,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  color: _Palette.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _Palette.line),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(b.emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(height: 4),
                    Text(
                      b.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: _sans(size: 11, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      b.earnedStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: _sans(size: 9, color: _Palette.inkMute),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CREATE WIZARD
// ═══════════════════════════════════════════════════════════════════════════════
class _Subject {
  final String key;
  final String emoji;
  final String name;
  final int topicsCount;
  final Color color;
  final List<String> topics;
  const _Subject(this.key, this.emoji, this.name, this.topicsCount, this.color, this.topics);
}

// Diğer Dersler sheet içindeki sürüklenebilir ders kartı.
// Top-8 kendi `DragTarget<String>`'ını zaten taşıdığı için, buradan sürüklenip
// bırakılan key `_swapDuelSubjects` üzerinden yer değiştirir. Ayrıca kendisi
// de `DragTarget<String>` olduğu için, sheet içindeki iki ders birbirinin
// üstüne bırakılınca onAcceptSwap tetiklenir.
class _DueloOverflowSubjectTile extends StatelessWidget {
  final _Subject subject;
  final Color? customColor;
  final Color? customTextColor;
  final VoidCallback onTap;
  final VoidCallback onDragStarted;
  final VoidCallback? onDragEnd;
  final ValueChanged<String>? onAcceptSwap;
  const _DueloOverflowSubjectTile({
    required this.subject,
    required this.customColor,
    required this.onTap,
    required this.onDragStarted,
    this.customTextColor,
    this.onDragEnd,
    this.onAcceptSwap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = customColor ?? Colors.white;
    final darkBg = (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) < 0.55;
    final fg = customTextColor ?? (darkBg ? Colors.white : _Palette.ink);
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != subject.key,
      onAcceptWithDetails: (d) => onAcceptSwap?.call(d.data),
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        final tile = AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering ? const Color(0xFFFF6A00) : _Palette.line,
              width: hovering ? 2.4 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(subject.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 3),
              Text(
                subject.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _sans(
                    size: 10,
                    weight: FontWeight.w600,
                    color: fg,
                    height: 1.15),
              ),
            ],
          ),
        );
        return LongPressDraggable<String>(
          data: subject.key,
          onDragStarted: onDragStarted,
          onDragEnd: (_) => onDragEnd?.call(),
          onDraggableCanceled: (_, __) => onDragEnd?.call(),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: 72, height: 72, child: tile),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: tile),
          child: GestureDetector(onTap: onTap, child: tile),
        );
      },
    );
  }
}

final List<_Subject> _allSubjects = [
  // Zorunlu - Ana müfredat
  const _Subject('math', '📐', 'Matematik', 12, _Palette.math, [
    'Türev', 'İntegral', 'Limit', 'Logaritma', 'Trigonometri', 'Olasılık', 'Permütasyon', 'Fonksiyonlar'
  ]),
  const _Subject('physics', '⚛️', 'Fizik', 8, _Palette.physics, [
    'Kuvvet ve Hareket', 'Enerji', 'Elektrik', 'Optik', 'Dalgalar', 'Manyetizma'
  ]),
  const _Subject('chem', '🧪', 'Kimya', 10, _Palette.chem, [
    'Atom', 'Mol', 'Asit-Baz', 'Kimyasal Tepkimeler', 'Gazlar'
  ]),
  const _Subject('bio', '🧬', 'Biyoloji', 9, _Palette.bio, [
    'Hücre', 'Kalıtım', 'Ekosistem', 'Sistemler'
  ]),
  const _Subject('turkish', '📖', 'Türkçe', 14, _Palette.turkish, [
    'Paragraf', 'Cümle', 'Yazım Kuralları', 'Noktalama'
  ]),
  const _Subject('lit', '✒️', 'Edebiyat', 15, _Palette.lit, [
    'Giriş', 'Hikaye', 'Şiir', 'Roman', 'Tiyatro', 'Masal ve Fabl', 'Edebi Akımlar'
  ]),
  const _Subject('history', '🏛️', 'Tarih', 11, _Palette.history, [
    'Osmanlı', 'Cumhuriyet', 'İlk Çağ', 'Orta Çağ'
  ]),
  const _Subject('geo', '🌍', 'Coğrafya', 13, _Palette.geo, [
    'İklim', 'Nüfus', 'Ekonomi', 'Türkiye Coğrafyası'
  ]),
  // Zorunlu - Diğer
  const _Subject('din_kultur', '📿', 'Din Kültürü', 8, Color(0xFF0F766E), [
    'İslam Ahlakı', 'İbadet', 'Kuran ve Sünnet', 'Peygamberler', 'Dinler Tarihi',
  ]),
  const _Subject('ingilizce', '🇬🇧', 'İngilizce', 10, Color(0xFF2563EB), [
    'Grammar', 'Vocabulary', 'Reading', 'Writing', 'Listening', 'Speaking',
  ]),
  const _Subject('beden', '⚽', 'Beden Eğitimi', 6, _Palette.success, [
    'Futbol', 'Basketbol', 'Voleybol', 'Atletizm', 'Sağlık ve Beslenme',
  ]),
  const _Subject('sanat_muzik', '🎨', 'Sanat / Müzik', 8, Color(0xFFDB2777), [
    'Resim', 'Renk Teorisi', 'Sanat Tarihi', 'Notalar', 'Türk Müziği', 'Klasik Müzik',
  ]),
  const _Subject('felsefe', '🤔', 'Felsefe', 6, Color(0xFF7C3AED), [
    'Ahlak Felsefesi', 'Bilgi Felsefesi', 'Varlık Felsefesi', 'Mantık', 'Politik Felsefe',
  ]),
  // Seçmeli dersler
  const _Subject('ikinci_dil', '🗣️', '2. Yabancı Dil', 6, Color(0xFF1D4ED8), [
    'Almanca', 'Fransızca', 'Arapça', 'İspanyolca', 'Rusça',
  ]),
  const _Subject('psikoloji_dersi', '🧠', 'Psikoloji', 5, Color(0xFFEC4899), [
    'Algı', 'Öğrenme', 'Kişilik', 'Duygu', 'Sosyal Psikoloji',
  ]),
  const _Subject('sosyoloji', '👥', 'Sosyoloji', 5, Color(0xFF0891B2), [
    'Toplum', 'Aile', 'Kültür', 'Sosyal Değişme', 'Sosyal Kurumlar',
  ]),
  const _Subject('mantik', '🧩', 'Mantık', 5, Color(0xFF6366F1), [
    'Önermeler', 'Kıyas', 'Sembolik Mantık', 'Çıkarım', 'Mantık Hataları',
  ]),
  const _Subject('girisimcilik', '🚀', 'Girişimcilik', 5, Color(0xFFEF4444), [
    'İş Fikri', 'Pazarlama', 'Finansman', 'Liderlik', 'İnovasyon',
  ]),
  const _Subject('demokrasi', '🗳️', 'İnsan Hakları', 5, Color(0xFF0369A1), [
    'İnsan Hakları', 'Demokrasi Türleri', 'Anayasa', 'Vatandaşlık',
  ]),
  const _Subject('kuran', '📿', 'Kur\'an-ı Kerim', 5, Color(0xFF166534), [
    'Tecvid', 'Ezberleme', 'Meal', 'Tefsir',
  ]),
  const _Subject('temel_din', '🕌', 'Temel Din', 4, Color(0xFF15803D), [
    'İtikat', 'İbadet', 'Ahlak',
  ]),
  const _Subject('peygamber_hayat', '📜', 'Peygamber Hayatı', 4, Color(0xFF166534), [
    'Mekke Dönemi', 'Medine Dönemi', 'Örnek Yaşam',
  ]),
  const _Subject('drama', '🎭', 'Drama', 4, Color(0xFFEC4899), [
    'Rol Yapma', 'Tiyatro Teknikleri', 'Sahne', 'Doğaçlama',
  ]),
  const _Subject('yazarlik', '✍️', 'Yazarlık', 4, Color(0xFFB45309), [
    'Öykü Yazma', 'Şiir', 'Deneme', 'Anlatı Teknikleri',
  ]),
  const _Subject('cagdas_tarih', '🌐', 'Çağdaş Tarih', 5, Color(0xFFA16207), [
    'Soğuk Savaş', 'Globalizasyon', 'AB Süreci', 'Türkiye Cumhuriyeti',
  ]),
  const _Subject('kultur_tarihi', '🏺', 'Kültür Tarihi', 5, Color(0xFF854D0E), [
    'İslamiyet Öncesi', 'Selçuklu', 'Osmanlı', 'Cumhuriyet',
  ]),
];

// ═══════════════════════════════════════════════════════════════════════════════
//  MÜFREDAT — kullanıcının sınıfına göre konu listesi
//  NOT: Gerçek sistemde kullanıcı profilinden çekilecek; şimdilik lise 10 default.
// ═══════════════════════════════════════════════════════════════════════════════
String _currentGrade = 'Lise 10. Sınıf';
String _currentCountry = 'Türkiye';
String _currentCountryKey = 'tr';
String _currentUsername = 'ahmet';
String? _currentLevel; // 'ilkokul' | 'ortaokul' | 'lise' | 'universite' | 'yuksek_lisans' | 'doktora' | 'sinav_hazirlik'
String? _currentFaculty; // 'muhendislik', 'insaat_muh', 'tip' vb.

// Ülke + sınıf için ders listesi (hangi dersler öğretiliyor)
// Lise için 9-12 sınıf × 4 alan (Sayısal, Eşit Ağırlık, Sözel, Dil) müfredatları
// Kaynak: MEB resmi müfredat + seçmeli ders seçenekleri
final Map<String, List<String>> _gradeSubjectKeys = {
  // İlkokul
  'İlkokul 1. Sınıf': ['math', 'turkish', 'beden', 'sanat_muzik'],
  'İlkokul 2. Sınıf': ['math', 'turkish', 'beden', 'sanat_muzik'],
  'İlkokul 3. Sınıf': ['math', 'turkish', 'beden', 'sanat_muzik', 'ingilizce'],
  'İlkokul 4. Sınıf': ['math', 'turkish', 'history', 'beden', 'sanat_muzik', 'ingilizce', 'din_kultur'],
  // Ortaokul
  'Ortaokul 5. Sınıf': ['math', 'turkish', 'history', 'geo', 'ingilizce', 'din_kultur', 'beden', 'sanat_muzik'],
  'Ortaokul 6. Sınıf': ['math', 'turkish', 'history', 'geo', 'ingilizce', 'din_kultur', 'beden', 'sanat_muzik'],
  'Ortaokul 7. Sınıf': ['math', 'turkish', 'history', 'geo', 'ingilizce', 'din_kultur', 'beden', 'sanat_muzik'],
  'Ortaokul 8. Sınıf': ['math', 'turkish', 'history', 'geo', 'ingilizce', 'din_kultur', 'beden', 'sanat_muzik'],
  // Lise 9 (ortak müfredat — alan 10'da belirlenir)
  'Lise 9. Sınıf': [
    'lit', 'math', 'physics', 'chem', 'bio', 'history', 'geo', 'din_kultur',
    'ingilizce', 'beden', 'sanat_muzik', 'ikinci_dil', 'mantik',
  ],
  // Lise 10 — alan bazlı
  'Lise 10. Sınıf · Sayısal': [
    'lit', 'math', 'physics', 'chem', 'bio', 'history', 'geo', 'din_kultur',
    'ingilizce', 'beden', 'sanat_muzik', 'ikinci_dil', 'mantik', 'drama',
  ],
  'Lise 10. Sınıf · Eşit Ağırlık': [
    'lit', 'math', 'physics', 'chem', 'bio', 'history', 'geo', 'din_kultur',
    'ingilizce', 'beden', 'sanat_muzik', 'ikinci_dil', 'mantik', 'yazarlik',
    'temel_din', 'kuran', 'peygamber_hayat',
  ],
  'Lise 10. Sınıf · Sözel': [
    'lit', 'math', 'history', 'geo', 'din_kultur',
    'ingilizce', 'beden', 'sanat_muzik', 'ikinci_dil', 'mantik',
    'drama', 'yazarlik', 'felsefe',
  ],
  'Lise 10. Sınıf · Dil': [
    'lit', 'math', 'history', 'geo', 'din_kultur',
    'ingilizce', 'ikinci_dil', 'beden', 'sanat_muzik', 'drama', 'yazarlik',
  ],
  // Lise 11 — alan bazlı
  'Lise 11. Sınıf · Sayısal': [
    'lit', 'math', 'physics', 'chem', 'bio', 'history', 'geo', 'felsefe',
    'din_kultur', 'ingilizce', 'beden', 'mantik', 'girisimcilik',
  ],
  'Lise 11. Sınıf · Eşit Ağırlık': [
    'lit', 'math', 'history', 'geo', 'felsefe', 'physics', 'chem', 'bio',
    'din_kultur', 'ingilizce', 'beden', 'psikoloji_dersi', 'sosyoloji', 'mantik',
    'ikinci_dil', 'girisimcilik', 'demokrasi', 'kuran', 'temel_din',
  ],
  'Lise 11. Sınıf · Sözel': [
    'lit', 'math', 'history', 'geo', 'felsefe', 'din_kultur',
    'ingilizce', 'beden', 'psikoloji_dersi', 'sosyoloji', 'mantik',
    'ikinci_dil', 'girisimcilik', 'demokrasi',
  ],
  'Lise 11. Sınıf · Dil': [
    'lit', 'math', 'history', 'geo', 'felsefe', 'din_kultur',
    'ingilizce', 'ikinci_dil', 'beden', 'mantik', 'girisimcilik',
  ],
  // Lise 12 — alan bazlı
  'Lise 12. Sınıf · Sayısal': [
    'lit', 'math', 'physics', 'chem', 'bio', 'history', 'geo', 'felsefe',
    'din_kultur', 'ingilizce', 'beden', 'mantik', 'girisimcilik',
    'cagdas_tarih',
  ],
  'Lise 12. Sınıf · Eşit Ağırlık': [
    'lit', 'math', 'history', 'geo', 'felsefe', 'din_kultur',
    'ingilizce', 'beden', 'psikoloji_dersi', 'sosyoloji', 'mantik',
    'cagdas_tarih', 'kultur_tarihi', 'ikinci_dil', 'girisimcilik',
    'kuran', 'peygamber_hayat',
  ],
  'Lise 12. Sınıf · Sözel': [
    'lit', 'history', 'geo', 'felsefe', 'din_kultur',
    'ingilizce', 'beden', 'psikoloji_dersi', 'sosyoloji', 'mantik',
    'cagdas_tarih', 'kultur_tarihi', 'ikinci_dil', 'girisimcilik',
  ],
  'Lise 12. Sınıf · Dil': [
    'lit', 'history', 'geo', 'felsefe', 'din_kultur',
    'ingilizce', 'ikinci_dil', 'beden', 'mantik', 'girisimcilik',
    'cagdas_tarih',
  ],
};

// Sınıf → ders → konu listesi (MEB müfredatı baz alındı)
final Map<String, Map<String, List<String>>> _curriculum = {
  'Lise 9. Sınıf': {
    'math': ['Mantık', 'Kümeler', 'Denklem ve Eşitsizlikler', 'Üçgenler', 'Veri'],
    'physics': ['Fizik Bilimine Giriş', 'Madde ve Özellikleri', 'Hareket ve Kuvvet', 'Enerji', 'Isı ve Sıcaklık'],
    'chem': ['Kimya Bilimi', 'Atom ve Periyodik Sistem', 'Kimyasal Türler Arası Etkileşimler', 'Maddenin Halleri'],
    'bio': ['Yaşam Bilimi Biyoloji', 'Hücre', 'Canlılar Dünyası'],
    'turkish': ['Hikaye', 'Şiir', 'Masal/Fabl', 'Haber Metni'],
    'history': ['Tarih ve Zaman', 'İnsanlığın İlk Dönemleri', 'Orta Çağda Dünya', 'İlk ve Orta Çağlarda Türk Dünyası'],
    'geo': ['Doğal Sistemler', 'Beşeri Sistemler', 'Mekansal Sentez: Türkiye'],
    'lit': ['Giriş', 'Hikaye', 'Şiir', 'Masal'],
  },
  'Lise 10. Sınıf': {
    'math': ['Sayma ve Olasılık', 'Fonksiyonlar', 'Polinomlar', 'İkinci Dereceden Denklemler', 'Dörtgenler ve Çokgenler', 'Çember ve Daire', 'Katı Cisimler'],
    'physics': ['Elektrik ve Manyetizma', 'Basınç ve Kaldırma Kuvveti', 'Dalgalar', 'Optik'],
    'chem': ['Kimyanın Temel Kanunları', 'Karışımlar', 'Asitler Bazlar ve Tuzlar', 'Kimya Her Yerde'],
    'bio': ['Hücre Bölünmeleri', 'Kalıtımın Genel İlkeleri', 'Ekosistem Ekolojisi', 'Güncel Çevre Sorunları'],
    'turkish': ['Giriş', 'Hikaye', 'Şiir', 'Masal ve Fabl', 'Roman', 'Tiyatro'],
    'history': ['Yerleşme ve Devletleşmede Selçuklu', 'Beylikten Devlete Osmanlı', 'Devletleşme Sürecinde Askerler', 'Osmanlı Medeniyeti', 'Dünya Gücü Osmanlı', 'Osmanlı Toplum Düzeni'],
    'geo': ['Doğal Sistemler', 'Beşeri Sistemler', 'Mekansal Sentez: Türkiye', 'Küresel Ortam: Bölgeler', 'Çevre ve Toplum'],
    'lit': ['İslamiyet Öncesi Edebiyat', 'Divan Edebiyatı', 'Halk Edebiyatı', 'Hikaye', 'Şiir', 'Roman'],
  },
  'Lise 11. Sınıf': {
    'math': ['Trigonometri', 'Analitik Geometri', 'Fonksiyonlar', 'Diziler', 'Logaritma'],
    'physics': ['Kuvvet ve Hareket', 'Elektrik ve Manyetizma', 'Dalgalar', 'Modern Fizik'],
    'chem': ['Modern Atom Teorisi', 'Gazlar', 'Sıvı Çözeltiler', 'Kimyasal Tepkimelerde Enerji', 'Kimyasal Tepkimelerde Hız'],
    'bio': ['İnsan Fizyolojisi (Sinir, Endokrin, Duyu)', 'Destek ve Hareket Sistemi', 'Sindirim Sistemi', 'Dolaşım Sistemi', 'Solunum ve Boşaltım Sistemi', 'Üreme Sistemi ve Embriyonik Gelişim', 'Komünite ve Popülasyon Ekolojisi'],
    'turkish': ['Roman', 'Öykü', 'Şiir', 'Eleştiri', 'Söyleşi', 'Makale'],
    'history': ['1600-1774 Değişim Çağında Osmanlı', 'Uluslararası İlişkilerde Denge Stratejisi', 'Devrimler Çağında Değişen Devlet-Toplum İlişkileri', 'Sermaye ve Emek', 'XIX. ve XX. Yüzyılda Değişen Gündelik Hayat'],
    'geo': ['Doğal Sistemler', 'Beşeri Sistemler', 'Mekansal Sentez: Türkiye', 'Küresel Ortam: Bölgeler ve Ülkeler'],
    'lit': ['Tanzimat Edebiyatı', 'Servet-i Fünun Edebiyatı', 'Milli Edebiyat', 'Cumhuriyet Dönemi Şiir', 'Cumhuriyet Dönemi Roman ve Hikaye'],
  },
  'Lise 12. Sınıf': {
    'math': ['Üstel ve Logaritmik Fonksiyonlar', 'Diziler', 'Türev', 'İntegral', 'Analitik Geometri'],
    'physics': ['Çembersel Hareket', 'Basit Harmonik Hareket', 'Dalga Mekaniği', 'Atom Fiziğine Giriş ve Radyoaktivite', 'Modern Fizik', 'Modern Fiziğin Teknolojideki Uygulamaları'],
    'chem': ['Kimya ve Elektrik', 'Karbon Kimyasına Giriş', 'Organik Bileşikler', 'Enerji Kaynakları ve Bilimsel Gelişmeler'],
    'bio': ['Genden Proteine', 'Canlılarda Enerji Dönüşümleri', 'Bitki Biyolojisi', 'Canlılar ve Çevre'],
    'turkish': ['Cumhuriyet Dönemi Romanı', 'Cumhuriyet Dönemi Şiiri', 'Tiyatro', 'Eleştiri', 'Deneme', 'Mülakat'],
    'history': ['20. Yüzyıl Başlarında Osmanlı Devleti ve Dünya', 'Milli Mücadele', 'Atatürkçülük ve Türk İnkılabı', 'İki Savaş Arasındaki Dönemde Türkiye ve Dünya', 'II. Dünya Savaşı Sürecinde Türkiye ve Dünya', 'II. Dünya Savaşı Sonrasında Türkiye ve Dünya', 'Toplumsal Devrim Çağında Dünya ve Türkiye', 'XXI. Yüzyılın Eşiğinde Türkiye ve Dünya'],
    'geo': ['Doğal Sistemler', 'Beşeri Sistemler', 'Mekansal Sentez: Türkiye', 'Küresel Ortam: Bölgeler ve Ülkeler', 'Çevre ve Toplum'],
    'lit': ['Edebiyat-Toplum-İletişim İlişkisi', 'Cumhuriyet Sonrası Hikaye', 'Cumhuriyet Sonrası Şiir', 'Cumhuriyet Sonrası Roman', 'Cumhuriyet Sonrası Tiyatro'],
  },
  'Ortaokul 8. Sınıf': {
    'math': ['Çarpanlar ve Katlar', 'Üslü İfadeler', 'Kareköklü İfadeler', 'Veri Analizi', 'Olasılık', 'Cebirsel İfadeler', 'Denklemler'],
    'turkish': ['Okuma', 'Yazma', 'Dilbilgisi', 'Sözcük Türleri'],
    'history': ['Bir Kahraman Doğuyor', 'Milli Uyanış', 'Milli Bir Destan', 'Çağdaş Türkiye Yolunda Adımlar', 'Atatürkçülük'],
    'geo': ['İletişim ve İnsan İlişkileri', 'Türk Tarihinde Yolculuk', 'Etkin Vatandaşlık'],
  },
};

// Konu listesini müfredattan getir (yoksa genel _Subject.topics'e düş)
List<String> _topicsForGrade(String subjectKey) {
  // Tam eşleşme (sınıf + alan)
  var byGrade = _curriculum[_currentGrade];
  if (byGrade != null && byGrade[subjectKey] != null) {
    return byGrade[subjectKey]!;
  }
  // Alan olmadan dene
  final baseGrade = _currentGrade.split(' · ').first;
  byGrade = _curriculum[baseGrade];
  if (byGrade != null && byGrade[subjectKey] != null) {
    return byGrade[subjectKey]!;
  }
  // Ders genel konu listesine düş
  return _findSubjectByKey(subjectKey).topics;
}

List<_Subject> _subjectsForGrade() {
  // Türkiye için detaylı müfredat (sınıf × alan bazlı)
  if (_currentCountryKey == 'tr') {
    var keys = _gradeSubjectKeys[_currentGrade];
    if (keys == null) {
      final baseGrade = _currentGrade.split(' · ').first;
      keys = _gradeSubjectKeys[baseGrade];
    }
    if (keys != null) {
      final subjectMap = {for (final s in _allSubjects) s.key: s};
      return [for (final k in keys) if (subjectMap[k] != null) subjectMap[k]!];
    }
  }
  // Diğer ülkeler: _countrySubjects haritasından level bazında çek
  final levelKey = _currentLevel ?? 'high';
  final keys = _countrySubjects[_currentCountryKey]?[levelKey];
  if (keys != null) {
    final subjectMap = {for (final s in _allSubjects) s.key: s};
    return [for (final k in keys) if (subjectMap[k] != null) subjectMap[k]!];
  }
  return List.of(_allSubjects);
}

class _WizardConfig {
  Set<String> selectedSubjects = {};
  Map<String, Set<String>> selectedTopics = {};
  bool mixer = false;
  int count = 10;
  String difficulty = 'medium';
  String timeMode = 'relax';
  String challengeMode = 'standard'; // standard | survival | speedrun | perfect
}

class _CreateWizard extends StatefulWidget {
  final _WizardConfig cfg;
  const _CreateWizard({required this.cfg});

  @override
  State<_CreateWizard> createState() => _CreateWizardState();
}

class _CreateWizardState extends State<_CreateWizard> {
  int _step = 0;

  _WizardConfig get _cfg => widget.cfg;

  void _next() {
    if (_step < 1) {
      setState(() => _step += 1);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _LoadingScreen(cfg: _cfg)),
      );
    }
  }

  void _prev() {
    if (_step > 0) {
      setState(() => _step -= 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _WizardTopbar(onBack: _prev, title: 'Yeni Test'),
            _WizardProgress(activeIndex: _step, stepCount: 2),
            Expanded(
              child: SingleChildScrollView(
                child: _stepBody(),
              ),
            ),
            _stickyButton(),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() {
    if (_step == 0) {
      return _StepTopics(cfg: _cfg, onChanged: () => setState(() {}));
    }
    return _StepSettings(cfg: _cfg, onChanged: () => setState(() {}));
  }

  Widget _stickyButton() {
    final String label = _step == 0 ? 'Devam Et' : '🚀 Testi Oluştur';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, _Palette.bg],
          stops: [0, 0.3],
        ),
      ),
      child: _PrimaryButton(
        label: label,
        brand: true,
        trailingIcon: _step < 1 ? Icons.arrow_forward_rounded : null,
        onTap: _next,
      ),
    );
  }
}

class _WizardTopbar extends StatelessWidget {
  final VoidCallback onBack;
  final String title;
  const _WizardTopbar({required this.onBack, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          _CircleBtn(icon: Icons.arrow_back_rounded, onTap: onBack),
          Expanded(
            child: Center(
              child: Text(title, style: _serif(size: 18, weight: FontWeight.w600, letterSpacing: -0.02)),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _WizardProgress extends StatelessWidget {
  final int activeIndex;
  final int stepCount;
  const _WizardProgress({required this.activeIndex, this.stepCount = 3});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Row(
        children: List.generate(stepCount, (i) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == stepCount - 1 ? 0 : 6),
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= activeIndex ? _Palette.ink : _Palette.line,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _WizTitleBlock extends StatelessWidget {
  final String title;
  final String subtitle;
  _WizTitleBlock({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _serif(size: 28, weight: FontWeight.w600, letterSpacing: -0.03, height: 1.1)),
          const SizedBox(height: 6),
          Text(subtitle, style: _sans(size: 13, color: _Palette.inkMute)),
        ],
      ),
    );
  }
}

// STEP 2: Topics
class _StepTopics extends StatefulWidget {
  final _WizardConfig cfg;
  final VoidCallback onChanged;
  const _StepTopics({required this.cfg, required this.onChanged});

  @override
  State<_StepTopics> createState() => _StepTopicsState();
}

class _StepTopicsState extends State<_StepTopics> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    if (widget.cfg.selectedSubjects.isNotEmpty) {
      _expanded.add(widget.cfg.selectedSubjects.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _allSubjects.where((s) => widget.cfg.selectedSubjects.contains(s.key)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WizTitleBlock(title: 'Hangi konular?', subtitle: 'En az bir konu seç ya da karışık olsun'.tr()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () {
              widget.cfg.mixer = !widget.cfg.mixer;
              widget.onChanged();
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFF0E8), Color(0xFFFFE0D1)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.cfg.mixer ? _Palette.brand : _Palette.brand.withValues(alpha: .6),
                  width: widget.cfg.mixer ? 2 : 1.5,
                  style: widget.cfg.mixer ? BorderStyle.solid : BorderStyle.solid,
                ),
              ),
              child: Row(
                children: [
                  Text('🎲'.tr(), style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Karışık / Sürpriz beni'.tr(), style: _sans(size: 13, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('AI tüm konulardan sana özel bir test hazırlasın'.tr(),
                            style: _sans(size: 11, color: _Palette.inkMute)),
                      ],
                    ),
                  ),
                  if (widget.cfg.mixer)
                    const Icon(Icons.check_circle_rounded, color: _Palette.brand, size: 22),
                ],
              ),
            ),
          ),
        ),
        for (final s in subjects)
          _TopicAccordion(
            subject: s,
            open: _expanded.contains(s.key),
            onToggleOpen: () {
              setState(() {
                if (_expanded.contains(s.key)) {
                  _expanded.remove(s.key);
                } else {
                  _expanded.add(s.key);
                }
              });
            },
            selectedTopics: widget.cfg.selectedTopics[s.key] ?? {},
            onToggleTopic: (t) {
              final cur = widget.cfg.selectedTopics[s.key] ?? {};
              if (cur.contains(t)) {
                cur.remove(t);
              } else {
                cur.add(t);
              }
              widget.cfg.selectedTopics[s.key] = cur;
              widget.onChanged();
              setState(() {});
            },
          ),
      ],
    );
  }
}

class _TopicAccordion extends StatelessWidget {
  final _Subject subject;
  final bool open;
  final VoidCallback onToggleOpen;
  final Set<String> selectedTopics;
  final ValueChanged<String> onToggleTopic;
  const _TopicAccordion({
    required this.subject,
    required this.open,
    required this.onToggleOpen,
    required this.selectedTopics,
    required this.onToggleTopic,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _Palette.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            GestureDetector(
              onTap: onToggleOpen,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Text(subject.emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subject.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _sans(size: 14, weight: FontWeight.w600)),
                          Text(
                            '📚 $_currentGrade müfredatı',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _sans(size: 10, color: _Palette.inkMute, weight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${selectedTopics.length}/${_topicsForGrade(subject.key).length}',
                      style: _sans(size: 12, color: subject.color, weight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: _Palette.inkSoft),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _Palette.line)),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in _topicsForGrade(subject.key))
                      GestureDetector(
                        onTap: () => onToggleTopic(t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: selectedTopics.contains(t) ? _Palette.ink : const Color(0xFFF5F1EA),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: selectedTopics.contains(t) ? _Palette.ink : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (selectedTopics.contains(t))
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                ),
                              Text(
                                t,
                                style: _sans(
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: selectedTopics.contains(t) ? Colors.white : _Palette.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// STEP 3: Settings
class _StepSettings extends StatelessWidget {
  final _WizardConfig cfg;
  final VoidCallback onChanged;
  const _StepSettings({required this.cfg, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WizTitleBlock(title: 'Son ayarlar', subtitle: 'AI testini buna göre hazırlayacak'.tr()),
        _PillGroup(
          label: '📊 SORU SAYISI'.tr(),
          options: const [
            _PillOpt('5', '⚡', '5 soru', '~5 dk'),
            _PillOpt('10', '📝', '10 soru', '~10 dk'),
            _PillOpt('20', '📚', '20 soru', '~20 dk'),
          ],
          selected: '${cfg.count}',
          onSelect: (v) {
            cfg.count = int.parse(v);
            onChanged();
          },
        ),
        _PillGroup(
          label: '⚡ ZORLUK SEVİYESİ'.tr(),
          options: const [
            _PillOpt('easy', '🟢', 'Kolay', 'Temel', tone: _Palette.success, toneBg: Color(0xFFECFDF5)),
            _PillOpt('medium', '🟡', 'Orta', 'Dengeli', tone: _Palette.warn, toneBg: Color(0xFFFFFBEB)),
            _PillOpt('hard', '🔴', 'Zor', 'Zorlayıcı', tone: _Palette.error, toneBg: Color(0xFFFEF2F2)),
          ],
          selected: cfg.difficulty,
          onSelect: (v) {
            cfg.difficulty = v;
            onChanged();
          },
        ),
        _PillGroup(
          label: '⏱️ SÜRE MODU'.tr(),
          options: const [
            _PillOpt('relax', '🧘', 'Rahat', 'Süre yok'),
            _PillOpt('normal', '⏲️', 'Normal', '90 sn/soru'),
            _PillOpt('race', '🔥', 'Yarış', '45 sn/soru'),
          ],
          selected: cfg.timeMode,
          onSelect: (v) {
            cfg.timeMode = v;
            onChanged();
          },
        ),
      ],
    );
  }
}

class _PillOpt {
  final String value;
  final String emoji;
  final String title;
  final String hint;
  final Color? tone;
  final Color? toneBg;
  const _PillOpt(this.value, this.emoji, this.title, this.hint, {this.tone, this.toneBg});
}

class _PillGroup extends StatelessWidget {
  final String label;
  final List<_PillOpt> options;
  final String selected;
  final ValueChanged<String> onSelect;
  const _PillGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _sans(size: 11, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (int i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onSelect(options[i].value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected == options[i].value
                            ? (options[i].toneBg ?? _Palette.surface)
                            : _Palette.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected == options[i].value
                              ? (options[i].tone ?? _Palette.ink)
                              : _Palette.line,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(options[i].emoji, style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text(options[i].title, style: _sans(size: 13, weight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(options[i].hint, style: _sans(size: 10, color: _Palette.inkMute)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LOADING
// ═══════════════════════════════════════════════════════════════════════════════
class _LoadingScreen extends StatefulWidget {
  final _WizardConfig cfg;
  const _LoadingScreen({required this.cfg});

  @override
  State<_LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<_LoadingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _spin;
  int _msgIdx = 0;
  Timer? _tick;
  late final List<_QuizQuestion> _questions;
  late final List<(String, String)> _messages;

  String _difficultyLabel() {
    switch (widget.cfg.difficulty) {
      case 'easy':
        return 'kolay';
      case 'hard':
        return 'zor';
      default:
        return 'orta';
    }
  }

  List<String> _selectedSubjectNames() {
    return _allSubjects
        .where((s) => widget.cfg.selectedSubjects.contains(s.key))
        .map((s) => s.name)
        .toList();
  }

  List<String> _selectedTopicSample() {
    final all = <String>[];
    for (final s in _allSubjects) {
      if (!widget.cfg.selectedSubjects.contains(s.key)) continue;
      final picked = widget.cfg.selectedTopics[s.key];
      if (picked != null && picked.isNotEmpty) {
        all.addAll(picked);
      }
    }
    return all;
  }

  @override
  void initState() {
    super.initState();
    _questions = _buildQuestions(widget.cfg);
    final subjNames = _selectedSubjectNames();
    final topicSample = _selectedTopicSample();
    final subjText = widget.cfg.mixer
        ? 'Karışık moda göre'
        : '${subjNames.length} dersten';
    _messages = [
      ('AI testini hazırlıyor...', '$subjText ${_questions.length} soru, ${_difficultyLabel()} zorlukta'),
      (
        'Konular analiz ediliyor...',
        topicSample.isEmpty
            ? (widget.cfg.mixer ? 'Tüm konulardan en uygunları seçiliyor...' : 'Her derse ait konular taranıyor...')
            : '${topicSample.take(3).join(', ')}${topicSample.length > 3 ? '...' : ''}'
      ),
      ('Sorular oluşturuluyor...', 'Senin seviyene özel'),
      ('Son kontroller...', 'Kalite onayı yapılıyor'),
    ];
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _tick = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (!mounted) return;
      if (_msgIdx >= _messages.length - 1) {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => _QuizScreen(cfg: widget.cfg, questions: _questions),
            ),
          );
        });
      } else {
        setState(() => _msgIdx += 1);
      }
    });
  }

  @override
  void dispose() {
    _spin.dispose();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Kamera akışıyla aynı loader — sabit etiket: "Test Sorularınız Oluşturuluyor"
    return Scaffold(
      backgroundColor: Colors.white,
      body: QuAlsarNumericLoader(
        primaryText: 'Test Sorularınız Oluşturuluyor'.tr(),
        staticLabel: true,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  QUIZ
// ═══════════════════════════════════════════════════════════════════════════════
class _QuizQuestion {
  final String subjectKey;
  final String subjectName;
  final String subjectEmoji;
  final Color subjectColor;
  final String topic;
  final String text;
  final String? formula;
  final List<String> options;
  final int correctIndex;
  final String hint;
  final String explanation;
  final String difficulty; // 'easy' | 'medium' | 'hard'
  const _QuizQuestion({
    required this.subjectKey,
    required this.subjectName,
    required this.subjectEmoji,
    required this.subjectColor,
    required this.topic,
    required this.text,
    this.formula,
    required this.options,
    required this.correctIndex,
    required this.hint,
    required this.explanation,
    this.difficulty = 'medium',
  });

  String get subjectTag => '$subjectName • $topic';
}

// Question bank: subjectKey → topic → questions
final Map<String, Map<String, List<_QuizQuestion>>> _questionBank = {
  'math': {
    'Türev': [
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'Türev',
        text: 'Aşağıdaki fonksiyonun x = 2 noktasındaki türevinin değeri kaçtır?',
        formula: 'f(x) = 3x² + 2x − 5',
        options: ['12', '14', '16', '18'],
        correctIndex: 1,
        hint: 'Polinom türevinde her terimin kuvveti 1 azalır ve katsayı ile çarpılır. Sabit terim kaybolur.',
        explanation: "f'(x) = 6x + 2. x = 2 için f'(2) = 6(2) + 2 = 14.",
      ),
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'Türev',
        text: "f(x) = x³ − 4x fonksiyonunun kritik noktalarındaki x değerlerinin toplamı kaçtır?",
        formula: "f(x) = x³ − 4x",
        options: ['−2', '0', '2', '4'],
        correctIndex: 1,
        hint: "Kritik noktalar f'(x) = 0'ı sağlayan x değerleridir.",
        explanation: "f'(x) = 3x² − 4 = 0 → x² = 4/3 → x = ±2/√3. Toplamları 0.",
        difficulty: 'hard',
      ),
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'Türev',
        text: 'f(x) = sin(x) fonksiyonunun x = 0 noktasındaki türevi kaçtır?',
        options: ['0', '1', '−1', 'π'],
        correctIndex: 1,
        hint: 'sin(x) fonksiyonunun türevi cos(x)\'tir.',
        explanation: "f'(x) = cos(x). cos(0) = 1.",
      ),
    ],
    'İntegral': [
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'İntegral',
        text: '∫(2x + 3)dx ifadesinin sonucu nedir?',
        options: ['x² + C', 'x² + 3', 'x² + 3x + C', '2x² + 3x + C'],
        correctIndex: 2,
        hint: "Belirsiz integralde her terimin kuvveti 1 artar ve bölünür. Sonuna C sabiti eklenir.",
        explanation: 'Belirsiz integralde 2x → x², 3 → 3x ve integral sabiti C eklenir.',
      ),
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'İntegral',
        text: '∫₀¹ 3x² dx belirli integralinin değeri kaçtır?',
        options: ['0', '1', '2', '3'],
        correctIndex: 1,
        hint: 'Belirli integral: F(üst) − F(alt). Önce antitürevi bul.',
        explanation: '∫3x² dx = x³. F(1) − F(0) = 1 − 0 = 1.',
      ),
    ],
    'Limit': [
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'Limit',
        text: 'lim (x→2) (x² − 4)/(x − 2) limitinin değeri kaçtır?',
        options: ['0', '2', '4', 'Tanımsız'],
        correctIndex: 2,
        hint: 'Pay 0/0 şekline geliyor. Payı çarpanlara ayır.',
        explanation: '(x² − 4) = (x−2)(x+2). Sadeleştirip x→2 koyunca 2+2 = 4.',
      ),
    ],
    'Logaritma': [
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'Logaritma',
        text: 'log₂(32) değeri kaçtır?',
        options: ['2', '3', '4', '5'],
        correctIndex: 3,
        hint: "log_a(b) = c demek a^c = b demektir.",
        explanation: '2⁵ = 32 olduğundan log₂(32) = 5.',
        difficulty: 'easy',
      ),
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'Logaritma',
        text: 'log(100) + log(10) toplamının değeri kaçtır? (taban 10)',
        options: ['1', '2', '3', '10'],
        correctIndex: 2,
        hint: 'log(a) + log(b) = log(a·b).',
        explanation: 'log(100·10) = log(1000) = 3.',
      ),
    ],
    'Trigonometri': [
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'Trigonometri',
        text: 'sin²(x) + cos²(x) ifadesi neye eşittir?',
        options: ['0', '1', '2', 'tan(x)'],
        correctIndex: 1,
        hint: 'Pisagor trigonometrik özdeşliğini düşün.',
        explanation: 'Her x için sin²(x) + cos²(x) = 1 (temel özdeşlik).',
      ),
    ],
    'Olasılık': [
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'Olasılık',
        text: 'Bir zarın atılmasında çift sayı gelme olasılığı kaçtır?',
        options: ['1/6', '1/3', '1/2', '2/3'],
        correctIndex: 2,
        hint: 'İstenen durum sayısı / toplam durum sayısı.',
        explanation: '6 yüzden 3 tanesi çift (2, 4, 6). 3/6 = 1/2.',
      ),
    ],
    'Permütasyon': [
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'Permütasyon',
        text: '4 farklı kitap kaç farklı şekilde yan yana dizilebilir?',
        options: ['12', '16', '24', '64'],
        correctIndex: 2,
        hint: 'n farklı nesnenin diziliş sayısı n! ile bulunur.',
        explanation: '4! = 4·3·2·1 = 24.',
      ),
    ],
    'Fonksiyonlar': [
      const _QuizQuestion(
        subjectKey: 'math', subjectName: 'Matematik', subjectEmoji: '📐',
        subjectColor: _Palette.math, topic: 'Fonksiyonlar',
        text: 'f(x) = 2x + 1 için f(3) değeri kaçtır?',
        options: ['5', '6', '7', '8'],
        correctIndex: 2,
        hint: 'f(x)\'in tanımında x yerine verilen değeri koy.',
        explanation: 'f(3) = 2·3 + 1 = 7.',
        difficulty: 'easy',
      ),
    ],
  },
  'physics': {
    'Kuvvet ve Hareket': [
      const _QuizQuestion(
        subjectKey: 'physics', subjectName: 'Fizik', subjectEmoji: '⚛️',
        subjectColor: _Palette.physics, topic: 'Kuvvet ve Hareket',
        text: 'Kütlesi 2 kg olan cisme 10 N kuvvet uygulanırsa ivmesi kaç m/s² olur?',
        formula: 'F = m · a',
        options: ['2', '5', '10', '20'],
        correctIndex: 1,
        hint: "Newton'un 2. yasası: F = m·a. İvmeyi bulmak için a = F/m.",
        explanation: 'a = F/m = 10/2 = 5 m/s².',
      ),
      const _QuizQuestion(
        subjectKey: 'physics', subjectName: 'Fizik', subjectEmoji: '⚛️',
        subjectColor: _Palette.physics, topic: 'Kuvvet ve Hareket',
        text: 'Sabit hızla hareket eden bir cismin üzerine etkiyen net kuvvet kaçtır?',
        options: ['Sıfır', 'm·g', 'Pozitif', 'Belirsiz'],
        correctIndex: 0,
        hint: "Newton'un 1. yasası (eylemsizlik): sabit hızda net kuvvet yoktur.",
        explanation: 'Sabit hız = ivme 0. F = m·a = 0 olur.',
      ),
    ],
    'Enerji': [
      const _QuizQuestion(
        subjectKey: 'physics', subjectName: 'Fizik', subjectEmoji: '⚛️',
        subjectColor: _Palette.physics, topic: 'Enerji',
        text: '2 kg kütleli cismin 10 m/s hızdaki kinetik enerjisi kaç J\'dir?',
        formula: 'E_k = ½ m v²',
        options: ['50', '100', '150', '200'],
        correctIndex: 1,
        hint: 'Kinetik enerji formülü: E_k = ½·m·v².',
        explanation: '½ · 2 · 10² = ½ · 2 · 100 = 100 J.',
      ),
    ],
    'Elektrik': [
      const _QuizQuestion(
        subjectKey: 'physics', subjectName: 'Fizik', subjectEmoji: '⚛️',
        subjectColor: _Palette.physics, topic: 'Elektrik',
        text: '10 Ω direnç uçlarına 20 V gerilim uygulanırsa geçen akım kaç A\'dir?',
        formula: 'V = I · R',
        options: ['0.5', '1', '2', '200'],
        correctIndex: 2,
        hint: "Ohm yasası: V = I · R. Akım I = V/R.",
        explanation: 'I = 20/10 = 2 A.',
      ),
    ],
    'Optik': [
      const _QuizQuestion(
        subjectKey: 'physics', subjectName: 'Fizik', subjectEmoji: '⚛️',
        subjectColor: _Palette.physics, topic: 'Optik',
        text: 'Düzlem aynada görüntü özelliği aşağıdakilerden hangisidir?',
        options: ['Gerçek', 'Ters', 'Sanal ve düz', 'Küçülmüş'],
        correctIndex: 2,
        hint: 'Düzlem aynada ışınlar uzantıları ile kesişir.',
        explanation: 'Düzlem aynada görüntü sanal, düz ve cisimle aynı büyüklüktedir.',
      ),
    ],
    'Dalgalar': [
      const _QuizQuestion(
        subjectKey: 'physics', subjectName: 'Fizik', subjectEmoji: '⚛️',
        subjectColor: _Palette.physics, topic: 'Dalgalar',
        text: 'Periyodu 0.5 s olan bir dalganın frekansı kaç Hz\'dir?',
        options: ['0.5', '1', '2', '5'],
        correctIndex: 2,
        hint: 'Frekans ve periyot arasında f = 1/T ilişkisi vardır.',
        explanation: 'f = 1/T = 1/0.5 = 2 Hz.',
      ),
    ],
    'Manyetizma': [
      const _QuizQuestion(
        subjectKey: 'physics', subjectName: 'Fizik', subjectEmoji: '⚛️',
        subjectColor: _Palette.physics, topic: 'Manyetizma',
        text: 'Manyetik alanda hareket eden yüklü parçacığa etkiyen kuvvet hangisine diktir?',
        options: ['Sadece hıza', 'Sadece alana', 'Hem hıza hem alana', 'Hiçbirine'],
        correctIndex: 2,
        hint: 'Lorentz kuvveti F = q·v×B vektörel çarpımdır.',
        explanation: 'F = qv×B ifadesinden kuvvet hem hız hem alan vektörüne diktir.',
      ),
    ],
  },
  'chem': {
    'Atom': [
      const _QuizQuestion(
        subjectKey: 'chem', subjectName: 'Kimya', subjectEmoji: '🧪',
        subjectColor: _Palette.chem, topic: 'Atom',
        text: 'Atom numarası 11 olan sodyumun değerlik elektron sayısı kaçtır?',
        options: ['1', '2', '7', '11'],
        correctIndex: 0,
        hint: '1A grubu elementleri en dış kabukta 1 elektron taşır.',
        explanation: 'Na: 1s² 2s² 2p⁶ 3s¹. Son kabukta 1 elektron var.',
      ),
    ],
    'Mol': [
      const _QuizQuestion(
        subjectKey: 'chem', subjectName: 'Kimya', subjectEmoji: '🧪',
        subjectColor: _Palette.chem, topic: 'Mol',
        text: '36 g saf suda (H₂O, M = 18) kaç mol vardır?',
        options: ['1', '1.5', '2', '3'],
        correctIndex: 2,
        hint: 'Mol sayısı = kütle / mol kütlesi.',
        explanation: 'n = 36/18 = 2 mol.',
      ),
    ],
    'Asit-Baz': [
      const _QuizQuestion(
        subjectKey: 'chem', subjectName: 'Kimya', subjectEmoji: '🧪',
        subjectColor: _Palette.chem, topic: 'Asit-Baz',
        text: 'pH = 3 olan bir çözelti nasıl tanımlanır?',
        options: ['Kuvvetli bazik', 'Zayıf bazik', 'Nötr', 'Asidik'],
        correctIndex: 3,
        hint: 'pH < 7 asidik, pH > 7 baziktir.',
        explanation: 'pH = 3 < 7 olduğundan çözelti asidiktir.',
      ),
    ],
    'Kimyasal Tepkimeler': [
      const _QuizQuestion(
        subjectKey: 'chem', subjectName: 'Kimya', subjectEmoji: '🧪',
        subjectColor: _Palette.chem, topic: 'Kimyasal Tepkimeler',
        text: 'H₂ + ½O₂ → H₂O tepkimesinde korunan hangisidir?',
        options: ['Molekül sayısı', 'Hacim', 'Atom sayısı', 'Basınç'],
        correctIndex: 2,
        hint: 'Kütlenin korunumu → atomlar yok olmaz, yeniden düzenlenir.',
        explanation: 'Kimyasal tepkimelerde her atomun sayısı iki tarafta da eşittir.',
      ),
    ],
    'Gazlar': [
      const _QuizQuestion(
        subjectKey: 'chem', subjectName: 'Kimya', subjectEmoji: '🧪',
        subjectColor: _Palette.chem, topic: 'Gazlar',
        text: 'Normal koşullarda (NK) 1 mol ideal gaz kaç litre hacim kaplar?',
        options: ['11.2', '22.4', '24.5', '44.8'],
        correctIndex: 1,
        hint: 'NK = 0°C ve 1 atm. Avogadro yasası molar hacmi verir.',
        explanation: "NK'da 1 mol ideal gaz 22.4 L hacim kaplar.",
      ),
    ],
  },
  'bio': {
    'Hücre': [
      const _QuizQuestion(
        subjectKey: 'bio', subjectName: 'Biyoloji', subjectEmoji: '🧬',
        subjectColor: _Palette.bio, topic: 'Hücre',
        text: 'Hücrenin enerji üreten organeli hangisidir?',
        options: ['Çekirdek', 'Ribozom', 'Mitokondri', 'Golgi'],
        correctIndex: 2,
        hint: 'ATP üretiminden sorumlu organel.',
        explanation: 'Mitokondri hücrede oksijenli solunumla ATP üretir.',
      ),
    ],
    'Kalıtım': [
      const _QuizQuestion(
        subjectKey: 'bio', subjectName: 'Biyoloji', subjectEmoji: '🧬',
        subjectColor: _Palette.bio, topic: 'Kalıtım',
        text: 'İnsan vücut hücrelerinde kaç çift kromozom bulunur?',
        options: ['22', '23', '46', '47'],
        correctIndex: 1,
        hint: 'Somatik hücrelerde 46 kromozom, "çift" olarak kaç tane?',
        explanation: '46 kromozom = 23 çift homolog kromozom.',
      ),
    ],
    'Ekosistem': [
      const _QuizQuestion(
        subjectKey: 'bio', subjectName: 'Biyoloji', subjectEmoji: '🧬',
        subjectColor: _Palette.bio, topic: 'Ekosistem',
        text: 'Besin zincirinde üreticiler aşağıdakilerden hangisidir?',
        options: ['Otçullar', 'Yeşil bitkiler', 'Etçiller', 'Ayrıştırıcılar'],
        correctIndex: 1,
        hint: 'Fotosentez yapabilenler kendi besinini üretir.',
        explanation: 'Yeşil bitkiler fotosentezle kendi besinini üretir; üretici konumundadır.',
      ),
    ],
    'Sistemler': [
      const _QuizQuestion(
        subjectKey: 'bio', subjectName: 'Biyoloji', subjectEmoji: '🧬',
        subjectColor: _Palette.bio, topic: 'Sistemler',
        text: 'Gaz değişiminin gerçekleştiği asıl yapı hangisidir?',
        options: ['Bronş', 'Alveol', 'Gırtlak', 'Yutak'],
        correctIndex: 1,
        hint: 'Akciğerlerde milyonlarca küçük hava kesesi vardır.',
        explanation: 'Alveoller ile kılcal damarlar arasında gaz alışverişi olur.',
      ),
    ],
  },
  'turkish': {
    'Paragraf': [
      const _QuizQuestion(
        subjectKey: 'turkish', subjectName: 'Türkçe', subjectEmoji: '📖',
        subjectColor: _Palette.turkish, topic: 'Paragraf',
        text: 'Bir paragrafın ana düşüncesi genellikle nerede yer alır?',
        options: ['Sadece başta', 'Sadece sonda', 'Baş veya sonda', 'Ortada'],
        correctIndex: 2,
        hint: 'Paragraf yapılarında giriş ve sonuç cümleleri belirleyicidir.',
        explanation: 'Ana düşünce çoğunlukla giriş (ilk) veya sonuç (son) cümlede verilir.',
      ),
    ],
    'Cümle': [
      const _QuizQuestion(
        subjectKey: 'turkish', subjectName: 'Türkçe', subjectEmoji: '📖',
        subjectColor: _Palette.turkish, topic: 'Cümle',
        text: '"Çocuk parka gitti." cümlesinin yüklemi hangisidir?',
        options: ['Çocuk', 'parka', 'gitti', 'Yok'],
        correctIndex: 2,
        hint: 'Yüklem, cümlede iş/oluş/durum bildiren öğedir.',
        explanation: '"Gitti" fiili cümlenin yüklemidir.',
      ),
    ],
    'Yazım Kuralları': [
      const _QuizQuestion(
        subjectKey: 'turkish', subjectName: 'Türkçe', subjectEmoji: '📖',
        subjectColor: _Palette.turkish, topic: 'Yazım Kuralları',
        text: 'Aşağıdakilerden hangisi doğru yazılmıştır?',
        options: ['herşey', 'her şey', 'herşeyi', 'hersey'],
        correctIndex: 1,
        hint: '"Her" sıfatı kendinden sonraki kelimeden ayrı yazılır.',
        explanation: 'Doğru yazım: "her şey" (iki kelime).',
      ),
    ],
    'Noktalama': [
      const _QuizQuestion(
        subjectKey: 'turkish', subjectName: 'Türkçe', subjectEmoji: '📖',
        subjectColor: _Palette.turkish, topic: 'Noktalama',
        text: 'Sıralı cümleleri ayırmak için hangi noktalama işareti kullanılır?',
        options: ['Nokta', 'Virgül', 'Noktalı virgül', 'İki nokta'],
        correctIndex: 2,
        hint: 'Kendi içinde virgülleri olan sıralı cümlelerde tercih edilir.',
        explanation: 'Noktalı virgül (;) genellikle sıralı cümleleri ayırmak için kullanılır.',
      ),
    ],
  },
  'history': {
    'Osmanlı': [
      const _QuizQuestion(
        subjectKey: 'history', subjectName: 'Tarih', subjectEmoji: '🏛️',
        subjectColor: _Palette.history, topic: 'Osmanlı',
        text: 'İstanbul kaç yılında fethedildi?',
        options: ['1299', '1453', '1492', '1683'],
        correctIndex: 1,
        hint: 'Fatih Sultan Mehmet döneminde, 15. yüzyılın ortasında.',
        explanation: 'İstanbul 29 Mayıs 1453\'te Fatih Sultan Mehmet tarafından fethedildi.',
      ),
    ],
    'Cumhuriyet': [
      const _QuizQuestion(
        subjectKey: 'history', subjectName: 'Tarih', subjectEmoji: '🏛️',
        subjectColor: _Palette.history, topic: 'Cumhuriyet',
        text: 'Türkiye Cumhuriyeti kaç yılında ilan edildi?',
        options: ['1920', '1922', '1923', '1938'],
        correctIndex: 2,
        hint: '29 Ekim... TBMM\'nin açılmasından 3 yıl sonra.',
        explanation: 'Cumhuriyet 29 Ekim 1923\'te ilan edildi.',
      ),
    ],
    'İlk Çağ': [
      const _QuizQuestion(
        subjectKey: 'history', subjectName: 'Tarih', subjectEmoji: '🏛️',
        subjectColor: _Palette.history, topic: 'İlk Çağ',
        text: 'Yazıyı ilk bulan uygarlık hangisidir?',
        options: ['Mısırlılar', 'Sümerler', 'Hititler', 'Fenikeliler'],
        correctIndex: 1,
        hint: 'Mezopotamya\'da çivi yazısını geliştirdiler.',
        explanation: 'Sümerler MÖ 3500 civarında çivi yazısını icat etti.',
      ),
    ],
    'Orta Çağ': [
      const _QuizQuestion(
        subjectKey: 'history', subjectName: 'Tarih', subjectEmoji: '🏛️',
        subjectColor: _Palette.history, topic: 'Orta Çağ',
        text: 'Malazgirt Savaşı hangi yıl yapılmıştır?',
        options: ['1071', '1176', '1243', '1299'],
        correctIndex: 0,
        hint: 'Anadolu\'nun kapılarını Türklere açan savaş, 11. yüzyılda.',
        explanation: 'Malazgirt Savaşı 1071\'de Selçuklu-Bizans arasında yapılmıştır.',
      ),
    ],
  },
  'geo': {
    'İklim': [
      const _QuizQuestion(
        subjectKey: 'geo', subjectName: 'Coğrafya', subjectEmoji: '🌍',
        subjectColor: _Palette.geo, topic: 'İklim',
        text: 'Türkiye\'nin Akdeniz kıyılarında hangi iklim tipi görülür?',
        options: ['Karasal', 'Karadeniz', 'Akdeniz', 'Tundra'],
        correctIndex: 2,
        hint: 'Yazları sıcak-kurak, kışları ılık-yağışlı iklim.',
        explanation: 'Güney kıyılarında Akdeniz iklimi hakimdir.',
      ),
    ],
    'Nüfus': [
      const _QuizQuestion(
        subjectKey: 'geo', subjectName: 'Coğrafya', subjectEmoji: '🌍',
        subjectColor: _Palette.geo, topic: 'Nüfus',
        text: 'Nüfus yoğunluğu nasıl hesaplanır?',
        options: ['Nüfus × alan', 'Nüfus / alan', 'Alan / nüfus', 'Nüfus + alan'],
        correctIndex: 1,
        hint: 'Birim alana düşen kişi sayısı.',
        explanation: 'Nüfus yoğunluğu = Toplam nüfus / Yüzölçümü (km²).',
      ),
    ],
    'Ekonomi': [
      const _QuizQuestion(
        subjectKey: 'geo', subjectName: 'Coğrafya', subjectEmoji: '🌍',
        subjectColor: _Palette.geo, topic: 'Ekonomi',
        text: 'Türkiye\'nin en çok ihraç ettiği tarım ürünlerinden biri hangisidir?',
        options: ['Kahve', 'Fındık', 'Kakao', 'Muz'],
        correctIndex: 1,
        hint: 'Dünya üretiminin büyük bölümü Karadeniz kıyılarında yapılır.',
        explanation: 'Türkiye dünya fındık üretiminin %70\'ini karşılar ve lider ihracatçıdır.',
      ),
    ],
    'Türkiye Coğrafyası': [
      const _QuizQuestion(
        subjectKey: 'geo', subjectName: 'Coğrafya', subjectEmoji: '🌍',
        subjectColor: _Palette.geo, topic: 'Türkiye Coğrafyası',
        text: 'Türkiye\'nin en uzun akarsuyu hangisidir?',
        options: ['Sakarya', 'Kızılırmak', 'Fırat', 'Yeşilırmak'],
        correctIndex: 1,
        hint: 'Yurdumuz sınırları içinden çıkıp yine yurt içinde denize dökülen en uzun ırmak.',
        explanation: 'Kızılırmak 1355 km ile Türkiye\'nin en uzun akarsuyudur.',
      ),
    ],
  },
  'lit': {
    'Şiir': [
      const _QuizQuestion(
        subjectKey: 'lit', subjectName: 'Edebiyat', subjectEmoji: '✒️',
        subjectColor: _Palette.lit, topic: 'Şiir',
        text: 'Türk edebiyatında "Hece ölçüsü" en çok hangi gelenekte kullanılır?',
        options: ['Divan', 'Halk', 'Servet-i Fünun', 'Tanzimat'],
        correctIndex: 1,
        hint: 'Âşık edebiyatının temel ölçüsüdür.',
        explanation: 'Halk edebiyatında hece ölçüsü, Divan\'da aruz ölçüsü kullanılır.',
      ),
    ],
    'Roman': [
      const _QuizQuestion(
        subjectKey: 'lit', subjectName: 'Edebiyat', subjectEmoji: '✒️',
        subjectColor: _Palette.lit, topic: 'Roman',
        text: '"Çalıkuşu" romanının yazarı kimdir?',
        options: ['Halide Edip', 'Reşat Nuri Güntekin', 'Yakup Kadri', 'Peyami Safa'],
        correctIndex: 1,
        hint: 'Feride karakterini yaratan Cumhuriyet dönemi yazarı.',
        explanation: 'Çalıkuşu, Reşat Nuri Güntekin tarafından yazılmıştır (1922).',
      ),
    ],
    'Tiyatro': [
      const _QuizQuestion(
        subjectKey: 'lit', subjectName: 'Edebiyat', subjectEmoji: '✒️',
        subjectColor: _Palette.lit, topic: 'Tiyatro',
        text: 'Türk edebiyatında Batılı anlamda ilk tiyatro eseri hangisidir?',
        options: ['Vatan yahut Silistre', 'Şair Evlenmesi', 'Akif Bey', 'Zavallı Çocuk'],
        correctIndex: 1,
        hint: 'Şinasi\'nin yazdığı kısa ve tek perdelik oyun.',
        explanation: '"Şair Evlenmesi" (Şinasi, 1859) Batılı anlamda ilk tiyatro eseri kabul edilir.',
      ),
    ],
    'Edebi Akımlar': [
      const _QuizQuestion(
        subjectKey: 'lit', subjectName: 'Edebiyat', subjectEmoji: '✒️',
        subjectColor: _Palette.lit, topic: 'Edebi Akımlar',
        text: 'Servet-i Fünun topluluğu hangi akıma daha yakındır?',
        options: ['Klasisizm', 'Romantizm', 'Realizm / Sembolizm', 'Naturalism'],
        correctIndex: 2,
        hint: 'Batı edebiyatının 19. yy sonu akımlarından etkilenmişlerdir.',
        explanation: 'Servet-i Fünun şair ve yazarları realizm ve sembolizmden beslenmiştir.',
      ),
    ],
  },
};

List<_QuizQuestion> _buildQuestions(_WizardConfig cfg) {
  final rng = math.Random();
  final pool = <_QuizQuestion>[];

  if (cfg.mixer) {
    for (final subj in _questionBank.values) {
      for (final list in subj.values) {
        pool.addAll(list);
      }
    }
  } else {
    for (final subjectKey in cfg.selectedSubjects) {
      final subjBank = _questionBank[subjectKey];
      if (subjBank == null) continue;
      final picked = cfg.selectedTopics[subjectKey];
      if (picked == null || picked.isEmpty) {
        for (final list in subjBank.values) {
          pool.addAll(list);
        }
      } else {
        // Müfredat konu adlarından hangisi soru bankasında eşleşiyorsa al
        bool matchedAny = false;
        for (final topic in picked) {
          final list = subjBank[topic];
          if (list != null) {
            pool.addAll(list);
            matchedAny = true;
          }
        }
        // Müfredat konusu bankada yoksa: aynı dersin tüm sorularını havuza at
        if (!matchedAny) {
          for (final list in subjBank.values) {
            pool.addAll(list);
          }
        }
      }
    }
  }

  // Zorluk filtreleme — tam eşleşme + yeterli değilse fallback
  List<_QuizQuestion> prioritized;
  if (cfg.difficulty == 'medium') {
    prioritized = List.of(pool);
  } else {
    final match = pool.where((q) => q.difficulty == cfg.difficulty).toList();
    if (match.length >= cfg.count) {
      prioritized = match;
    } else {
      // Eksikse: önce seçilen zorluk, sonra medium, sonra diğer
      final rest = pool.where((q) => q.difficulty != cfg.difficulty).toList()
        ..sort((a, b) {
          final prefer = cfg.difficulty == 'hard' ? 'medium' : 'medium';
          if (a.difficulty == prefer && b.difficulty != prefer) return -1;
          if (b.difficulty == prefer && a.difficulty != prefer) return 1;
          return 0;
        });
      prioritized = [...match, ...rest];
    }
  }

  prioritized.shuffle(rng);
  if (prioritized.length > cfg.count) {
    return prioritized.sublist(0, cfg.count);
  }
  return prioritized;
}

class _QuizScreen extends StatefulWidget {
  final _WizardConfig cfg;
  final List<_QuizQuestion> questions;
  final ValueChanged<int>? onProgress; // Düello için ilerleme bildirimi
  // Düello modunda varsayılan result ekranına gitme. Çağıran taraf
  // (örn. _DueloQuizScreen) kendi akışını yönetsin.
  final void Function({
    required int elapsedSeconds,
    required Map<int, int> answers,
    required int correctCount,
    required int hintsUsed,
    required int comboMax,
  })? onFinish;
  // Opsiyonel: "Testi Bitir" tıklanınca önce onay iste (true dönerse devam).
  // false dönerse bitir aksiyonu iptal.
  final Future<bool> Function()? onBeforeFinish;
  const _QuizScreen({
    required this.cfg,
    required this.questions,
    this.onProgress,
    this.onFinish,
    this.onBeforeFinish,
  });

  @override
  State<_QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<_QuizScreen> {
  int _index = 0;
  int? _selected;
  final Map<int, int> _answers = {}; // qIndex -> chosen
  final Set<int> _lockedQuestions = {}; // cevap verilmiş & kilitli
  // Power-up state (aktif soru için)
  final Set<int> _hiddenOptions = {}; // 50:50 ile gizlenen şıklar
  final Set<String> _usedInThisQ = {}; // bir soruda aynı power-up tekrar kullanılmaz
  bool _doublePointsActive = false; // 2x QP modunu bu test boyunca aktif tut
  int _hintUsed = 0;
  int _seconds = 0; // toplam geçen süre
  int _qSecondsLeft = 0; // aktif soru için kalan saniye (Normal/Yarış modu)
  Timer? _timer;
  // Combo / streak
  int _combo = 0; // ardışık doğru sayısı
  int _comboMax = 0;
  bool _showComboBurst = false;

  int _perQuestionLimit() {
    switch (widget.cfg.timeMode) {
      case 'normal':
        return 90;
      case 'race':
        return 45;
      default:
        return 0; // Rahat mod
    }
  }

  bool get _countdownActive => _perQuestionLimit() > 0;

  @override
  void initState() {
    super.initState();
    _qSecondsLeft = _perQuestionLimit();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _seconds += 1;
        if (_countdownActive) {
          _qSecondsLeft -= 1;
          if (_qSecondsLeft <= 0) {
            _qSecondsLeft = 0;
            _autoAdvance();
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _total => widget.questions.length;

  String _timerText() {
    final src = _countdownActive ? _qSecondsLeft : _seconds;
    final m = (src ~/ 60).toString().padLeft(2, '0');
    final s = (src % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _lockAnswer() {
    if (_selected == null) return;
    if (_lockedQuestions.contains(_index)) return;
    _lockedQuestions.add(_index);
    _answers[_index] = _selected!;
    final q = widget.questions[_index];
    final isCorrect = _selected == q.correctIndex;
    if (isCorrect) {
      _combo += 1;
      if (_combo > _comboMax) _comboMax = _combo;
      if (_combo >= 3) {
        _showComboBurst = true;
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) setState(() => _showComboBurst = false);
        });
      }
    } else {
      _combo = 0;
      // Survival / Perfect modunda yanlış cevap → anında bitir
      final mode = widget.cfg.challengeMode;
      if (mode == 'survival' || mode == 'perfect') {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) _finishToResults();
        });
      }
    }
  }

  void _usePowerUp(String id) {
    if (_usedInThisQ.contains(id)) return;
    final q = widget.questions[_index];
    switch (id) {
      case 'fiftyFifty':
        if (_arenaState.powerFiftyFifty <= 0) return;
        final wrongs = <int>[];
        for (int i = 0; i < q.options.length; i++) {
          if (i != q.correctIndex) wrongs.add(i);
        }
        wrongs.shuffle();
        setState(() {
          _hiddenOptions.addAll(wrongs.take(2));
          _arenaState.powerFiftyFifty--;
          _usedInThisQ.add(id);
        });
        break;
      case 'freeze':
        if (_arenaState.powerFreeze <= 0) return;
        if (!_countdownActive) return;
        setState(() {
          _qSecondsLeft += 30;
          _arenaState.powerFreeze--;
          _usedInThisQ.add(id);
        });
        break;
      case 'skip':
        if (_arenaState.powerSkip <= 0) return;
        _arenaState.powerSkip--;
        _lockedQuestions.add(_index);
        _combo = 0; // skip sayılır
        if (_index >= _total - 1) {
          _finishToResults();
        } else {
          setState(() {
            _index += 1;
            _selected = _answers[_index];
            _qSecondsLeft = _perQuestionLimit();
            _hiddenOptions.clear();
            _usedInThisQ.clear();
          });
        }
        break;
      case 'double':
        if (_arenaState.powerDoublePoints <= 0) return;
        setState(() {
          _doublePointsActive = true;
          _arenaState.powerDoublePoints--;
          _usedInThisQ.add(id);
        });
        break;
    }
    _arenaState.save();
  }

  int _countCorrect() {
    int c = 0;
    for (final e in _answers.entries) {
      if (e.value == widget.questions[e.key].correctIndex) c++;
    }
    return c;
  }

  Future<void> _finishToResults() async {
    // Düello/custom akışı varsa önce onay sor.
    if (widget.onBeforeFinish != null) {
      final ok = await widget.onBeforeFinish!();
      if (!ok) return;
    }
    _timer?.cancel();

    // Callback varsa dış akışa bırak (düello bekleme/sonuç sayfasını açar).
    if (widget.onFinish != null) {
      widget.onFinish!(
        elapsedSeconds: _seconds,
        answers: Map<int, int>.from(_answers),
        correctCount: _countCorrect(),
        hintsUsed: _hintUsed,
        comboMax: _comboMax,
      );
      return;
    }

    // Solo mod — standart akış.
    await _arenaState.onQuizCompleted(
      questions: widget.questions,
      answers: _answers,
      comboMax: _comboMax,
      doublePoints: _doublePointsActive,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _ResultsScreen(
          questions: widget.questions,
          answers: _answers,
          elapsedSeconds: _seconds,
          hintsUsed: _hintUsed,
          comboMax: _comboMax,
        ),
      ),
    );
  }

  void _autoAdvance() {
    if (_selected != null && !_lockedQuestions.contains(_index)) {
      _lockAnswer();
    }
    if (_index >= _total - 1) {
      _finishToResults();
    } else {
      _index += 1;
      _selected = _answers[_index];
      _qSecondsLeft = _perQuestionLimit();
    }
  }

  void _next() {
    _lockAnswer();
    widget.onProgress?.call(_index + 1);
    if (_index >= _total - 1) {
      _finishToResults();
    } else {
      setState(() {
        _index += 1;
        _selected = _answers[_index];
        _qSecondsLeft = _perQuestionLimit();
        _hiddenOptions.clear();
        _usedInThisQ.clear();
      });
    }
  }

  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Testten çıkmak istiyor musun?'.tr(), style: _sans(size: 15, weight: FontWeight.w600)),
        content: Text('İlerlemen kaydedilmeyecek.'.tr(), style: _sans(size: 13, color: _Palette.inkSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Vazgeç'.tr())),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Çık'.tr())),
        ],
      ),
    );
    if (ok == true && mounted) {
      _timer?.cancel();
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _openHint() async {
    // Test başına tek ipucu hakkı. Daha önce kullanıldıysa kısa bir
    // bilgilendirme göster ve çık.
    if (_hintUsed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('İpucu hakkını bu testte zaten kullandın.'.tr()),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    // Önce onay dialog'u — kullanıcı isterse bu soruda kullansın,
    // isterse vazgeçip başka soru için saklasın.
    const lightOrangeBg = Color(0xFFFED7AA); // açık turuncu zemin
    const lightOrangeText = Color(0xFFC2410C); // okunur koyu turuncu
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: const Text('💡', style: TextStyle(fontSize: 28)),
              ),
              const SizedBox(height: 14),
              Text(
                'İpucu Hakkı'.tr(),
                style: _serif(
                  size: 18,
                  weight: FontWeight.w700,
                  letterSpacing: -0.01,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bu test için sadece bir defa kullanacaksın.\n'
                        'Bu soru için açmak ister misin, yoksa başka soruya saklamak mı?'
                    .tr(),
                textAlign: TextAlign.center,
                style: _sans(
                  size: 13,
                  weight: FontWeight.w500,
                  color: _Palette.inkSoft,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(false),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: lightOrangeBg,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Sakla'.tr(),
                          style: _sans(
                            size: 13,
                            weight: FontWeight.w800,
                            color: lightOrangeText,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(true),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: lightOrangeBg,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Bu Soruda Kullan'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sans(
                            size: 13,
                            weight: FontWeight.w900,
                            color: lightOrangeText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _hintUsed += 1);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HintSheet(q: widget.questions[_index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return _EmptyQuizPlaceholder();
    }
    final q = widget.questions[_index];
    final progress = (_index + 1) / _total;
    return Scaffold(
      backgroundColor: _Palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _confirmExit,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _Palette.surface,
                            border: Border.all(color: _Palette.line),
                          ),
                          child: const Icon(Icons.close_rounded, size: 16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      RichText(
                        text: TextSpan(
                          style: _sans(size: 13, weight: FontWeight.w600),
                          children: [
                            TextSpan(text: '${_index + 1}'),
                            TextSpan(text: '/$_total', style: _sans(size: 13, color: _Palette.inkMute, weight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _countdownActive && _qSecondsLeft <= 10
                              ? _Palette.error
                              : _Palette.ink,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _countdownActive ? Icons.timer_rounded : Icons.access_time_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(_timerText(), style: _mono(size: 12, color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: _Palette.line,
                      valueColor: const AlwaysStoppedAnimation(_Palette.brand),
                    ),
                  ),
                  if (_combo >= 2) ...[
                    const SizedBox(height: 8),
                    _ComboBadge(combo: _combo, burst: _showComboBurst),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _Palette.surface,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: _Palette.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 7, height: 7, decoration: BoxDecoration(color: q.subjectColor, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                q.subjectTag,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _sans(size: 11, weight: FontWeight.w600, color: _Palette.inkSoft),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // ── Soru metni beyaz çerçeve içinde ──────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _Palette.line, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            q.text,
                            style: _serif(
                              size: 22,
                              weight: FontWeight.w500,
                              letterSpacing: -0.02,
                              height: 1.35,
                            ),
                          ),
                          if (q.formula != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: _Palette.ink,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                q.formula!,
                                style: _mono(
                                    size: 15, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (int i = 0; i < q.options.length; i++)
                      if (!_hiddenOptions.contains(i))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _OptionTile(
                            letter: String.fromCharCode(65 + i),
                            text: q.options[i],
                            selected: _selected == i,
                            onTap: () => setState(() => _selected = i),
                          ),
                        ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _hintUsed > 0 ? null : _openHint,
                    child: Opacity(
                      opacity: _hintUsed > 0 ? 0.45 : 1.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E5),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                              color: const Color(0xFFFFE0B8), width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Text(_hintUsed > 0 ? '✅' : '💡',
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(
                              _hintUsed > 0
                                  ? 'Kullanıldı'.tr()
                                  : 'İpucu'.tr(),
                              style: _sans(
                                  size: 13,
                                  weight: FontWeight.w600,
                                  color: const Color(0xFFB45309)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PrimaryButton(
                      label: _index >= _total - 1 ? 'Testi Bitir' : 'Sonraki Soru',
                      trailingIcon: _index >= _total - 1 ? Icons.check_rounded : Icons.arrow_forward_rounded,
                      onTap: _selected == null ? null : _next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerUpButton extends StatelessWidget {
  final String emoji;
  final String label;
  final int count;
  final bool disabled;
  final bool active;
  final VoidCallback onTap;
  const _PowerUpButton({
    required this.emoji,
    required this.label,
    required this.count,
    required this.disabled,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = !disabled && count > 0;
    return GestureDetector(
      onTap: canTap ? onTap : null,
      child: Opacity(
        opacity: canTap || active ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: active ? _Palette.brand : _Palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? _Palette.brand : _Palette.line,
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                  if (count > 0)
                    Positioned(
                      top: -4,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: active ? Colors.white : _Palette.ink,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          '$count',
                          style: _sans(
                            size: 8,
                            weight: FontWeight.w800,
                            color: active ? _Palette.brand : Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(
                  size: 9,
                  weight: FontWeight.w700,
                  color: active ? Colors.white : _Palette.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComboBadge extends StatelessWidget {
  final int combo;
  final bool burst;
  const _ComboBadge({required this.combo, required this.burst});

  int get _mult {
    if (combo >= 5) return 3;
    if (combo >= 3) return 2;
    return 1; // 2'lik combo'da hala 1x ama flame gösterilir
  }

  @override
  Widget build(BuildContext context) {
    final mult = _mult;
    return AnimatedScale(
      scale: burst ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          gradient: LinearGradient(
            colors: mult >= 3
                ? const [Color(0xFFFF5B2E), Color(0xFFC00E0E)]
                : mult >= 2
                    ? const [Color(0xFFFF9E44), Color(0xFFFF5B2E)]
                    : [Colors.white, Colors.white],
          ),
          border: Border.all(
            color: mult >= 2 ? Colors.transparent : _Palette.line,
            width: 1,
          ),
          boxShadow: mult >= 2
              ? [BoxShadow(color: _Palette.brand.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(combo >= 5 ? '🚀' : '🔥', style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(
              '$combo\'lı COMBO · ${mult}x puan',
              style: _sans(
                size: 11,
                weight: FontWeight.w800,
                color: mult >= 2 ? Colors.white : _Palette.ink,
                letterSpacing: 0.04,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String letter;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({required this.letter, required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _Palette.ink : _Palette.line, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? _Palette.ink : Colors.transparent,
                border: Border.all(color: selected ? _Palette.ink : _Palette.inkMute, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(letter, style: _sans(size: 12, weight: FontWeight.w700, color: selected ? Colors.white : _Palette.ink)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: _sans(size: 14, height: 1.4))),
          ],
        ),
      ),
    );
  }
}

class _HintSheet extends StatefulWidget {
  final _QuizQuestion q;
  const _HintSheet({required this.q});

  @override
  State<_HintSheet> createState() => _HintSheetState();
}

class _HintSheetState extends State<_HintSheet> {
  bool _level2Open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      decoration: const BoxDecoration(
        color: _Palette.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: _Palette.inkMute, borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          Text('💡 İpucu'.tr(), style: _serif(size: 20, weight: FontWeight.w600, letterSpacing: -0.02)),
          const SizedBox(height: 6),
          Text('İpucu puanını etkilemez, sadece yönlendirir.'.tr(),
              style: _sans(size: 12, color: _Palette.inkMute)),
          const SizedBox(height: 14),
          _hintCard(
            title: '${widget.q.subjectName.toUpperCase()} · ${widget.q.topic.toUpperCase()}',
            body: widget.q.hint,
          ),
          const SizedBox(height: 10),
          if (!_level2Open)
            GestureDetector(
              onTap: () => setState(() => _level2Open = true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1EA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Palette.line),
                ),
                alignment: Alignment.center,
                child: Text("🔒 Kademe 2'yi göster — Çözüme yaklaş",
                    style: _sans(size: 14, color: _Palette.inkMute)),
              ),
            )
          else
            _hintCard(
              title: 'KADEME 2 — ÇÖZÜME YAKLAŞ'.tr(),
              body: widget.q.explanation,
            ),
        ],
      ),
    );
  }

  Widget _hintCard({required String title, required String body}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _sans(size: 12, weight: FontWeight.w700, color: _Palette.brand, letterSpacing: 0.06)),
          const SizedBox(height: 6),
          Text(body, style: _sans(size: 14, color: _Palette.inkSoft, height: 1.5)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  RESULTS
// ═══════════════════════════════════════════════════════════════════════════════
class _ResultsScreen extends StatefulWidget {
  final Map<int, int> answers;
  final int elapsedSeconds;
  final int hintsUsed;
  final List<_QuizQuestion> questions;
  final int comboMax;
  const _ResultsScreen({
    required this.questions,
    required this.answers,
    required this.elapsedSeconds,
    required this.hintsUsed,
    this.comboMax = 0,
  });

  @override
  State<_ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<_ResultsScreen> with TickerProviderStateMixin {
  late AnimationController _scoreCtrl;
  late Animation<double> _scoreAnim;

  int get _correct {
    int c = 0;
    for (int i = 0; i < widget.questions.length; i++) {
      if (widget.answers[i] == widget.questions[i].correctIndex) c++;
    }
    return c;
  }

  int get _total => widget.questions.length;
  double get _percent => _total == 0 ? 0 : _correct / _total;

  // Subject performance: key → (name, emoji, color, correct, total)
  Map<String, _SubjectStat> _subjectStats() {
    final map = <String, _SubjectStat>{};
    for (int i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final stat = map.putIfAbsent(
        q.subjectKey,
        () => _SubjectStat(name: q.subjectName, emoji: q.subjectEmoji, color: q.subjectColor),
      );
      stat.total += 1;
      if (widget.answers[i] == q.correctIndex) stat.correct += 1;
    }
    return map;
  }

  // Topic that had the most wrong answers (returns null if perfect score or no data)
  ({String subjectName, String topic, int wrong, int total})? _weakestTopic() {
    final perTopic = <String, (_QuizQuestion sample, int wrong, int total)>{};
    for (int i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final key = '${q.subjectKey}|${q.topic}';
      final cur = perTopic[key];
      final isWrong = widget.answers[i] != q.correctIndex;
      if (cur == null) {
        perTopic[key] = (q, isWrong ? 1 : 0, 1);
      } else {
        perTopic[key] = (cur.$1, cur.$2 + (isWrong ? 1 : 0), cur.$3 + 1);
      }
    }
    String? bestKey;
    int bestWrong = 0;
    double bestRatio = 0;
    perTopic.forEach((k, v) {
      if (v.$2 == 0) return;
      final ratio = v.$2 / v.$3;
      if (v.$2 > bestWrong || (v.$2 == bestWrong && ratio > bestRatio)) {
        bestKey = k;
        bestWrong = v.$2;
        bestRatio = ratio;
      }
    });
    if (bestKey == null) return null;
    final tuple = perTopic[bestKey]!;
    return (
      subjectName: tuple.$1.subjectName,
      topic: tuple.$1.topic,
      wrong: tuple.$2,
      total: tuple.$3,
    );
  }

  @override
  void initState() {
    super.initState();
    _scoreCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _scoreAnim = CurvedAnimation(parent: _scoreCtrl, curve: Curves.easeOutCubic);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _scoreCtrl.forward();
    });
  }

  @override
  void dispose() {
    _scoreCtrl.dispose();
    super.dispose();
  }

  String _elapsed() {
    final m = (widget.elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (widget.elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_percent * 100).round();
    final badgeWon = pct >= 70;
    return Scaffold(
      backgroundColor: _Palette.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _hero(pct: pct, badgeWon: badgeWon),
              const SizedBox(height: 8),
              _statsRow(),
              _rewardCard(),
              _perfCard(),
              _weakCard(),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ShareCTA(onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => _SocialShareSheet(
                      questions: widget.questions,
                      answers: widget.answers,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _SecondaryButton(
                        label: '📝 Cevapları İncele'.tr(),
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => _ReviewScreen(
                              questions: widget.questions,
                              answers: widget.answers,
                            ),
                          ));
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SecondaryButton(
                        label: '🔄 Tekrar Çöz'.tr(),
                        onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero({required int pct, required bool badgeWon}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.4,
              colors: [Color(0x1FFF5B2E), _Palette.bg],
              stops: [0, 0.5],
            ),
          ),
          child: Column(
            children: [
              Text('🎉 TAMAMLANDI'.tr(),
                  style: _sans(size: 11, weight: FontWeight.w700, color: _Palette.brand, letterSpacing: 0.1)),
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                height: 200,
                child: AnimatedBuilder(
                  animation: _scoreAnim,
                  builder: (_, __) {
                    final anim = _scoreAnim.value * _percent;
                    final num = (_scoreAnim.value * _correct);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(200, 200),
                          painter: _ScoreRingPainter(progress: anim),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RichText(
                              text: TextSpan(
                                text: num.round().toString(),
                                style: _serif(size: 54, weight: FontWeight.w700, letterSpacing: -0.04, height: 1),
                                children: [
                                  TextSpan(
                                    text: '/$_total',
                                    style: _serif(size: 26, weight: FontWeight.w700, color: _Palette.inkMute),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text('%${(anim * 100).round()} başarı'.tr(),
                                style: _sans(size: 14, color: _Palette.inkMute, weight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (badgeWon) ...[
                const SizedBox(height: 4),
                ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _scoreCtrl,
                    curve: const Interval(0.5, 1.0, curve: Curves.elasticOut),
                  ),
                  child: Column(
                    children: [
                      Text('🏆'.tr(), style: TextStyle(fontSize: 44)),
                      const SizedBox(height: 4),
                      Text('Bilgi Ustası'.tr(), style: _serif(size: 20, weight: FontWeight.w600, letterSpacing: -0.01)),
                      const SizedBox(height: 2),
                      Text('Harika iş çıkardın!'.tr(), style: _sans(size: 12, color: _Palette.inkMute)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statsRow() {
    final cells = [
      ('✅', '$_correct', 'Doğru'),
      ('❌', '${_total - _correct}', 'Yanlış'),
      ('⏱️', _elapsed(), 'Süre'),
      ('💡', '${widget.hintsUsed}', 'İpucu'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (int i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                decoration: BoxDecoration(
                  color: _Palette.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _Palette.line),
                ),
                child: Column(
                  children: [
                    Text(cells[i].$1, style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(cells[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _serif(size: 18, weight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 2),
                    Text(cells[i].$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sans(size: 10, color: _Palette.inkMute)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _perfCard() {
    final stats = _subjectStats();
    if (stats.isEmpty) return const SizedBox.shrink();
    final entries = stats.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ders Performansın'.tr(), style: _serif(size: 16, weight: FontWeight.w600, letterSpacing: -0.01)),
          const SizedBox(height: 4),
          Text('Bu testte çözdüğün ${entries.length} derste nasıl gittin'.tr(),
              style: _sans(size: 11, color: _Palette.inkMute)),
          const SizedBox(height: 14),
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _perfRow(
              '${entries[i].emoji} ${entries[i].name}',
              entries[i].total == 0 ? 0 : entries[i].correct / entries[i].total,
              entries[i].color,
              '${entries[i].correct}/${entries[i].total}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _perfRow(String name, double value, Color color, String score) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(name, style: _sans(size: 13, weight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: _Palette.line,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 36, child: Text(score, textAlign: TextAlign.right, style: _sans(size: 12, weight: FontWeight.w600))),
      ],
    );
  }

  Widget _rewardCard() {
    // Kazanılan QP'yi yeniden hesapla (UI amaçlı)
    final correct = _correct;
    final baseQP = correct * 15;
    final comboBonus = widget.comboMax * 5;
    const finishBonus = 20;
    final totalQP = baseQP + comboBonus + finishBonus;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8E1), Color(0xFFFFE0B2)],
        ),
        border: Border.all(color: const Color(0xFFFFD180)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚡', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Kazandığın QP',
                  style: _sans(size: 12, weight: FontWeight.w800, color: Color(0xFFB45309), letterSpacing: 0.06),
                ),
              ),
              Text(
                '+$totalQP QP',
                style: _serif(size: 26, weight: FontWeight.w800, color: Color(0xFFB45309), letterSpacing: -0.03),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _rewardBreakdown('🎯 Doğru cevaplar', '$correct × 15', '+$baseQP'),
          if (widget.comboMax >= 2)
            _rewardBreakdown('🔥 En uzun combo', '${widget.comboMax} × 5', '+$comboBonus'),
          _rewardBreakdown('✅ Test bitirme', 'sabit', '+$finishBonus'),
          const SizedBox(height: 6),
          Text(
            'Yeni bakiye: ${_arenaState.qp} QP',
            style: _sans(size: 11, color: _Palette.inkSoft, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _rewardBreakdown(String label, String calc, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _sans(size: 12, color: const Color(0xFF78350F)),
            ),
          ),
          Text(
            calc,
            style: _sans(size: 10, color: const Color(0xFF9A3412)),
          ),
          const SizedBox(width: 8),
          Text(
            val,
            style: _sans(size: 12, weight: FontWeight.w700, color: const Color(0xFFB45309)),
          ),
        ],
      ),
    );
  }

  Widget _weakCard() {
    final weak = _weakestTopic();
    // If there's no weak topic: show a positive reinforcement card instead
    if (weak == null) {
      if (widget.questions.isEmpty) return const SizedBox.shrink();
      final sample = widget.questions.first;
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🎉 HARİKA SONUÇ'.tr(),
                style: _sans(size: 12, weight: FontWeight.w700, color: const Color(0xFF047857), letterSpacing: 0.06)),
            const SizedBox(height: 6),
            Text(
              'Tüm soruları doğru yanıtladın! ${sample.subjectName} alanında kendini geliştirmeye devam etmek ister misin?',
              style: _sans(size: 14, color: _Palette.ink, height: 1.4),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _weakBtn(
                  '🚀 Daha zor seviye dene',
                  bg: Colors.white,
                  border: const Color(0xFFA7F3D0),
                  color: const Color(0xFF047857),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFE0B8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💡 GELİŞİM ÖNERİSİ'.tr(),
              style: _sans(size: 12, weight: FontWeight.w700, color: const Color(0xFFB45309), letterSpacing: 0.06)),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: _sans(size: 14, color: _Palette.ink, height: 1.4),
              children: [
                TextSpan(
                  text: '${weak.subjectName} · ${weak.topic}',
                  style: _sans(size: 14, weight: FontWeight.w700, color: _Palette.ink),
                ),
                TextSpan(
                  text: " konusunda ${weak.total} sorudan ${weak.wrong}'i yanlış. Bu konuyu pekiştirmeni öneriyorum.",
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _weakBtn('📸 Bu konudan çöz'),
              _weakBtn('🎯 Sadece ${weak.topic} testi'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weakBtn(String text, {Color? bg, Color? border, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: bg ?? Colors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: border ?? const Color(0xFFFFE0B8)),
      ),
      child: Text(text, style: _sans(size: 12, weight: FontWeight.w600, color: color ?? const Color(0xFFB45309))),
    );
  }
}

class _SubjectStat {
  final String name;
  final String emoji;
  final Color color;
  int correct;
  int total;
  _SubjectStat({required this.name, required this.emoji, required this.color}) : correct = 0, total = 0;
}

class _EmptyQuizPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🔍'.tr(), style: TextStyle(fontSize: 60)),
                const SizedBox(height: 16),
                Text(
                  'Seçilen konu için soru bulunamadı',
                  textAlign: TextAlign.center,
                  style: _serif(size: 20, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lütfen geri dönüp farklı bir ders veya konu seç.',
                  textAlign: TextAlign.center,
                  style: _sans(size: 13, color: _Palette.inkMute),
                ),
                const SizedBox(height: 20),
                _PrimaryButton(
                  label: 'Geri dön'.tr(),
                  onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  final double progress;
  _ScoreRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 12;
    final strokeWidth = 12.0;

    final bg = Paint()
      ..color = _Palette.line
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, bg);

    final grad = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: 3 * math.pi / 2,
      colors: const [_Palette.brand, _Palette.brandDeep],
    );
    final fg = Paint()
      ..shader = grad.createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter old) => old.progress != progress;
}

class _ShareCTA extends StatelessWidget {
  final VoidCallback onTap;
  const _ShareCTA({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_Palette.brand, _Palette.brandDeep],
          ),
          boxShadow: [
            BoxShadow(color: _Palette.brand.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.share_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Sosyal Medya Hesaplarında Paylaş',
                style: _sans(size: 15, weight: FontWeight.w700, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  REVIEW
// ═══════════════════════════════════════════════════════════════════════════════
class _ReviewScreen extends StatelessWidget {
  final List<_QuizQuestion> questions;
  final Map<int, int> answers;
  const _ReviewScreen({required this.questions, required this.answers});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      appBar: AppBar(
        backgroundColor: _Palette.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: _CircleBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
        ),
        title: Text('Cevap İnceleme'.tr(), style: _serif(size: 18, weight: FontWeight.w600, letterSpacing: -0.02)),
        shape: const Border(bottom: BorderSide(color: _Palette.line)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        itemCount: questions.length,
        itemBuilder: (_, i) {
          final q = questions[i];
          final chosen = answers[i];
          final correct = chosen == q.correctIndex;
          return _ReviewItem(
            index: i + 1,
            question: q,
            chosen: chosen,
            correct: correct,
          );
        },
      ),
    );
  }
}

class _ReviewItem extends StatelessWidget {
  final int index;
  final _QuizQuestion question;
  final int? chosen;
  final bool correct;
  const _ReviewItem({required this.index, required this.question, required this.chosen, required this.correct});

  @override
  Widget build(BuildContext context) {
    final bg = correct ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final border = correct ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: correct ? _Palette.success : _Palette.error,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(correct ? '✓ Doğru' : '✗ Yanlış',
                    style: _sans(size: 11, weight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Soru $index • ${question.subjectTag.split('•').last.trim()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(size: 11, color: _Palette.inkMute, weight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(question.text, style: _sans(size: 14, weight: FontWeight.w500, height: 1.5)),
          if (question.formula != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: _Palette.ink, borderRadius: BorderRadius.circular(8)),
              child: Text(question.formula!, style: _mono(size: 13, color: Colors.white)),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: correct ? Colors.white.withValues(alpha: .6) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: RichText(
              text: TextSpan(
                style: _sans(size: 12, color: _Palette.ink, height: 1.5),
                children: [
                  TextSpan(text: 'Senin cevabın: ', style: _sans(size: 12, weight: FontWeight.w700)),
                  TextSpan(
                    text: chosen == null
                        ? 'Boş'
                        : '${String.fromCharCode(65 + chosen!)}) ${question.options[chosen!]} ${correct ? "✓" : "✗"}',
                  ),
                ],
              ),
            ),
          ),
          if (!correct) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(10)),
              child: RichText(
                text: TextSpan(
                  style: _sans(size: 12, color: _Palette.ink, height: 1.5),
                  children: [
                    TextSpan(text: 'Doğru cevap: ', style: _sans(size: 12, weight: FontWeight.w700)),
                    TextSpan(
                      text: '${String.fromCharCode(65 + question.correctIndex)}) ${question.options[question.correctIndex]} ✓',
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _Palette.line, style: BorderStyle.solid)),
            ),
            child: RichText(
              text: TextSpan(
                style: _sans(size: 12, color: _Palette.inkSoft, height: 1.5),
                children: [
                  TextSpan(text: 'Çözüm: ', style: _sans(size: 12, weight: FontWeight.w700, color: _Palette.ink)),
                  TextSpan(text: question.explanation),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SOSYAL MEDYA PAYLAŞIM SHEET — telefondaki yüklü uygulamaları tespit edip listeler
// ═══════════════════════════════════════════════════════════════════════════════

class _SocialApp {
  final String key;
  final String name;
  final Color color;
  final Gradient? gradient;
  final Widget logo;
  final String iosDetectScheme; // canLaunchUrl için
  final String Function(String encodedText) shareUrl;
  const _SocialApp({
    required this.key,
    required this.name,
    required this.color,
    this.gradient,
    required this.logo,
    required this.iosDetectScheme,
    required this.shareUrl,
  });
}

// Türkiye'de en çok kullanılan sosyal medya uygulamaları, popülerliğe göre sıralı.
List<_SocialApp> _allSocialApps = [
  _SocialApp(
    key: 'whatsapp',
    name: 'WhatsApp',
    color: const Color(0xFF25D366),
    logo: const _BrandLogo(icon: Icons.chat_rounded),
    iosDetectScheme: 'whatsapp://send?text=test',
    shareUrl: (t) => 'whatsapp://send?text=$t',
  ),
  _SocialApp(
    key: 'instagram',
    name: 'Instagram',
    color: const Color(0xFFE1306C),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF833AB4), Color(0xFFE1306C), Color(0xFFFD1D1D), Color(0xFFFCB045)],
    ),
    logo: const _BrandLogo(icon: Icons.camera_alt_rounded),
    iosDetectScheme: 'instagram://app',
    shareUrl: (t) => 'instagram://library?AssetPath=',
  ),
  _SocialApp(
    key: 'tiktok',
    name: 'TikTok',
    color: const Color(0xFF000000),
    logo: const _BrandLogo(icon: Icons.music_note_rounded),
    iosDetectScheme: 'snssdk1233://',
    shareUrl: (t) => 'snssdk1233://',
  ),
  _SocialApp(
    key: 'x',
    name: 'X',
    color: const Color(0xFF000000),
    logo: const _BrandLogo(icon: Icons.close_rounded),
    iosDetectScheme: 'twitter://',
    shareUrl: (t) => 'twitter://post?message=$t',
  ),
  _SocialApp(
    key: 'telegram',
    name: 'Telegram',
    color: const Color(0xFF26A5E4),
    logo: const _BrandLogo(icon: Icons.send_rounded),
    iosDetectScheme: 'tg://msg?text=hi',
    shareUrl: (t) => 'tg://msg?text=$t',
  ),
  _SocialApp(
    key: 'threads',
    name: 'Threads',
    color: const Color(0xFF000000),
    logo: const _BrandLogo(icon: Icons.alternate_email_rounded),
    iosDetectScheme: 'barcelona://',
    shareUrl: (t) => 'barcelona://',
  ),
  _SocialApp(
    key: 'messenger',
    name: 'Messenger',
    color: const Color(0xFF006AFF),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0084FF), Color(0xFFA033FF), Color(0xFFFF5E3A)],
    ),
    logo: const _BrandLogo(icon: Icons.forum_rounded),
    iosDetectScheme: 'fb-messenger://',
    shareUrl: (t) => 'fb-messenger://share?link=https://snapans.app',
  ),
  _SocialApp(
    key: 'facebook',
    name: 'Facebook',
    color: const Color(0xFF1877F2),
    logo: const _BrandLogo(icon: Icons.facebook_rounded),
    iosDetectScheme: 'fb://',
    shareUrl: (t) => 'fb://facewebmodal/f?href=https%3A%2F%2Fsnapans.app',
  ),
  _SocialApp(
    key: 'snapchat',
    name: 'Snapchat',
    color: const Color(0xFFFFFC00),
    logo: const _BrandLogo(icon: Icons.photo_camera_back_rounded, iconColor: Colors.black87),
    iosDetectScheme: 'snapchat://',
    shareUrl: (t) => 'snapchat://',
  ),
  _SocialApp(
    key: 'linkedin',
    name: 'LinkedIn',
    color: const Color(0xFF0A66C2),
    logo: const _BrandLogo(icon: Icons.business_center_rounded),
    iosDetectScheme: 'linkedin://',
    shareUrl: (t) => 'linkedin://shareArticle?mini=true&url=https%3A%2F%2Fsnapans.app',
  ),
  _SocialApp(
    key: 'pinterest',
    name: 'Pinterest',
    color: const Color(0xFFE60023),
    logo: const _BrandLogo(icon: Icons.push_pin_rounded),
    iosDetectScheme: 'pinterest://',
    shareUrl: (t) => 'pinterest://',
  ),
  _SocialApp(
    key: 'discord',
    name: 'Discord',
    color: const Color(0xFF5865F2),
    logo: const _BrandLogo(icon: Icons.gamepad_rounded),
    iosDetectScheme: 'discord://',
    shareUrl: (t) => 'discord://',
  ),
  _SocialApp(
    key: 'reddit',
    name: 'Reddit',
    color: const Color(0xFFFF4500),
    logo: const _BrandLogo(icon: Icons.forum_outlined),
    iosDetectScheme: 'reddit://',
    shareUrl: (t) => 'reddit://',
  ),
];

class _BrandLogo extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  const _BrandLogo({required this.icon, this.iconColor = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 26, color: iconColor);
  }
}

Future<List<_SocialApp>> _detectInstalledApps() async {
  final results = <_SocialApp>[];
  for (final app in _allSocialApps) {
    try {
      final uri = Uri.parse(app.iosDetectScheme);
      if (await canLaunchUrl(uri)) {
        results.add(app);
      }
    } catch (_) {
      // canLaunchUrl kırılırsa sessizce atla
    }
  }
  return results;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ŞABLONLAR — 6 renk, QuAlsar başlığı her şablonda al kırmızı
// ═══════════════════════════════════════════════════════════════════════════════
class _ShareTemplate {
  final Gradient? gradient;
  final Color? solidColor;
  final Color textColor;
  final Color mutedColor;
  final Color brandColor; // QuAlsar brand rengi (al kırmızı varyantı)
  final Color cardBadgeBg;
  const _ShareTemplate({
    this.gradient,
    this.solidColor,
    required this.textColor,
    required this.mutedColor,
    required this.brandColor,
    required this.cardBadgeBg,
  });
}

// Al kırmızı (#C8102E) — Türk bayrağı kırmızısına yakın klasik tonu
const _alRed = Color(0xFFC8102E);
const _alRedBright = Color(0xFFFF2E47); // koyu arka planlarda kullanılan parlak varyant

final List<_ShareTemplate> _shareTemplates = [
  // 1 — Saf beyaz, minimalist
  _ShareTemplate(
    solidColor: Colors.white,
    textColor: _Palette.ink,
    mutedColor: _Palette.inkSoft,
    brandColor: _alRed,
    cardBadgeBg: Color(0x140E0E10),
  ),
  // 2 — Krem kağıt
  _ShareTemplate(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFF8F0), Color(0xFFFAE4D0)],
    ),
    textColor: _Palette.ink,
    mutedColor: _Palette.inkSoft,
    brandColor: _alRed,
    cardBadgeBg: Color(0x140E0E10),
  ),
  // 3 — Koyu tema
  _ShareTemplate(
    solidColor: Color(0xFF0E0E10),
    textColor: Colors.white,
    mutedColor: Color(0xFFB5B5BC),
    brandColor: _alRedBright,
    cardBadgeBg: Color(0x26FFFFFF),
  ),
  // 4 — Mavi-mor (elektrik)
  _ShareTemplate(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2D5BFF), Color(0xFF8B5CF6)],
    ),
    textColor: Colors.white,
    mutedColor: Color(0xFFE8E4FF),
    brandColor: Color(0xFFFFE066),
    cardBadgeBg: Color(0x33FFFFFF),
  ),
  // 5 — Yeşil
  _ShareTemplate(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF10B981), Color(0xFF047857)],
    ),
    textColor: Colors.white,
    mutedColor: Color(0xFFD1FAE5),
    brandColor: Color(0xFFFF4B55),
    cardBadgeBg: Color(0x33FFFFFF),
  ),
  // 6 — Pembe-mor
  _ShareTemplate(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
    ),
    textColor: Colors.white,
    mutedColor: Color(0xFFFCE7F3),
    brandColor: Color(0xFFFFE066),
    cardBadgeBg: Color(0x33FFFFFF),
  ),
];

class _SocialShareSheet extends StatefulWidget {
  final List<_QuizQuestion> questions;
  final Map<int, int> answers;
  const _SocialShareSheet({required this.questions, required this.answers});

  @override
  State<_SocialShareSheet> createState() => _SocialShareSheetState();
}

class _SocialShareSheetState extends State<_SocialShareSheet> {
  late Future<List<_SocialApp>> _future;
  int _templateIdx = 0;

  late final List<String> _subjects;
  late final List<String> _topics;
  late final int _correctCount;
  late final int _wrongCount;
  late final int _emptyCount;
  int get _total => widget.questions.length;
  int get _pct => _total == 0 ? 0 : (_correctCount * 100 / _total).round();

  @override
  void initState() {
    super.initState();
    _future = _detectInstalledApps();

    final subjOrder = <String>[];
    final topicSet = <String>{};
    final topicOrder = <String>[];
    int c = 0, w = 0, e = 0;
    for (int i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      if (!subjOrder.contains(q.subjectName)) subjOrder.add(q.subjectName);
      if (topicSet.add(q.topic)) topicOrder.add(q.topic);
      final a = widget.answers[i];
      if (a == null) {
        e += 1;
      } else if (a == q.correctIndex) {
        c += 1;
      } else {
        w += 1;
      }
    }
    _subjects = subjOrder;
    _topics = topicOrder;
    _correctCount = c;
    _wrongCount = w;
    _emptyCount = e;
  }

  String get _caption {
    final subj = _subjects.join(' + ');
    final emptyLine = _emptyCount > 0 ? ' · ⬜ $_emptyCount boş' : '';
    return "QuAlsar'da $subj testinde $_correctCount/$_total yaptım — sıra sende! 🎯\n"
        "✅ $_correctCount doğru · ❌ $_wrongCount yanlış$emptyLine · %$_pct başarı\n\n"
        "QuAlsar ile neler yapabilirsin:\n"
        "📸 Sorunun fotoğrafını çek, anında çöz\n"
        "📚 Konu özetleri oluştur\n"
        "🧠 Benzer sorular üret\n"
        "🎯 Kendi mini testini hazırla\n"
        "🎴 Bilgi kartları oluştur\n\n"
        "👉 qualsar.app";
  }

  Future<void> _shareVia(_SocialApp app) async {
    final encoded = Uri.encodeComponent(_caption);
    final url = Uri.parse(app.shareUrl(encoded));
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) throw 'launch failed';
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      await Share.share(_caption);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _caption));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Metin kopyalandı ✓'.tr()),
        backgroundColor: _Palette.ink,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _systemShare() async {
    await Share.share(_caption);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: _Palette.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _Palette.inkMute,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Başarını Paylaş'.tr(),
                style: _serif(size: 22, weight: FontWeight.w600, letterSpacing: -0.02)),
            const SizedBox(height: 4),
            Text('Renk seç, sosyal medyada arkadaşlarına göster.'.tr(),
                style: _sans(size: 12, color: _Palette.inkMute)),
            const SizedBox(height: 18),
            // Önizleme kartı
            Center(
              child: _ShareCardPreview(
                template: _shareTemplates[_templateIdx],
                subjects: _subjects,
                topics: _topics,
                total: _total,
                correct: _correctCount,
                wrong: _wrongCount,
                empty: _emptyCount,
                pct: _pct,
              ),
            ),
            const SizedBox(height: 18),
            // 6 renk seçici
            _TemplatePickerRow(
              templates: _shareTemplates,
              selected: _templateIdx,
              onSelect: (i) => setState(() => _templateIdx = i),
            ),
            const SizedBox(height: 22),
            Text('TELEFONDA YÜKLÜ UYGULAMALAR'.tr(),
                style: _sans(size: 11, weight: FontWeight.w700, color: _Palette.inkMute, letterSpacing: 0.08)),
            const SizedBox(height: 12),
            FutureBuilder<List<_SocialApp>>(
              future: _future,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return SizedBox(
                    height: 96,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation(_Palette.brand),
                        ),
                      ),
                    ),
                  );
                }
                final installed = snap.data ?? [];
                if (installed.isEmpty) {
                  return _emptyDetectionFallback();
                }
                return SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: installed.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _appTile(installed[i]),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: _Palette.line),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _secondaryTile(
                    Icons.copy_rounded,
                    _Palette.accent,
                    'Metni kopyala',
                    _copyLink,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _secondaryTile(
                    Icons.ios_share_rounded,
                    _Palette.ink,
                    'Diğer…',
                    _systemShare,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _appTile(_SocialApp app) {
    return GestureDetector(
      onTap: () => _shareVia(app),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: app.gradient == null ? app.color : null,
                gradient: app.gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: app.color.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: app.logo,
            ),
            const SizedBox(height: 6),
            Text(
              app.name,
              style: _sans(size: 11, weight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyDetectionFallback() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Palette.line),
      ),
      child: Row(
        children: [
          Text('📱'.tr(), style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yüklü sosyal medya hesabı bulunamadı'.tr(),
                    style: _sans(size: 13, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Sistem paylaşım menüsünü açmayı deneyebilirsin.'.tr(),
                    style: _sans(size: 11, color: _Palette.inkMute)),
              ],
            ),
          ),
          TextButton(
            onPressed: _systemShare,
            child: Text('Aç'.tr(), style: _sans(size: 13, weight: FontWeight.w700, color: _Palette.brand)),
          ),
        ],
      ),
    );
  }

  Widget _secondaryTile(IconData icon, Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Palette.line),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: _sans(size: 13, weight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════════
//  ŞABLON SEÇİCİ + ÖNİZLEME KARTI
// ═══════════════════════════════════════════════════════════════════════════════
class _TemplatePickerRow extends StatelessWidget {
  final List<_ShareTemplate> templates;
  final int selected;
  final ValueChanged<int> onSelect;
  const _TemplatePickerRow({
    required this.templates,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(templates.length, (i) {
        final active = i == selected;
        final t = templates[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 36,
              height: 56,
              decoration: BoxDecoration(
                gradient: t.gradient,
                color: t.solidColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? _Palette.ink : _Palette.line,
                  width: active ? 2.5 : 1,
                ),
                boxShadow: active
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 3))]
                    : null,
              ),
              transform: active ? (Matrix4.identity()..scaleByDouble(1.08, 1.08, 1.0, 1.0)) : Matrix4.identity(),
              transformAlignment: Alignment.center,
            ),
          ),
        );
      }),
    );
  }
}

class _ShareCardPreview extends StatelessWidget {
  final _ShareTemplate template;
  final List<String> subjects;
  final List<String> topics;
  final int total;
  final int correct;
  final int wrong;
  final int empty;
  final int pct;
  const _ShareCardPreview({
    required this.template,
    required this.subjects,
    required this.topics,
    required this.total,
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    final subjText = subjects.isEmpty ? '—' : subjects.join(' + ');
    final topicText = topics.isEmpty
        ? '—'
        : (topics.length <= 3 ? topics.join(' · ') : '${topics.take(3).join(' · ')} +${topics.length - 3}');

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = math.min(340.0, math.max(280.0, screenWidth - 60));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: cardWidth,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: template.gradient,
        color: template.solidColor,
        borderRadius: BorderRadius.circular(22),
        border: template.solidColor == Colors.white ? Border.all(color: _Palette.line) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // QuAlsar — kartın tam ortasında, al kırmızı
          Center(
            child: Text(
              'QuAlsar',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _serif(
                size: 26,
                weight: FontWeight.w800,
                color: template.brandColor,
                letterSpacing: -0.03,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Row: DERS (sol) · KONU (sağ)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DERS', style: _miniLabel(template)),
                    const SizedBox(height: 2),
                    Text(
                      subjText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: _sans(
                        size: 14,
                        weight: FontWeight.w700,
                        color: template.textColor,
                        letterSpacing: -0.01,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('KONU', style: _miniLabel(template)),
                    const SizedBox(height: 2),
                    Text(
                      topicText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: _sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: template.textColor.withValues(alpha: 0.92),
                        letterSpacing: -0.01,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row: SORU SAYISI (sol) · çerçeveli sayaç (sağ)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SORU SAYISI', style: _miniLabel(template)),
                    const SizedBox(height: 2),
                    Text(
                      'Toplam $total soru',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(
                        size: 13,
                        weight: FontWeight.w700,
                        color: template.textColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: template.mutedColor.withValues(alpha: 0.55),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _countInline(template, '✅', correct),
                    _countDivider(template),
                    _countInline(template, '❌', wrong),
                    if (empty > 0) ...[
                      _countDivider(template),
                      _countInline(template, '⬜', empty),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Başarı oranı — büyük
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: template.cardBadgeBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BAŞARI ORANI'.tr(), style: _miniLabel(template)),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RichText(
                    text: TextSpan(
                      style: _serif(
                        size: 40,
                        weight: FontWeight.w800,
                        color: template.textColor,
                        letterSpacing: -0.05,
                        height: 1.0,
                      ),
                      children: [
                        TextSpan(text: '%$pct'),
                        TextSpan(
                          text: '  $correct/$total',
                          style: _serif(
                            size: 15,
                            weight: FontWeight.w600,
                            color: template.mutedColor,
                            letterSpacing: -0.02,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Kullanıcı ismi (sol hizalı)
          Row(
            children: [
              Icon(Icons.account_circle_rounded, size: 14, color: template.mutedColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '@$_currentUsername',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(
                    size: 12,
                    weight: FontWeight.w600,
                    color: template.mutedColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // "QuAlsar ile neler yapabilirsin?" — al kırmızı
          Text(
            'QuAlsar ile neler yapabilirsin?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sans(
              size: 12,
              weight: FontWeight.w700,
              color: template.brandColor,
              letterSpacing: -0.01,
            ),
          ),
          const SizedBox(height: 6),

          // Bilgi kartları (pill şeklinde yan yana)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _infoPill(template, '📸', 'Soru fotoğrafı çek'),
              _infoPill(template, '📚', 'Konu özeti oluştur'),
              _infoPill(template, '🧠', 'Benzer sorular üret'),
              _infoPill(template, '🎯', 'Mini test hazırla'),
              _infoPill(template, '🎴', 'Bilgi kartları oluştur'),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle _miniLabel(_ShareTemplate t) => _sans(
        size: 9,
        weight: FontWeight.w700,
        color: t.mutedColor,
        letterSpacing: 0.08,
      );

  Widget _countInline(_ShareTemplate t, String emoji, int value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 3),
        Text(
          '$value',
          style: _sans(
            size: 13,
            weight: FontWeight.w700,
            color: t.textColor,
          ),
        ),
      ],
    );
  }

  Widget _countDivider(_ShareTemplate t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '·',
        style: _sans(size: 13, weight: FontWeight.w700, color: t.mutedColor),
      ),
    );
  }

  Widget _infoPill(_ShareTemplate t, String emoji, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: t.cardBadgeBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sans(
              size: 10,
              weight: FontWeight.w600,
              color: t.textColor,
              letterSpacing: -0.01,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SHARED BUTTONS
// ═══════════════════════════════════════════════════════════════════════════════
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool brand;
  final IconData? trailingIcon;
  const _PrimaryButton({required this.label, this.onTap, this.brand = false, this.trailingIcon});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: !enabled ? _Palette.line : (brand ? _Palette.brand : _Palette.ink),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: _sans(
                size: 15,
                weight: FontWeight.w600,
                color: !enabled ? _Palette.inkMute : Colors.white,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, size: 16, color: !enabled ? _Palette.inkMute : Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: _Palette.line, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(label, style: _sans(size: 14, weight: FontWeight.w600)),
      ),
    );
  }
}
