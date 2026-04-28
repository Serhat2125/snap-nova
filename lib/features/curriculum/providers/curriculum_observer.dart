// ═══════════════════════════════════════════════════════════════════════════════
//  CurriculumObserver — Global "profil değişti" yan-etki dispatcher
//
//  ÇALIŞMA: Riverpod ref.listen ile `curriculumControllerProvider`'i izler.
//  Profile değiştiğinde subscribe edilen tüm callback'leri çağırır:
//    • Library'nin ders listesi temizlenir
//    • Quiz creator'ın işaretli konu seti sıfırlanır
//    • Arena'nın matchmaking criteria güncellenir
//    • Konu Özeti'nin aktif seçimi temizlenir
//
//  Kullanım:
//   1. Uygulama başlangıcında `ref.read(curriculumObserverProvider).attach(ref);`
//   2. Bir modül kayıt olur: `observer.subscribe('library', () => myReset())`
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/user_preference.dart';
import 'curriculum_controller.dart';

typedef CurriculumChangeCallback = void Function(UserPreference? newPref);

class CurriculumObserver {
  final Map<String, CurriculumChangeCallback> _subscribers = {};
  ProviderSubscription<CurriculumState>? _sub;

  /// Riverpod provider değişimini dinlemek için bir kez attach edin.
  void attach(Ref ref) {
    _sub?.close();
    _sub = ref.listen<CurriculumState>(
      curriculumControllerProvider,
      (previous, next) {
        // Aynı profile ise no-op (gereksiz reset spam'i önler).
        if (previous?.preference == next.preference) return;
        _broadcast(next.preference);
      },
      fireImmediately: false,
    );
  }

  void detach() {
    _sub?.close();
    _sub = null;
  }

  /// Bir modül abone olur. ID benzersiz olmalı; tekrar subscribe ile değiştirilir.
  /// Modül dispose olunca `unsubscribe(id)` çağırılmalı.
  void subscribe(String id, CurriculumChangeCallback cb) {
    _subscribers[id] = cb;
  }

  void unsubscribe(String id) {
    _subscribers.remove(id);
  }

  void _broadcast(UserPreference? pref) {
    for (final entry in _subscribers.entries) {
      try {
        entry.value(pref);
      } catch (e) {
        debugPrint('[CurriculumObserver] subscriber "${entry.key}" failed: $e');
      }
    }
  }
}

/// Singleton observer — uygulama yaşam döngüsü boyunca aynı.
final curriculumObserverProvider = Provider<CurriculumObserver>((ref) {
  final obs = CurriculumObserver();
  obs.attach(ref);
  ref.onDispose(obs.detach);
  return obs;
});
