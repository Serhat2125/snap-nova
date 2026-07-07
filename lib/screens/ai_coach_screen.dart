// ═══════════════════════════════════════════════════════════════════════════════
//  AICoachScreen — Kişisel AI Çalışma Koçu
//
//  Kullanıcının geçmiş çözüm + Pomodoro + test verilerinden zayıf konularını
//  analiz eder ve Gemini ile günlük + haftalık çalışma planı üretir.
//
//  Akış:
//    1. Yerel veri (SolutionsStorage + PomodoroStats) toplanır.
//    2. Zayıf konular ders/konu bazında error rate ile sıralanır.
//    3. Gemini.generateCoachPlan() çağrılır → 3 öneri + 7 günlük plan + motivasyon.
//    4. Hata olursa deterministic fallback (en zayıf 3 konu) çalışır.
//
//  Tasarım: kart bazlı, modern, dark-mode uyumlu.
//  Offline: Yerel veri her zaman analiz edilir; Gemini fail olsa bile kullanıcı
//  yine kişisel önerilerini görür.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart' show localeService;
import '../services/ai_quota_service.dart';
import '../services/app_settings_service.dart';
import '../services/coach_data_service.dart';
import '../services/gemini_service.dart';
import '../services/pomodoro_stats.dart';
import '../services/runtime_translator.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import 'academic_planner.dart' show AcademicPlanner, LibraryMode;
import 'ai_coach_chat_screen.dart';
import 'premium_screen.dart';

class AICoachScreen extends StatefulWidget {
  const AICoachScreen({super.key});

  @override
  State<AICoachScreen> createState() => _AICoachScreenState();
}

class _AICoachScreenState extends State<AICoachScreen> {
  bool _loading = true;
  bool _refreshing = false;

  // ── Free tier: 5dk ücretsiz süre ──────────────────────────────────────────
  Timer? _freeTimer;

