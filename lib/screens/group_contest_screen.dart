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

import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

import '../services/contest_group_service.dart';
import '../services/group_contest_service.dart';
import '../services/parent_preview.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../utils/math_text_cleaner.dart';

class GroupContestScreen extends StatefulWidget {
  final String contestId;

  /// Davet linki/QR ile gelindiyse açılışta otomatik katıl.
  final bool autoJoin;

  /// Yarışı BAŞLATAN kişi için lobiyi atla, doğrudan quiz'e (sorulara) geç.
  final bool autoStart;

  /// Demo yarışta yerel (Firestore'a yazılmayan) bot katılımcılar — sonuç
  /// tablosunda gerçek katılımcılarla birlikte gösterilir. Güvenlik kuralları
  /// başka uid'li participant yazımına izin vermediğinden bot'lar yereldir.
  final List<GroupParticipant> demoParticipants;

  /// Grup ismi — paylaşılan sonuç görselinin başlığında gösterilir.
  final String? groupName;

  const GroupContestScreen({
    super.key,
    required this.contestId,
    this.autoJoin = false,
    this.autoStart = false,
    this.demoParticipants = const [],
    this.groupName,
  });

  @override
  State<GroupContestScreen> createState() => _GroupContestScreenState();
}

enum _Phase { loading, lobby, quiz, result, notFound }

class _GroupContestScreenState extends State<GroupContestScreen> {
  static const _orange = Color(0xFFFF6A00);

  _Phase _phase = _Phase.loading;
  GroupContest? _contest;
  // Kayıtlı gruba bağlıysa: üye kadrosu + simge + durum mesajı. Sonuç
  // tablosunda TÜM grup üyeleri (henüz çözmeyenler dahil) listelenir ve
  // başlıkta grubun simgesi/mesajı gösterilir.
  ContestGroup? _group;
  // Sonuç ekranında "Sorular ve Cevaplar" dökümü aç/kapa (varsayılan gizli).
  bool _answersExpanded = false;
  bool _alreadyFinished = false;
  // Sonuç tablosunu PNG olarak yakalamak için (görsel paylaş).
  final GlobalKey _tableShareKey = GlobalKey();

  // Quiz durumu
  int _qIndex = 0;
  // Her sorunun cevabı; null = boş bırakıldı. Kullanıcı geri/ileri gezip
  // boş bıraktığı soruları sonradan doldurabilir; puan en sonda hesaplanır.
  final List<int?> _answers = [];
  DateTime? _quizStart;

