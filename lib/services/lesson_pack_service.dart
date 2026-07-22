// ═══════════════════════════════════════════════════════════════════════════
//  LessonPackService — İNDİRİLEBİLİR DİL PAKETİ (offline çeviri)
//
//  AMAÇ: 3D ders sahnelerindeki (ve tüm .tr() metinlerinin) çevirisi her
//  kullanıcının cihazında Gemini ile tekrar tekrar üretilmesin. Bunun yerine
//  bir dil SUNUCUDA bir kez çevrilir (dil-başına-bir-kez), Firebase Storage'a
//  yazılır ve o dildeki TÜM kullanıcılara aynı paket servis edilir — tıpkı
//  Netflix'in altyazı izini indirmesi gibi. İkinci açılıştan sonra tamamen
//  offline ve anında.
//
//  AKIŞ:
//    1. Kullanıcı TR-dışı bir dile geçince sync(lang) çağrılır.
//    2. Firestore manifest'i (lesson_packs/{lang}) okunur — küçük doc:
//       { version, count, path, status }. Sürüm yerelde cache'liden yeni mi?
//    3. Yeniyse Storage'dan paket (lesson_i18n/{lang}.json) indirilir,
//       RuntimeTranslator.ingestPack ile cache'e basılır, sürüm kaydedilir.
//    4. Paket henüz yoksa (status != 'ready') → hiçbir şey yapılmaz; mevcut
//       runtime Gemini akışı geçici olarak devreye girer, paket hazır olunca
//       bir sonraki sync'te iner.
//
//  MALİYET: istemci tarafı yalnızca 1 küçük Firestore okuması + hazırsa 1
//  dosya indirme (dil başına, sürüm değişene dek tekrarsız). Sıfır AI çağrısı.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'error_logger.dart';
import 'locale_service.dart';
import 'runtime_translator.dart';

class LessonPackService {
  LessonPackService._();
  static final LessonPackService instance = LessonPackService._();

  static const _tag = '📦 [LessonPack]';
  static const _prefVersionPrefix = 'lesson_pack_ver_';
  static const _manifestCollection = 'lesson_packs';
  // Storage yolu: sunucu üreticisi (lesson_pack_generator.ts) buraya yazar.
  static const _storagePrefix = 'lesson_i18n';

  // Aynı dil için eşzamanlı tek sync.
  final Map<String, Future<void>> _inflight = {};

  /// Aktif dil için paketi (varsa ve yeniyse) indirip cache'e uygula.
  /// Ağ yoksa / paket yoksa sessizce döner — runtime akışı bozulmaz.
  Future<void> sync(String lang) {
    if (lang == 'tr') return Future<void>.value();
    if (!LocaleService.supportedLocales.contains(lang)) {
      return Future<void>.value();
    }
    final existing = _inflight[lang];
    if (existing != null) return existing;
    final f = _sync(lang).whenComplete(() => _inflight.remove(lang));
    _inflight[lang] = f;
    return f;
  }

  Future<void> _sync(String lang) async {
    try {
      // 1) Manifest'i oku (küçük, ucuz).
      final snap = await FirebaseFirestore.instance
          .collection(_manifestCollection)
          .doc(lang)
          .get();
      final data = snap.data();
      final status = (data?['status'] as String?) ?? '';
      final remoteVer = (data?['version'] as num?)?.toInt() ?? 0;
      final count = (data?['count'] as num?)?.toInt() ?? 0;
      if (data == null || status != 'ready' || count <= 0) {
        // Paket yok/hazır değil → bu dilin ilk kullanıcısı sunucuda üretimi
        // TETİKLESİN (dil-başına-bir-kez). Fire-and-forget: sonucu beklemeyiz;
        // hazır olunca bir sonraki sync'te iner. Bu arada runtime Gemini akışı
        // geçici olarak çeviriyi karşılar.
        unawaited(_triggerGeneration(lang));
        _log('$lang: paket hazır değil (status=$status) — üretim tetiklendi');
        return;
      }

      // 2) Yerel sürümle karşılaştır.
      final prefs = await SharedPreferences.getInstance();
      final localVer = prefs.getInt('$_prefVersionPrefix$lang') ?? -1;
      if (localVer >= remoteVer) {
        _log('$lang: güncel (v$localVer)');
        return;
      }

      // 3) Paketi indir (Storage). Manifest 'path' verirse onu kullan.
      final path = (data['path'] as String?) ?? '$_storagePrefix/$lang.json';
      final bytes = await FirebaseStorage.instance
          .ref(path)
          .getData(64 * 1024 * 1024); // 64 MB tavan
      if (bytes == null) {
        _log('$lang: indirme boş döndü');
        return;
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        _log('$lang: beklenmeyen paket biçimi');
        return;
      }
      final pack = <String, String>{};
      decoded.forEach((k, v) {
        if (k is String && v is String) pack[k] = v;
      });

      // 4) Cache'e bas + sürümü kaydet.
      final added = await RuntimeTranslator.instance.ingestPack(lang, pack);
      await prefs.setInt('$_prefVersionPrefix$lang', remoteVer);
      _log('$lang: paket uygulandı v$remoteVer (+$added / ${pack.length})');
    } catch (e, st) {
      // Ağ/izin/format hatası → runtime akışı devrede kalır, sessiz geç.
      ErrorLogger.instance.capture(e, st, context: 'lesson_pack_service');
      _log('$lang: sync hatası: $e');
    }
  }

  // Sunucuda paket üretimini başlat/devam ettir (ensureLessonPack callable).
  // Aynı dil için oturumda bir kez tetikle (gereksiz çağrı yok).
  final Set<String> _triggered = {};
  Future<void> _triggerGeneration(String lang) async {
    if (!_triggered.add(lang)) return;
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('ensureLessonPack')
          .call<void>({'lang': lang});
    } catch (e) {
      // Kredi yok / ağ hatası → sessiz; runtime akışı devrede kalır.
      _log('$lang: üretim tetikleme hatası: $e');
    }
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('$_tag $msg');
  }
}
