import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Hafif ağ durumu servisi — `connectivity_plus` paketine ihtiyaç yok.
///
/// - DNS araması (`InternetAddress.lookup`) ile gerçek çıkışı sınar
///   (WiFi'ye bağlı olmak ≠ internet olmak).
/// - Birden fazla probe host kullanır: Google (default), Cloudflare DNS,
///   Apple — tek host çalışmıyorsa diğerlerini dener (Çin, İran gibi
///   bölgelerde bazıları bloklu).
/// - Periyodik sağlık kontrolü yerine **talep üzerine** çalışır; pil
///   ve RAM etkisi ihmal edilebilir düzeydedir.
class ConnectivityService extends ChangeNotifier {
  /// Probe sırası — biri çalışırsa "online" kabul edilir.
  /// Cloudflare 1.1.1.1 + Apple captive portal genellikle her yerde açık.
  static const _probeHosts = [
    'www.google.com',
    'one.one.one.one', // Cloudflare 1.1.1.1
    'captive.apple.com',
    'generativelanguage.googleapis.com', // Gemini API'nin kendisi
  ];
  static const _probeTimeout = Duration(seconds: 3);

  bool _online = true;
  bool get online => _online;

  Timer? _timer;

  /// İlk kontrol + 30 saniyede bir periyodik tazelenme.
  Future<void> init() async {
    await checkNow();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => checkNow());
  }

  /// Anlık kontrol (login, API çağrısından önce).
  Future<bool> checkNow() async {
    final wasOnline = _online;
    _online = await _probe();
    if (wasOnline != _online) {
      notifyListeners();
      if (kDebugMode) {
        debugPrint('📡 [Connectivity] durumu: ${_online ? 'online' : 'offline'}');
      }
    }
    return _online;
  }

  static Future<bool> _probe() async {
    // Sırayla dene — biri çalışırsa hemen true. Hepsi düşerse false.
    for (final host in _probeHosts) {
      try {
        final result =
            await InternetAddress.lookup(host).timeout(_probeTimeout);
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException {
        continue;
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