  int get _answeredCount => _answers.where((e) => e != null).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.autoJoin && !ParentPreview.active) {
      // Ebeveyn önizlemesinde yarışmaya katılım YAZILMAZ (salt-izleme).
      await GroupContestService.joinContest(widget.contestId);
    }
    final c = await GroupContestService.getContest(widget.contestId);
    if (!mounted) return;
    if (c == null || c.questions.isEmpty) {
      setState(() => _phase = _Phase.notFound);
      return;
    }
    final finished = await GroupContestService.hasFinished(widget.contestId);
    // Kayıtlı gruba bağlıysa üye kadrosunu çek — sonuç tablosunda herkes
    // (henüz çözmeyenler dahil) görünsün, "Herkes bitirdi" ancak gerçekten
    // herkes bitince yazılsın; başlıkta grubun simgesi + mesajı çıksın.
    ContestGroup? group;
    if (c.groupId.isNotEmpty) {
      group = await ContestGroupService.getGroup(c.groupId);
    }
    // Daha önce (belki başka oturumda) bitirdiysen cevapların kalıcı kayıtlı;
    // "Sorular ve Cevaplar" dökümü için geri yükle.
    List<int?>? savedAnswers;
    if (finished) {
      savedAnswers = await GroupContestService.getMyAnswers(widget.contestId);
    }
    if (!mounted) return;
    setState(() {
      _contest = c;
      _group = group;
      _alreadyFinished = finished;
      if (savedAnswers != null &&
          savedAnswers.length == c.questions.length) {
        _answers
          ..clear()
          ..addAll(savedAnswers);
      }
      _phase = finished ? _Phase.result : _Phase.lobby;
    });
    // Başlatan kişi (autoStart) → lobiyi atla, doğrudan sorulara geç.
    if (widget.autoStart && !finished && mounted) {
      _startQuiz();
    }
  }

  // ─── Quiz akışı ──────────────────────────────────────────────────────────

  void _startQuiz() {
    setState(() {
      _phase = _Phase.quiz;
      _qIndex = 0;
      _answers
        ..clear()
        ..addAll(List<int?>.filled(_contest!.questions.length, null));
      _quizStart = DateTime.now();
    });
  }

  List<String> _optsOf(Map<String, dynamic> q) =>
      ((q['options'] as List?) ?? const [])
          .map((e) => cleanMathText(e.toString()))
          .toList();

  void _choose(int i) {
    setState(() {
      // Aynı şıkka tekrar dokununca seçim kalkar (boş bırakma).
      _answers[_qIndex] = (_answers[_qIndex] == i) ? null : i;
    });
  }

  void _prev() {
    if (_qIndex == 0) return;
    setState(() => _qIndex--);
  }

  void _skip() {
    // Boş bırak → cevabı temizle ve ilerle.
    setState(() => _answers[_qIndex] = null);
    _next();
  }

  Future<void> _next() async {
    final qs = _contest!.questions;
    if (_qIndex < qs.length - 1) {
      setState(() => _qIndex++);
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    final qs = _contest!.questions;
    // Boş kalan sorular varsa kullanıcıyı uyar; isterse geri dönüp doldurur.
    final blanks = <int>[
      for (int i = 0; i < qs.length; i++)
        if (_answers[i] == null) i
    ];
    if (blanks.isNotEmpty) {
      final choice = await _confirmBlanks(blanks.length);
      if (choice == null) return; // iptal → aynı soruda kal
      if (choice == false) {
        // İlk boş soruya dön.
        setState(() => _qIndex = blanks.first);
        return;
      }
    }
    int correct = 0;
    for (int i = 0; i < qs.length; i++) {
      final a = _answers[i];
      if (a != null && a == ((qs[i]['correctIndex'] as int?) ?? 0)) correct++;
    }
    final durationMs = _quizStart == null
        ? 0
        : DateTime.now().difference(_quizStart!).inMilliseconds;
    if (!mounted || ParentPreview.guard(context)) {
      return; // önizlemede skor yazılmaz
    }
    await GroupContestService.submitResult(
      widget.contestId,
      correct: correct,
      total: qs.length,
      durationMs: durationMs,
      answers: List<int?>.from(_answers),
    );
    if (!mounted) return;
    setState(() {
      _alreadyFinished = true;
      _phase = _Phase.result;
    });
  }

  /// Boş soru uyarısı. true = yine de bitir, false = geri dön ve çöz, null = iptal.
  Future<bool?> _confirmBlanks(int count) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(context),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('$count ${"soru boş".tr()}',
            style: GoogleFonts.fraunces(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context))),
        content: Text(
            'Boş bıraktığın sorular yanlış sayılır. Geri dönüp çözmek ister misin?'
                .tr(),
            style: GoogleFonts.inter(
                fontSize: 13.5,
                height: 1.4,
                color: AppPalette.textSecondary(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Yine de bitir'.tr(),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Geri dön ve çöz'.tr(),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900, color: _orange)),
          ),
        ],
      ),
    );
  }

  // ─── Davet ───────────────────────────────────────────────────────────────

  /// Paylaşılan görselin başlığı — grup ismi (varsa) + ders · konu.
  String _shareTitle() {
    final c = _contest;
    final subj = c == null
        ? ''
        : '${c.subjectEmoji} ${c.subjectName}'
            '${c.topic.trim().isNotEmpty ? ' · ${c.topic}' : ''}';
    final gn = widget.groupName?.trim() ?? '';
    if (gn.isNotEmpty) {
      return subj.isEmpty ? gn : '$gn — $subj';
    }
    return subj.isEmpty ? 'Grup Sıralaması'.tr() : subj;
  }

  /// Grup simgesi (emoji) — kayıtlı grup varsa onun avatarı, yoksa 👥.
  String _groupEmoji() {
    final a = _group?.avatar.trim() ?? '';
    return a.isNotEmpty ? a : '👥';
  }

  /// Grup adı — kayıtlı grup > ekrana verilen groupName > boş.
  String _groupTitle() {
    final g = _group?.name.trim() ?? '';
    if (g.isNotEmpty) return g;
    return widget.groupName?.trim() ?? '';
  }

  /// Grubun durum mesajı (varsa).
  String _groupMessage() => _group?.status.trim() ?? '';

  /// Sonuç tablosunu (grup ismi + Excel tablo) PNG olarak yakalayıp paylaşır.
  Future<void> _shareResultImage() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary = _tableShareKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/grup_siralamasi_${widget.contestId}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: '🏆 ${_shareTitle()}');
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Görsel paylaşılamadı: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

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
              Text('$_answeredCount/${qs.length} ${"dolu".tr()}',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: _orange)),
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
              Text(cleanMathText((q['text'] ?? '').toString()),
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
                final isPicked = i == _answers[_qIndex];
                final Color border =
                    isPicked ? _orange : AppPalette.border(context);
                final Color bg = isPicked
                    ? _orange.withValues(alpha: 0.08)
                    : AppPalette.card(context);
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
                              color: isPicked ? _orange : AppPalette.bg(context),
                              border: Border.all(
                                  color: isPicked
                                      ? _orange
                                      : AppPalette.border(context)),
                            ),
                            child: Text(String.fromCharCode(65 + i),
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: isPicked
                                        ? Colors.white
                                        : AppPalette.textPrimary(context))),
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
                          if (isPicked)
                            const Icon(Icons.check_circle_rounded,
                                color: _orange, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        // Geri / Boş Bırak / Sonraki-Bitir — kullanıcı sorular arası gezebilir.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            children: [
              if (_qIndex > 0) ...[
                SizedBox(
                  width: 76,
                  child: _ghostBtn(
                    icon: Icons.arrow_back_rounded,
                    label: 'Geri'.tr(),
                    onTap: _prev,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              SizedBox(
                width: 82,
                child: _ghostBtn(
                  icon: Icons.remove_circle_outline_rounded,
                  label: 'Boş Bırak'.tr(),
                  onTap: _skip,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _primaryBtn(
                  label: _qIndex < qs.length - 1
                      ? 'Sonraki'.tr()
                      : 'Bitir'.tr(),
                  icon: Icons.arrow_forward_rounded,
                  onTap: _next,
                ),
              ),
            ],
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
              // Sonuç tablosunu GÖRSEL paylaş — küçük yeşil çerçeveli, yeşil
              // gönderme oku (ok ucu +x/+y yönünde 45°).
              GestureDetector(
                onTap: _shareResultImage,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.6),
                        width: 1.4),
                  ),
                  child: Transform.rotate(
                    angle: -0.785398, // -45° → ok ucu sağ-yukarı
                    child: const Icon(Icons.send_rounded,
                        color: Color(0xFF16A34A), size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _resultTable()),
      ],
    );
  }

  // ── Excel görünümlü sonuç tablosu ───────────────────────────────────────────
  // Yarışa katılan herkes ada göre satır satır listelenir; sıra + doğru + süre
  // sütunlarıyla gerçek bir tablo (gridli) olarak çizilir.
  Widget _resultTable() {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<GroupParticipant>>(
      stream: GroupContestService.participantsStream(widget.contestId),
      builder: (context, snap) {
        // Gerçek katılımcılar (Firestore) + yerel demo botları uid'e göre
        // birleştir; ardından kayıtlı GRUBUN henüz çözmemiş üyelerini de
        // "bekliyor" satırı olarak ekle — sıralama SADECE ben değil, grubun
        // TAMAMIdır ve "Herkes bitirdi" ancak herkes bitince yazılır.
        final byUid = <String, GroupParticipant>{};
        for (final p in [
          ...(snap.data ?? const <GroupParticipant>[]),
          ...widget.demoParticipants,
        ]) {
          byUid[p.uid] = p;
        }
        for (final m in (_group?.members ?? const <Map<String, dynamic>>[])) {
          final mu = (m['uid'] ?? '').toString();
          if (mu.isEmpty || byUid.containsKey(mu)) continue;
          byUid[mu] = GroupParticipant(
            uid: mu,
            username: (m['username'] ?? 'Oyuncu').toString(),
            avatar: (m['avatar'] ?? '👤').toString(),
            status: 'joined',
            score: 0,
            correct: 0,
            total: 0,
            durationMs: 0,
          );
        }
        // Başarıya göre sırala (bitiren önce, skor↓, süre↑).
        final list = byUid.values.toList()
          ..sort((a, b) {
            if (a.isDone != b.isDone) return a.isDone ? -1 : 1;
            if (a.score != b.score) return b.score.compareTo(a.score);
            return a.durationMs.compareTo(b.durationMs);
          });
        if (list.isEmpty) {
          return Center(
            child: Text('Henüz katılımcı yok'.tr(),
                style: GoogleFonts.inter(
                    color: AppPalette.textSecondary(context))),
          );
        }
        final doneCount = list.where((p) => p.isDone).length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Text(
                doneCount >= list.length
                    ? 'Herkes bitirdi · nihai sıralama'.tr()
                    : '$doneCount/${list.length} ${"katılımcı bitirdi".tr()}',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context)),
              ),
            ),
            // Paylaşılan görselin içeriği: ÜSTTE grup ismi + SADECE tablo.
            RepaintBoundary(
              key: _tableShareKey,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Grup simgesi + adı + durum mesajı; altında Ders ve
                    // Konu AYRI satırlarda.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_groupTitle().isNotEmpty) ...[
                          Text('${_groupEmoji()}  ${_groupTitle()}',
                              style: GoogleFonts.fraunces(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF111111))),
                          if (_groupMessage().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(_groupMessage(),
                                style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF6B7280))),
                          ],
                          const SizedBox(height: 5),
                        ],
                        Text('${"Ders:".tr()} ${_contest?.subjectName ?? ''}',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF374151))),
                        if ((_contest?.topic.trim() ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('${"Konu:".tr()} ${_contest!.topic.trim()}',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF374151))),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Table(
                        border: TableBorder.all(
                            color: const Color(0xFFD5D8DC), width: 1),
                        columnWidths: const {
                          0: FixedColumnWidth(24),
                          1: FlexColumnWidth(),
                          2: FixedColumnWidth(38),
                          3: FixedColumnWidth(40),
                          4: FixedColumnWidth(40),
                          5: FixedColumnWidth(46),
                        },
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: [
                          // Başlık satırı — yeşil, Excel his.
                          TableRow(
                            decoration: const BoxDecoration(
                                color: Color(0xFF16A34A)),
                            children: [
                              _th('#'),
                              _th('İsim Soyisim'.tr()),
                              _th('Soru'.tr()),
                              _th('Doğru'.tr()),
                              _th('Yanlış'.tr()),
                              _th('Başarı'.tr()),
                            ],
                          ),
                          for (int i = 0; i < list.length; i++)
                            _resultRow(list[i], i, i < doneCount, myUid),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _myAnswersBreakdown(),
          ],
        );
      },
    );
  }

  /// Bu oturumda / kayıttan bilinen cevap (yoksa null = boş kabul edilir).
  int? _answerAt(int i) =>
      (i >= 0 && i < _answers.length) ? _answers[i] : null;

  // ── Soru bazlı döküm — bu yarışın TÜM soruları kalıcı kayıtlıdır; altta
  // "Sorular ve Cevaplar" başlığından AÇ/KAPA edilir (varsayılan gizli).
  // Cevaplar bellekte olmasa bile (yarış başka oturumda çözülmüş) sorular +
  // doğru şıklar gösterilir; kayıtlı cevap varsa senin şıkkın işaretlenir.
  Widget _myAnswersBreakdown() {
    final c = _contest;
    if (c == null) return const SizedBox.shrink();
    final qs = c.questions;
    if (qs.isEmpty) return const SizedBox.shrink();

    final hasAnswers = _answers.length == qs.length;
    int correct = 0, wrong = 0, blank = 0;
    if (hasAnswers) {
      for (int i = 0; i < qs.length; i++) {
        final a = _answers[i];
        if (a == null) {
          blank++;
        } else if (a == ((qs[i]['correctIndex'] as int?) ?? 0)) {
          correct++;
        } else {
          wrong++;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        // Aç/kapa başlığı.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              setState(() => _answersExpanded = !_answersExpanded),
          child: Row(
            children: [
              Icon(
                  _answersExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: _orange),
              const SizedBox(width: 4),
              Expanded(
                child: Text('Sorular ve Cevaplar'.tr(),
                    style: GoogleFonts.fraunces(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.textPrimary(context))),
              ),
              Text('${qs.length} ${"soru".tr()}',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondary(context))),
              const SizedBox(width: 10),
              Text(_answersExpanded ? 'Gizle'.tr() : 'Göster'.tr(),
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: _orange)),
            ],
          ),
        ),
        if (_answersExpanded) ...[
          const SizedBox(height: 10),
          if (hasAnswers) ...[
            Row(
              children: [
                _summaryChip(
                    '$correct ${"doğru".tr()}', const Color(0xFF16A34A)),
                const SizedBox(width: 8),
                _summaryChip(
                    '$wrong ${"yanlış".tr()}', const Color(0xFFDC2626)),
                const SizedBox(width: 8),
                _summaryChip('$blank ${"boş".tr()}',
                    AppPalette.textSecondary(context)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          for (int i = 0; i < qs.length; i++) _answerCard(qs[i], i),
        ],
      ],
    );
  }

  Widget _summaryChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Text(text,
          style: GoogleFonts.inter(
              fontSize: 12, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Widget _answerCard(Map<String, dynamic> q, int i) {
    final opts = _optsOf(q);
    final correctIdx = (q['correctIndex'] as int?) ?? 0;
    final mine = _answerAt(i);
    final isBlank = mine == null;
    final isCorrect = !isBlank && mine == correctIdx;
    final Color statusColor = isBlank
        ? AppPalette.textSecondary(context)
        : (isCorrect ? const Color(0xFF16A34A) : const Color(0xFFDC2626));
    final String statusLabel = isBlank
        ? 'Boş'.tr()
        : (isCorrect ? 'Doğru'.tr() : 'Yanlış'.tr());
    final IconData statusIcon = isBlank
        ? Icons.remove_circle_outline_rounded
        : (isCorrect
            ? Icons.check_circle_rounded
            : Icons.cancel_rounded);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Text('${i + 1}',
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: statusColor)),
              ),
              const SizedBox(width: 8),
              Icon(statusIcon, size: 16, color: statusColor),
              const SizedBox(width: 4),
              Text(statusLabel,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: statusColor)),
            ],
          ),
          const SizedBox(height: 8),
          Text(cleanMathText((q['text'] ?? '').toString()),
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: AppPalette.textPrimary(context))),
          const SizedBox(height: 10),
          ...List.generate(opts.length, (o) {
            final isRight = o == correctIdx;
            final isMineWrong = o == mine && !isCorrect && !isBlank;
            Color bg = AppPalette.bg(context);
            Color line = AppPalette.border(context);
            if (isRight) {
              bg = const Color(0xFF16A34A).withValues(alpha: 0.10);
              line = const Color(0xFF16A34A);
            } else if (isMineWrong) {
              bg = const Color(0xFFDC2626).withValues(alpha: 0.10);
              line = const Color(0xFFDC2626);
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: line, width: 1.2),
                ),
                child: Row(
                  children: [
                    Text(String.fromCharCode(65 + o),
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppPalette.textSecondary(context))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(opts[o],
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textPrimary(context))),
                    ),
                    if (isRight)
                      const Icon(Icons.check_rounded,
                          size: 16, color: Color(0xFF16A34A)),
                    if (isMineWrong)
                      const Icon(Icons.close_rounded,
                          size: 16, color: Color(0xFFDC2626)),
                  ],
                ),
              ),
            );
          }),
          if (isBlank) ...[
            const SizedBox(height: 2),
            Text('Bu soruyu boş bıraktın.'.tr(),
                style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: AppPalette.textSecondary(context))),
          ],
        ],
      ),
    );
  }

  TableRow _resultRow(
      GroupParticipant p, int i, bool ranked, String? myUid) {
    final isMe = p.uid == myUid;
    final medal = i == 0
        ? const Color(0xFFF59E0B)
        : i == 1
            ? const Color(0xFF94A3B8)
            : i == 2
                ? const Color(0xFFB45309)
                : AppPalette.textPrimary(context);
    final Color rowBg = isMe
        ? _orange.withValues(alpha: 0.10)
        : (i.isEven ? AppPalette.card(context) : AppPalette.bg(context));
    return TableRow(
      decoration: BoxDecoration(color: rowBg),
      children: [
        _td(
          ranked ? '${i + 1}' : '—',
          align: TextAlign.center,
          weight: FontWeight.w900,
          color: ranked ? medal : AppPalette.textSecondary(context),
        ),
        // İsim Soyisim — hücrede ORTALI (avatar + kullanıcı adı).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _avatarWidget(p.avatar, 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text('@${p.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight:
                            isMe ? FontWeight.w900 : FontWeight.w700,
                        color: AppPalette.textPrimary(context))),
              ),
            ],
          ),
        ),
        // Soru sayısı (toplam soru).
        _td(
          '${p.total}',
          align: TextAlign.center,
          weight: FontWeight.w800,
          size: 11.5,
          color: AppPalette.textPrimary(context),
        ),
        // Doğru.
        _td(
          p.isDone ? '${p.correct}' : '—',
          align: TextAlign.center,
          weight: FontWeight.w800,
          size: 11.5,
          color: p.isDone
              ? const Color(0xFF16A34A)
              : AppPalette.textSecondary(context),
        ),
        // Yanlış (toplam − doğru; boşlar da yanlışa dahil).
        _td(
          p.isDone ? '${p.total - p.correct}' : '—',
          align: TextAlign.center,
          weight: FontWeight.w800,
          size: 11.5,
          color: p.isDone
              ? const Color(0xFFDC2626)
              : AppPalette.textSecondary(context),
        ),
        // Başarı oranı (% doğru) — EN SAĞDA, Yanlış'tan sonra.
        _td(
          p.isDone && p.total > 0
              ? '%${(p.correct * 100 / p.total).round()}'
              : '—',
          align: TextAlign.center,
          weight: FontWeight.w900,
          size: 11.5,
          color: p.isDone
              ? const Color(0xFF16A34A)
              : AppPalette.textSecondary(context),
        ),
      ],
    );
  }

  // Tablo başlık hücresi (beyaz, kalın).
  Widget _th(String text, {TextAlign align = TextAlign.center}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
      child: Text(text,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white)),
    );
  }

  // Tablo veri hücresi.
  Widget _td(String text,
      {TextAlign align = TextAlign.left,
      FontWeight weight = FontWeight.w600,
      Color? color,
      double size = 13}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
      child: Text(text,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
              fontSize: size,
              fontWeight: weight,
              color: color ?? AppPalette.textPrimary(context))),
    );
  }

  // ── Katılımcı/sıralama listesi (canlı) ──────────────────────────────────────
  Widget _participantsList({required bool showRank}) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<GroupParticipant>>(
      stream: GroupContestService.participantsStream(widget.contestId),
      builder: (context, snap) {
        // Gerçek katılımcılar (Firestore) + yerel demo botları birleştir,
        // başarıya göre yeniden sırala (bitiren önce, skor↓, süre↑).
        final list = <GroupParticipant>[
          ...(snap.data ?? const <GroupParticipant>[]),
          ...widget.demoParticipants,
        ]..sort((a, b) {
            if (a.isDone != b.isDone) return a.isDone ? -1 : 1;
            if (a.score != b.score) return b.score.compareTo(a.score);
            return a.durationMs.compareTo(b.durationMs);
          });
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
