// ============================================================
//  known_opponents_service.dart
//  "Arkadaşlarınla Yarış" listesinin KALICI hafızası.
//
//  Sorun: FriendService.watchFriends() yalnızca KARŞILIKLI kabul edilmiş
//  arkadaşları döner (friends/{uid}/list). Kullanıcı birini eklediğinde
//  aslında yalnızca istek gönderiliyor; karşı taraf kabul edene kadar kişi
//  hiçbir listede görünmüyordu. Bu yüzden "eklediğim arkadaş kayboldu" ve
//  "daha önce yarıştığım kişileri bulamıyorum" yaşanıyordu.
//
//  Çözüm: eklenen ve/veya birlikte yarışılan herkes CİHAZDA saklanır ve
//  arkadaş listesiyle birleştirilerek gösterilir. Firestore tarafındaki
//  karşılıklı-onay modeli aynen korunur (kimse habersiz "arkadaş" yapılmaz);
//  burada tutulan yalnızca kullanıcının kendi geçmişidir.
// ============================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcının eklediği / yarıştığı bir kişi (cihazda saklanır).
class KnownOpponent {
  final String uid;
  final String username;
  final String displayName;
  final String avatar;

  /// Son etkileşim (ekleme veya yarış) — liste bu tarihe göre sıralanır.
  final DateTime lastSeen;

  /// Daha önce birlikte yarışıldı mı? (yalnız eklendiyse false)
  final bool played;

  const KnownOpponent({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.avatar,
    required this.lastSeen,
    this.played = false,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'username': username,
        'displayName': displayName,
        'avatar': avatar,
        'lastSeen': lastSeen.toIso8601String(),
        'played': played,
      };

  static KnownOpponent? fromJson(Map<String, dynamic> m) {
    final uid = (m['uid'] ?? '').toString();
    if (uid.isEmpty) return null;
    DateTime when;
    try {
      when = DateTime.parse((m['lastSeen'] ?? '').toString());
    } catch (_) {
      when = DateTime.now();
    }
    return KnownOpponent(
      uid: uid,
      username: (m['username'] ?? '').toString(),
      displayName: (m['displayName'] ?? '').toString(),
      avatar: (m['avatar'] ?? '').toString(),
      lastSeen: when,
      played: m['played'] == true,
    );
  }
}

class KnownOpponentsService {
  KnownOpponentsService._();

  static const _key = 'arena_known_opponents_v1';

  /// Listeyi sınırsız büyütme — en yeni 100 kişi yeter.
  static const _cap = 100;

  /// Bellek içi kopya + değişiklik bildirimi (liste anında tazelenir).
  static final ValueNotifier<List<KnownOpponent>> notifier =
      ValueNotifier<List<KnownOpponent>>(const []);

  static bool _loaded = false;

  /// Uygulama açılışında veya listeyi ilk gösterirken çağrılır.
  static Future<List<KnownOpponent>> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      final out = <KnownOpponent>[];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) {
              final o = KnownOpponent.fromJson(Map<String, dynamic>.from(e));
              if (o != null) out.add(o);
            }
          }
        }
      }
      out.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      _loaded = true;
      notifier.value = out;
      return out;
    } catch (_) {
      _loaded = true;
      return notifier.value;
    }
  }

  static Future<void> _save(List<KnownOpponent> list) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final capped = list.length > _cap ? list.sublist(0, _cap) : list;
      await sp.setString(
          _key, jsonEncode([for (final o in capped) o.toJson()]));
      notifier.value = capped;
    } catch (_) {}
  }

  /// Kişiyi kaydet/güncelle. [played] true ise "birlikte yarışıldı" işaretlenir
  /// ve bir daha false'a düşmez (geçmiş kaybolmasın).
  static Future<void> remember({
    required String uid,
    String username = '',
    String displayName = '',
    String avatar = '',
    bool played = false,
  }) async {
    if (uid.trim().isEmpty) return;
    if (!_loaded) await load();
    final list = [...notifier.value];
    final i = list.indexWhere((o) => o.uid == uid);
    final prev = i >= 0 ? list[i] : null;
    final merged = KnownOpponent(
      uid: uid,
      // Boş gelen alanlar öncekini silmesin.
      username: username.isNotEmpty ? username : (prev?.username ?? ''),
      displayName:
          displayName.isNotEmpty ? displayName : (prev?.displayName ?? ''),
      avatar: avatar.isNotEmpty ? avatar : (prev?.avatar ?? ''),
      lastSeen: DateTime.now(),
      played: played || (prev?.played ?? false),
    );
    if (i >= 0) list.removeAt(i);
    list.insert(0, merged);
    await _save(list);
  }

  static Future<void> forget(String uid) async {
    if (!_loaded) await load();
    final list = [...notifier.value]..removeWhere((o) => o.uid == uid);
    await _save(list);
  }

  static List<KnownOpponent> get current => notifier.value;
}
