// ═══════════════════════════════════════════════════════════════════════════
//  AICoachChatScreen — Öğrenci ile AI Koç birebir sohbet ekranı.
//
//  • Çoklu sohbet desteği — kullanıcı birden fazla konuşma açabilir, geçmiş
//    drawer'dan açılır, istediği sohbete geçer.
//  • Sabitleme (pin) — önemli sohbetler en üstte kalır.
//  • Yeniden adlandır + sil — uzun basınca menü açılır.
//  • Otomatik başlık — ilk kullanıcı mesajından üretilir (40 kar kırpılı).
//  • Tüm veri SharedPreferences (ai_coach_chats_meta_v1 + ai_coach_chat_{id}).
//    Eski tek-konuşma cache'i (ai_coach_chat_v1) ilk açılışta otomatik migrate.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import '../services/ai_quota_service.dart';
import 'premium_screen.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show localeService;
import '../services/analytics.dart';
import '../services/education_profile.dart';
import '../services/gemini_service.dart';
import '../services/runtime_translator.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';

// ───────────────────────────────────────────────────────────────────────────
// Models
// ───────────────────────────────────────────────────────────────────────────

class _ChatMessage {
  final bool isUser;
  final String text;
  final DateTime time;
  _ChatMessage({required this.isUser, required this.text, required this.time});

  Map<String, dynamic> toJson() => {
        'u': isUser,
        't': text,
        'd': time.millisecondsSinceEpoch,
      };
  factory _ChatMessage.fromJson(Map<String, dynamic> m) => _ChatMessage(
        isUser: (m['u'] ?? true) == true,
        text: (m['t'] ?? '').toString(),
        time: DateTime.fromMillisecondsSinceEpoch(m['d'] ?? 0),
      );
}

class _ChatMeta {
  String id;
  String title;
  bool pinned;
  int updatedMs;
  int createdMs;
  String preview; // son mesajın kısa önizlemesi (drawer subtitle)

  _ChatMeta({
    required this.id,
    required this.title,
    this.pinned = false,
    required this.updatedMs,
    required this.createdMs,
    this.preview = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        't': title,
        'p': pinned,
        'u': updatedMs,
        'c': createdMs,
        'pv': preview,
      };
  factory _ChatMeta.fromJson(Map<String, dynamic> m) => _ChatMeta(
        id: (m['id'] ?? '').toString(),
        title: (m['t'] ?? 'Yeni Sohbet'.tr()).toString(),
        pinned: (m['p'] ?? false) == true,
        updatedMs: (m['u'] ?? 0) as int,
        createdMs: (m['c'] ?? 0) as int,
        preview: (m['pv'] ?? '').toString(),
      );
}

// ───────────────────────────────────────────────────────────────────────────
// Storage helper
// ───────────────────────────────────────────────────────────────────────────

class _ChatStore {
  static const _kMetaKey = 'ai_coach_chats_meta_v1';
  static const _kCurrentIdKey = 'ai_coach_current_chat_id_v1';
  static const _kLegacyKey = 'ai_coach_chat_v1';
  static String _msgKey(String id) => 'ai_coach_chat_$id';

  static Future<List<_ChatMeta>> loadMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kMetaKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => _ChatMeta.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMeta(List<_ChatMeta> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kMetaKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static Future<List<_ChatMessage>> loadMessages(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_msgKey(id));
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => _ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMessages(
      String id, List<_ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    // Son 80 mesaj cache'lenir (token tasarrufu zaten history'de yapılır).
    final tail = messages.length > 80
        ? messages.sublist(messages.length - 80)
        : messages;
    await prefs.setString(
        _msgKey(id), jsonEncode(tail.map((e) => e.toJson()).toList()));
  }

  static Future<String?> getCurrentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCurrentIdKey);
  }

