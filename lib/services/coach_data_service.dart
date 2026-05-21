// ═══════════════════════════════════════════════════════════════════════════════
//  CoachDataService — AI Koç için kullanıcı verisi agregasyonu.
//
//  Üç veri kaynağından zayıf konu sinyallerini toplar:
//
//  1) Konu Özetleri (library_subjects_v2)
//     • Hangi ders/konuda kaç özet üretmiş (çalışma yoğunluğu)
//     • Çok çalışılan ≠ iyi öğrenilen → yalın sinyal olarak "ilgi" olur
//
//  2) Sınav Soruları (library_subjects_questions_v2)
//     • Test denemeleri içindeki cevaplar (_TestAttempt.answers)
//     • Her sorunun doğru cevabı (q.ans) ile karşılaştır → DOĞRU/YANLIŞ oranı
//     • Tamamlanmış testler değerlendirilir; boş bırakılan sorular "wrong" sayılır
//
//  3) Fotoğraf Çözümleri (SolutionsStorage.loadAll)
//     • Kullanıcının kameradan attığı sorular — ders/konu istatistiği
//     • aiTitle "Ders - Konu" formatından parse edilir
//
//  Zayıf konu skoru hesabı:
//     • errorRate = yanlış / toplamCevap  (sadece tests verisi)
//     • testler yoksa fallback: çok çalışıldı + az favori = zorlu
//     • attempts (örnek sayısı) confidence göstergesi; <3 ise düşük güvenle
//       gösterilir (UI'da bunu rapor etmek opsiyonel).
//
//  Tüm yöntemler SharedPreferences yerel okur — Firestore çağrısı yok.
//  Performans: 200ms altı (lokal JSON parse).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'solutions_storage.dart';

class CoachWeakTopic {
  final String subject;
  final String topic;
  /// 0.0 (mükemmel) – 1.0 (tamamı yanlış). Karma kaynaktan hesaplanır.
  final double errorRate;
  /// Toplam değerlendirilen örnek (test sorusu + foto çözüm + özet).
  final int attempts;
  /// Doğru cevap sayısı (sadece test verisinde).
  final int correctCount;
  /// Yanlış cevap sayısı (sadece test verisinde).
  final int wrongCount;
  /// Bu konuda üretilen özet sayısı.
  final int summaryCount;
  /// Bu konuda kameradan çözülen soru sayısı.
  final int photoCount;
  /// errorRate'in güven seviyesi (0–1). Düşükse yetersiz örnek var.
  double get confidence {
    // 5+ örnek → tam güven; 1 örnek → düşük
    return (attempts / 5.0).clamp(0.0, 1.0);
  }

  const CoachWeakTopic({
    required this.subject,
    required this.topic,
    required this.errorRate,
    required this.attempts,
    required this.correctCount,
    required this.wrongCount,
    required this.summaryCount,
    required this.photoCount,
  });

  Map<String, dynamic> toCompactMap() => {
        'subject': subject,
        'topic': topic,
        'errorRate': errorRate,
        'attempts': attempts,
        'correct': correctCount,
        'wrong': wrongCount,
        'summaries': summaryCount,
        'photos': photoCount,
      };
}

class CoachSnapshot {
  final List<CoachWeakTopic> weakTopics;
  /// Genel doğruluk oranı (tüm tests genelinde).
  final double overallAccuracy;
  /// Toplam test sorusu cevaplanmış.
  final int totalTestAnswers;
  /// Toplam test sorusu doğru.
  final int totalTestCorrect;
  /// Toplam özet üretilmiş.
  final int totalSummaries;
  /// Toplam fotoğraf çözüm.
  final int totalPhotos;
  /// En çok çalışılan 3 ders.
  final List<String> topSubjects;

  const CoachSnapshot({
    required this.weakTopics,
    required this.overallAccuracy,
    required this.totalTestAnswers,
    required this.totalTestCorrect,
    required this.totalSummaries,
    required this.totalPhotos,
    required this.topSubjects,
  });

  static const empty = CoachSnapshot(
    weakTopics: [],
    overallAccuracy: 0,
    totalTestAnswers: 0,
    totalTestCorrect: 0,
    totalSummaries: 0,
    totalPhotos: 0,
    topSubjects: [],
  );
}

class CoachDataService {
  CoachDataService._();

  static const _kSummarySubjects = 'library_subjects_v2';
  static const _kQuestionSubjects = 'library_subjects_questions_v2';

