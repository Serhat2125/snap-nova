// ═══════════════════════════════════════════════════════════════════════════════
//  GroupContestScreen — Arkadaş grubu yarışması (özel lig).
//
//  Tek ekran, 3 faz:
//    1. lobby   → yarışma bilgisi + katılımcılar + davet (QR/link) + "Başla"
//    2. quiz    → SABİT soru setini çöz (herkes aynı sorular), süre ölçülür
//    3. result  → grup sıralaması (canlı), skor + süreye göre
//
//  Sorular contest dokümanına gömülü geldiği için bu ekran arena'nın özel
//  soru/ders makinesinden BAĞIMSIZDIR — sadece contestId ile çalışır.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

import '../services/group_contest_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

class GroupContestScreen extends StatefulWidget {
  final String contestId;

  /// Davet linki/QR ile gelindiyse açılışta otomatik katıl.
  final bool autoJoin;

  const GroupContestScreen({
    super.key,
    required this.contestId,
    this.autoJoin = false,
  });

  @override
  State<GroupContestScreen> createState() => _GroupContestScreenState();
}

enum _Phase { loading, lobby, quiz, result, notFound }

class _GroupContestScreenState extends State<GroupContestScreen> {
  static const _orange = Color(0xFFFF6A00);

  _Phase _phase = _Phase.loading;
  GroupContest? _contest;
  bool _alreadyFinished = false;

