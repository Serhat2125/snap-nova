// Bilgi Ligi konum tutarlılığı — skor YAZMA (LeagueScores.add) ile sıralama
// OKUMA (bilgi_ligi_screen._effectiveLocation) aynı ülke kodu formülünü
// kullanmalı. 2026-07-08'de bu ikisi ayrışınca "puan buluta yazılıyor ama
// kullanıcı sıralamada görünmüyor / sıra — kalıyor" hatası yaşandı; bu test
// o hata sınıfını kalıcı olarak kilitler.

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_nova/features/leaderboard/domain/user_location.dart';
import 'package:snap_nova/features/league/league_scores.dart';
import 'package:snap_nova/services/education_profile.dart';

void main() {
  const trProfile = EduProfile(country: 'tr', level: 'high', grade: '12');
  const frProfile = EduProfile(country: 'fr', level: 'middle', grade: '5');
  const loc = UserLocation(
    country: 'Türkiye',
    countryCode: 'TR',
    city: 'İstanbul',
    cityCode: 'istanbul',
  );

  test('konum seçiliyse HER ZAMAN konumun ülke kodu kazanır', () {
    expect(LeagueScores.effectiveCountryCode(trProfile, loc), 'TR');
    expect(LeagueScores.effectiveCountryCode(frProfile, loc), 'TR');
    expect(LeagueScores.effectiveCountryCode(null, loc), 'TR');
  });

  test('konum yoksa profil ülkesi upper-case kullanılır (gönderimle birebir)',
      () {
    expect(LeagueScores.effectiveCountryCode(trProfile, null), 'TR');
    expect(LeagueScores.effectiveCountryCode(frProfile, null), 'FR');
    // 'uk' gibi uygulama-içi kodlar da olduğu gibi upper-case geçer —
    // gönderim tarafı da aynısını yaptığı için scope anahtarları eşleşir.
    const ukProfile = EduProfile(country: 'uk', level: 'high', grade: '10');
    expect(LeagueScores.effectiveCountryCode(ukProfile, null), 'UK');
  });

  test('hiçbir kaynak yoksa boş döner (sorgu atılmaz, çökme olmaz)', () {
    expect(LeagueScores.effectiveCountryCode(null, null), '');
    const emptyProfile = EduProfile(country: '', level: 'high', grade: '9');
    expect(LeagueScores.effectiveCountryCode(emptyProfile, null), '');
  });

  test('boş countryCode taşıyan konum, profil fallback\'ini engellemez', () {
    const emptyLoc = UserLocation(
      country: '',
      countryCode: '',
      city: '',
      cityCode: '',
    );
    expect(LeagueScores.effectiveCountryCode(trProfile, emptyLoc), 'TR');
  });
}