  /// Tüm kaynakları okuyup agrege CoachSnapshot döner.
  /// 0 fotoğraf + 0 özet + 0 test → empty snapshot.
  static Future<CoachSnapshot> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Paralel topla: 3 lokal kaynak
      final summarySubjects =
          _decodeSubjects(prefs.getStringList(_kSummarySubjects) ?? const []);
      final questionSubjects =
          _decodeSubjects(prefs.getStringList(_kQuestionSubjects) ?? const []);
      final solutions = await SolutionsStorage.loadAll();

      // (subject, topic) → accumulator
      final acc = <String, _Acc>{};
      void touch(String subject, String topic) {
        if (subject.isEmpty) subject = 'Genel';
        if (topic.isEmpty) topic = 'Genel';
        final key = '$subject||$topic';
        acc.putIfAbsent(key, () => _Acc(subject, topic));
      }

      // 1) ÖZETLER — her özet 1 "çalışma" sinyali
      for (final s in summarySubjects) {
        for (final summ in s.summaries) {
          touch(s.name, summ.topic);
          acc['${s.name}||${summ.topic}']!.summaryCount++;
        }
      }

      // 2) SINAV SORULARI — tamamlanmış testleri parse et, doğru/yanlış say
      for (final subject in questionSubjects) {
        for (final summ in subject.summaries) {
          for (final attempt in summ.tests) {
            if (!attempt.completed) continue;
            final questions = _parseQuestions(attempt.content);
            if (questions.isEmpty) continue;
            touch(subject.name, summ.topic);
            final a = acc['${subject.name}||${summ.topic}']!;
            for (int i = 0; i < questions.length; i++) {
              final userAns = attempt.answers[i];
              final correct = questions[i].correctAnswer;
              if (userAns == null || userAns.isEmpty) {
                a.wrong++; // boş bırakılan = yanlış
              } else if (userAns.trim().toUpperCase() == correct) {
                a.correct++;
              } else {
                a.wrong++;
              }
            }
          }
        }
      }

      // 3) FOTOĞRAF ÇÖZÜMLERİ — aiTitle "Ders - Konu"
      for (final r in solutions) {
        String subject = r.subject.isEmpty ? 'Genel' : r.subject;
        String topic = 'Genel';
        if (r.aiTitle.contains('-')) {
          final parts = r.aiTitle.split('-');
          if (parts.length >= 2) {
            if (parts[0].trim().isNotEmpty) subject = parts[0].trim();
            topic = parts.sublist(1).join('-').trim();
          }
        } else if (r.aiTitle.isNotEmpty) {
          topic = r.aiTitle;
        }
        touch(subject, topic);
        final a = acc['$subject||$topic']!;
        a.photoCount++;
        // Favorisi olmayan çözüm = kullanıcı zor buldu sinyali (zayıf veri)
        if (!r.isFavorite) a.softWrong++;
      }

      // Skor hesabı + sıralama
      final list = acc.values.map((a) {
        final total = a.correct + a.wrong;
        double errorRate;
        if (total > 0) {
          // GERÇEK test verisi varsa onu kullan
          errorRate = a.wrong / total;
        } else if (a.photoCount > 0) {
          // Sadece fotoğraf çözümü var — soft sinyal
          errorRate = (a.softWrong / a.photoCount).clamp(0.0, 1.0);
        } else if (a.summaryCount > 2) {
          // Çok çalışılmış ama hiç test yok → orta belirsizlik
          errorRate = 0.5;
        } else {
          errorRate = 0.0;
        }
        final totalAttempts =
            total + a.photoCount + (a.summaryCount > 0 ? 1 : 0);
        return CoachWeakTopic(
          subject: a.subject,
          topic: a.topic,
          errorRate: errorRate.clamp(0.0, 1.0),
          attempts: totalAttempts,
          correctCount: a.correct,
          wrongCount: a.wrong,
          summaryCount: a.summaryCount,
          photoCount: a.photoCount,
        );
      }).toList();

      // En zayıftan (errorRate * confidence) sırala
      list.sort((a, b) {
        final sa = a.errorRate * a.confidence;
        final sb = b.errorRate * b.confidence;
        return sb.compareTo(sa);
      });

