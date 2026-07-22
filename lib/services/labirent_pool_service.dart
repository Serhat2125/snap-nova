// ═══════════════════════════════════════════════════════════════════════════
//  LabirentPoolService — Bilgi Labirenti topluluk içerik havuzu.
//
//  AMAÇ: TR dışındaki ülkelerde labirent içeriği (soru + bilgi kartı) her
//  kullanıcı için tekrar tekrar AI ile üretilmesin. Ülke × kademe × sınıf
//  (× alan) × DİL başına Firestore'da bir havuz tutulur:
//
//    labirent_pool/{country|level|grade|track|lang}
//      country, level, grade, track, lang, kind ('class'|'exam'),
//      subjectsHint (üretim prompt'u için ders+konu özeti),
//      curriculumSig (müfredat imzası — aynı müfredatlı ülkeler arası
//                     kopya/çeviri için), optionCount,
//      questionCount, factCount, status ('generating'|'ready'), targets
//      /q/{hash}  → {q, opts[], a, sol}
//      /f/{hash}  → {t}
//
//  AKIŞ (kullanıcı isteği):
//    • Havuz HAZIR değilken (soru < 300 VEYA bilgi < 500): oturum içeriği AI
//      ile üretilir ve fire-and-forget havuza da yazılır (organik doluş).
//      Cloud Function (labirent_pool_generator.ts) da arka planda havuzu
//      hedefe kadar doldurur.
//    • Havuz HAZIR olunca (≥300 soru VE ≥500 bilgi): o ülke+kademe+dildeki
//      TÜM kullanıcılar içeriği havuzdan çeker — AI devre dışı, maliyet 0,
//      açılış anında.
//    • Aynı curriculumSig'e sahip başka bir ülkenin dolu havuzu varsa CF
//      oradan kopyalar (aynı dil) veya çevirir (farklı dil) — bkz. generator.
//
//  Tekrar önleme: kullanıcının gördüğü soru/bilgi id'leri SharedPreferences
//  defterinde tutulur; havuz tükenene kadar aynı içerik tekrar gelmez.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'error_logger.dart';
import 'locale_service.dart';

/// Havuzun kimliği + üretim meta'sı. Draw da insert de aynı meta ile çağrılır.
class LabirentPoolMeta {
  final String country; // 'tr', 'de', ... (küçük harf)
  final String level; // 'primary'|'middle'|'high'|'uni'|'exam'
  final String grade; // sınıf yılı '5' — exam modunda sınav anahtarı 'lgs'
  final String? track; // alan anahtarı ('sayisal' vb.) — yoksa null
  final String lang; // içerik dili (uygulama dili)
  final String kind; // 'class' | 'exam'
  final String subjectsHint; // CF üretim prompt'u için ders+konu özeti
  final String curriculumSig; // müfredat imzası (ülkeler arası paylaşım)
  final int optionCount; // şık sayısı (3/4/5)

  LabirentPoolMeta({
    required this.country,
    required this.level,
    required this.grade,
    this.track,
    String? lang,
    required this.kind,
    required this.subjectsHint,
    required this.curriculumSig,
    required this.optionCount,
  }) : lang = lang ?? (LocaleService.global?.localeCode ?? 'tr');

  String get poolKey =>
      '${country.toLowerCase()}|$level|$grade|${track ?? '-'}|$lang';
}

class LabirentPoolService {
  LabirentPoolService._();

  static const _collection = 'labirent_pool';
  static const _seenPrefix = 'labirent_pool_seen_v1::';
  static const _cachePrefix = 'labirent_pool_cache_v1::';

  /// Cihaz cache tavanları — ilk başarılı çekişten/üretimden sonra oyun
  /// OFFLINE da açılabilsin diye içerik lokalde biriktirilir.
  static const int _cacheQuestionCap = 150;
  static const int _cacheFactCap = 250;

  /// Kullanıcının hedefi: her ülke+kademe için EN AZ bu kadar birikince havuz
  /// "hazır" sayılır ve AI devreden çıkar.
  static const int kQuestionTarget = 300;
  static const int kFactTarget = 500;

