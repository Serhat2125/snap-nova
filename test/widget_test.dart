// Smoke test — temel sinyal: paket compile ediyor + EduProfile çalışıyor.
// Önceki içerik (camera/image_picker mini app) eski Flutter starter'dan
// kalan tutarsız stub'tı; doğru testle değiştirildi.
//
// Daha detaylı testler:
//   - test/curriculum_catalog_test.dart
//   - test/education_profile_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_nova/services/education_profile.dart';

void main() {
  test('EduProfile basit smoke — constructor + alanlar', () {
    const p = EduProfile(country: 'tr', level: 'high', grade: '11');
    expect(p.country, equals('tr'));
    expect(p.level, equals('high'));
    expect(p.grade, equals('11'));
    expect(p.track, isNull);
  });

  test('subjectsForProfile çalışır + boş dönmez', () {
    const p = EduProfile(country: 'tr', level: 'high', grade: '11');
    final result = subjectsForProfile(p);
    expect(result, isNotEmpty);
  });
}
