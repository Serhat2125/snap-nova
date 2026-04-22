import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Hafif ağ durumu servisi — `connectivity_plus` paketine ihtiyaç yok.
///
/// - DNS araması (`InternetAddress.lookup`) ile gerçek çıkışı sınar
///   (WiFi'ye bağlı olmak ≠ internet olmak).
/// - Periyodik sağlık kontrolü yerine **talep üzerine** çalışır; pil
///   ve RAM etkisi ihmal edilebilir düzeydedir.
/// - `onChange` akışı UI'da dinlenebilir (snackbar, offline rozeti vb).
class ConnectivityService extends ChangeNotifier {
  static const _probeHost = 'www.google.com';
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
    try {
      final result = await InternetAddress.lookup(_probeHost)
          .timeout(_probeTimeout);
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
