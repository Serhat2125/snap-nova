// LeagueDemoStudents — kapalı test demo dolgusu birim testleri.
// Amaç: her kapsam × periyot kombinasyonunda 30 demo öğrencinin gerçekten
// üretildiğini ve deterministik olduğunu kanıtlamak.

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_nova/features/league/league_demo_students.dart';
import 'package:snap_nova/features/league/league_leaderboard_service.dart';
import 'package:snap_nova/features/league/league_scores.dart';
import 'package:snap_nova/features/leaderboard/domain/user_location.dart';
import 'package:snap_nova/services/education_profile.dart';

void main() {
  const profile = EduProfile(country: 'tr', level: 'high', grade: '9');
  const loc = UserLocation(
    country: 'Türkiye',
    countryCode: 'TR',
    city: 'İstanbul',
    cityCode: 'istanbul',
  );

  test('her kapsam ve periyotta 30 demo öğrenci üretilir', () {
    for (final scope in LeagueScope.values) {
      for (final period in LeaguePeriod.values) {
        final rows = LeagueDemoStudents.forView(
          scope: scope,
          profile: profile,
          location: loc,
          period: period,
          modeKey: 'all',
        );
        expect(rows.length, 30, reason: 'scope=$scope period=$period');
        // Puan DESC sıralı
        for (int i = 1; i < rows.length; i++) {
          expect(rows[i - 1].score >= rows[i].score, isTrue);
        }
        // uid'ler demo-işaretli ve benzersiz
        expect(rows.every((r) => LeagueDemoStudents.isDemoUid(r.uid)), isTrue);
        expect(rows.map((r) => r.uid).toSet().length, 30);
        // İsim ve puan dolu
        expect(rows.every((r) => r.displayName.trim().isNotEmpty), isTrue);
        expect(rows.every((r) => r.score > 0), isTrue);
      }
    }
  });

  test('deterministik — aynı görünüm iki çağrıda aynı listeyi verir', () {
    final a = LeagueDemoStudents.forView(
      scope: LeagueScope.world,
      profile: profile,
      location: loc,
      period: LeaguePeriod.weekly,
      modeKey: 's:mat',
    );
    final b = LeagueDemoStudents.forView(
      scope: LeagueScope.world,
      profile: profile,
      location: loc,
      period: LeaguePeriod.weekly,
      modeKey: 's:mat',
    );
    expect(a.length, b.length);
    for (int i = 0; i < a.length; i++) {
      expect(a[i].uid, b[i].uid);
      expect(a[i].displayName, b[i].displayName);
      expect(a[i].score, b[i].score);
    }
  });

  test('dünya kapsamı profil/konum OLMADAN da 30 öğrenci üretir', () {
    final rows = LeagueDemoStudents.forView(
      scope: LeagueScope.world,
      profile: null,
      location: null,
      period: LeaguePeriod.daily,
      modeKey: 'all',
    );
    expect(rows.length, 30);
    // Dünya satırları bayrak + ülke içerir
    expect(rows.every((r) => r.location.trim().isNotEmpty), isTrue);
  });

  test('şehir/ülke kapsamı konum YOKKEN bile 30 öğrenci üretir (fallback)',
      () {
    for (final scope in [LeagueScope.city, LeagueScope.country]) {
      final rows = LeagueDemoStudents.forView(
        scope: scope,
        profile: null,
        location: null,
        period: LeaguePeriod.weekly,
        modeKey: 'all',
      );
      expect(rows.length, 30, reason: 'scope=$scope');
    }
  });

  test('konum yokken profil ülkesi kullanılır — TR profili Türk isimleri görür',
      () {
    final rows = LeagueDemoStudents.forView(
      scope: LeagueScope.country,
      profile: profile, // country: 'tr'
      location: null,
      period: LeaguePeriod.weekly,
      modeKey: 'all',
    );
    expect(rows.length, 30);
    const trFirstNames = [
      'Elif', 'Yusuf', 'Zeynep', 'Emir', 'Defne', 'Ali', 'Ecrin', 'Ömer',
      'Azra', 'Mert', 'Eylül', 'Kerem', 'Nisa', 'Baran', 'Duru', 'Çınar',
    ];
    for (final r in rows) {
      final first = r.displayName.split(' ').first;
      expect(trFirstNames.contains(first), isTrue,
          reason: 'beklenmeyen isim: ${r.displayName}');
    }
  });

  test('seviye/sınıf farklı → şehir kapsamında farklı kadro', () {
    const p9 = EduProfile(country: 'tr', level: 'high', grade: '9');
    const p5 = EduProfile(country: 'tr', level: 'middle', grade: '5');
    final a = LeagueDemoStudents.forView(
      scope: LeagueScope.city,
      profile: p9,
      location: loc,
      period: LeaguePeriod.weekly,
      modeKey: 'all',
    );
    final b = LeagueDemoStudents.forView(
      scope: LeagueScope.city,
      profile: p5,
      location: loc,
      period: LeaguePeriod.weekly,
      modeKey: 'all',
    );
    expect(a.map((r) => r.uid).toSet(), isNot(b.map((r) => r.uid).toSet()));
  });

  test('Fransız kullanıcı ülke kapsamında Fransız isimleri görür', () {
    const fr = UserLocation(
      country: 'France',
      countryCode: 'FR',
      city: 'Paris',
      cityCode: 'paris',
    );
    final rows = LeagueDemoStudents.forView(
      scope: LeagueScope.country,
      profile: profile,
      location: fr,
      period: LeaguePeriod.monthly,
      modeKey: 'all',
    );
    expect(rows.length, 30);
    const frFirstNames = [
      'Léa', 'Hugo', 'Chloé', 'Louis', 'Manon', 'Jules', 'Camille', 'Lucas',
      'Emma', 'Nathan', 'Inès', 'Théo', 'Jade', 'Gabriel', 'Zoé', 'Arthur',
    ];
    for (final r in rows) {
      final first = r.displayName.split(' ').first;
      expect(frFirstNames.contains(first), isTrue,
          reason: 'beklenmeyen isim: ${r.displayName}');
    }
  });
}
