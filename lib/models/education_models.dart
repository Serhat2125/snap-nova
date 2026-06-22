// ═══════════════════════════════════════════════════════════════════════════
//  Education Data Models — Veli/Öğretmen/Sınıf akışı için kullanılan
//  serileştirilebilir veri yapıları.
//
//  Tasarım kararı: freezed yerine standart Dart class — daha az dış bağımlılık
//  ve mevcut proje stiliyle (toJson/fromJson) tutarlı.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';

// ─── StudentActivityModel ──────────────────────────────────────────────────
//
// Bir öğrencinin (çocuğun) günlük / haftalık etkinlik özeti.
// Ebeveyn Dashboard grafikleri ve AI içgörü motoru bunu okur.
//
// Firestore yolu:
//   users/{childUid}/activity/{yyyyMMdd}
// ───────────────────────────────────────────────────────────────────────────
class StudentActivityModel {
  /// ISO tarih anahtarı (yyyy-MM-dd) — günlük rollup için key.
  final String dateKey;
  /// Bugün toplam odak süresi (saniye).
  final int focusSeconds;
  /// Ders bazlı odak dağılımı (ders adı → saniye).
  final Map<String, int> subjectDurations;
  /// Bugün üretilen AI özetlerinin sayısı.
  final int summariesCreated;
  /// Bugün tarattığı (fotoğrafladığı) soru sayısı.
  final int photoQuestionsSolved;
  /// Bugün çözdüğü test sayısı.
  final int testsSolved;
  /// Bugünkü test cevap dağılımı.
  final int correctAnswers;
  final int wrongAnswers;
  final int blankAnswers;
  /// Ders bazlı test doğru/yanlış birikimi (ebeveyn paneli ders tablosu).
  final Map<String, int> subjectCorrect;
  final Map<String, int> subjectWrong;
  /// Bugünkü ortalama başarı yüzdesi (0-100). Test yapılmadıysa null.
  final double? successPercent;

  const StudentActivityModel({
    required this.dateKey,
    this.focusSeconds = 0,
    this.subjectDurations = const {},
    this.summariesCreated = 0,
    this.photoQuestionsSolved = 0,
    this.testsSolved = 0,
    this.correctAnswers = 0,
    this.wrongAnswers = 0,
    this.blankAnswers = 0,
    this.subjectCorrect = const {},
    this.subjectWrong = const {},
    this.successPercent,
  });

  /// Toplam cevaplanmış soru (boş olmayan).
  int get totalAnswered => correctAnswers + wrongAnswers;
  int get totalAttempted => correctAnswers + wrongAnswers + blankAnswers;

  /// Odak süresinin dakika cinsi (UI gösterimi için).
  int get focusMinutes => focusSeconds ~/ 60;

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'focusSeconds': focusSeconds,
        'subjectDurations': subjectDurations,
        'summariesCreated': summariesCreated,
        'photoQuestionsSolved': photoQuestionsSolved,
        'testsSolved': testsSolved,
        'correctAnswers': correctAnswers,
        'wrongAnswers': wrongAnswers,
        'blankAnswers': blankAnswers,
        if (successPercent != null) 'successPercent': successPercent,
      };

  factory StudentActivityModel.fromJson(Map<String, dynamic> j) {
    return StudentActivityModel(
      dateKey: (j['dateKey'] ?? '').toString(),
      focusSeconds: (j['focusSeconds'] ?? 0) as int,
      subjectDurations: (j['subjectDurations'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v ?? 0) as int)) ??
          const {},
      summariesCreated: (j['summariesCreated'] ?? 0) as int,
      photoQuestionsSolved: (j['photoQuestionsSolved'] ?? 0) as int,
      testsSolved: (j['testsSolved'] ?? 0) as int,
      correctAnswers: (j['correctAnswers'] ?? 0) as int,
      wrongAnswers: (j['wrongAnswers'] ?? 0) as int,
      blankAnswers: (j['blankAnswers'] ?? 0) as int,
      subjectCorrect: (j['subjectCorrect'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v ?? 0) as int)) ??
          const {},
      subjectWrong: (j['subjectWrong'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v ?? 0) as int)) ??
          const {},
      successPercent: (j['successPercent'] as num?)?.toDouble(),
    );
  }

  /// Boş günler için sentinel.
  factory StudentActivityModel.empty(String dateKey) =>
      StudentActivityModel(dateKey: dateKey);
}

