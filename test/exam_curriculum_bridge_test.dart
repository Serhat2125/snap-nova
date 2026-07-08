// Sınav profili → ders+konu köprüsü testleri (curriculum_catalog).
// Amaç: seçilen HER sınav için ekranların kullandığı curriculumFor()
// sınava uygun dersleri döndürmeli — jenerik lise şablonuna düşmemeli.

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_nova/services/curriculum_catalog.dart';
import 'package:snap_nova/services/education_profile.dart';

void main() {
  test('statik girişi olan sınavlar zengin konularla gelir (YKS, LGS)', () {
    for (final grade in [
      'YKS (Yükseköğretim Kurumları Sınavı)',
      'LGS (Liselere Geçiş Sınavı)',
    ]) {
      final subs = curriculumFor(
          EduProfile(country: 'tr', level: 'exam_prep', grade: grade));
      expect(subs, isNotEmpty, reason: grade);
      // Statik katalog girişleri konu listeleriyle dolu olmalı.
      expect(subs.any((s) => s.topics.isNotEmpty), isTrue, reason: grade);
    }
  });

  test('KPSS Ortaöğretim artık kendi girişine eşleşir (ilk-kelime tuzağı)',
      () {
    final subs = curriculumFor(EduProfile(
        country: 'tr', level: 'exam_prep', grade: 'KPSS Ortaöğretim'));
    expect(subs, isNotEmpty);
    expect(subs.any((s) => s.topics.isNotEmpty), isTrue);
  });

  test('TUS/DUS/EUS köprüden sınava uygun dersleri alır (jenerik değil)', () {
    final tus = curriculumFor(EduProfile(
        country: 'tr',
        level: 'exam_prep',
        grade: 'TUS (Tıpta Uzmanlık Sınavı)'));
    expect(tus.map((s) => s.key), contains('anatomi'));

    final dus = curriculumFor(EduProfile(
        country: 'tr',
        level: 'exam_prep',
        grade: 'DUS (Diş Hekimliğinde Uzmanlık Sınavı)'));
    expect(dus.map((s) => s.key), contains('restoratif'));

    final eus = curriculumFor(EduProfile(
        country: 'tr',
        level: 'exam_prep',
        grade: 'EUS (Eczacılıkta Uzmanlık Sınavı)'));
    expect(eus.map((s) => s.key), contains('farmakognozi'));
  });

  test('yabancı meslek sınavları da köprüden doğru kategoriye düşer', () {
    final mir = curriculumFor(EduProfile(
        country: 'es', level: 'exam_prep', grade: 'MIR (Médicos)'));
    expect(mir.map((s) => s.key), contains('anatomi'), reason: 'MIR');

    final oab = curriculumFor(EduProfile(
        country: 'br', level: 'exam_prep', grade: 'OAB (Direito)'));
    expect(oab.map((s) => s.key), contains('anayasa'), reason: 'OAB');
  });

  test('tamamen bilinmeyen sınav adı bile boş dönmez', () {
    final subs = curriculumFor(EduProfile(
        country: 'xx', level: 'exam_prep', grade: 'Yerel Bilinmeyen Sınav'));
    expect(subs, isNotEmpty);
  });

  test('sınıf profilleri her ülkede dolu döner (örneklem)', () {
    for (final cc in ['tr', 'fr', 'de', 'jp', 'br', 'ng', 'xx']) {
      for (final level in ['primary', 'middle', 'high']) {
        final subs = curriculumFor(
            EduProfile(country: cc, level: level, grade: '3'));
        expect(subs, isNotEmpty, reason: '$cc/$level');
      }
    }
  });
}