  /// Yazım tavanı — hedefin biraz üstünde durulur (kontrolsüz şişme yok).
  static const int kQuestionCap = 360;
  static const int kFactCap = 600;

  static const Duration _timeout = Duration(seconds: 8);

  /// Basit stabil FNV-1a hash — String.hashCode platform/sürüm bağımlı
  /// olduğu için kullanılmaz (doc id ve müfredat imzası her yerde aynı olmalı).
  static String stableHash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36);
  }

  /// Müfredat imzası: ders anahtarları + konu listelerinden stabil hash.
  /// Master+variant kopya müfredatlı ülkeler aynı imzayı üretir → CF havuzu
  /// ülkeler arası kopyalayabilir/çevirebilir.
  static String curriculumSigFrom(Iterable<String> parts) {
    final norm = parts.map((p) => p.trim().toLowerCase()).toList()..sort();
    return stableHash(norm.join('§'));
  }

  static DocumentReference<Map<String, dynamic>> _doc(String key) =>
      FirebaseFirestore.instance.collection(_collection).doc(key);

  // ─── Okuma: havuz hazırsa oyun paketi çek ─────────────────────────────────

  /// Havuz HAZIRSA (≥300 soru ve ≥500 bilgi) rastgele [qCount] soru +
  /// [fCount] bilgi çeker ve oyun formatında döner:
  /// {'questions': [{q,opts,a,sol,type}], 'facts': [..]}.
  /// Havuz yoksa dokümanı [meta] ile init eder (CF generator tetiklenir) ve
  /// null döner; hazır değilse null döner → caller AI yoluna düşer.
  static Future<Map<String, dynamic>?> drawBundle(
    LabirentPoolMeta meta, {
    int qCount = 24,
    int fCount = 40,
  }) async {
    try {
      final ref = _doc(meta.poolKey);
      final doc = await ref.get().timeout(_timeout);
      if (!doc.exists) {
        unawaited(_initPool(ref, meta));
        return null;
      }
      final data = doc.data() ?? const <String, dynamic>{};
      final qTotal = (data['questionCount'] as int?) ?? 0;
      final fTotal = (data['factCount'] as int?) ?? 0;
      if (qTotal < kQuestionTarget || fTotal < kFactTarget) return null;

      final rng = math.Random();
      final seen = await _readSeen(meta.poolKey);
      final qs = await _drawDocs(ref.collection('q'), qTotal, qCount, seen, rng);
      final fs = await _drawDocs(ref.collection('f'), fTotal, fCount, seen, rng);
      if (qs.isEmpty) return null;

      final questions = <Map<String, dynamic>>[];
      for (final d in qs) {
        final j = d.data();
        final opts =
            (j['opts'] as List? ?? const []).map((e) => e.toString()).toList();
        var a = (j['a'] is int) ? j['a'] as int : int.tryParse('${j['a']}') ?? 0;
        if (opts.length < 3) continue;
        if (a < 0 || a >= opts.length) a = 0;
        questions.add({
          'q': (j['q'] ?? '').toString(),
          'opts': opts,
          'a': a,
          'sol': (j['sol'] ?? '').toString(),
          'type': 'multi',
        });
      }
      if (questions.isEmpty) return null;
      final facts = [
        for (final d in fs) (d.data()['t'] ?? '').toString()
      ]..removeWhere((t) => t.trim().isEmpty);

      unawaited(_markSeen(meta.poolKey,
          [...qs.map((d) => 'q:${d.id}'), ...fs.map((d) => 'f:${d.id}')]));
      // Çekilen içeriği cihaza da yaz → sonraki açılışlar offline çalışır.
      unawaited(cacheBundle(meta, questions, facts));
      debugPrint(
          '[LabirentPool] havuzdan servis: ${questions.length} soru + ${facts.length} bilgi → ${meta.poolKey}');
      return {'questions': questions, 'facts': facts};
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'labirent_pool.draw');
      return null;
    }
  }

  /// Rastgele başlangıçlı sıralı çekim (question_pool ile aynı desen) +
  /// görülmüş filtresi. [prefix] görülmüş defter anahtarı için ('q:'/'f:').
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _drawDocs(
    CollectionReference<Map<String, dynamic>> col,
    int total,
    int count,
    Set<String> seen,
    math.Random rng,
  ) async {
    final fetch = count * 3;
    final offset = total > fetch ? rng.nextInt(total - fetch) : 0;
    final snap = await col
        .orderBy(FieldPath.documentId)
        .limit(fetch + offset)
        .get()
        .timeout(_timeout);
    final docs = snap.docs.skip(offset).toList()..shuffle(rng);
    final isFact = col.id == 'f';
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    // 1) görülmemişler; 2) yetmezse görülmüşlerle tamamla (havuz tükenmesin).
    for (final d in docs) {
      if (out.length >= count) break;
      if (seen.contains('${isFact ? 'f' : 'q'}:${d.id}')) continue;
      out.add(d);
    }
    if (out.length < count) {
      for (final d in docs) {
        if (out.length >= count) break;
        if (!out.contains(d)) out.add(d);
      }
    }
    return out;
  }

  // ─── Yazma: AI üretimini havuza kat (organik doluş) ───────────────────────

  /// AI'ın bu oturum için ürettiği paketi havuza yazar (fire-and-forget
  /// çağrılır; hata kullanıcı akışını bozmaz). Havuz doluysa (cap) yazmaz.
  /// Dedup: doc id = normalize edilmiş metnin stabil hash'i → aynı içerik
  /// ikinci kez yazılırsa üzerine biner, YENİ doc oluşmaz; sayaç yalnız
  /// gerçekten yeni doc'lar için artırılır.
  static Future<void> insertBundle(
    LabirentPoolMeta meta,
    List<Map<String, dynamic>> questions,
    List<String> facts,
  ) async {
    if (questions.isEmpty && facts.isEmpty) return;
    try {
      final ref = _doc(meta.poolKey);
      final doc = await ref.get().timeout(_timeout);
      if (!doc.exists) await _initPool(ref, meta);
      final data = doc.data() ?? const <String, dynamic>{};
      final qTotal = (data['questionCount'] as int?) ?? 0;
      final fTotal = (data['factCount'] as int?) ?? 0;

      var newQ = 0, newF = 0;
      final batch = FirebaseFirestore.instance.batch();

      if (qTotal < kQuestionCap) {
        final room = kQuestionCap - qTotal;
        for (final q in questions.take(room)) {
          final text = (q['q'] ?? '').toString().trim();
          final opts = (q['opts'] as List? ?? const [])
              .map((e) => e.toString())
              .toList();
          final a = (q['a'] is int) ? q['a'] as int : 0;
          if (text.length < 10 || opts.length < 3) continue;
          if (a < 0 || a >= opts.length) continue;
          final id = stableHash(text.toLowerCase().replaceAll(RegExp(r'\s+'), ' '));
          final qRef = ref.collection('q').doc(id);
          // Var mı kontrolü — sayaç şişmesin (yalnız doluş fazında çalışır,
          // oturum başına ≤24 okuma).
          final exists = (await qRef.get().timeout(_timeout)).exists;
          if (exists) continue;
          batch.set(qRef, {
            'q': text,
            'opts': opts,
            'a': a,
            'sol': (q['sol'] ?? '').toString(),
            'src': 'user_ai',
            'createdAt': FieldValue.serverTimestamp(),
          });
          newQ++;
        }
      }
      if (fTotal < kFactCap) {
        final room = kFactCap - fTotal;
        for (final f in facts.take(room)) {
          final t = f.trim();
          if (t.length < 10 || t.length > 380) continue;
          final id = stableHash(t.toLowerCase());
          final fRef = ref.collection('f').doc(id);
          final exists = (await fRef.get().timeout(_timeout)).exists;
          if (exists) continue;
          batch.set(fRef, {
            't': t,
            'src': 'user_ai',
            'createdAt': FieldValue.serverTimestamp(),
          });
          newF++;
        }
      }
      if (newQ == 0 && newF == 0) return;
      batch.set(ref, {
        if (newQ > 0) 'questionCount': FieldValue.increment(newQ),
        if (newF > 0) 'factCount': FieldValue.increment(newF),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      debugPrint(
          '[LabirentPool] organik doluş: +$newQ soru +$newF bilgi → ${meta.poolKey}');
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'labirent_pool.insert');
    }
  }

  // ─── Init ────────────────────────────────────────────────────────────────

  static Future<void> _initPool(
      DocumentReference<Map<String, dynamic>> ref, LabirentPoolMeta meta) async {
    try {
      await ref.set({
        'country': meta.country.toLowerCase(),
        'level': meta.level,
        'grade': meta.grade,
        'track': meta.track ?? '-',
        'lang': meta.lang,
        'kind': meta.kind,
        'subjectsHint': meta.subjectsHint,
        'curriculumSig': meta.curriculumSig,
        'optionCount': meta.optionCount,
        'questionCount': 0,
        'factCount': 0,
        'questionTarget': kQuestionTarget,
        'factTarget': kFactTarget,
        'status': 'generating',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[LabirentPool] pool init → ${meta.poolKey}');
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'labirent_pool.init');
    }
  }

  // ─── Cihaz cache'i (offline oynanış) ─────────────────────────────────────

  /// Havuzdan çekilen veya AI'ın ürettiği paketi cihazda biriktirir.
  /// Metin hash'iyle dedup edilir; tavan aşılınca en eskiler atılır.
  /// Fire-and-forget çağrılır — hata oyunu etkilemez.
  static Future<void> cacheBundle(
    LabirentPoolMeta meta,
    List<Map<String, dynamic>> questions,
    List<String> facts,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_cachePrefix${meta.poolKey}';
      Map<String, dynamic> store;
      try {
        store = jsonDecode(prefs.getString(key) ?? '{}') as Map<String, dynamic>;
      } catch (_) {
        store = <String, dynamic>{};
      }
      final q = (store['q'] as List? ?? const []).cast<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final f =
          (store['f'] as List? ?? const []).map((e) => e.toString()).toList();
      final qSeen = {for (final e in q) stableHash((e['q'] ?? '').toString())};
      for (final it in questions) {
        final h = stableHash((it['q'] ?? '').toString());
        if (qSeen.add(h)) q.add(it);
      }
      final fSeen = f.map(stableHash).toSet();
      for (final t in facts) {
        if (t.trim().isEmpty) continue;
        if (fSeen.add(stableHash(t))) f.add(t);
      }
      final qOut = q.length > _cacheQuestionCap
          ? q.sublist(q.length - _cacheQuestionCap)
          : q;
      final fOut =
          f.length > _cacheFactCap ? f.sublist(f.length - _cacheFactCap) : f;
      await prefs.setString(key, jsonEncode({'q': qOut, 'f': fOut}));
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'labirent_pool.cache');
    }
  }

  /// Offline yedek: cihazda biriken içerikten rastgele bir oyun paketi.
  /// En az 5 soru yoksa null (oyun anlamlı olmaz) → caller hata mesajı verir.
  static Future<Map<String, dynamic>?> cachedBundle(
    LabirentPoolMeta meta, {
    int qCount = 24,
    int fCount = 40,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix${meta.poolKey}');
      if (raw == null) return null;
      final store = jsonDecode(raw) as Map<String, dynamic>;
      final q = (store['q'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final f =
          (store['f'] as List? ?? const []).map((e) => e.toString()).toList();
      if (q.length < 5) return null;
      final rng = math.Random();
      q.shuffle(rng);
      f.shuffle(rng);
      debugPrint(
          '[LabirentPool] OFFLINE cache servis: ${math.min(qCount, q.length)} soru → ${meta.poolKey}');
      return {
        'questions': q.take(qCount).toList(),
        'facts': f.take(fCount).toList(),
      };
    } catch (_) {
      return null;
    }
  }

  // ─── Görülmüş defteri ────────────────────────────────────────────────────

  static Future<Set<String>> _readSeen(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('$_seenPrefix$key')?.toSet() ?? <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> _markSeen(String key, List<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList('$_seenPrefix$key') ?? [];
      seen.addAll(ids);
      final trimmed =
          seen.length > 1500 ? seen.sublist(seen.length - 1500) : seen;
      await prefs.setStringList('$_seenPrefix$key', trimmed);
    } catch (_) {}
  }
}