// ─── HomeworkModel ─────────────────────────────────────────────────────────
//
// Öğretmenin oluşturup sınıfa dağıttığı ödev.
// AiHomeworkGeneratorWidget bunu üretir, ClassService.shareToClass'la kayıt.
//
// Firestore yolu:
//   classes/{classId}/homeworks/{homeworkId}
// ───────────────────────────────────────────────────────────────────────────
enum HomeworkQuestionType {
  multipleChoice, // Çoktan seçmeli
  trueFalse,      // Doğru / yanlış
  fillBlank,      // Boşluk doldurma
  openEnded,      // Açık uçlu
}

extension HomeworkQuestionTypeX on HomeworkQuestionType {
  String get key {
    switch (this) {
      case HomeworkQuestionType.multipleChoice: return 'mc';
      case HomeworkQuestionType.trueFalse:      return 'tf';
      case HomeworkQuestionType.fillBlank:      return 'fill';
      case HomeworkQuestionType.openEnded:      return 'open';
    }
  }

  String get tr {
    switch (this) {
      case HomeworkQuestionType.multipleChoice: return 'Çoktan Seçmeli';
      case HomeworkQuestionType.trueFalse:      return 'Doğru / Yanlış';
      case HomeworkQuestionType.fillBlank:      return 'Boşluk Doldurma';
      case HomeworkQuestionType.openEnded:      return 'Açık Uçlu';
    }
  }

  String get emoji {
    switch (this) {
      case HomeworkQuestionType.multipleChoice: return '🔘';
      case HomeworkQuestionType.trueFalse:      return '✅';
      case HomeworkQuestionType.fillBlank:      return '✏️';
      case HomeworkQuestionType.openEnded:      return '📝';
    }
  }

  static HomeworkQuestionType fromKey(String? k) {
    switch (k) {
      case 'tf':   return HomeworkQuestionType.trueFalse;
      case 'fill': return HomeworkQuestionType.fillBlank;
      case 'open': return HomeworkQuestionType.openEnded;
      case 'mc':
      default:     return HomeworkQuestionType.multipleChoice;
    }
  }
}

class HomeworkModel {
  final String id;
  final String classId;
  final String teacherUid;
  final String title;
  final String subject;       // Ders adı
  final String topic;         // Konu
  final String level;         // İlkokul/Ortaokul/Lise
  final List<HomeworkQuestionType> types;
  final int questionCount;
  final DateTime assignedAt;
  final DateTime dueAt;
  /// AI tarafından üretilen ödev içeriği — soruları tutar.
  /// Şema: [{q: '...', type: 'mc', choices: [...], answer: '...'}, ...]
  final List<Map<String, dynamic>> questions;
  /// Hatırlatıcı atıldı mı (auto-reminder idempotency için).
  final bool reminderSent;

  const HomeworkModel({
    required this.id,
    required this.classId,
    required this.teacherUid,
    required this.title,
    required this.subject,
    required this.topic,
    required this.level,
    required this.types,
    required this.questionCount,
    required this.assignedAt,
    required this.dueAt,
    this.questions = const [],
    this.reminderSent = false,
  });

  bool get isOverdue => DateTime.now().isAfter(dueAt);
  Duration get timeRemaining => dueAt.difference(DateTime.now());

  Map<String, dynamic> toJson() => {
        'classId': classId,
        'teacherUid': teacherUid,
        'title': title,
        'subject': subject,
        'topic': topic,
        'level': level,
        'types': types.map((t) => t.key).toList(),
        'questionCount': questionCount,
        'assignedAt': Timestamp.fromDate(assignedAt),
        'dueAt': Timestamp.fromDate(dueAt),
        'questions': questions,
        'reminderSent': reminderSent,
      };

  factory HomeworkModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    DateTime assigned = DateTime.now();
    DateTime due = DateTime.now().add(const Duration(days: 7));
    if (m['assignedAt'] is Timestamp) assigned = (m['assignedAt'] as Timestamp).toDate();
    if (m['dueAt'] is Timestamp) due = (m['dueAt'] as Timestamp).toDate();
    return HomeworkModel(
      id: d.id,
      classId: (m['classId'] ?? '').toString(),
      teacherUid: (m['teacherUid'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      subject: (m['subject'] ?? '').toString(),
      topic: (m['topic'] ?? '').toString(),
      level: (m['level'] ?? '').toString(),
      types: ((m['types'] as List?) ?? const [])
          .map((t) => HomeworkQuestionTypeX.fromKey(t?.toString()))
          .toList(),
      questionCount: (m['questionCount'] ?? 0) as int,
      assignedAt: assigned,
      dueAt: due,
      questions: ((m['questions'] as List?) ?? const [])
          .whereType<Map>()
          .map((q) => Map<String, dynamic>.from(q))
          .toList(),
      reminderSent: (m['reminderSent'] ?? false) == true,
    );
  }
}

// ─── HomeworkSubmissionModel ──────────────────────────────────────────────
//
// Öğrencinin bir ödevi tamamlama durumu.
// Firestore yolu:
//   classes/{classId}/homeworks/{hwId}/submissions/{studentUid}
// ──────────────────────────────────────────────────────────────────────────
/// Öğrencinin tek bir ödev sorusuna verdiği cevap (öğretmen değerlendirmesi
/// için saklanır). Açık uçlu sorularda `isCorrect == null` ise öğretmenin
/// manuel puanlamasını bekliyor demektir.
class SubmissionAnswer {
  final int index;
  final String type;          // mc | tf | fill | open
  final String questionText;
  final String studentAnswer;
  final bool? isCorrect;       // null = öğretmen değerlendirmesi bekliyor

