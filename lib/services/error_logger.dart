import 'dart:async';
import 'dart:collection';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama genelinde hata toplama + uzaktan raporlama.
///
/// Crashlytics yerine **Firestore'a özel bir koleksiyon** (`app_errors`)
/// kullanıyoruz çünkü zaten Firestore yapılandırılmış; ek bağımlılık yok.
/// İstemci tarafında bir ring buffer tutar; periyodik olarak flush eder.
///
/// Kullanım:
///   ErrorLogger.instance.capture(error, stack, context: 'camera_init');
///
/// Fatal + fatal olmayan ayrımı yapılır. PII toplanmaz; sadece anonim
/// cihaz imzası (ilk çalıştırmada üretilen random id).
class ErrorLogger {
  ErrorLogger._();
  static final ErrorLogger instance = ErrorLogger._();

  static const _collection = 'app_errors';
  static const _prefInstanceIdKey = 'error_logger_instance_id_v1';
  static const _flushInterval = Duration(minutes: 2);
  static const _maxBuffer = 50;

  final Queue<_ErrorEvent> _buffer = Queue();
  Timer? _flushTimer;
  String? _instanceId;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _instanceId = prefs.getString(_prefInstanceIdKey) ??
        () {
          final id = _generateId();
          prefs.setString(_prefInstanceIdKey, id);
          return id;
        }();

    // Flutter çerçeve hataları → bize gelsin
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      capture(
        details.exception,
        details.stack,
        context: details.context?.toString(),
        fatal: false,
      );
    };

    // Platform kanalı / zone'dan sızan hatalar
    PlatformDispatcher.instance.onError = (error, stack) {
      capture(error, stack, context: 'platform_dispatcher', fatal: true);
      return true;
    };

    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  /// Yakalanmış hatayı kuyruğa ekler. UI'ı etkilemez.
  void capture(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extra,
  }) {
    if (!_initialized) {
      // init edilmediyse konsola yaz + işleme devam
      debugPrint('⚠️ [ErrorLogger] init edilmedi: $error');
      return;
    }
    final event = _ErrorEvent(
      message: error.toString(),
      stack: stack?.toString(),
      context: context,
      fatal: fatal,
      extra: extra,
      timestamp: DateTime.now(),
      instanceId: _instanceId ?? 'unknown',
    );
    _buffer.addLast(event);
    // Taşmayı engelle
    while (_buffer.length > _maxBuffer) {
      _buffer.removeFirst();
    }
    if (kDebugMode) {
      debugPrint('🐞 [ErrorLogger] kuyrukta ${_buffer.length}/$_maxBuffer - $error');
    }
    // Fatal ise hemen flush dene
    if (fatal) unawaited(flush());
  }

  /// Kuyruğu Firestore'a yollar. Firestore yoksa in-memory tutmaya devam
  /// eder (crash olmaz).
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    // Firestore var mı?
    final apps = Firebase.apps;
    if (apps.isEmpty) return; // init olmamış; sessizce geç
    final firestore = FirebaseFirestore.instanceFor(app: apps.first);
    // Batch yaz — hepsi başarı ya da hepsi geri yazılır
    final pending = List<_ErrorEvent>.from(_buffer);
    _buffer.clear();
    try {
      final batch = firestore.batch();
      final col = firestore.collection(_collection);
      for (final e in pending) {
        batch.set(col.doc(), e.toJson());
      }
      await batch.commit();
    } catch (err) {
      // Başarısız — kuyruğa geri koy ki sonra yeniden denenebilsin
      for (final e in pending) {
        _buffer.addLast(e);
      }
      if (kDebugMode) debugPrint('⚠️ [ErrorLogger] flush başarısız: $err');
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  static String _generateId() {
    // Random + timestamp karışımı — UUID kütüphanesi eklemeye gerek yok
    final rnd = DateTime.now().microsecondsSinceEpoch;
    final hex = rnd.toRadixString(16);
    return 'dev_${hex.padLeft(16, '0')}';
  }
}

class _ErrorEvent {
  final String message;
  final String? stack;
  final String? context;
  final bool fatal;
  final Map<String, dynamic>? extra;
  final DateTime timestamp;
  final String instanceId;

  _ErrorEvent({
    required this.message,
    this.stack,
    this.context,
    required this.fatal,
    this.extra,
    required this.timestamp,
    required this.instanceId,
  });

  Map<String, dynamic> toJson() => {
        'message': message,
        if (stack != null) 'stack': stack,
        if (context != null) 'context': context,
        'fatal': fatal,
        if (extra != null) 'extra': extra,
        'timestamp': Timestamp.fromDate(timestamp),
        'instanceId': instanceId,
        'platform': defaultTargetPlatform.name,
        'buildMode': kReleaseMode
            ? 'release'
            : kProfileMode
                ? 'profile'
                : 'debug',
      };
}
