// ═══════════════════════════════════════════════════════════════════════════
//  UserAvatar — uygulama genelinde TEK profil avatarı widget'ı.
//
//  Öncelik sırası (profil sayfasındaki gerçek görünümle birebir):
//   1) avatarData (base64 data-URL profil fotoğrafı) → dairesel fotoğraf
//   2) avatar alanı yanlışlıkla http(s) URL içeriyorsa → network görseli
//      (yüklenemezse 👤 fallback) — "http..." gibi HAM METİN asla görünmez
//   3) avatar emojisi (boşsa 👤)
//
//  Düello Arenası, Dünya Sıralaması, arkadaş/grup yarışları, öğretmen ve
//  ebeveyn panellerindeki öğrenci profilleri dahil avatarın göründüğü her
//  yerde bu widget kullanılır.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  /// Emoji avatar — bazı eski kayıtlarda yanlışlıkla URL olabilir.
  final String avatar;

  /// Base64 profil fotoğrafı (data:image/...;base64,...) — varsa kazanır.
  final String avatarData;

  /// Verilirse ve avatarData boşsa users/{uid}.avatarData CANLI çekilir
  /// (oturum boyunca cache'lenir) — kayıtta foto alanı olmayan eski
  /// listelerde bile gerçek profil fotoğrafı görünür.
  final String uid;

  /// Dairenin dış çapı.
  final double size;

  /// Emoji punto boyutu (verilmezse size'dan hesaplanır).
  final double? emojiSize;

  final Color? background;
  final BoxBorder? border;

  const UserAvatar({
    super.key,
    required this.avatar,
    this.avatarData = '',
    this.uid = '',
    required this.size,
    this.emojiSize,
    this.background,
    this.border,
  });

  static bool _isUrl(String s) =>
      s.startsWith('http://') || s.startsWith('https://');

  /// uid → avatarData fetch cache'i (oturum ömrü). Aynı kullanıcı birden çok
  /// listede görünse bile users/{uid} yalnız bir kez okunur.
  static final Map<String, Future<String>> _fetchCache = {};

  static Future<String> _fetchAvatarData(String uid) {
    return _fetchCache.putIfAbsent(uid, () async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 6));
        return (snap.data()?['avatarData'] ?? '').toString();
      } catch (_) {
        return '';
      }
    });
  }

  static Uint8List? _decodedBytes(String data) {
    final d = data.trim();
    if (d.isEmpty) return null;
    try {
      final b64 = d.contains(',') ? d.split(',').last : d;
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Widget _emoji(String e) => Text(
        e,
        style: TextStyle(fontSize: emojiSize ?? size * 0.52, height: 1.0),
      );

  Widget _content(String data) {
    final bytes = _decodedBytes(data);
    final a = avatar.trim();
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _emoji('👤'),
      );
    }
    if (_isUrl(a)) {
      return Image.network(
        a,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _emoji('👤'),
      );
    }
    // Uzun ham metin (bozuk kayıt) asla basılmaz — 👤 fallback.
    // Eşik 16: birleşik aile emojileri (👨‍👩‍👧 = 8 UTF-16 birim) geçer,
    // URL/metin artıkları geçmez.
    if (a.isEmpty || a.length > 16) return _emoji('👤');
    return _emoji(a);
  }

  Widget _circle(Widget child) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background,
          border: border,
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    if (avatarData.trim().isNotEmpty || uid.isEmpty) {
      return _circle(_content(avatarData));
    }
    return FutureBuilder<String>(
      future: _fetchAvatarData(uid),
      builder: (_, snap) => _circle(_content((snap.data ?? '').trim())),
    );
  }
}