  // ── Veri ────────────────────────────────────────────────────────────────
  PomodoroStatsSnapshot _stats = PomodoroStatsSnapshot.empty;
  CoachSnapshot _coach = CoachSnapshot.empty;
  String _greeting = '';
  List<_TodayRec> _today = const [];
  List<_WeekDay> _week = const [];
  String _tip = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
    if (!AiQuotaService.instance.isPremium) {
      _freeTimer = Timer(const Duration(minutes: 5), () {
        if (!mounted) return;
        _showFreeExpiredSheet();
      });
    }
  }

  @override
  void dispose() {
    _freeTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
    });
    try {
      // 1) Yerel veriyi paralel topla — 3 kaynak: özetler + sınav soruları + foto
      final results = await Future.wait([
        PomodoroStats.read(),
        CoachDataService.build(),
      ]);
      _stats = results[0] as PomodoroStatsSnapshot;
      _coach = results[1] as CoachSnapshot;

      // "AI Koç önerileri" kapalıysa kişisel çalışma verin (zayıf konular,
      // streak vb.) AI'a GÖNDERİLMEZ → kişiselleştirilmemiş fallback gösterilir.
      if (!AppSettingsService.instance.aiCoachData) {
        _applyFallback();
      } else {
        // 2) AI önerisi (Gemini, ~25sn timeout — fail olursa fallback)
        final aiPlan = await GeminiService.generateCoachPlan(
          weakTopics: _coach.weakTopics
              .take(8)
              .map((w) => w.toCompactMap())
              .toList(),
          streakDays: _stats.streakDays,
          todayFocusMin: _stats.todayPhases * 25,
          lang: localeService.localeCode,
          userName: UserProfileService.instance.username.isNotEmpty
              ? UserProfileService.instance.username
              : null,
        );
        if (aiPlan.isNotEmpty) {
          _applyAiPlan(aiPlan);
        } else {
          _applyFallback();
        }
      }
    } catch (_) {
      _applyFallback();
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _refreshing = false;
    });
  }

  void _applyAiPlan(Map<String, dynamic> m) {
    _greeting = (m['greeting'] ?? '').toString();
    _tip = (m['tip'] ?? '').toString();
    final today = (m['today'] as List?) ?? const [];
    _today = today.whereType<Map>().map((e) {
      final rawKind = (e['kind'] ?? '').toString().toLowerCase();
      // Kabul edilen değerler: 'summary' / 'test'. Diğeri → fallback 'summary'.
      final kind = (rawKind == 'test' || rawKind == 'questions')
          ? 'test'
          : 'summary';
      return _TodayRec(
        emoji: (e['emoji'] ?? '📚').toString(),
        title: (e['title'] ?? '').toString(),
        subject: (e['subject'] ?? '').toString(),
        topic: (e['topic'] ?? '').toString(),
        durationMin:
            (e['durationMin'] is num) ? (e['durationMin'] as num).toInt() : 10,
        why: (e['why'] ?? '').toString(),
        kind: kind,
      );
    }).take(3).toList();
    final week = (m['week'] as List?) ?? const [];
    _week = week.whereType<Map>().map((e) {
      return _WeekDay(
        day: (e['day'] ?? '').toString(),
        subject: (e['subject'] ?? '').toString(),
        topic: (e['topic'] ?? '').toString(),
        durationMin:
            (e['durationMin'] is num) ? (e['durationMin'] as num).toInt() : 15,
      );
    }).take(7).toList();
    // Boşsa fallback'e düş
    if (_today.isEmpty || _week.length < 7) _applyFallback();
  }

  /// Gemini yoksa zayıf konulardan deterministic öneri üret.
  void _applyFallback() {
    final w = _coach.weakTopics;
    final acc = (_coach.overallAccuracy * 100).round();
    final uname = UserProfileService.instance.username;
    final hello = uname.isNotEmpty ? 'Merhaba $uname, '.tr() : '';
    _greeting = _stats.streakDays > 0
        ? '$hello${_stats.streakDays} gün streak — başarın %$acc, devam! 🔥'.tr()
        : (_coach.totalTestAnswers > 0
            ? '${hello}test başarın %$acc. Hadi zayıf konuları kapatalım. 💪'.tr()
            : '${hello}bugün küçük bir başlangıç yap. 💪'.tr());
    _tip =
        'Bilim: Yanlış yaptığın soruları 24 saat içinde tekrar et — bellek %60 daha sağlam tutar.'.tr();
    if (w.isEmpty) {
      _today = [
        _TodayRec(
          emoji: '📚',
          title: 'Konu özeti üret'.tr(),
          subject: 'Genel'.tr(),
          topic: 'Özet'.tr(),
          durationMin: 15,
          why: 'Önce konuyu özetleyelim — temeli kuralım.'.tr(),
          kind: 'summary',
        ),
        _TodayRec(
          emoji: '🎯',
          title: 'Test çöz'.tr(),
          subject: 'Sınav'.tr(),
          topic: 'Genel deneme'.tr(),
          durationMin: 15,
          why: 'Doğru/yanlış oranını gör, zayıf konuları çıkar.'.tr(),
          kind: 'test',
        ),
        _TodayRec(
          emoji: '📷',
          title: 'Bir soru tara'.tr(),
          subject: 'Genel'.tr(),
          topic: 'Soru çöz'.tr(),
          durationMin: 10,
          why: 'Veri biriksin diye ilk çözümünü yapalım.'.tr(),
          kind: 'summary',
        ),
      ];
    } else {
      // Zayıf konulardan öneri üret: konu için test verisi varsa "test çöz",
      // henüz hiç test verisi yoksa önce "özet" — sonra test daha mantıklı.
      _today = [
        for (final t in w.take(3))
          _TodayRec(
            emoji: _emojiForSubject(t.subject),
            title: (t.correctCount + t.wrongCount) >= 3
                ? '${t.topic} ${'testini tekrar et'.tr()}'
                : '${t.topic} ${'özetini çalış'.tr()}',
            subject: t.subject,
            topic: t.topic,
            durationMin: 10 + (t.errorRate * 10).round(),
            why: _whyText(t),
            kind: (t.correctCount + t.wrongCount) >= 3 ? 'test' : 'summary',
          ),
      ];
    }
    final days = [
      'Pzt'.tr(), 'Sal'.tr(), 'Çar'.tr(), 'Per'.tr(),
      'Cum'.tr(), 'Cmt'.tr(), 'Paz'.tr(),
    ];
    _week = List.generate(7, (i) {
      if (w.isEmpty) {
        return _WeekDay(
          day: days[i],
          subject: 'Genel'.tr(),
          topic: 'Çalışma'.tr(),
          durationMin: 25,
        );
      }
      final t = w[i % w.length];
      return _WeekDay(
        day: days[i],
        subject: t.subject,
        topic: t.topic,
        durationMin: 15 + (i % 3) * 10,
      );
    });
  }

  /// Zayıf konunun verilerine göre "neden bu konu önerildi" kısa metin üret.
  String _whyText(CoachWeakTopic t) {
    final total = t.correctCount + t.wrongCount;
    if (total >= 3) {
      final pct = (t.errorRate * 100).round();
      return 'Testte $total sorudan ${t.wrongCount} yanlış — başarı %${100 - pct}. Tekrar zamanı.'.tr();
    }
    if (t.photoCount > 0 && total == 0) {
      return 'Bu konuda ${t.photoCount} fotoğraf çözümün var, henüz test yok. Hadi test yap.'.tr();
    }
    if (t.summaryCount > 0 && t.photoCount == 0 && total == 0) {
      return '${t.summaryCount} özet çalışmışsın, henüz pekiştirmedin. Şimdi test çöz.'.tr();
    }
    return 'Bu konu sana zorluk çıkarmış — birkaç dakika tekrar yapalım.'.tr();
  }

  String _emojiForSubject(String s) {
    final l = s.toLowerCase();
    if (l.contains('mat')) return '📐';
    if (l.contains('fiz')) return '⚛️';
    if (l.contains('kim')) return '🧪';
    if (l.contains('biy')) return '🧬';
    if (l.contains('tar')) return '🏛️';
    if (l.contains('coğ') || l.contains('cog')) return '🌍';
    if (l.contains('ede') || l.contains('lit')) return '📖';
    if (l.contains('ing') || l.contains('eng')) return '🗣️';
    if (l.contains('fels') || l.contains('phil')) return '🤔';
    return '📚';
  }

  void _showFreeExpiredSheet() {
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
              width: 64, height: 64,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFEC4899)]),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 16),
            Text('Premium\'a Geç'.tr(),
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black)),
            const SizedBox(height: 8),
            Text(
              '5 dakikalık ücretsiz AI Koç süren doldu.\nSınırsız analiz ve plan için Premium\'a geç.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                },
                child: Text('Premium\'a Geç'.tr(),
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).maybePop();
              },
              child: Text('Geri Dön'.tr(),
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.black38)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded,
              color: AppPalette.textPrimary(context), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'AI Koç'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Yenile'.tr(),
            icon: AnimatedRotation(
              turns: _refreshing ? 1 : 0,
              duration: const Duration(milliseconds: 600),
              child: Icon(Icons.refresh_rounded,
                  color: AppPalette.textPrimary(context)),
            ),
            onPressed: _refreshing
                ? null
                : () {
                    setState(() => _refreshing = true);
                    _bootstrap();
                  },
          ),
        ],
      ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AICoachChatScreen(),
                ),
              ),
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              elevation: 6,
              icon: const Icon(Icons.chat_bubble_rounded, size: 20),
              label: Text(
                'AI Koç\'la Sohbet'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
      body: _loading
          ? _buildLoading()
          : RefreshIndicator(
              onRefresh: _bootstrap,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                children: [
                  _buildGreetingCard(),
                  const SizedBox(height: 16),
                  _sectionTitle('🎯 Bugün ne çalış?'.tr()),
                  const SizedBox(height: 10),
                  ..._today.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _todayCard(r),
                      )),
                  const SizedBox(height: 16),
                  _sectionTitle('📊 Zayıf konularım'.tr()),
                  const SizedBox(height: 10),
                  _buildWeakTopicsCard(),
                  const SizedBox(height: 16),
                  _sectionTitle('🗓️ Haftanın planı'.tr()),
                  const SizedBox(height: 10),
                  _buildWeekCard(),
                  const SizedBox(height: 16),
                  if (_tip.isNotEmpty) _buildTipCard(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            'Verilerin analiz ediliyor…'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppPalette.textSecondary(context),
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String s) => Text(
        s,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppPalette.textPrimary(context),
        ),
      );

  Widget _buildGreetingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFFDB2777)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🧠', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(
                'Senin Koçun'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const Spacer(),
              if (_stats.streakDays > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        '${_stats.streakDays} ${'gün'.tr()}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _greeting.isEmpty
                ? 'Bugünün planını birlikte yapalım.'.tr()
                : _greeting,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statChip(
                  '🎯',
                  _coach.totalTestAnswers > 0
                      ? '%${(_coach.overallAccuracy * 100).round()}'
                      : '—',
                  'Test Başarı'.tr()),
              const SizedBox(width: 8),
              _statChip('📚', '${_coach.totalSummaries}', 'Özet'.tr()),
              const SizedBox(width: 8),
              _statChip('📷', '${_coach.totalPhotos}', 'Foto Çöz.'.tr()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String emoji, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 2),
            Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85))),
          ],
        ),
      ),
    );
  }

  Widget _todayCard(_TodayRec r) {
    final isTest = r.kind == 'test';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(r.emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.title,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6A00)
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${r.durationMin} ${'dk'.tr()}',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFFF6A00),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.subject} • ${r.topic}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textSecondary(context),
                      ),
                    ),
                    if (r.why.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        r.why,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppPalette.textSecondary(context),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Sağ altta turuncu CTA — özet aç / test çöz ───────────────
          Align(
            alignment: Alignment.centerRight,
            child: _OrangeCta(
              icon:
                  isTest ? Icons.quiz_rounded : Icons.menu_book_rounded,
              label: isTest ? 'Test Çöz'.tr() : 'Özeti Aç'.tr(),
              onTap: () => _navigateToWork(r),
            ),
          ),
        ],
      ),
    );
  }

  /// Önerinin kindine göre özet ya da sınav soruları sayfasına yönlendir.
  /// Şu an library landing'i mode ile açıyor — kullanıcı subject/topic'i
  /// gözle bulup giriyor. İleride deep-link ile direkt konuya götürülebilir.
  void _navigateToWork(_TodayRec r) {
    final mode = r.kind == 'test'
        ? LibraryMode.questions
        : LibraryMode.summary;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AcademicPlanner(mode: mode),
      ),
    );
  }

  Widget _emptyHint(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeakTopicsCard() {
    if (_coach.weakTopics.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🌱', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Henüz yeterli veri yok'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'AI Koç şu üç kaynaktan analiz yapar:'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
              ),
            ),
            const SizedBox(height: 8),
            _emptyHint('🎯',
                'Sınav Soruları — testleri çöz, doğru/yanlış oranın çıkar'.tr()),
            _emptyHint('📚',
                'Konu Özetleri — özet ürettiğin konular ilgi alanını gösterir'.tr()),
            _emptyHint('📷',
                'Fotoğraf çözümleri — kameradan attığın sorular dahil edilir'.tr()),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _coach.weakTopics.take(5).length; i++) ...[
            _weakRow(_coach.weakTopics[i], i),
            if (i < 4 && i < _coach.weakTopics.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(
                    height: 1, color: AppPalette.border(context)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _weakRow(CoachWeakTopic w, int idx) {
    final pct = (w.errorRate * 100).round();
    final color = pct > 60
        ? const Color(0xFFEF4444)
        : pct > 30
            ? const Color(0xFFF59E0B)
            : const Color(0xFF22C55E);
    // Veri kaynak özeti: 3T (test), 2Ö (özet), 5F (foto)
    final sources = <String>[];
    if (w.correctCount + w.wrongCount > 0) {
      sources.add('${w.correctCount + w.wrongCount}T');
    }
    if (w.summaryCount > 0) sources.add('${w.summaryCount}Ö');
    if (w.photoCount > 0) sources.add('${w.photoCount}F');
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(_emojiForSubject(w.subject),
              style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                w.topic,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${w.subject} • ${sources.join(" • ")}',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '%$pct',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        children: [
          for (final d in _week)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      d.day,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1A73E8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.topic,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textPrimary(context),
                          ),
                        ),
                        Text(
                          d.subject,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${d.durationMin} ${'dk'.tr()}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTipCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF6E3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD580)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _tip,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF7C5500),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Yardımcı veri modelleri (UI iç state)
//  Zayıf konu modeli `CoachWeakTopic` services/coach_data_service.dart'ta.
// ═══════════════════════════════════════════════════════════════════════════════
class _TodayRec {
  final String emoji;
  final String title;
  final String subject;
  final String topic;
  final int durationMin;
  final String why;
  /// 'summary' (özet okuma) veya 'test' (sınav soruları çözme).
  /// UI alt sağ köşedeki turuncu butonun etiketi ve yönlendirilen sayfa
  /// bu alana bakar. Eski Gemini cevapları için varsayılan: 'summary'.
  final String kind;
  const _TodayRec({
    required this.emoji,
    required this.title,
    required this.subject,
    required this.topic,
    required this.durationMin,
    required this.why,
    this.kind = 'summary',
  });
}

class _WeekDay {
  final String day;
  final String subject;
  final String topic;
  final int durationMin;
  const _WeekDay({
    required this.day,
    required this.subject,
    required this.topic,
    required this.durationMin,
  });
}

/// Turuncu gradient pill CTA — "Özeti Aç" / "Test Çöz" butonları için.
/// Uygulamada başka yerde kullanılan turuncu kimliği ile tutarlı.
class _OrangeCta extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _OrangeCta({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6A00), Color(0xFFFF8A3C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6A00).withValues(alpha: 0.30),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
