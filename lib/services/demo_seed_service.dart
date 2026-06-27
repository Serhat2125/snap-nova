// ═══════════════════════════════════════════════════════════════════════════
//  DemoSeedService — Bir sınıfa GERÇEKÇİ demo verisi yazar (öğretmenin analiz
//  ekranını dolu görmesi/önizlemesi için).
//
//  Yazdıkları (hepsi `demo: true` işaretli → tek tıkla temizlenebilir):
//    • students/{demo_*}        → 18 demo öğrenci (TR isim + avatar)
//    • homeworks/{demo_*}       → 3 demo ödev (çoktan seçmeli / açık uçlu / boşluk)
//    • homeworks/*/submissions  → her öğrenci×ödev için gerçekçi teslim
//        (doğru/yanlış/boş, aktif/pasif süre, hazır AI yorumu → AI çağrısı YOK)
//
//  Demo submission'lar `aiComment` alanını önceden doldurur; böylece teslim
//  detayında AI yorumu anında görünür, ücretli AI çağrısı yapılmaz.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class DemoSeedService {
  DemoSeedService._();
  static final _fs = FirebaseFirestore.instance;

  static const _students = [
    ('Ayşe Yılmaz', 'ayse.y', '👧'),
    ('Mehmet Demir', 'mehmet.d', '👦'),
    ('Zeynep Kaya', 'zeynep.k', '🧒'),
    ('Emre Şahin', 'emre.s', '👦'),
    ('Elif Çelik', 'elif.c', '👧'),
    ('Burak Aydın', 'burak.a', '🧑'),
    ('Selin Arslan', 'selin.a', '👧'),
    ('Can Yıldız', 'can.y', '👦'),
    ('Deniz Koç', 'deniz.k', '🧒'),
    ('Ece Öztürk', 'ece.o', '👧'),
    ('Kaan Doğan', 'kaan.d', '👦'),
    ('Merve Aksoy', 'merve.a', '👧'),
    ('Ali Polat', 'ali.p', '🧑'),
    ('Sıla Kurt', 'sila.k', '👧'),
    ('Ozan Erdoğan', 'ozan.e', '👦'),
    ('Naz Bulut', 'naz.b', '🧒'),
    ('Yusuf Acar', 'yusuf.a', '👦'),
    ('Defne Şen', 'defne.s', '👧'),
  ];

  static bool _isDemoClassEmptyName(String s) => s.trim().isEmpty;

  /// Sınıfta zaten demo öğrenci var mı?
  static Future<bool> hasDemo(String classId) async {
    final snap = await _fs
        .collection('classes').doc(classId)
        .collection('students')
        .where('demo', isEqualTo: true)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Sınıfa demo öğrenci + ödev + teslim yazar.
  static Future<bool> seedClass({
    required String classId,
    required String teacherUid,
    required String subject,
    required String level,
  }) async {
    try {
      final rng = math.Random();
      final now = DateTime.now();
      final subj = _isDemoClassEmptyName(subject) ? 'Genel' : subject;

      // ── Demo ödevler (sabit id → tekrar seed'de üzerine yazar) ──────────
      final homeworks = <Map<String, dynamic>>[
        {
          'id': 'demo_hw1',
          'title': '10 Çoktan Seçmeli Soru Ödevi',
          'topic': 'Genel Tekrar',
          'type': 'mc',
          'qc': 10,
          'assignedAt': now.subtract(const Duration(days: 9)),
          'dueAt': now.subtract(const Duration(days: 2)),
        },
        {
          'id': 'demo_hw2',
          'title': '5 Açık Uçlu Soru Ödevi',
          'topic': 'Yorumlama',
          'type': 'open',
          'qc': 5,
          'assignedAt': now.subtract(const Duration(days: 6)),
          'dueAt': now.add(const Duration(days: 1)),
        },
        {
          'id': 'demo_hw3',
          'title': '8 Boşluk Doldurma Ödevi',
          'topic': 'Kavramlar',
          'type': 'fill',
          'qc': 8,
          'assignedAt': now.subtract(const Duration(days: 3)),
          'dueAt': now.add(const Duration(days: 4)),
        },
      ];

      final batch = _fs.batch();
      final classRef = _fs.collection('classes').doc(classId);

      // ── Öğrenciler ──────────────────────────────────────────────────────
      for (int i = 0; i < _students.length; i++) {
        final (name, username, avatar) = _students[i];
        batch.set(
          classRef.collection('students').doc('demo_s$i'),
          {
            'username': username,
            'displayName': name,
            'avatar': avatar,
            'joinedAt': Timestamp.fromDate(
                now.subtract(Duration(days: 12 - i))),
            'demo': true,
          },
          SetOptions(merge: true),
        );
      }

      // ── Ödevler + teslimler ─────────────────────────────────────────────
      for (final hw in homeworks) {
        final hwRef = classRef.collection('homeworks').doc(hw['id'] as String);
        final qc = hw['qc'] as int;
        final type = hw['type'] as String;
        batch.set(hwRef, {
          'classId': classId,
          'teacherUid': teacherUid,
          'title': hw['title'],
          'subject': subj,
          'topic': hw['topic'],
          'level': level,
          'types': [type],
          'questionCount': qc,
          'assignedAt': Timestamp.fromDate(hw['assignedAt'] as DateTime),
          'dueAt': Timestamp.fromDate(hw['dueAt'] as DateTime),
          'questions': _demoQuestions(type, qc),
          'reminderSent': true,
          'demo': true,
        });

        for (int i = 0; i < _students.length; i++) {
          final (name, username, _) = _students[i];
          // Bazı öğrenciler bazı ödevleri teslim etmemiş olsun (gerçekçilik).
          final skip = rng.nextInt(10) < 2; // ~%20 teslim etmemiş
          if (skip) continue;

          final correct = rng.nextInt(qc + 1);
          final remaining = qc - correct;
          final wrong = remaining <= 0 ? 0 : rng.nextInt(remaining + 1);
          final blank = qc - correct - wrong;
          final scored = correct + wrong;
          final score = scored > 0 ? correct * 100.0 / scored : 0.0;

          final activeMs = (4 + rng.nextInt(18)) * 60 * 1000; // 4-21 dk
          final passiveMs = rng.nextInt(11) * 60 * 1000;      // 0-10 dk
          final started = (hw['assignedAt'] as DateTime)
              .add(Duration(hours: 2 + rng.nextInt(40)));
          final submitted =
              started.add(Duration(milliseconds: activeMs + passiveMs));
          final due = hw['dueAt'] as DateTime;
          final status = submitted.isAfter(due) ? 'late' : 'submitted';

          batch.set(
            hwRef.collection('submissions').doc('demo_s$i'),
            {
              'studentUid': 'demo_s$i',
              'studentUsername': username,
              'studentDisplayName': name,
              'correct': correct,
              'wrong': wrong,
              'scorePercent': score,
              'status': status,
              'startedAt': Timestamp.fromDate(started),
              'submittedAt': Timestamp.fromDate(submitted),
              'activeMs': activeMs,
              'passiveMs': passiveMs,
              'answers': _demoAnswers(type, qc, correct, wrong),
              'aiComment': _demoComment(name, score, blank, qc),
              'demo': true,
            },
            SetOptions(merge: true),
          );
        }
      }

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[DemoSeedService] seed fail: $e');
      return false;
    }
  }

  /// Sınıftaki tüm demo verisini siler.
  static Future<bool> clearDemo(String classId) async {
    try {
      final classRef = _fs.collection('classes').doc(classId);
      final batch = _fs.batch();

      // Demo ödevler + altındaki submission'lar
      final hwSnap = await classRef.collection('homeworks')
          .where('demo', isEqualTo: true).get();
      for (final hw in hwSnap.docs) {
        final subs = await hw.reference.collection('submissions').get();
        for (final s in subs.docs) {
          batch.delete(s.reference);
        }
        batch.delete(hw.reference);
      }
      // Demo öğrenciler
      final stSnap = await classRef.collection('students')
          .where('demo', isEqualTo: true).get();
      for (final s in stSnap.docs) {
        batch.delete(s.reference);
      }
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[DemoSeedService] clear fail: $e');
      return false;
    }
  }

  // ── Yardımcılar ─────────────────────────────────────────────────────────
  static List<Map<String, dynamic>> _demoQuestions(String type, int qc) {
    return List.generate(qc, (i) {
      if (type == 'mc') {
        return {
          'q': '${i + 1}. soru: Aşağıdakilerden hangisi doğrudur?',
          'type': 'mc',
          'choices': ['A) Birinci', 'B) İkinci', 'C) Üçüncü', 'D) Dördüncü'],
          'answer': 'A',
        };
      }
      if (type == 'open') {
        return {
          'q': '${i + 1}. soru: Konuyu kendi cümlelerinle açıkla.',
          'type': 'open',
          'answer': '',
        };
      }
      return {
        'q': '${i + 1}. soru: Boşluğu doldur: ____',
        'type': 'fill',
        'answer': 'cevap',
      };
    });
  }

  static List<Map<String, dynamic>> _demoAnswers(
      String type, int qc, int correct, int wrong) {
    final list = <Map<String, dynamic>>[];
    for (int i = 0; i < qc; i++) {
      bool? isCorrect;
      String ans;
      if (i < correct) {
        isCorrect = true;
        ans = type == 'mc' ? 'A' : 'Doğru cevap';
      } else if (i < correct + wrong) {
        isCorrect = false;
        ans = type == 'mc' ? 'C' : 'Eksik cevap';
      } else {
        isCorrect = false;
        ans = '';
      }
      final qLabel = type == 'mc'
          ? 'Çoktan seçmeli soru'
          : type == 'open'
              ? 'Açık uçlu soru'
              : 'Boşluk doldurma sorusu';
      list.add({
        'index': i,
        'type': type,
        'q': qLabel,
        'studentAnswer': ans,
        'isCorrect': isCorrect,
      });
    }
    return list;
  }

  static String _demoComment(String name, double score, int blank, int qc) {
    final first = name.split(' ').first;
    if (score >= 75) {
      return '$first bu ödevde güçlü bir performans gösterdi (%${score.round()}). '
          'Konuya hâkim; daha zorlayıcı sorularla ilerleyebilir.';
    }
    if (score >= 50) {
      return '$first ortalama bir sonuç aldı (%${score.round()}). '
          'Temel kavramlar oturmuş, ${blank > 0 ? 'boş bıraktığı $blank soru ' : 'eksik konular '}'
          'üzerinde kısa bir tekrar faydalı olur.';
    }
    return '$first bu ödevde zorlandı (%${score.round()}). '
        '${blank > 0 ? '$qc sorudan $blank tanesini boş bıraktı; ' : ''}'
        'konuyu birlikte tekrar etmek ve örnek çözmek motivasyonu artırır.';
  }
}
