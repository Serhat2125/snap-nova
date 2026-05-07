// RAG (Retrieval-Augmented Generation) — kullanıcının ülke + sınıf
// etiketine göre yerel müfredat parçalarını vektör veritabanından çağırır
// ve prompt'a enjekte edilebilir bağlam bloğu üretir.
//
// Backend tipleri:
//   • RagBackend.none      → boş dönüş, AI kendi bilgisiyle üretir (default).
//   • RagBackend.supabase  → Supabase pgvector RPC: match_curriculum_v1.
//   • RagBackend.pinecone  → Pinecone REST: POST {indexUrl}/query.
//
// Aktivasyon: app boot'ta RagService.configure(...) çağrılır.
// secrets.dart'a dokunmuyoruz — API key politikası gereği. Kullanıcı kendi
// kurulumunda env veya farklı bir secrets kanalı tanımlayıp configure edecek.
//
// PostgreSQL şeması (Supabase Vector için referans — kullanıcı kendi
// projesinde uygulayacak):
//   create extension if not exists vector;
//   create table curriculum (
//     id bigserial primary key,
//     country text not null,        -- 'tr', 'us', 'de', ...
//     grade   text not null,        -- '12', '12. Sınıf', ...
//     subject text not null,        -- 'Biyoloji', 'Matematik'
//     source  text not null,        -- pdf dosyası / url
//     content text not null,
//     embedding vector(1536) not null
//   );
//   create or replace function match_curriculum_v1(
//     p_country text, p_grade text, p_subject text,
//     p_query_embedding vector(1536), p_top_k int default 5)
//   returns table (content text, source text, score float) ...
//
// Pinecone tarafı: index'te metadata olarak {country, grade, subject, source}
// + vector field. Sorgu Pinecone Inference API ile (veya client-side
// embedding'le) yapılır.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

enum RagBackend { none, supabase, pinecone }

class RagChunk {
  final String text;
  final String source;
  final double score;
  RagChunk({
    required this.text,
    required this.source,
    this.score = 0,
  });
}

class RagResult {
  /// Sıralı (alaka skoru azalan) bağlam parçaları.
  final List<RagChunk> chunks;

  /// true → vektör DB hiçbir parça döndürmedi veya backend kapalı.
  /// UI bunu kullanarak "Sistem genel bilgileri kullanıyor" rozetini gösterir.
  final bool usedFallback;

  /// Hata olduysa kısa açıklama (telemetri için, UI'a sızdırılmaz).
  final String? error;

  RagResult({
    required this.chunks,
    required this.usedFallback,
    this.error,
  });

  factory RagResult.fallback([String? reason]) =>
      RagResult(chunks: const [], usedFallback: true, error: reason);
}

class RagService {
  // ── Konfigürasyon (boot'ta inject edilir) ───────────────────────────────
  static RagBackend backend = RagBackend.none;
  static String? supabaseUrl;
  static String? supabaseAnonKey;
  static String? pineconeIndexUrl;
  static String? pineconeApiKey;
  static Duration timeout = Duration(seconds: 8);

  static void configure({
    RagBackend? backend,
    String? supabaseUrl,
    String? supabaseAnonKey,
    String? pineconeIndexUrl,
    String? pineconeApiKey,
    Duration? timeout,
  }) {
    if (backend != null) RagService.backend = backend;
    if (supabaseUrl != null) RagService.supabaseUrl = supabaseUrl;
    if (supabaseAnonKey != null) RagService.supabaseAnonKey = supabaseAnonKey;
    if (pineconeIndexUrl != null) RagService.pineconeIndexUrl = pineconeIndexUrl;
    if (pineconeApiKey != null) RagService.pineconeApiKey = pineconeApiKey;
    if (timeout != null) RagService.timeout = timeout;
  }

  /// Müfredat parçalarını çek — country/grade/subject ile filtrelenmiş,
  /// topic ile semantik benzerlik. Backend 'none' ise boş dönüş + fallback.
  static Future<RagResult> fetchCurriculumChunks({
    required String country,
    required String grade,
    required String subject,
    required String topic,
    int topK = 5,
  }) async {
    if (backend == RagBackend.none) {
      return RagResult.fallback('rag_disabled');
    }
    final query = '$subject — $topic';
    try {
      switch (backend) {
        case RagBackend.supabase:
          return await _querySupabase(country, grade, subject, query, topK);
        case RagBackend.pinecone:
          return await _queryPinecone(country, grade, subject, query, topK);
        case RagBackend.none:
          return RagResult.fallback('rag_disabled');
      }
    } on TimeoutException {
      return RagResult.fallback('timeout');
    } catch (e) {
      dev.log('RagService error: $e', name: 'rag');
      return RagResult.fallback('error');
    }
  }

