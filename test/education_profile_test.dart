// Unit tests for education_profile — exam mapping, subjectsForProfile fallback,
// displayLabel insan-okur etiketleri, kElectiveSubjectKeys.

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_nova/services/education_profile.dart';

void main() {
  group('subjectsForProfile() — fallback zinciri', () {
    test('Türkiye Lise 11 — TR-special path (tüm tracklar union)', () {
      const p = EduProfile(country: 'tr', level: 'high', grade: '11');
      final result = subjectsForProfile(p);
      expect(result, isNotEmpty);
      final keys = result.map((s) => s.key).toSet();
      expect(keys.length, greaterThan(5));
    });

    test('Sınav profili (YKS) — _examSubjectKeys path', () {
      const p = EduProfile(
        country: 'tr',
        level: 'exam_prep',
        grade: 'YKS (Yükseköğretim Kurumları Sınavı)',
      );
      final result = subjectsForProfile(p);
      expect(result, isNotEmpty);
    });

    test('MSÜ exam — yeni eklenen sınav', () {
      const p = EduProfile(country: 'tr', level: 'exam_prep', grade: 'MSU');
      final result = subjectsForProfile(p);
      expect(result, isNotEmpty);
    });

    test('Bilinmeyen ülke + level — international_${'high'} fallback', () {
      // Yeni: subjectsForProfile country-level miss durumunda
      // international_${level}'a düşer (eskiden direkt _fallbackKeys'e atlıyordu)
      const p = EduProfile(country: 'mt', level: 'high', grade: '10');
      final result = subjectsForProfile(p);
      expect(result, isNotEmpty);
      // international_high 14 ders içeriyor → fallback (_fallbackKeys, 8 ders)
      // değil, daha zengin olmalı
      expect(result.length, greaterThan(7));
    });

    test('Bilinmeyen ülke + masters — international_masters', () {
      const p = EduProfile(country: 'is', level: 'masters', grade: 'tez');
      final result = subjectsForProfile(p);
      expect(result, isNotEmpty);
    });

    test('Profile null — _fallbackKeys kullanılır', () {
      final result = subjectsForProfile(null);
      expect(result.length, equals(8)); // _fallbackKeys exact count
    });
  });

  group('EduProfile.displayLabel() — insan-okur sınav etiketleri', () {
    test('YKS · TYT etiketi', () {
      const p = EduProfile(country: 'tr', level: 'exam_prep', grade: 'yks_tyt');
      expect(p.displayLabel(), contains('YKS · TYT'));
    });

    test('MSÜ etiketi (büyük harf + UTF-8)', () {
      const p = EduProfile(country: 'tr', level: 'exam_prep', grade: 'msu');
      expect(p.displayLabel(), contains('MSÜ'));
    });

    test('KPSS Ortaöğretim — alt çizgili anahtar etikete çevrilir', () {
      const p = EduProfile(
        country: 'tr',
        level: 'exam_prep',
        grade: 'kpss_ortaogretim',
      );
      expect(p.displayLabel(), contains('KPSS Ortaöğretim'));
    });

    test('SAT (uluslararası)', () {
      const p = EduProfile(country: 'us', level: 'exam_prep', grade: 'sat');
      expect(p.displayLabel(), contains('SAT'));
    });

    test('Gaokao 高考 (Çince endonim)', () {
      const p = EduProfile(country: 'cn', level: 'exam_prep', grade: 'gaokao');
      expect(p.displayLabel(), contains('Gaokao'));
    });

    test('Bilinmeyen sınav — orijinal grade kullanılır', () {
      const p = EduProfile(
        country: 'tr',
        level: 'exam_prep',
        grade: 'custom_exam_xyz',
      );
      // Pretty etiket yok → grade aynen geçer
      expect(p.displayLabel(), contains('custom_exam_xyz'));
    });
  });

  group('kElectiveSubjectKeys — seçmeli ders sınıflandırması', () {
    test('beden, sanat_muzik, din_kultur — TR seçmeli derslerini içerir', () {
      expect(isElectiveSubjectKey('beden'), isTrue);
      expect(isElectiveSubjectKey('sanat_muzik'), isTrue);
      expect(isElectiveSubjectKey('din_kultur'), isTrue);
    });

    test('math, physics — çekirdek dersler seçmeli DEĞİL', () {
      expect(isElectiveSubjectKey('math'), isFalse);
      expect(isElectiveSubjectKey('physics'), isFalse);
    });

    test('Bilinmeyen key — false döner (default davranış)', () {
      expect(isElectiveSubjectKey('xyz_unknown'), isFalse);
    });
  });
}