  const SubmissionAnswer({
    required this.index,
    required this.type,
    required this.questionText,
    required this.studentAnswer,
    this.isCorrect,
  });

  bool get needsReview => isCorrect == null;

  Map<String, dynamic> toJson() => {
        'index': index,
        'type': type,
        'q': questionText,
        'studentAnswer': studentAnswer,
        'isCorrect': isCorrect,
      };

  factory SubmissionAnswer.fromMap(Map<String, dynamic> m) => SubmissionAnswer(
        index: (m['index'] ?? 0) as int,
        type: (m['type'] ?? 'mc').toString(),
        questionText: (m['q'] ?? '').toString(),
        studentAnswer: (m['studentAnswer'] ?? '').toString(),
        isCorrect: m['isCorrect'] is bool ? m['isCorrect'] as bool : null,
      );
}

class HomeworkSubmissionModel {
  final String studentUid;
  final String studentUsername;
  final String studentDisplayName;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final int? correct;
  final int? wrong;
  final double? scorePercent;
  final String status; // 'pending' | 'in_progress' | 'submitted' | 'late'
  /// Öğrencinin soru-soru cevapları (öğretmen puanlaması için saklanır).
  final List<SubmissionAnswer> answers;
  /// Ödevi çözerken ekran önündeyken geçen aktif süre (ms).
  final int? activeMs;
  /// Ödev açıkken uygulamadan çıkıp/arka planda geçen pasif süre (ms).
  final int? passiveMs;
  /// AI'nin bu teslim için ürettiği kısa performans yorumu (cache).
  final String? aiComment;

  const HomeworkSubmissionModel({
    required this.studentUid,
    required this.studentUsername,
    required this.studentDisplayName,
    this.startedAt,
    this.submittedAt,
    this.correct,
    this.wrong,
    this.scorePercent,
    this.status = 'pending',
    this.answers = const [],
    this.activeMs,
    this.passiveMs,
    this.aiComment,
  });

  bool get isSubmitted => status == 'submitted' || status == 'late';
  bool get isPending => status == 'pending';

  /// Ekran önünde geçen aktif süre (yoksa null).
  Duration? get activeTime =>
      activeMs == null ? null : Duration(milliseconds: activeMs!);

  /// Arka planda/dışarıda geçen pasif süre (yoksa null).
  Duration? get passiveTime =>
      passiveMs == null ? null : Duration(milliseconds: passiveMs!);

  /// Açık uçlu cevaplardan en az biri öğretmen puanlaması bekliyor mu?
  bool get needsReview =>
      isSubmitted && answers.any((a) => a.needsReview);

  /// Öğretmen puanlaması bekleyen cevaplar.
  List<SubmissionAnswer> get pendingAnswers =>
      answers.where((a) => a.needsReview).toList();

  /// Öğrencinin ödevi çözmek için harcadığı süre (başlangıç → teslim).
  /// startedAt veya submittedAt yoksa null döner ("salladı" tespiti için
  /// öğretmen panelinde gösterilir).
  Duration? get solveDuration {
    if (startedAt == null || submittedAt == null) return null;
    final d = submittedAt!.difference(startedAt!);
    return d.isNegative ? null : d;
  }

  Map<String, dynamic> toJson() => {
        'studentUid': studentUid,
        'studentUsername': studentUsername,
        'studentDisplayName': studentDisplayName,
        if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt!),
        if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
        if (correct != null) 'correct': correct,
        if (wrong != null) 'wrong': wrong,
        if (scorePercent != null) 'scorePercent': scorePercent,
        'status': status,
        if (answers.isNotEmpty)
          'answers': answers.map((a) => a.toJson()).toList(),
        if (activeMs != null) 'activeMs': activeMs,
        if (passiveMs != null) 'passiveMs': passiveMs,
        if (aiComment != null) 'aiComment': aiComment,
      };