  static Future<void> setCurrentId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrentIdKey, id);
  }

  static Future<void> deleteChat(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_msgKey(id));
    final metas = await loadMeta();
    metas.removeWhere((m) => m.id == id);
    await saveMeta(metas);
  }

  /// Eski tek-sohbet anahtarını yeni şemaya taşı (idempotent).
  static Future<void> migrateLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLegacyKey);
    if (raw == null || raw.isEmpty) return;
    final metas = await loadMeta();
    if (metas.isNotEmpty) {
      // Yeni şema doluysa eski'yi sil, tekrar import etme.
      await prefs.remove(_kLegacyKey);
      return;
    }
    try {
      final msgs = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => _ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (msgs.isEmpty) {
        await prefs.remove(_kLegacyKey);
        return;
      }
      final id = _generateId();
      final firstUser = msgs.firstWhere(
        (m) => m.isUser,
        orElse: () => msgs.first,
      );
      final title = _autoTitle(firstUser.text);
      final now = DateTime.now().millisecondsSinceEpoch;
      final meta = _ChatMeta(
        id: id,
        title: title,
        updatedMs: now,
        createdMs: msgs.first.time.millisecondsSinceEpoch,
        preview: msgs.last.text.split('\n').first,
      );
      await saveMessages(id, msgs);
      await saveMeta([meta]);
      await setCurrentId(id);
      await prefs.remove(_kLegacyKey);
    } catch (_) {
      await prefs.remove(_kLegacyKey);
    }
  }

  static String _generateId() {
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final r = math.Random()
        .nextInt(0xFFFFFF)
        .toRadixString(36)
        .padLeft(4, '0');
    return 'c_${t}_$r';
  }
}

String _autoTitle(String text) {
  final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.length <= 38) return clean.isEmpty ? 'Yeni Sohbet'.tr() : clean;
  return '${clean.substring(0, 38)}…';
}

// ───────────────────────────────────────────────────────────────────────────
// Screen
// ───────────────────────────────────────────────────────────────────────────

class AICoachChatScreen extends StatefulWidget {
  const AICoachChatScreen({super.key});

  @override
  State<AICoachChatScreen> createState() => _AICoachChatScreenState();
}

