// ═══════════════════════════════════════════════════════════════════════════════
//  UserProfilesProvider — kullanıcının çoklu eğitim profillerini yöneten
//  Riverpod state notifier.
//
//  Persistans: SharedPreferences `mini_test_profiles_v1` anahtarında JSON liste.
//  Eski tek-profil pref'leri (`mini_test_level/grade/faculty/track`) ana
//  (primary) profil olarak otomatik senkronize edilir — eski ekranlar
//  bozulmaz; new ekranlar tüm listeyi kullanır.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/user_education_profile.dart';

const _kPrefsList = 'mini_test_profiles_v1';
const _kPrefsLevel = 'mini_test_level';
const _kPrefsGrade = 'mini_test_grade';
const _kPrefsFaculty = 'mini_test_faculty';
const _kPrefsTrack = 'mini_test_track';
const _kPrefsCountry = 'mini_test_country';

class UserProfilesController extends StateNotifier<List<UserEducationProfile>> {
  UserProfilesController() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsList) ?? '';
    final list = decodeProfilesJson(raw);
    if (list.isNotEmpty) {
      state = list;
      return;
    }
    // Geriye dönük uyumluluk: eski tek-profil pref'lerinden tek bir profil
    // oluştur (eğer kullanıcı eski yapıyla kaydedilmişse).
    final level = prefs.getString(_kPrefsLevel);
    final grade = prefs.getString(_kPrefsGrade);
    if (level != null && grade != null && grade.isNotEmpty) {
      final p = UserEducationProfile(
        country: prefs.getString(_kPrefsCountry) ?? 'tr',
        level: level,
        grade: grade,
        track: prefs.getString(_kPrefsTrack),
        faculty: prefs.getString(_kPrefsFaculty),
        addedAt: DateTime.now(),
      );
      state = [p];
      await _persist();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsList, encodeProfilesJson(state));
    // Birinci profil (primary) eski tek-profil pref'lerine de yazılır →
    // eski ekranlar (EduProfile.load) sorunsuz okur.
    if (state.isNotEmpty) {
      final p = state.first;
      await prefs.setString(_kPrefsCountry, p.country);
      await prefs.setString(_kPrefsLevel, p.level);
      await prefs.setString(_kPrefsGrade, p.grade);
      if (p.faculty != null) {
        await prefs.setString(_kPrefsFaculty, p.faculty!);
      } else {
        await prefs.remove(_kPrefsFaculty);
      }
      if (p.track != null) {
        await prefs.setString(_kPrefsTrack, p.track!);
      } else {
        await prefs.remove(_kPrefsTrack);
      }
    }
  }

  /// Profil ekle. Aynı signature varsa duplicate eklemez (eklendi olarak döner).
  bool add(UserEducationProfile profile) {
    if (state.any((p) => p.signature == profile.signature)) return false;
    state = [...state, profile];
    _persist();
    return true;
  }

  /// Profili kaldır.
  void remove(UserEducationProfile profile) {
    state = state.where((p) => p.signature != profile.signature).toList();
    _persist();
  }

  /// Verilen profili listenin başına taşı (= primary yap).
  void setPrimary(UserEducationProfile profile) {
    final filtered =
        state.where((p) => p.signature != profile.signature).toList();
    state = [profile, ...filtered];
    _persist();
  }

  /// Tüm profilleri sıfırla.
  Future<void> clear() async {
    state = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsList);
  }

  /// Onboarding bittikten sonra çoklu profil listesini bir kerede yaz.
  Future<void> replaceAll(List<UserEducationProfile> profiles) async {
    state = List.unmodifiable(profiles);
    await _persist();
  }
}

final userProfilesProvider =
    StateNotifierProvider<UserProfilesController, List<UserEducationProfile>>(
        (ref) => UserProfilesController());

/// Primary (ilk) profil — UI'de "kim olduğunu" özetleyen yerlerde kullanılır.
final primaryProfileProvider = Provider<UserEducationProfile?>((ref) {
  final list = ref.watch(userProfilesProvider);
  return list.isEmpty ? null : list.first;
});