  // Quiz durumu
  int _qIndex = 0;
  int _correct = 0;
  int? _selected;
  bool _revealed = false;
  DateTime? _quizStart;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.autoJoin) {
      await GroupContestService.joinContest(widget.contestId);
    }
    final c = await GroupContestService.getContest(widget.contestId);
    if (!mounted) return;
    if (c == null || c.questions.isEmpty) {
      setState(() => _phase = _Phase.notFound);
      return;
    }
    final finished = await GroupContestService.hasFinished(widget.contestId);
    if (!mounted) return;
    setState(() {
      _contest = c;
      _alreadyFinished = finished;
      _phase = finished ? _Phase.result : _Phase.lobby;
    });
  }

  // ─── Quiz akışı ──────────────────────────────────────────────────────────

  void _startQuiz() {
    setState(() {
      _phase = _Phase.quiz;
      _qIndex = 0;
      _correct = 0;
      _selected = null;
      _revealed = false;
      _quizStart = DateTime.now();
    });
  }

  List<String> _optsOf(Map<String, dynamic> q) =>
      ((q['options'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();

  void _choose(int i) {
    if (_revealed) return;
    final q = _contest!.questions[_qIndex];
    final correctIdx = (q['correctIndex'] as int?) ?? 0;
    setState(() {
      _selected = i;
      _revealed = true;
      if (i == correctIdx) _correct++;
    });
  }

  Future<void> _next() async {
    final qs = _contest!.questions;
    if (_qIndex < qs.length - 1) {
      setState(() {
        _qIndex++;
        _selected = null;
        _revealed = false;
      });
      return;
    }
    // Bitti → sonucu gönder.
    final durationMs = _quizStart == null
        ? 0
        : DateTime.now().difference(_quizStart!).inMilliseconds;
    await GroupContestService.submitResult(
      widget.contestId,
      correct: _correct,
      total: qs.length,
      durationMs: durationMs,
    );
    if (!mounted) return;
    setState(() {
      _alreadyFinished = true;
      _phase = _Phase.result;
    });
  }

  // ─── Davet ───────────────────────────────────────────────────────────────

  void _shareInvite() async {
    final link = GroupContestService.inviteLinkFor(widget.contestId);
    final c = _contest;
    final topic = c == null ? '' : '${c.subjectName} • ${c.topic}';
    final text = '${"Grup yarışıma katıl!".tr()} 🏆\n'
        '$topic\n$link';
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Davet linki kopyalandı'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _showQr() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppPalette.bg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Yarışma QR Kodu'.tr(),
                style: GoogleFonts.fraunces(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Arkadaşın okutsun, yarışmaya katılsın'.tr(),
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppPalette.textSecondary(context))),
            const SizedBox(height: 16),
            Container(
              width: 220,
              height: 220,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppPalette.border(context)),
              ),
              child: QrImageView(
                data: GroupContestService.inviteLinkFor(widget.contestId),
                version: QrVersions.auto,
                gapless: true,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square, color: Color(0xFF111111)),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF111111)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Grup Yarışı'.tr(),
            style: GoogleFonts.fraunces(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context))),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.notFound:
        return _notFound();
      case _Phase.lobby:
        return _lobby();
      case _Phase.quiz:
        return _quiz();
      case _Phase.result:
        return _result();
    }
  }

  Widget _notFound() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔍', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 14),
              Text('Yarışma bulunamadı'.tr(),
                  style: GoogleFonts.fraunces(
                      fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                'Bu yarışma kaldırılmış veya süresi dolmuş olabilir.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppPalette.textSecondary(context)),
              ),
            ],
          ),
        ),
      );

  // ── Lobi ──────────────────────────────────────────────────────────────────
  Widget _lobby() {
    final c = _contest!;
    return Column(
      children: [
        // Başlık kartı
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [_orange, Color(0xFFFF8A3C)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text('${c.subjectEmoji}  ${c.subjectName}',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.92))),
              const SizedBox(height: 4),
              Text(c.topic,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
              const SizedBox(height: 6),
              Text('${c.questionCount} ${"soru".tr()} · ${"sadece grubunuz".tr()}',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.9))),
            ],
          ),
        ),
        // Davet butonları — QR / Link / Kullanıcı adı
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _ghostBtn(
                    icon: Icons.qr_code_rounded,
                    label: 'QR Göster'.tr(),
                    onTap: _showQr),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ghostBtn(
                    icon: Icons.link_rounded,
                    label: 'Link Paylaş'.tr(),
                    onTap: _shareInvite),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ghostBtn(
                    icon: Icons.alternate_email_rounded,
                    label: 'Kullanıcı Adı'.tr(),
                    onTap: _inviteByUsername),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Katılımcılar
        Expanded(child: _participantsList(showRank: false)),
        // Başla
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: SizedBox(
            width: double.infinity,
            child: _primaryBtn(
              label: 'Yarışı Başlat'.tr(),
              icon: Icons.play_arrow_rounded,
              onTap: _startQuiz,
            ),
          ),
        ),
      ],
    );
  }

  // ── Quiz ────────────────────────────────────────────────────────────────
  Widget _quiz() {
    final qs = _contest!.questions;
    final q = qs[_qIndex];
    final opts = _optsOf(q);
    final correctIdx = (q['correctIndex'] as int?) ?? 0;
    final formula = (q['formula'] ?? '').toString();
    return Column(
      children: [
        // İlerleme
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text('${_qIndex + 1} / ${qs.length}',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textSecondary(context))),
              const Spacer(),
              Text('✓ $_correct',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF16A34A))),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (_qIndex + 1) / qs.length,
            minHeight: 6,
            backgroundColor: AppPalette.border(context),
            valueColor: const AlwaysStoppedAnimation(_orange),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              Text((q['text'] ?? '').toString(),
                  style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: AppPalette.textPrimary(context))),
              if (formula.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppPalette.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppPalette.border(context)),
                  ),
                  child: Text(formula,
                      style: GoogleFonts.robotoMono(
                          fontSize: 15,
                          color: AppPalette.textPrimary(context))),
                ),
              ],
              const SizedBox(height: 16),
              ...List.generate(opts.length, (i) {
                final isCorrect = i == correctIdx;
                final isPicked = i == _selected;
                Color border = AppPalette.border(context);
                Color bg = AppPalette.card(context);
                if (_revealed) {
                  if (isCorrect) {
                    border = const Color(0xFF16A34A);
                    bg = const Color(0xFF16A34A).withValues(alpha: 0.10);
                  } else if (isPicked) {
                    border = const Color(0xFFDC2626);
                    bg = const Color(0xFFDC2626).withValues(alpha: 0.10);
                  }
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => _choose(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border, width: 1.4),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppPalette.bg(context),
                              border:
                                  Border.all(color: AppPalette.border(context)),
                            ),
                            child: Text(String.fromCharCode(65 + i),
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(opts[i],
                                style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        AppPalette.textPrimary(context))),
                          ),
                          if (_revealed && isCorrect)
                            const Icon(Icons.check_circle_rounded,
                                color: Color(0xFF16A34A), size: 20),
                          if (_revealed && isPicked && !isCorrect)
                            const Icon(Icons.cancel_rounded,
                                color: Color(0xFFDC2626), size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (_revealed) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    (q['explanation'] ?? '').toString().isEmpty
                        ? (q['hint'] ?? '').toString()
                        : (q['explanation'] ?? '').toString(),
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.4,
                        color: AppPalette.textPrimary(context)),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_revealed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: _primaryBtn(
                label: _qIndex < qs.length - 1
                    ? 'Sonraki'.tr()
                    : 'Bitir'.tr(),
                icon: Icons.arrow_forward_rounded,
                onTap: _next,
              ),
            ),
          ),
      ],
    );
  }

  // ── Sonuç / sıralama ──────────────────────────────────────────────────────
  Widget _result() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Grup Sıralaması'.tr(),
                        style: GoogleFonts.fraunces(
                            fontSize: 18, fontWeight: FontWeight.w900)),
                    Text(
                        _alreadyFinished
                            ? 'Sonucun kaydedildi'.tr()
                            : '',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppPalette.textSecondary(context))),
                  ],
                ),
              ),
              IconButton(
                onPressed: _shareInvite,
                icon: const Icon(Icons.person_add_alt_1_rounded,
                    color: _orange),
                tooltip: 'Davet et'.tr(),
              ),
            ],
          ),
        ),
        Expanded(child: _participantsList(showRank: true)),
      ],
    );
  }

  // ── Katılımcı/sıralama listesi (canlı) ──────────────────────────────────────
  Widget _participantsList({required bool showRank}) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<GroupParticipant>>(
      stream: GroupContestService.participantsStream(widget.contestId),
      builder: (context, snap) {
        final list = snap.data ?? const <GroupParticipant>[];
        if (list.isEmpty) {
          return Center(
            child: Text('Henüz katılımcı yok'.tr(),
                style: GoogleFonts.inter(
                    color: AppPalette.textSecondary(context))),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final p = list[i];
            final isMe = p.uid == myUid;
            final rankColor = i == 0
                ? const Color(0xFFF59E0B)
                : i == 1
                    ? const Color(0xFF94A3B8)
                    : i == 2
                        ? const Color(0xFFB45309)
                        : AppPalette.textSecondary(context);
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: isMe
                    ? _orange.withValues(alpha: 0.08)
                    : AppPalette.card(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isMe
                        ? _orange.withValues(alpha: 0.40)
                        : AppPalette.border(context)),
              ),
              child: Row(
                children: [
                  if (showRank)
                    SizedBox(
                      width: 26,
                      child: Text('${i + 1}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.fraunces(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: rankColor)),
                    ),
                  _avatarWidget(p.avatar, 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('@${p.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textPrimary(context))),
                  ),
                  if (p.isDone)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${p.correct}/${p.total}',
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF16A34A))),
                        Text(_fmtDuration(p.durationMs),
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppPalette.textSecondary(context))),
                      ],
                    )
                  else
                    Text('bekliyor'.tr(),
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: AppPalette.textSecondary(context))),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _fmtDuration(int ms) {
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    final r = s % 60;
    if (m > 0) return '${m}d ${r}s';
    return '${r}s';
  }

  // ── Ortak butonlar ──────────────────────────────────────────────────────────
  Widget _primaryBtn(
      {required String label,
      required IconData icon,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient:
                const LinearGradient(colors: [_orange, Color(0xFFFF8A3C)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ghostBtn(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: _orange),
              const SizedBox(height: 5),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      color: AppPalette.textPrimary(context))),
            ],
          ),
        ),
      ),
    );
  }

  /// Avatar: 'http…' URL ise yuvarlak resim, kısa emoji ise metin, aksi halde
  /// (uzun/base64 çöp) varsayılan 👤. (URL'i düz metin basıp taşma yapmasın.)
  Widget _avatarWidget(String avatar, double size) {
    final a = avatar.trim();
    if (a.startsWith('http')) {
      return ClipOval(
        child: Image.network(
          a,
          width: size + 6,
          height: size + 6,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Text('👤', style: TextStyle(fontSize: size)),
        ),
      );
    }
    if (a.isEmpty || a.length > 4) {
      return Text('👤', style: TextStyle(fontSize: size));
    }
    return Text(a, style: TextStyle(fontSize: size), maxLines: 1);
  }

  /// Kullanıcı adıyla davet — küçük dialog: @kullanıcı_adı gir → bildirim gönder.
  Future<void> _inviteByUsername() async {
    final ctrl = TextEditingController();
    final c = _contest;
    await showDialog<void>(
      context: context,
      builder: (dctx) {
        bool sending = false;
        return StatefulBuilder(
          builder: (dctx, setLocal) {
            Future<void> send() async {
              final uname = ctrl.text.trim().replaceAll('@', '');
              if (uname.isEmpty) return;
              setLocal(() => sending = true);
              final res = await GroupContestService.inviteByUsername(
                widget.contestId,
                uname,
                subjectName: c?.subjectName ?? '',
                topic: c?.topic ?? '',
              );
              if (!dctx.mounted) return;
              Navigator.of(dctx).pop();
              if (!mounted) return;
              final msg = res == 'ok'
                  ? '@$uname davet edildi'.tr()
                  : res == 'notfound'
                      ? 'Bu kullanıcı adı bulunamadı'.tr()
                      : res == 'self'
                          ? 'Kendini davet edemezsin'.tr()
                          : 'Davet gönderilemedi'.tr();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(msg),
                behavior: SnackBarBehavior.floating,
              ));
            }

            return AlertDialog(
              backgroundColor: AppPalette.card(dctx),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text('Kullanıcı Adıyla Davet Et'.tr(),
                  style: GoogleFonts.fraunces(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Arkadaşının kullanıcı adını yaz; bildirimle davet gitsin.'
                        .tr(),
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppPalette.textSecondary(dctx)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => sending ? null : send(),
                    decoration: InputDecoration(
                      prefixText: '@',
                      hintText: 'kullanici_adi'.tr(),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      sending ? null : () => Navigator.of(dctx).pop(),
                  child: Text('Vazgeç'.tr(),
                      style: TextStyle(
                          color: AppPalette.textSecondary(dctx))),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _orange),
                  onPressed: sending ? null : send,
                  child: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Davet Et'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