class _AICoachChatScreenState extends State<AICoachChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Chat state
  List<_ChatMeta> _chats = [];
  _ChatMeta? _current;
  List<_ChatMessage> _messages = [];
  bool _sending = false;
  bool _booting = true;

  // Profile context
  String? _userName;
  String? _gradeLabel;

  // Drawer chat search filter
  final _searchCtrl = TextEditingController();
  String _search = '';

  /// Tüm öneri promptları — 15 farklı seçenek. initState'te 5'i random
  /// seçilir; her sohbet açılışında farklı 5 görünür.
  static const _allSuggestions = <(String, String)>[
    ('🎯', 'Çalışma planı hazırla'),
    ('🧠', 'Verimli ders çalışma teknikleri öner'),
    ('💪', 'Motivasyona ihtiyacım var'),
    ('📚', 'Sınava nasıl hazırlanırım?'),
    ('⏱️', 'Zamanımı nasıl daha iyi yönetirim?'),
    ('😰', 'Sınav kaygısıyla nasıl başa çıkarım?'),
    ('🌙', 'Uyku düzenimi nasıl iyileştiririm?'),
    ('📖', 'Hızlı okuma teknikleri'),
    ('✏️', 'Etkili not alma yöntemleri'),
    ('🧘', 'Konsantrasyonumu nasıl artırırım?'),
    ('🎓', 'Hangi bölüme yönelmeliyim?'),
    ('🔥', 'Çalışma isteğim düştü, yardım et'),
    ('⚡', 'Pomodoro tekniği nasıl uygulanır?'),
    ('📊', 'Test analizimi nasıl yaparım?'),
    ('☕', 'Bugün için kısa bir hedef belirle'),
  ];

  /// Her sohbet açılışında random seçilen 5 öneri.
  late final List<(String, String)> _suggestions;

  // Ücretsiz koç süresi (hub ile tutarlı: 5 dk). Dolunca sohbet de premium
  // gate'ine takılır — önceden chat ekranı bu limiti baypas ediyordu.
  Timer? _freeTimer;
  bool _freeExpired = false;

  @override
  void initState() {
    super.initState();
    Analytics.logFeatureOpen('ai_coach');
    // 15 öneri arasından random 5 seç — her açılışta farklı.
    final shuffled = List<(String, String)>.from(_allSuggestions)
      ..shuffle(math.Random());
    _suggestions = shuffled.take(5).toList();
    _bootstrap();
    if (!AiQuotaService.instance.isPremium) {
      _freeTimer = Timer(const Duration(minutes: 5), () {
        if (!mounted) return;
        setState(() => _freeExpired = true);
        _showCoachPremiumSheet();
      });
    }
  }

  @override
  void dispose() {
    _freeTimer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showCoachPremiumSheet() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFEC4899)]),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 32),
            ),
            const SizedBox(height: 16),
            Text('Premium\'a Geç'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
            const SizedBox(height: 8),
            Text(
              '5 dakikalık ücretsiz AI Koç süren doldu.\nSınırsız sohbet için Premium\'a geç.'
                  .tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PremiumScreen()));
                },
                child: Text('Premium\'a Geç'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).maybePop();
              },
              child: Text('Geri Dön'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.black38)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bootstrap() async {
    await _ChatStore.migrateLegacy();
    await _loadProfile();
    final metas = await _ChatStore.loadMeta();
    _chats = metas;
    _sortChats();
    final savedId = await _ChatStore.getCurrentId();
    _ChatMeta? current;
    if (savedId != null) {
      current = _chats.firstWhere(
        (m) => m.id == savedId,
        orElse: () => _chats.isNotEmpty ? _chats.first : _emptyMeta(),
      );
      if (current.id.isEmpty) current = null;
    }
    current ??= _chats.isNotEmpty ? _chats.first : null;
    // Hiç sohbet yok — taze bir tane oluştur.
    current ??= await _createNewChatInternal(saveCurrent: true);
    await _loadMessagesFor(current);
    if (!mounted) return;
    setState(() {
      _booting = false;
    });
  }

  _ChatMeta _emptyMeta() => _ChatMeta(
        id: '',
        title: '',
        updatedMs: 0,
        createdMs: 0,
      );

  void _sortChats() {
    _chats.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedMs.compareTo(a.updatedMs);
    });
  }

  Future<void> _loadProfile() async {
    final name = UserProfileService.instance.username;
    String? grade;
    try {
      final p = await EduProfile.load();
      if (p != null) {
        grade = _humanGradeLabel(p.level, p.grade, p.faculty);
      }
    } catch (_) {}
    _userName = name.isEmpty ? null : name;
    _gradeLabel = grade;
  }

  /// EduProfile level/grade kodlarını AI'nın net anlayacağı Türkçe etikete
  /// çevirir. Örn: ("primary","3",null) → "İlkokul 3. sınıf (9 yaş civarı)"
  String _humanGradeLabel(String level, String grade, String? faculty) {
    final lvl = level.toLowerCase();
    final g = grade.trim();
    switch (lvl) {
      case 'primary':
        // int.tryParse(g)! null-assertion'ı sayısal olmayan sınıfta çökerdi +
        // operatör önceliği hatası (ternary işlevsizdi). Güvenli hale getirildi.
        final n = int.tryParse(g) ?? 3;
        return 'İlkokul $g. sınıf (yaklaşık ${5 + n} yaş)';
      case 'middle':
        return 'Ortaokul $g. sınıf (yaklaşık ${9 + (int.tryParse(g) ?? 5)} yaş)';
      case 'high':
        return 'Lise $g. sınıf (yaklaşık ${13 + (int.tryParse(g) ?? 9)} yaş)';
      case 'exam_prep':
        // grade içeriği: YKS, LGS, TYT vb.
        return 'Sınav hazırlığı: $g (yoğun deneme + analiz dönemi)';
      case 'university':
        final fac = (faculty ?? '').isEmpty ? '' : ', $faculty';
        return 'Üniversite $g. sınıf$fac';
      case 'masters':
        return 'Yüksek lisans${(faculty ?? '').isEmpty ? '' : ' ($faculty)'}';
      case 'doctorate':
        return 'Doktora${(faculty ?? '').isEmpty ? '' : ' ($faculty)'}';
      case 'other':
        return 'Yetişkin / kişisel öğrenme';
      default:
        return '$level $g';
    }
  }

  Future<void> _loadMessagesFor(_ChatMeta meta) async {
    _current = meta;
    await _ChatStore.setCurrentId(meta.id);
    final msgs = await _ChatStore.loadMessages(meta.id);
    if (msgs.isEmpty) {
      msgs.add(_ChatMessage(
        isUser: false,
        text:
            'Merhaba! Ben senin AI Koçunum. Hangi konuda yardıma ihtiyacın var? '
                    'Bir derste mi zorlanıyorsun, planlama mı gerekli, motivasyon mu istersin?'
                .tr(),
        time: DateTime.now(),
      ));
    }
    _messages = msgs;
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  Future<_ChatMeta> _createNewChatInternal({bool saveCurrent = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final meta = _ChatMeta(
      id: _ChatStore._generateId(),
      title: 'Yeni Sohbet'.tr(),
      updatedMs: now,
      createdMs: now,
    );
    _chats.insert(0, meta);
    _sortChats();
    await _ChatStore.saveMeta(_chats);
    if (saveCurrent) await _ChatStore.setCurrentId(meta.id);
    return meta;
  }

  Future<void> _createNewChat() async {
    final meta = await _createNewChatInternal(saveCurrent: true);
    await _loadMessagesFor(meta);
    if (!mounted) return;
    Navigator.of(context).maybePop(); // drawer kapanır
  }

  /// Mevcut sohbetin mesajlarını temizle (sohbet kalır, başa döner).
  /// Sabitleme/başlık korunur; sadece konuşma sıfırlanır.
  Future<void> _clearCurrentChat() async {
    final c = _current;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Sohbeti temizle?'.tr()),
        content: Text(
            'Bu sohbetteki tüm mesajlar silinir. Sohbet baştan başlar.'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Temizle'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _messages.clear();
    });
    // Karşılama mesajını tekrar ekle, kaydet.
    _messages.add(_ChatMessage(
      isUser: false,
      text:
          'Merhaba! Ben senin AI Koçunum. Hangi konuda yardıma ihtiyacın var? '
                  'Bir derste mi zorlanıyorsun, planlama mı gerekli, motivasyon mu istersin?'
              .tr(),
      time: DateTime.now(),
    ));
    c.preview = '';
    c.updatedMs = DateTime.now().millisecondsSinceEpoch;
    _sortChats();
    await _ChatStore.saveMessages(c.id, _messages);
    await _ChatStore.saveMeta(_chats);
    if (mounted) setState(() {});
  }

  Future<void> _switchChat(_ChatMeta meta) async {
    if (meta.id == _current?.id) {
      Navigator.of(context).maybePop();
      return;
    }
    await _loadMessagesFor(meta);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _persistCurrent() async {
    final c = _current;
    if (c == null) return;
    await _ChatStore.saveMessages(c.id, _messages);
    // Meta güncelle (preview + updated + auto-title gerekirse)
    c.updatedMs = DateTime.now().millisecondsSinceEpoch;
    c.preview = _messages.isEmpty
        ? ''
        : _messages.last.text.split('\n').first.trim();
    if (c.title == 'Yeni Sohbet' || c.title.isEmpty) {
      final firstUser = _messages.firstWhere(
        (m) => m.isUser,
        orElse: () => _ChatMessage(isUser: false, text: '', time: DateTime.now()),
      );
      if (firstUser.text.isNotEmpty) {
        c.title = _autoTitle(firstUser.text);
      }
    }
    _sortChats();
    await _ChatStore.saveMeta(_chats);
  }

  // ── Send ───────────────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    // Ücretsiz süre dolduysa premium gate (hub ile tutarlı; baypas kapatıldı).
    if (_freeExpired && !AiQuotaService.instance.isPremium) {
      _showCoachPremiumSheet();
      return;
    }
    setState(() {
      _messages.add(_ChatMessage(
        isUser: true,
        text: text,
        time: DateTime.now(),
      ));
      _ctrl.clear();
      _sending = true;
    });
    // Kullanıcı mesajı görünür olsun — sohbet en alta kayar.
    _scrollToBottom();
    unawaited(_persistCurrent());

    try {
      final history = _messages
          .sublist(0, _messages.length - 1)
          .map((m) => {
                'role': m.isUser ? 'user' : 'coach',
                'text': m.text,
              })
          .toList();
      final tail = history.length > 12
          ? history.sublist(history.length - 12)
          : history;
      final reply = await GeminiService.chatWithCoach(
        userMessage: text,
        history: tail,
        userName: _userName,
        gradeLabel: _gradeLabel,
        langCode: localeService.localeCode,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          isUser: false,
          text: reply.isEmpty
              ? 'Şu an cevap üretemiyorum, az sonra tekrar dener misin?'.tr()
              : reply,
          time: DateTime.now(),
        ));
        _sending = false;
      });
      // AI cevabı geldi — WhatsApp gibi: sohbet EN ALTA kayar, cevap tam
      // görünür (eski "soruyu üste hizala" davranışı uzun cevabı ekran
      // dışında bırakıyordu).
      _scrollToBottom();
      unawaited(_persistCurrent());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          isUser: false,
          text:
              'Bağlantı sorunu — internet veya sunucu erişilemiyor. Tekrar dener misin?'
                  .tr(),
          time: DateTime.now(),
        ));
        _sending = false;
      });
      _scrollToBottom();
    }
  }

  /// WhatsApp davranışı: her yeni mesajda (kullanıcı + AI) sohbet EN ALTA
  /// kayar. Uzun AI cevaplarında layout bir sonraki frame'de büyüyebildiği
  /// için hedef İKİ frame üst üste doğrulanır — tek animateTo maxExtent'i
  /// eski (küçük) değerle yakalayıp cevabı yarıda bırakabiliyordu.
  void _scrollToBottom() {
    void go() {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      go();
      // Markdown/uzun metin bir frame sonra ek yükseklik kazanabilir —
      // ikinci geçiş son konumu garantiler.
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    });
  }

  // ── Long-press menu actions ────────────────────────────────────────────
  Future<void> _openChatMenu(_ChatMeta meta) async {
    final ink = AppPalette.textPrimary(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Text(
                meta.title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: Icon(
                meta.pinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                color: const Color(0xFF7C3AED),
              ),
              title: Text(
                meta.pinned ? 'Sabitlemeyi kaldır'.tr() : 'Sabitle'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600, color: ink),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _togglePin(meta);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded,
                  color: Color(0xFF2563EB)),
              title: Text(
                'Yeniden adlandır'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600, color: ink),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _renameChat(meta);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444)),
              title: Text(
                'Sil'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFEF4444),
                ),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _deleteChat(meta);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePin(_ChatMeta meta) async {
    meta.pinned = !meta.pinned;
    _sortChats();
    await _ChatStore.saveMeta(_chats);
    if (mounted) setState(() {});
  }

  Future<void> _renameChat(_ChatMeta meta) async {
    final tc = TextEditingController(text: meta.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Yeniden adlandır'.tr()),
        content: TextField(
          controller: tc,
          autofocus: true,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          decoration: InputDecoration(
            hintText: 'Sohbet adı'.tr(),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(tc.text.trim()),
            child: Text('Kaydet'.tr()),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty) return;
    meta.title = newTitle;
    await _ChatStore.saveMeta(_chats);
    if (mounted) setState(() {});
  }

  Future<void> _deleteChat(_ChatMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Sohbeti sil?'.tr()),
        content: Text(
            '"${meta.title}" silinecek. Bu işlem geri alınamaz.'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Sil'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _ChatStore.deleteChat(meta.id);
    _chats.removeWhere((m) => m.id == meta.id);
    if (_current?.id == meta.id) {
      if (_chats.isEmpty) {
        final fresh = await _createNewChatInternal(saveCurrent: true);
        await _loadMessagesFor(fresh);
      } else {
        await _loadMessagesFor(_chats.first);
      }
    } else {
      if (mounted) setState(() {});
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppPalette.bg(context),
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.menu_rounded,
              color: AppPalette.textPrimary(context)),
          tooltip: 'Sohbetler'.tr(),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.support_agent_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('AI Koç'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context),
                      )),
                  Text('uzman rehber & koç'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textSecondary(context),
                      )),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sohbeti temizle'.tr(),
            icon: Icon(Icons.delete_outline_rounded,
                color: AppPalette.textSecondary(context)),
            onPressed: (_booting || _current == null)
                ? null
                : _clearCurrentChat,
          ),
        ],
      ),
      body: _booting
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _isEmptyConversation
                      ? _buildWelcomeView()
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                          itemCount: _messages.length + (_sending ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (_sending && i == _messages.length) {
                              return _bubble(
                                isUser: false,
                                child: _TypingDots(),
                              );
                            }
                            final m = _messages[i];
                            return GestureDetector(
                              onLongPress: () => _openMessageMenu(m),
                              child: _bubble(
                                isUser: m.isUser,
                                child: m.isUser
                                    ? SelectableText(
                                        m.text,
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Colors.white,
                                          height: 1.45,
                                        ),
                                      )
                                    : _coachMarkdown(m.text),
                              ),
                            );
                          },
                        ),
                ),
                _buildInputBar(),
              ],
            ),
    );
  }

  /// Sohbet "boş mu" — sadece varsayılan karşılama mesajı varsa boş sayılır.
  bool get _isEmptyConversation {
    if (_messages.length != 1) return false;
    return !_messages.first.isUser;
  }

  /// Boş sohbet ekranı:
  ///  • Üstte küçük gradient avatar + tek satır karşılama
  ///  • Ortada flexible boşluk
  ///  • Altta (input'un hemen üstünde) 5 öneri chip'i — çerçevesiz, beyaz
  ///  • Arka plan hafif soluk beyaz; chip içi tam beyaz
  ///  • Klavye açıkken bile 5 chip görünür (compact tasarım)
  Widget _buildWelcomeView() {
    final ink = AppPalette.textPrimary(context);
    // İnterpolasyon DIŞINDA .tr() — RuntimeTranslator cache çalışsın diye
    // sabit string'i çevir, sonra kullanıcı adını ekle.
    final hello = 'Merhaba!'.tr();
    final greeting = (_userName != null && _userName!.isNotEmpty)
        ? '${hello.replaceAll('!', '')} ${_userName!}!'
        : hello;
    return Container(
      // Hafif soluk beyaz arka plan
      color: const Color(0xFFFAFAFA),
      child: Column(
        children: [
          // ── Karşılama (üstte, kompakt) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.support_agent_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  greeting,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // ── Öneri chip'leri (input'un hemen üstünde) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in _suggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _suggestionChip(s.$1, s.$2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionChip(String emoji, String label) {
    final ink = AppPalette.textPrimary(context);
    // Dil değişikliğinde RuntimeTranslator label'ı kullanıcının diline çevirir.
    // Hem gösterilen metin hem AI'ya gönderilen prompt çevrilmiş olur.
    final translated = label.tr();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _ctrl.text = translated;
          _send();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  translated,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ink,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mesaja uzun basınca açılan menü — kopyala + paylaş.
  Future<void> _openMessageMenu(_ChatMessage m) async {
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded,
                  color: Color(0xFF7C3AED)),
              title: Text('Mesajı kopyala'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textPrimary(context),
                  )),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Clipboard.setData(ClipboardData(text: m.text));
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(
                  content: Text('Mesaj kopyalandı'.tr()),
                  behavior: SnackBarBehavior.floating,
                ));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Drawer'daki sohbetleri tarih grubuna göre ayır:
  /// "Sabitlenenler", "Bugün", "Dün", "Son 7 gün", "Daha önce".
  /// Search filtresi aktifse gruplar uygulanmadan düz liste döner.
  List<(String?, List<_ChatMeta>)> _groupChatsForDrawer() {
    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _chats
        : _chats
            .where((c) =>
                c.title.toLowerCase().contains(q) ||
                c.preview.toLowerCase().contains(q))
            .toList();
    if (q.isNotEmpty) {
      return [(null, filtered)];
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastWeek = today.subtract(const Duration(days: 7));
    final pinned = <_ChatMeta>[];
    final todayList = <_ChatMeta>[];
    final yesterdayList = <_ChatMeta>[];
    final weekList = <_ChatMeta>[];
    final olderList = <_ChatMeta>[];
    for (final c in filtered) {
      if (c.pinned) {
        pinned.add(c);
        continue;
      }
      final d = DateTime.fromMillisecondsSinceEpoch(c.updatedMs);
      final dd = DateTime(d.year, d.month, d.day);
      if (!dd.isBefore(today)) {
        todayList.add(c);
      } else if (!dd.isBefore(yesterday)) {
        yesterdayList.add(c);
      } else if (!dd.isBefore(lastWeek)) {
        weekList.add(c);
      } else {
        olderList.add(c);
      }
    }
    return [
      if (pinned.isNotEmpty) ('Sabitlenenler'.tr(), pinned),
      if (todayList.isNotEmpty) ('Bugün'.tr(), todayList),
      if (yesterdayList.isNotEmpty) ('Dün'.tr(), yesterdayList),
      if (weekList.isNotEmpty) ('Son 7 gün'.tr(), weekList),
      if (olderList.isNotEmpty) ('Daha önce'.tr(), olderList),
    ];
  }

  // ── Drawer ─────────────────────────────────────────────────────────────
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppPalette.bg(context),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.support_agent_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sohbetler'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _createNewChat,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7C3AED)
                              .withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.add_rounded,
                            color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Yeni Sohbet'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Arama çubuğu — drawer içinde sohbet filtresi
            if (_chats.length > 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppPalette.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppPalette.border(context), width: 1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          size: 18,
                          color: AppPalette.textSecondary(context)),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) =>
                              setState(() => _search = v),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: AppPalette.textPrimary(context),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Sohbet ara…'.tr(),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppPalette.textSecondary(context),
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      if (_search.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _search = '');
                          },
                          child: Icon(Icons.close_rounded,
                              size: 16,
                              color: AppPalette.textSecondary(context)),
                        ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: Builder(builder: (ctx) {
                final groups = _groupChatsForDrawer();
                final isEmpty = groups.isEmpty ||
                    groups.every((g) => g.$2.isEmpty);
                if (isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _search.isEmpty
                            ? 'Henüz sohbet yok'.tr()
                            : 'Sonuç bulunamadı'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: AppPalette.textSecondary(context),
                        ),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: groups.fold<int>(
                      0,
                      (sum, g) =>
                          sum +
                          g.$2.length +
                          (g.$1 == null ? 0 : 1)),
                  itemBuilder: (ctx, idx) {
                    int cursor = 0;
                    for (final g in groups) {
                      final hasHeader = g.$1 != null;
                      if (hasHeader) {
                        if (idx == cursor) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(
                                14, 10, 14, 6),
                            child: Text(
                              g.$1!,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: AppPalette.textSecondary(context),
                              ),
                            ),
                          );
                        }
                        cursor++;
                      }
                      final end = cursor + g.$2.length;
                      if (idx < end) {
                        return _drawerItem(g.$2[idx - cursor]);
                      }
                      cursor = end;
                    }
                    return const SizedBox.shrink();
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(_ChatMeta meta) {
    final selected = meta.id == _current?.id;
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _switchChat(meta),
        onLongPress: () => _openChatMenu(meta),
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF7C3AED).withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF7C3AED).withValues(alpha: 0.35)
                  : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              if (meta.pinned)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.push_pin_rounded,
                      size: 14, color: const Color(0xFF7C3AED)),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      meta.title.isEmpty ? 'Yeni Sohbet'.tr() : meta.title,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.preview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          meta.preview,
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.more_horiz_rounded,
                    color: muted, size: 18),
                onPressed: () => _openChatMenu(meta),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bubble + markdown ──────────────────────────────────────────────────
  Widget _coachMarkdown(String text) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final base = GoogleFonts.poppins(
      fontSize: 14,
      color: ink,
      height: 1.5,
    );
    return MarkdownBody(
      data: text,
      shrinkWrap: true,
      selectable: true,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: base,
        strong: base.copyWith(fontWeight: FontWeight.w800, color: ink),
        em: base.copyWith(
            fontStyle: FontStyle.italic, color: const Color(0xFF7C3AED)),
        h1: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF7C3AED),
          height: 1.3,
        ),
        h2: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF7C3AED),
          height: 1.3,
        ),
        h3: GoogleFonts.poppins(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFEC4899),
          height: 1.3,
        ),
        listBullet: base,
        listIndent: 18,
        blockquote: base.copyWith(color: muted, fontStyle: FontStyle.italic),
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: const Color(0xFF7C3AED), width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        code: GoogleFonts.firaCode(
          fontSize: 12.5,
          color: ink,
          backgroundColor: AppPalette.border(context).withValues(alpha: 0.4),
        ),
        tableHead: base.copyWith(fontWeight: FontWeight.w800),
        tableBody: base,
        tableBorder: TableBorder.all(
          color: AppPalette.border(context),
          width: 1,
          borderRadius: BorderRadius.circular(6),
        ),
        tableCellsPadding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 6),
        tableColumnWidth: const IntrinsicColumnWidth(),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppPalette.border(context), width: 1),
          ),
        ),
        a: base.copyWith(
            color: const Color(0xFF2563EB),
            decoration: TextDecoration.underline),
      ),
    );
  }

  Widget _bubble({required bool isUser, required Widget child}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
          decoration: BoxDecoration(
            gradient: isUser
                ? const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isUser ? null : AppPalette.card(context),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
            border: isUser
                ? null
                : Border.all(color: AppPalette.border(context), width: 1),
            boxShadow: [
              BoxShadow(
                color: (isUser
                        ? const Color(0xFF7C3AED)
                        : Colors.black)
                    .withValues(alpha: isUser ? 0.18 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          border: Border(
            top: BorderSide(color: AppPalette.border(context), width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppPalette.bg(context),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color: AppPalette.border(context), width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 800,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(800),
                  ],
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: AppPalette.textPrimary(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'AI Koç\'a yaz…'.tr(),
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      color: AppPalette.textSecondary(context),
                    ),
                    border: InputBorder.none,
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _sending ? null : _send,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Mavi gradient (kullanıcı talebi)
                    gradient: _sending
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                          ),
                    color: _sending
                        ? AppPalette.textSecondary(context)
                            .withValues(alpha: 0.3)
                        : null,
                    boxShadow: _sending
                        ? null
                        : [
                            BoxShadow(
                              color: const Color(0xFF2563EB)
                                  .withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  // Ok 45° sola (counter-clockwise) — sağ → kuzeydoğu görünümü.
                  child: Transform.rotate(
                    angle: -math.pi / 4,
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 18,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final t = ((_ctl.value + i * 0.18) % 1.0);
              final scale = 0.7 + 0.5 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.85),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
