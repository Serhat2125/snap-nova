// ═══════════════════════════════════════════════════════════════════════════════
//  InviteAcceptScreen — Davet linkinden açılan ekran.
//
//  Akış:
//    1. Deep link `qualsar.app/davet/{username}` tıklanır.
//    2. DeepLinkService.pendingInvite = username.
//    3. main.dart navigatorKey üzerinden bu ekran push'lanır.
//    4. Ekran: davet eden kullanıcının profilini gösterir + "Arkadaş Ekle" CTA.
//    5. Auth yoksa önce login'e yönlendirir; oturum sonrası geri gelir.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/contest_group_service.dart';
import '../services/friend_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'group_contest_screen.dart';

class InviteAcceptScreen extends StatefulWidget {
  final String username;
  const InviteAcceptScreen({super.key, required this.username});

  @override
  State<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends State<InviteAcceptScreen> {
  FriendUser? _user;
  bool _loading = true;
  bool _sending = false;
  String? _result;

  /// Davet eden kişiden BEKLEYEN bir grup yarışı daveti varsa buraya gelir —
  /// ekran "yarışma daveti" moduna geçer: CTA "Yarışma İsteğini Kabul Et"
  /// olur ve kabulde yarışma (grubun ORTAK sorularıyla) doğrudan açılır.
  GroupInvite? _contestInvite;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await FriendService.getUserByUsername(widget.username);
    GroupInvite? invite;
    try {
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid != null && user != null) {
        final q = await FirebaseFirestore.instance
            .collection('notifications')
            .doc(myUid)
            .collection('items')
            .where('type', isEqualTo: 'group_contest_invite')
            .where('fromUid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          invite = GroupInvite.fromDoc(q.docs.first.id, q.docs.first.data());
        }
      }
    } catch (_) {/* bildirim okunamazsa arkadaşlık moduna düş */}
    if (!mounted) return;
    setState(() {
      _user = user;
      _contestInvite = invite;
      _loading = false;
    });
  }

  /// Yarışma davetini kabul et → yarışmayı grubun ortak sorularıyla aç.
  void _acceptContest() {
    final inv = _contestInvite;
    if (inv == null || inv.contestId.isEmpty) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) =>
          GroupContestScreen(contestId: inv.contestId, autoJoin: true),
    ));
  }

  Future<void> _send() async {
    final u = _user;
    if (u == null) return;
    if (FirebaseAuth.instance.currentUser == null) {
      setState(() => _result = 'Önce giriş yapmalısın');
      return;
    }
    setState(() => _sending = true);
    final ok = await FriendService.sendRequest(toUid: u.uid);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _result = ok
          ? '@${u.username} adlı kullanıcıya istek gönderildi'
          : 'İstek gönderilemedi (zaten arkadaş olabilirsiniz)';
    });
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6A00);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : _user == null
                  ? _notFound(context)
                  : _profileCard(context, orange),
        ),
      ),
    );
  }

  Widget _notFound(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            'Kullanıcı bulunamadı'.tr(),
            style: GoogleFonts.fraunces(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppPalette.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '@${widget.username} adlı kullanıcı sistemde değil, ya da link bozuk.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppPalette.textSecondary(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Davet edenin avatarı — öncelik: profil fotoğrafı (base64 avatarData) →
  /// http foto → emoji → baş harf. URL asla düz METİN olarak basılmaz
  /// (eskiden "http…" yazısı görünüyordu).
  Widget _avatarWidget(FriendUser u) {
    Widget initial() => Text(
          (u.avatar.startsWith('http') || u.avatar.isEmpty)
              ? (u.displayName.isNotEmpty
                  ? u.displayName[0].toUpperCase()
                  : (u.username.isNotEmpty ? u.username[0].toUpperCase() : '?'))
              : u.avatar,
          style: const TextStyle(fontSize: 36),
        );
    final data = u.avatarData.trim();
    if (data.isNotEmpty) {
      try {
        final raw = data.contains(',') ? data.split(',').last : data;
        return Image.memory(
          base64Decode(raw),
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => initial(),
        );
      } catch (_) {/* bozuk base64 → fallback */}
    }
    if (u.avatar.startsWith('http')) {
      return Image.network(
        u.avatar,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => initial(),
      );
    }
    return initial();
  }

  Widget _profileCard(BuildContext context, Color orange) {
    final u = _user!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Üst banner
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [orange, const Color(0xFFFF8A3C)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: orange.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: _avatarWidget(u),
                ),
                const SizedBox(height: 12),
                Text(
                  u.displayName.isEmpty ? '@${u.username}' : u.displayName,
                  style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '@${u.username}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _contestInvite != null
                ? '${"Grup yarışına davet edildin".tr()} 🏆'
                : '${"Bilgi Yarışı'na davet ediliyorsun".tr()} 🏆',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppPalette.textPrimary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _contestInvite != null
                ? [
                    if (_contestInvite!.groupName.isNotEmpty)
                      '“${_contestInvite!.groupName}”',
                    [
                      _contestInvite!.subjectName,
                      _contestInvite!.topic,
                    ].where((s) => s.isNotEmpty).join(' • '),
                    'Kabul edince grubun ortak sorularını sen de çözersin.'
                        .tr(),
                  ].where((s) => s.isNotEmpty).join('\n')
                : 'Arkadaş eklediğinde düello yapabilir, sıralamayı karşılaştırabilirsiniz.'
                    .tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppPalette.textSecondary(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          // Sonuç mesajı
          if (_result != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: orange.withValues(alpha: 0.30)),
              ),
              child: Text(
                _result!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context),
                ),
              ),
            ),
          // CTA — bekleyen grup yarışı daveti varsa "kabul et" (yarışmayı
          // grubun ortak sorularıyla açar), yoksa arkadaşlık isteği.
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _sending
                    ? null
                    : (_contestInvite != null ? _acceptContest : _send),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _sending
                          ? [
                              AppPalette.textSecondary(context)
                                  .withValues(alpha: 0.5),
                              AppPalette.textSecondary(context)
                                  .withValues(alpha: 0.5),
                            ]
                          : [orange, const Color(0xFFFF8A3C)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_sending)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else
                        Icon(
                            _contestInvite != null
                                ? Icons.emoji_events_rounded
                                : Icons.person_add_rounded,
                            color: Colors.white,
                            size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _sending
                            ? 'Gönderiliyor…'.tr()
                            : (_contestInvite != null
                                ? 'Yarışma İsteğini Kabul Et'.tr()
                                : 'Arkadaş İsteği Gönder'.tr()),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