  factory HomeworkSubmissionModel.fromMap(Map<String, dynamic> m) {
    DateTime? started;
    if (m['startedAt'] is Timestamp) {
      started = (m['startedAt'] as Timestamp).toDate();
    }
    DateTime? when;
    if (m['submittedAt'] is Timestamp) {
      when = (m['submittedAt'] as Timestamp).toDate();
    }
    return HomeworkSubmissionModel(
      studentUid: (m['studentUid'] ?? '').toString(),
      studentUsername: (m['studentUsername'] ?? '').toString(),
      studentDisplayName: (m['studentDisplayName'] ?? '').toString(),
      startedAt: started,
      submittedAt: when,
      correct: (m['correct'] as num?)?.toInt(),
      wrong: (m['wrong'] as num?)?.toInt(),
      scorePercent: (m['scorePercent'] as num?)?.toDouble(),
      status: (m['status'] ?? 'pending').toString(),
      answers: ((m['answers'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SubmissionAnswer.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      activeMs: (m['activeMs'] as num?)?.toInt(),
      passiveMs: (m['passiveMs'] as num?)?.toInt(),
      aiComment: (m['aiComment'] as String?),
    );
  }
}

// ─── TeacherProfileModel ──────────────────────────────────────────────────
//
// Öğretmenin seçili branş + eğitim seviyeleri + okul.
// Firestore yolu:
//   users/{teacherUid}/teacher_profile/main
// ──────────────────────────────────────────────────────────────────────────
class TeacherProfileModel {
  final String displayName;
  final String schoolName;
  /// Tek branş veya çoklu branş — birden fazla ders veren öğretmen için.
  final List<String> subjects;
  /// Verdiği seviyeler: 'İlkokul', 'Ortaokul', 'Lise', 'Üniversite'.
  final List<String> levels;
  /// Müfredat anahtarı (locale + ülke bazlı):
  /// 'tr-MEB' (Türkiye), 'us-CCSS' (US Common Core), 'gb-NC' (UK), vb.
  final String curriculumKey;
  /// Hangi ülke koduna göre içerik seçileceği (locale autodetect).
  final String countryCode;

  const TeacherProfileModel({
    required this.displayName,
    required this.schoolName,
    required this.subjects,
    required this.levels,
    required this.curriculumKey,
    required this.countryCode,
  });

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'schoolName': schoolName,
        'subjects': subjects,
        'levels': levels,
        'curriculumKey': curriculumKey,
        'countryCode': countryCode,
      };

  factory TeacherProfileModel.fromJson(Map<String, dynamic> j) {
    return TeacherProfileModel(
      displayName: (j['displayName'] ?? '').toString(),
      schoolName: (j['schoolName'] ?? '').toString(),
      subjects: ((j['subjects'] as List?) ?? const [])
          .map((s) => s.toString()).toList(),
      levels: ((j['levels'] as List?) ?? const [])
          .map((s) => s.toString()).toList(),
      curriculumKey: (j['curriculumKey'] ?? 'tr-MEB').toString(),
      countryCode: (j['countryCode'] ?? 'TR').toString(),
    );
  }
}

// ─── CurriculumModel ──────────────────────────────────────────────────────
//
// Öğretmen ödev üretirken hangi kazanıma yönelik soru üreteceğini seçer.
// CurriculumService bunu locale + level + subject'ye göre döner.
// ──────────────────────────────────────────────────────────────────────────
class CurriculumStandard {
  final String key;         // Müfredat anahtarı: 'tr-MEB', 'us-CCSS', vb.
  final String label;       // "MEB (Türkiye)", "Common Core (US)"
  final String countryCode; // ISO ülke kodu

  const CurriculumStandard({
    required this.key,
    required this.label,
    required this.countryCode,
  });
}

class CurriculumTopic {
  final String id;
  final String level;       // 'İlkokul', 'Ortaokul', 'Lise'
  final String grade;       // '5. sınıf', 'Lise 11', vb.
  final String subject;     // 'Matematik', 'Fizik'
  final String topic;       // 'Üslü Sayılar'
  final List<String> outcomes; // Kazanımlar: ["M.5.1.1.1. ...", ...]

  const CurriculumTopic({
    required this.id,
    required this.level,
    required this.grade,
    required this.subject,
    required this.topic,
    required this.outcomes,
  });
}