  /// Çekilen chunk'ları prompt'a enjekte edilebilir tek metne çevirir.
  /// Boş ise null döner — caller fallback uyarısı ekler.
  static String? buildContextBlock(RagResult result) {
    if (result.chunks.isEmpty) return null;
    final sb = StringBuffer();
    sb.writeln('[MÜFREDAT VERİSİ — RAG]');
    for (var i = 0; i < result.chunks.length; i++) {
      final c = result.chunks[i];
      final src = c.source.isNotEmpty ? c.source : 'kaynak#${i + 1}';
      sb.writeln('--- KAYNAK ${i + 1} ($src) ---');
      sb.writeln(c.text.trim());
      sb.writeln();
    }
    sb.writeln('[Yukarıdaki MÜFREDAT VERİSİ senin BİRİNCİL kaynağındır. '
        'Mümkün olan her yerde bu veriden alıntıla; eksik kaldığı yerde '
        'genel bilgini kullan ve "(genel bilgi)" notuyla işaretle.]');
    return sb.toString();
  }

  // ── Supabase pgvector ──────────────────────────────────────────────────
  static Future<RagResult> _querySupabase(
    String country,
    String grade,
    String subject,
    String query,
    int topK,
  ) async {
    final url = supabaseUrl;
    final key = supabaseAnonKey;
    if (url == null || key == null) {
      return RagResult.fallback('supabase_unconfigured');
    }
    // Edge Function veya SQL RPC: query metnini server-side embedding'liyor,
    // similarity döndürüyor. Müşteri tarafında embedding üretmiyoruz.
    final res = await http
        .post(
          Uri.parse('$url/rest/v1/rpc/match_curriculum_v1'),
          headers: {
            'apikey': key,
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'p_country': country,
            'p_grade': grade,
            'p_subject': subject,
            'p_query': query,
            'p_top_k': topK,
          }),
        )
        .timeout(timeout);
    if (res.statusCode != 200) {
      return RagResult.fallback('supabase_${res.statusCode}');
    }
    final raw = jsonDecode(res.body);
    final list = raw is List ? raw : const [];
    final chunks = list
        .whereType<Map>()
        .map((e) => RagChunk(
              text: (e['content'] ?? '').toString(),
              source: (e['source'] ?? '').toString(),
              score: ((e['score'] as num?) ?? 0).toDouble(),
            ))
        .where((c) => c.text.trim().isNotEmpty)
        .toList();
    return RagResult(chunks: chunks, usedFallback: chunks.isEmpty);
  }

  // ── Pinecone REST ──────────────────────────────────────────────────────
  static Future<RagResult> _queryPinecone(
    String country,
    String grade,
    String subject,
    String query,
    int topK,
  ) async {
    final url = pineconeIndexUrl;
    final key = pineconeApiKey;
    if (url == null || key == null) {
      return RagResult.fallback('pinecone_unconfigured');
    }
    // Pinecone Inference API ile server-side embedding (model integrated).
    // Eğer index'te embedding integrated değilse, kullanıcı buradaki
    // payload'ı kendi embedding pipeline'ına göre uyarlayacak.
    final res = await http
        .post(
          Uri.parse('$url/query'),
          headers: {
            'Api-Key': key,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'topK': topK,
            'includeMetadata': true,
            'filter': {
              'country': country,
              'grade': grade,
              'subject': subject,
            },
            'inputs': {'text': query},
          }),
        )
        .timeout(timeout);
    if (res.statusCode != 200) {
      return RagResult.fallback('pinecone_${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final matches = (body['matches'] as List?) ?? const [];
    final chunks = matches
        .whereType<Map>()
        .map((m) {
          final meta = (m['metadata'] as Map?) ?? const {};
          return RagChunk(
            text: (meta['content'] ?? '').toString(),
            source: (meta['source'] ?? '').toString(),
            score: ((m['score'] as num?) ?? 0).toDouble(),
          );
        })
        .where((c) => c.text.trim().isNotEmpty)
        .toList();
    return RagResult(chunks: chunks, usedFallback: chunks.isEmpty);
  }
}
