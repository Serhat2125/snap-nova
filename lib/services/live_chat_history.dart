// LiveChatHistory — Karşılıklı konuşma (LiveAnalysis) geçmişi.
//
// Konuşmalar SharedPreferences'a JSON olarak yazılır → uygulama yeniden
// açıldığında ya da mod değiştiğinde geçmiş KAYBOLMAZ. Sol üstteki menü
// (☰) butonundan geçmiş sohbetler listelenir, dokununca geri yüklenir.
//
// Her oturum: id + zaman + başlık (ilk kullanıcı mesajı) + mesaj listesi.
// En yeni üstte; en fazla [_max] oturum tutulur (eskiler düşer).

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LiveChatHistoryMsg {
  final String role; // 'user' | 'ai'
  final String text;
  final int ts; // epoch ms
  const LiveChatHistoryMsg(
      {required this.role, required this.text, required this.ts});

  Map<String, dynamic> toJson() => {'r': role, 't': text, 'ts': ts};

  factory LiveChatHistoryMsg.fromJson(Map<String, dynamic> j) =>
      LiveChatHistoryMsg(
        role: (j['r'] ?? 'ai').toString(),
        text: (j['t'] ?? '').toString(),
        ts: (j['ts'] is int) ? j['ts'] as int : 0,
      );
}

class LiveChatSession {
  final String id;
  final int ts; // son güncelleme (epoch ms)
  final String title;
  final List<LiveChatHistoryMsg> messages;
  const LiveChatSession({
    required this.id,
    required this.ts,
    required this.title,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': ts,
        'title': title,
        'm': messages.map((e) => e.toJson()).toList(),
      };

  factory LiveChatSession.fromJson(Map<String, dynamic> j) => LiveChatSession(
        id: (j['id'] ?? '').toString(),
        ts: (j['ts'] is int) ? j['ts'] as int : 0,
        title: (j['title'] ?? '').toString(),
        messages: ((j['m'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => LiveChatHistoryMsg.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class LiveChatHistory {
  static const _key = 'live_chat_history_v1';
  static const _max = 40;

  /// Tüm oturumları en yeni önce döndürür.
  static Future<List<LiveChatSession>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => LiveChatSession.fromJson(e.cast<String, dynamic>()))
          .toList();
      list.sort((a, b) => b.ts.compareTo(a.ts));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Oturumu ekler/günceller (id eşleşiyorsa üzerine yazar). Boş mesajlıysa
  /// yok sayar. En yeni üste taşır, [_max] ile sınırlar.
  static Future<void> upsert(LiveChatSession session) async {
    if (session.messages.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final list = await load();
      list.removeWhere((s) => s.id == session.id);
      list.insert(0, session);
      if (list.length > _max) list.removeRange(_max, list.length);
      await p.setString(
          _key, jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> delete(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = await load();
      list.removeWhere((s) => s.id == id);
      await p.setString(
          _key, jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }
}