      // Genel istatistik
      int totalCorrect = 0;
      int totalAnswers = 0;
      final subjectCount = <String, int>{};
      int totalSummaries = 0;
      int totalPhotos = 0;
      for (final a in acc.values) {
        totalCorrect += a.correct;
        totalAnswers += a.correct + a.wrong;
        totalSummaries += a.summaryCount;
        totalPhotos += a.photoCount;
        subjectCount[a.subject] =
            (subjectCount[a.subject] ?? 0) + a.correct + a.wrong + a.photoCount;
      }
      final topSubjects = subjectCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return CoachSnapshot(
        weakTopics: list,
        overallAccuracy:
            totalAnswers == 0 ? 0 : totalCorrect / totalAnswers,
        totalTestAnswers: totalAnswers,
        totalTestCorrect: totalCorrect,
        totalSummaries: totalSummaries,
        totalPhotos: totalPhotos,
        topSubjects: topSubjects.take(3).map((e) => e.key).toList(),
      );
    } catch (e) {
      debugPrint('[CoachData] build hata: $e');
      return CoachSnapshot.empty;
    }
  }

  // ── Yardımcı parserlar ────────────────────────────────────────────────────

  /// `library_subjects_v2` veya `library_subjects_questions_v2` listesini
  /// hafifletilmiş _LibSubject objesine çevirir (yalnız ad + özetler + testler).
  static List<_LibSubject> _decodeSubjects(List<String> raw) {
    final out = <_LibSubject>[];
    for (final s in raw) {
      try {
        final j = jsonDecode(s);
        if (j is! Map) continue;
        final name = (j['name'] ?? '').toString();
        final summariesRaw = (j['summaries'] as List?) ?? const [];
        final summaries = <_LibSummary>[];
        for (final ent in summariesRaw) {
          if (ent is! Map) continue;
          final topic = (ent['topic'] ?? '').toString();
          final testsRaw = (ent['tests'] as List?) ?? const [];
          final tests = <_LibAttempt>[];
          for (final t in testsRaw) {
            if (t is! Map) continue;
            final completed = (t['completed'] as bool?) ?? false;
            final content = (t['content'] ?? '').toString();
            final rawAns = (t['answers'] as Map?) ?? const {};
            final answers = <int, String?>{};
            rawAns.forEach((k, v) {
              final key = int.tryParse(k.toString());
              if (key != null) answers[key] = v?.toString();
            });
            tests.add(_LibAttempt(
              completed: completed,
              content: content,
              answers: answers,
            ));
          }
          summaries.add(_LibSummary(topic: topic, tests: tests));
        }
        out.add(_LibSubject(name: name, summaries: summaries));
      } catch (_) {/* bozuk kayıt skip */}
    }
    return out;
  }

  /// `_TestAttempt.content` (JSON array string) → soru listesi.
  /// Sadece doğru cevabı çıkartmak için yeter — opts/hint/sol yok sayılır.
  static List<_QInfo> _parseQuestions(String content) {
    try {
      var s = content.trim();
      if (s.startsWith('```')) {
        final firstNl = s.indexOf('\n');
        if (firstNl > -1) s = s.substring(firstNl + 1);
        final last = s.lastIndexOf('```');
        if (last > -1) s = s.substring(0, last);
      }
      final start = s.indexOf('[');
      final end = s.lastIndexOf(']');
      if (start >= 0 && end > start) s = s.substring(start, end + 1);
      final decoded = jsonDecode(s);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => _QInfo(
                correctAnswer:
                    (e['ans'] ?? '').toString().trim().toUpperCase(),
              ))
          .where((q) => q.correctAnswer.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

// ─── Hafifletilmiş iç modeller ───────────────────────────────────────────────
class _LibSubject {
  final String name;
  final List<_LibSummary> summaries;
  _LibSubject({required this.name, required this.summaries});
}

class _LibSummary {
  final String topic;
  final List<_LibAttempt> tests;
  _LibSummary({required this.topic, required this.tests});
}

class _LibAttempt {
  final bool completed;
  final String content;
  final Map<int, String?> answers;
  _LibAttempt(
      {required this.completed,
      required this.content,
      required this.answers});
}

class _QInfo {
  final String correctAnswer;
  const _QInfo({required this.correctAnswer});
}

class _Acc {
  final String subject;
  final String topic;
  int correct = 0;
  int wrong = 0;
  int summaryCount = 0;
  int photoCount = 0;
  int softWrong = 0;
  _Acc(this.subject, this.topic);
}
