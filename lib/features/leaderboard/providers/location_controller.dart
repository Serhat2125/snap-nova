import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/runtime_translator.dart';
import '../data/location_catalog.dart';
import '../domain/user_location.dart';

/// LocationController state'i — ekran 4 ana hâl gösterir:
///   • loading       : auto-detect devam ediyor
///   • detected      : IP'den geldiği varsayılan konum hazır, kullanıcı
///                     "Evet, doğru" / "Bilgileri Değiştir" seçecek
///   • editing       : kullanıcı manuel ülke + şehir seçim formunda
///   • saving        : Firestore'a yazma sırasında
///   • saved/error   : sonuç durumu
@immutable
class LocationState {
  /// IP'den otomatik tespit edilen konum (mock veya gerçek geo-IP).
  /// İlk yüklemede null; mock servis dönünce dolar.
  final UserLocation? detected;

  /// Kullanıcının düzenleme modundaki seçimi. Detected ile aynı başlar;
  /// kullanıcı dropdown ile değiştirdikçe güncellenir. Confirm tarafından
  /// Firestore'a yazılan değer budur.
  final UserLocation? draft;

  /// true → "Evet, doğru" / "Bilgileri Değiştir" arasında karar;
  /// false → manuel ülke/şehir seçim formu.
  final bool isEditing;

  /// Auto-detect veya save in-progress.
  final bool isLoading;

  /// "Şehir seçilmedi" gibi son hata mesajı.
  final String? error;

  /// Confirm başarılı — sayfa kapansın / bir daha gösterme.
  final bool isConfirmed;

  const LocationState({
    this.detected,
    this.draft,
    this.isEditing = false,
    this.isLoading = false,
    this.error,
    this.isConfirmed = false,
  });

  factory LocationState.initial() => LocationState(isLoading: true);

  LocationState copyWith({
    UserLocation? detected,
    UserLocation? draft,
    bool? isEditing,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? isConfirmed,
  }) {
    return LocationState(
      detected: detected ?? this.detected,
      draft: draft ?? this.draft,
      isEditing: isEditing ?? this.isEditing,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isConfirmed: isConfirmed ?? this.isConfirmed,
    );
  }
}

/// Mock geo-IP servisi — production'da bir HTTPS endpoint
/// (örn. ipapi.co/json) ile değiştirilir. İmza aynı kalır.
class _MockGeoIpService {
  static Future<UserLocation> detect() async {
    // Gerçek IP lookup'ı simüle eden kısa gecikme
    await Future<void>.delayed(Duration(milliseconds: 700));
    // Varsayılan: Türkiye / İstanbul
    return UserLocation(
      country: 'Türkiye',
      countryCode: 'TR',
      city: 'İstanbul',
      cityCode: 'istanbul',
    );
  }
}

class LocationController extends StateNotifier<LocationState> {
  /// Açık olarak verilen user ID (testlerde sabitlemek için).
  /// Verilmezse `FirebaseAuth.instance.currentUser?.uid` kullanılır.
  final String? userId;

  /// Firestore instance — testlerde override edilebilsin diye constructor'da.
  final FirebaseFirestore? _firestore;

  LocationController({this.userId, FirebaseFirestore? firestore})
      : _firestore = firestore,
        super(LocationState.initial()) {
    _autoDetect();
  }

  /// Etkin UID — açık verilen veya FirebaseAuth'tan resolve edilen.
  /// Her ikisi de null ise anonim mod (Firestore yazma atlanır).
  String? get _effectiveUid {
    if (userId != null && userId!.isNotEmpty) return userId;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _autoDetect() async {
    try {
      final loc = await _MockGeoIpService.detect();
      if (!mounted) return;
      state = state.copyWith(
        detected: loc,
        draft: loc,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      if (!mounted) return;
      // Auto-detect başarısızsa bile düzenleme moduna düşürerek devam et —
      // kullanıcı manuel seçer.
      state = state.copyWith(
        isLoading: false,
        isEditing: true,
        error: 'Konum tahmin edilemedi, lütfen manuel seç.'.tr(),
      );
    }
  }

  /// "Bilgileri Değiştir" → manuel form moduna geç.
  void enterEditMode() {
    state = state.copyWith(isEditing: true, clearError: true);
  }

  /// Düzenleme modundan iptal — algılanan konuma dön.
  void cancelEdit() {
    state = state.copyWith(
      isEditing: false,
      draft: state.detected,
      clearError: true,
    );
  }

  /// Ülke seçimi değişti — ilk şehir otomatik seçilir (kullanıcı sonra
  /// değiştirebilir). Şehir kataloğunda eşleşme yoksa cityCode boş kalır.
  void selectCountry(String code) {
    final entry = LocationCatalog.findByCode(code);
    if (entry == null) return;
    final firstCity =
        entry.cities.isNotEmpty ? entry.cities.first : null;
    state = state.copyWith(
      draft: UserLocation(
        country: entry.name,
        countryCode: entry.code,
        city: firstCity?.name ?? '',
        cityCode: firstCity?.code ?? '',
      ),
      clearError: true,
    );
  }

  /// Şehir seçimi değişti.
  void selectCity(String cityCode) {
    final draft = state.draft;
    if (draft == null) return;
    final city =
        LocationCatalog.findCity(draft.countryCode, cityCode);
    if (city == null) return;
    state = state.copyWith(
      draft: draft.copyWith(city: city.name, cityCode: city.code),
      clearError: true,
    );
  }

  /// Onay → Firestore'a yaz + onConfirm callback'i tetikle.
  /// Etkin UID yoksa (anonim mod) sadece callback çağrılır.
  Future<void> confirm({
    required ValueChanged<UserLocation> onConfirm,
  }) async {
    final loc = state.draft ?? state.detected;
    if (loc == null || loc.city.isEmpty || loc.cityCode.isEmpty) {
      state = state.copyWith(error: 'Şehir seçilmeden ilerlenemez.'.tr());
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final uid = _effectiveUid;
      if (uid != null && uid.isNotEmpty) {
        final fs = _firestore ?? FirebaseFirestore.instance;
        await fs.collection('users').doc(uid).set({
          'location': loc.toJson(),
          'isLocationSet': true,
          'locationSetAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (!mounted) return;
      state = state.copyWith(isLoading: false, isConfirmed: true);
      onConfirm(loc);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: '${'Kaydedilemedi'.tr()}: $e',
      );
    }
  }
}

/// Provider — userId family ile, çünkü her oturuma özgü.
/// userId null ise "anonim" mod (sadece callback, Firestore'a yazma yok).
final locationControllerProvider = StateNotifierProvider.autoDispose
    .family<LocationController, LocationState, String?>(
  (ref, userId) => LocationController(userId: userId),
);

/// Yardımcı: kullanıcı dokümanında `isLocationSet == true` mi?
/// Yarışma sayfasının açılışında bu kontrol edilir; true ise sheet
/// gösterilmez. userId verilmezse FirebaseAuth.currentUser'dan resolve edilir.
/// Auth yoksa false döner — sheet açılır, anonim mod akışı çalışır.
Future<bool> isUserLocationSet([String? userId]) async {
  String? uid = userId;
  if (uid == null || uid.isEmpty) {
    try {
      uid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      uid = null;
    }
  }
  if (uid == null || uid.isEmpty) return false;
  try {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null) return false;
    return data['isLocationSet'] == true;
  } catch (_) {
    // Hata durumunda false döner — sheet gösterilir, kullanıcı yine onaylar.
    return false;
  }
}
