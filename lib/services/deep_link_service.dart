// ═══════════════════════════════════════════════════════════════════════════════
//  DeepLinkService — Davet linki, paylaşım linki açma.
//
//  Desteklenen URL şeması (Firebase Hosting + custom scheme):
//    • https://qualsar2-640f0.web.app/davet/{username}  ← davet linki
//    • qualsar://davet/{username}                       ← custom scheme
//    • https://qualsar2-640f0.web.app/u/{username}      ← profil paylaşımı
//
//  Akış:
//    1. init() → AppLinks dinleyicisini kurar (cold start + warm).
//    2. Cold start: getInitialAppLink() → uygulama linkten açıldıysa hemen route.
//    3. Warm: uriLinkStream → uygulama açıkken link gelirse anlık route.
//    4. _handle(uri) → path'i parse et, ValueNotifier ile UI'yi tetikle.
//       Main navigatorKey hazır olunca _consumePending() route'u açar.
//
//  UI tarafı: main.dart `DeepLinkService.instance.pendingInvite` ValueListenable'ı
//  dinler, davet username'i geldiğinde InviteAcceptPage'e push eder.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _initialized = false;

  /// Bekleyen davet kullanıcı adı — UI bunu dinler, route hazır olunca açar.
  /// null = bekleyen yok.
  final ValueNotifier<String?> pendingInvite = ValueNotifier<String?>(null);

  /// Bekleyen profil görüntüleme — `/u/{username}` linkinden.
  final ValueNotifier<String?> pendingProfile = ValueNotifier<String?>(null);

  /// Bekleyen referral kodu — `/i/{kod}` linkinden. Onboarding tarafından
  /// dinlenir; kod varsa otomatik `ReferralService.redeemCode()` çağrılır.
  final ValueNotifier<String?> pendingReferralCode = ValueNotifier<String?>(null);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      // Cold start — uygulama linkten yeni açıldıysa.
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handle(initial);
      }
    } catch (e) {
      debugPrint('[DeepLink] initial link fail: $e');
    }
    // Warm — uygulama açıkken gelen linkler.
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (e) => debugPrint('[DeepLink] stream error: $e'),
    );
  }

  void _handle(Uri uri) {
    debugPrint('[DeepLink] uri=$uri');
    // Path segmentlerini parse et — host fark etmez (web.app / custom scheme).
    final segs = uri.pathSegments
        .where((s) => s.isNotEmpty)
        .map((s) => s.toLowerCase())
        .toList();
    if (segs.isEmpty) return;

    if (segs.length >= 2 && segs[0] == 'davet') {
      // /davet/{username}
      pendingInvite.value = segs[1];
    } else if (segs.length >= 2 && segs[0] == 'u') {
      // /u/{username}
      pendingProfile.value = segs[1];
    } else if (segs.length >= 2 && segs[0] == 'i') {
      // /i/{referralCode} — case-insensitive case'i orijinal koru
      final original = uri.pathSegments.length >= 2
          ? uri.pathSegments[1].toUpperCase()
          : segs[1].toUpperCase();
      pendingReferralCode.value = original;
    }
  }

  /// UI tarafı route'u açtıktan sonra bayrakları sıfırlar.
  void clearInvite() => pendingInvite.value = null;
  void clearProfile() => pendingProfile.value = null;
  void clearReferralCode() => pendingReferralCode.value = null;

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _initialized = false;
  }

  /// Davet linki üretici — paylaşım butonu bunu kullanır.
  /// Production hosting URL'i kullanılır; deep link handler'ı bu pattern'i tanır.
  static String inviteLinkFor(String username) {
    return 'https://qualsar2-640f0.web.app/davet/$username';
  }

  static String profileLinkFor(String username) {
    return 'https://qualsar2-640f0.web.app/u/$username';
  }
}
