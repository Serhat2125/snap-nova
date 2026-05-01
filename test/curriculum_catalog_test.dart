// Unit tests for curriculum_catalog — lookup zinciri ve sınav normalize.
// `flutter test test/curriculum_catalog_test.dart` ile çalıştırılır.

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_nova/services/education_profile.dart';
import 'package:snap_nova/services/curriculum_catalog.dart';

void main() {
  group('curriculumFor() — lookup zinciri', () {
    test('TR Lise 11 Sayısal — tam eşleşme bulunur', () {
      const p = EduProfile(
        country: 'tr',
        level: 'high',
        grade: '11',
        track: 'sayisal',
      );
      final result = curriculumFor(p);
      expect(result, isNotEmpty);
      // tr_high_11_sayisal anahtarında math + physics + chem olmalı
      final keys = result.map((s) => s.key).toSet();
      expect(keys, contains('math'));
      expect(keys, contains('physics'));
    });

    test('TR YKS hazırlık — sınav anahtarı normalize edilir', () {
      // Grade key olarak "yks_tyt" saklanır; lookup tr_exam_prep_yks_tyt'i bulmalı
      const p = EduProfile(
        country: 'tr',
        level: 'exam_prep',
        grade: 'yks_tyt',
      );
      final result = curriculumFor(p);
      expect(result, isNotEmpty);
      final keys = result.map((s) => s.key).toSet();
      expect(keys, contains('math'));
    });

    test('TR LGS — ana liste\'den seçilse de exam_prep+lgs olarak işlenir', () {
      const p = EduProfile(
        country: 'tr',
        level: 'exam_prep',
        grade: 'lgs',
      );
      final result = curriculumFor(p);
      expect(result, isNotEmpty);
      final keys = result.map((s) => s.key).toSet();
      // LGS müfredatında matematik + Türkçe olmalı
      expect(keys, contains('math'));
      expect(keys, contains('turkish'));
    });

    test('Bilinmeyen ülke (mt = Malta) — international fallback\'a düşer', () {
      const p = EduProfile(
        country: 'mt',
        level: 'high',
        grade: '11',
      );
      final result = curriculumFor(p);
      // Fallback: international_high zenginliğinde ders olmalı
      expect(result, isNotEmpty);
      final keys = result.map((s) => s.key).toSet();
      expect(keys, contains('math'));
    });

    test('Profile null — international_high fallback', () {
      final result = curriculumFor(null);
      expect(result, isNotEmpty);
    });

    test('Argentina Lise 10 — eklenen ülke-spesifik müfredat çıkar', () {
      const p = EduProfile(
        country: 'ar',
        level: 'high',
        grade: '10',
      );
      final result = curriculumFor(p);
      expect(result, isNotEmpty);
      final keys = result.map((s) => s.key).toSet();
      // ar_high_10'da Borges, Cortázar konuları olan lit dersi var
      expect(keys, contains('math'));
    });

    test('Yeni eklenen sınav: MSÜ — tr_exam_prep_msu bulunur', () {
      const p = EduProfile(
        country: 'tr',
        level: 'exam_prep',
        grade: 'msu',
      );
      final result = curriculumFor(p);
      expect(result, isNotEmpty);
      final keys = result.map((s) => s.key).toSet();
      // MSÜ müfredatı: math + geometry + turkish + history + geo
      expect(keys, contains('math'));
      expect(keys, contains('history'));
    });

    test('KPSS Ortaöğretim — _ ile ayrılmış key korunur', () {
      const p = EduProfile(
        country: 'tr',
        level: 'exam_prep',
        grade: 'kpss_ortaogretim',
      );
      final result = curriculumFor(p);
      expect(result, isNotEmpty);
    });

    test('Generic exam_prep (international) — bilinmeyen sınav adı', () {
      // Bilinmeyen ülke + bilinmeyen sınav → international_exam_prep
      const p = EduProfile(
        country: 'mt',
        level: 'exam_prep',
        grade: 'national_exam',
      );
      final result = curriculumFor(p);
      expect(result, isNotEmpty);
      final keys = result.map((s) => s.key).toSet();
      // international_exam_prep'te math, english, logic, science, social olmalı
      expect(keys.length, greaterThan(2));
    });
  });

  group('Lookup zinciri — country fallback davranışı', () {
    test('UK High — country branch (8 entries var)', () {
      const p = EduProfile(country: 'uk', level: 'high', grade: '11');
      final result = curriculumFor(p);
      expect(result, isNotEmpty);
    });

    test('JP Kokō — endonim subject names', () {
      const p = EduProfile(country: 'jp', level: 'high', grade: '11');
      final result = curriculumFor(p);
      expect(result, isNotEmpty);
      // Japonya'nın subject display override'ı 国語/数学 endonimleriyle
      final names = result.map((s) => s.displayName).toSet();
      // En azından bir Japonca-yerel ad olmalı
      final hasJapanese = names.any(
          (n) => n.contains('数') || n.contains('国') || n.contains('Sūgaku'));
      expect(hasJapanese, isTrue,
          reason: 'JP override\'ı çalışmıyor: $names');
    });
  });
}
