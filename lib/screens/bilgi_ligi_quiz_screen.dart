// ═══════════════════════════════════════════════════════════════════════════════
//  BİLGİ LİGİ — Test Çözme + Sonuç Ekranı
//
//  Akış:
//    1) Gemini'den 10 soruluk MCQ üret (loading)
//    2) Soru × 10 — her sorunun 4 şıkkı, kullanıcı seçer
//    3) Tüm sorular bitince sonuç (skor + doğru/yanlış dağılımı + sıraya yansıma)
//    4) Result ekranından geri = Bilgi Ligi listesine skor enjekte edilir
//
//  Pop ile dönerken: kazanılan puan (0-1000) Bilgi Ligi'ne return edilir.
//  Puanlama: doğru sayısı × hız bonusu × konu zorluğu (basit formül).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/league/league_scores.dart';
import '../features/league/quiz_pool_service.dart';
import '../services/education_profile.dart';
import '../services/gemini_service.dart';
import '../services/runtime_translator.dart';
import '../services/usage_quota.dart';
import '../theme/app_theme.dart';
import '../widgets/qualsar_loading_widget.dart';

class BilgiLigiQuizScreen extends StatefulWidget {
  final EduProfile profile;
  final String subjectKey;
  final String subjectName;
  final String subjectEmoji;
  final String? topic;
  /// Bilgi Ligi'nde seçili periyot — Günlük/Haftalık/Aylık/Genel. Quiz
  /// içeriğini SEÇMEZ (sorular periyottan bağımsız) ama puan kaydı bu
  /// periyot etiketi ile yapılır ve quiz header'ında rozet olarak gösterilir
  /// → kullanıcı seçimin etkisini görür.
  final LeaguePeriod period;
  /// Sınav Modu — kullanıcı "LGS"/"AYT (Sayısal)"/"KPSS Lisans" gibi resmi
  /// bir sınav seçtiyse burada gelir. Verilirse AI üretimine o sınavın
  /// format/zorluk/üslubuna uyması için ek talimat geçilir.
  final String? examLabel;
  /// Şık sayısı — gerçek sınav formatına göre (ör. LGS 4, TYT/AYT/DGS/KPSS
  /// 5). Sınav modu dışında (normal müfredat testi) varsayılan 4.
  final int optionCount;
  /// PUANIN yazılacağı ders anahtarı [subjectKey]'den farklıysa (profil
  /// sınavı = Sınav Modu sınavı → müfredat dersiyle tek havuz) burada gelir.
  /// Tekrar-çözme (replay) kontrolü de bu anahtara bakar — yerel deneme
  /// kayıtları bu anahtar altında tutulur.
  final String? scoreSubjectKey;
  /// Testteki soru sayısı — yarış öncesi panelden seçilir (5/10/15/20).
  final int questionCount;

  const BilgiLigiQuizScreen({
    super.key,
    required this.profile,
    required this.subjectKey,
    required this.subjectName,
    required this.subjectEmoji,
    this.topic,
    this.period = LeaguePeriod.weekly,
    this.examLabel,
    this.optionCount = 4,
    this.scoreSubjectKey,
    this.questionCount = 10,
  });

  @override
  State<BilgiLigiQuizScreen> createState() => _BilgiLigiQuizScreenState();
}

class _BilgiLigiQuizScreenState extends State<BilgiLigiQuizScreen> {
  // ── Aşamalar ───────────────────────────────────────────────────────────────
  // loading → playing → result (yerel state ile yönetiliyor)
  bool _loading = true;
  String? _error;
  List<_Question> _questions = const [];
  int _index = 0;
  int? _selected;
  bool _finished = false;

  // Sonuç istatistik
  int _correctCount = 0;
  int _wrongCount = 0;
  int _skippedCount = 0;
  int _totalSec = 0;
  DateTime? _quizStartedAt;
  Timer? _ticker;

  /// Her sorunun kullanıcı cevabı: int (0-3) seçilen şık veya null (boş).
  /// Quiz bittikten sonra "Yanlış Yaptığın Sorular" ekranı için kullanılır.
  late List<int?> _userAnswers;

  /// Şüpheli (sonra dönmek istenen) işaretli sorular — soru pilleri +
  /// bayrak ikonuyla gösterilir/toggle edilir.
  final Set<int> _flagged = {};

  /// Periyot için deterministik seed — aynı gün/hafta/ay = aynı 10 soru.
  /// allTime → null (rastgele her seferinde).
  /// Hafta hesabı ISO 8601 standardına göre yapılır → her ülkede aynı sonuç.
  int? _periodSeed(LeaguePeriod p) {
    // Sunucu-düzeltmeli saat — cihaz saati yanlışsa bile seed, liderlik
    // kovasıyla aynı güne denk gelir.
    final now = LeagueScores.correctedNow();
    switch (p) {
      case LeaguePeriod.daily:
        // UTC'ye normalize edilmiş "gün" — kullanıcı timezone'larından
        // bağımsız olarak aynı gün herkeste aynı seed.
        final utc = now.toUtc();
        final dayOfYear =
            utc.difference(DateTime.utc(utc.year, 1, 1)).inDays + 1;
        return utc.year * 1000 + dayOfYear;
      case LeaguePeriod.weekly:
        return _isoWeekSeed(now.toUtc());
      case LeaguePeriod.monthly:
        final utc = now.toUtc();
        return utc.year * 12 + utc.month;
      case LeaguePeriod.allTime:
        return null;
    }
  }

  /// ISO 8601 hafta numarası — Pazartesi başlangıç, Perşembe içeren hafta
  /// o yılın haftasıdır. Yıl sınırlarında doğru çalışır.
  int _isoWeekSeed(DateTime utc) {
    // Bu haftaki Perşembe gününü bul (ISO: hafta Perşembe içerdiği yılın).
    final dayOfWeek = utc.weekday; // 1=Pzt, 7=Paz
    final thursday = utc.add(Duration(days: 4 - dayOfWeek));
    // Bu Perşembenin yıl içindeki sırası
    final jan1 = DateTime.utc(thursday.year, 1, 1);
    final dayOfYear = thursday.difference(jan1).inDays + 1;
    final week = ((dayOfYear - 1) / 7).floor() + 1;
    return thursday.year * 100 + week;
  }

  // ÖSYM tarzı net: Doğru − (Yanlış / divisor); divisor yaş bazlı.
  //   primary (1-4)        → ceza yok (null)
  //   middle (5-8)         → 5 yanlış = 1 net
  //   high / exam_prep / +  → 4 yanlış = 1 net
  int? _wrongDivisor() {
    switch (widget.profile.level) {
      case 'primary':
        return null;
      case 'middle':
        return 5;
      case 'high':
      case 'exam_prep':
      case 'university':
      case 'masters':
      case 'doctorate':
        return 4;
      default:
        return 5;
    }
  }

  /// Ondalıklı net (gösterim için).
  double get _net {
    final div = _wrongDivisor();
    if (div == null) return _correctCount.toDouble();
    final n = _correctCount - (_wrongCount / div);
    return n < 0 ? 0 : n;
  }

  /// Sıralama puanı = net (ondalıklı). 1 net = 1 puan, 7.75 net = 7.75 puan.
  double get _finalScore => _net;

  /// Puan formatı: tam sayı ise "8", ondalıksa "7.75".
  String _formatScore(double n) {
    if (n == n.truncateToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Bootstrap sırasında UsageQuota.increment'i yaptıysak true — fail
  /// path'lerinde decrement'le iade ederiz.
  bool _quotaCharged = false;

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // ── KOTA: günlük + aylık global ───────────────────────────────────────
    final quota = await UsageQuota.get(QuotaKind.arenaQuiz);
    if (quota.isExhausted) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = quota.isDailyExhausted
            ? 'Günlük yarışma sınırına ulaştın (${quota.dailyLimit}). Yarın tekrar dene.'
                .tr()
            : 'Aylık yarışma sınırına ulaştın (${quota.monthlyLimit}). Ay başında sıfırlanır.'
                .tr();
      });
      return;
    }
    await UsageQuota.increment(QuotaKind.arenaQuiz);
    _quotaCharged = true;
    try {
      // 1) Önce havuzdan dene (ilk 100 doluysa AI'a hiç gitme).
      final key = QuizPoolService.poolKey(
        country: widget.profile.country,
        level: widget.profile.level,
        grade: widget.profile.grade,
        subjectKey: widget.subjectKey,
        topic: widget.topic,
      );
      // Periyot rotasyonu için deterministik seed:
      //   • daily   → yıl+gün → her gün farklı 10 soru, tüm kullanıcı aynı set
      //   • weekly  → yıl+haftaNo → her hafta farklı set
      //   • monthly → yıl+ay → her ay farklı set
      //   • allTime → null → her açılışta rastgele
      //
      // TEKRAR-ÇÖZME KORUMASI: deterministik seed yalnızca bu kovadaki İLK
      // denemede kullanılır. Aynı gün aynı derse ikinci kez girildiğinde
      // sorular RASTGELE gelir — aksi halde cevapları ezberleyip aynı 10
      // soruyu tekrar tekrar çözerek puan şişirmek mümkündü.
      int? seed = _periodSeed(widget.period);
      if (seed != null) {
        try {
          final replays = await LeagueScores.attemptsInBucket(
            // Puan havuzu birleştirilmişse yerel kayıtlar scoreSubjectKey
            // altında — replay kontrolü de aynı anahtara bakmalı, yoksa
            // deterministik seed tekrar kullanılıp aynı sorular gelirdi.
            subjectKey: widget.scoreSubjectKey ?? widget.subjectKey,
            topic: widget.topic,
            period: widget.period,
          );
          if (replays > 0) seed = null;
        } catch (_) {/* yerel okuma hatası → seed'li devam, kritik değil */}
      }
      // Kullanıcının bu havuzda daha önce GÖRDÜĞÜ sorular hariç tutulur —
      // replay'de (seed=null) aynı soruların tekrar gelmemesi için. Kova
      // ilk denemesi (deterministik seed) herkes için ortak set olduğundan
      // orada eleme yapılmaz.
      Set<String> served = const {};
      if (seed == null) {
        try {
          served = await QuizPoolService.servedHashes(key);
        } catch (_) {/* okunamazsa elemesiz devam */}
      }
      List<Map<String, dynamic>> raw = await QuizPoolService.fetchPoolQuestions(
        key: key,
        count: widget.questionCount,
        seed: seed,
        exclude: served.isEmpty ? null : served,
      );

      // 2) Havuz boş veya yetersiz (görülmemiş soru kalmadıysa da buraya
      //    düşer) → Gemini'den TAZE üret + (cap altındaysa) havuza ekle.
      if (raw.length < widget.questionCount) {
        final fresh = await GeminiService.generateLeagueQuiz(
          profile: widget.profile,
          subjectName: widget.subjectName,
          topic: widget.topic,
          count: widget.questionCount,
          // Doğrulama (ikinci AI geçişi) kapalı: tek üretim çağrısı yeterli;
          // çift geçiş süreyi ~ikiye katlıyor ve "test hazırlanamadı" timeout'a
          // yol açıyordu. Üretim zinciri Gemini → ChatGPT → Grok ile failover'lı.
          validate: false,
          examLabel: widget.examLabel,
          optionCount: widget.optionCount,
        );
        // Üretilen soruları havuza ekle (cap altındaysa). Hata yutulur.
        unawaited(QuizPoolService.addToPool(
          key: key,
          profile: widget.profile,
          subjectKey: widget.subjectKey,
          topic: widget.topic,
          questions: fresh,
        ));
        raw = fresh;
      }

      final qs = raw.map((m) => _Question.fromMap(m)).toList();
      if (qs.isEmpty) {
        // AI cevap verdi ama parse fail / 0 soru — kotayı iade et.
        await UsageQuota.decrement(QuotaKind.arenaQuiz);
        _quotaCharged = false;
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'AI bu konu için soru üretemedi. Lütfen tekrar dene.'.tr();
        });
        return;
      }
      if (!mounted) return;
      // Sorular kullanıcıya GERÇEKTEN gösterilecek — sunulmuş olarak işaretle
      // ki aynı konudan bir sonraki testte tekrar gelmesinler. (Parse-fail /
      // erken çıkış yollarında işaretlenmez; görülmemiş soru yakılmaz.)
      unawaited(QuizPoolService.markServed(key, raw));
      setState(() {
        _questions = qs;
        _loading = false;
        // "Yeni Test" butonundan tekrar çağrılınca sonuç ekranını kapatıp
        // baştan başla — _finished bayrağını sıfırla.
        _finished = false;
        _index = 0;
        _selected = null;
        _correctCount = 0;
        _wrongCount = 0;
        _skippedCount = 0;
        _totalSec = 0;
        _flagged.clear();
        _quizStartedAt = DateTime.now();
        _userAnswers = List<int?>.filled(qs.length, null);
      });
      _startTicker();
    } catch (e) {
      // Raw exception yerine kullanıcı-okuyabilir mesaj.
      if (_quotaCharged) {
        await UsageQuota.decrement(QuotaKind.arenaQuiz);
        _quotaCharged = false;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Test hazırlanamadı. İnternet bağlantını kontrol et ve tekrar dene.'
            .tr();
      });
      debugPrint('[BilgiLigiQuiz] bootstrap fail: $e');
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  /// Şık seçimi ANINDA `_userAnswers`e yazılır — serbest gezinme (pil
  /// navigatörüyle başka soruya atlayıp geri dönme) cevabı korur.
  void _selectOption(int i) {
    setState(() {
      _selected = i;
      _userAnswers[_index] = i;
    });
  }

  void _toggleFlag() {
    setState(() {
      if (_flagged.contains(_index)) {
        _flagged.remove(_index);
      } else {
        _flagged.add(_index);
      }
    });
  }

  /// Pil navigatöründen veya Geri/Sonraki'den herhangi bir soruya atla —
  /// önceki cevap varsa geri yüklenir.
  void _goTo(int i) {
    if (i < 0 || i >= _questions.length) return;
    setState(() {
      _index = i;
      _selected = _userAnswers[i];
    });
  }

  /// Soruyu boş bırak (varsa mevcut cevabı sil) ve ilerle.
  void _skip() {
    setState(() {
      _userAnswers[_index] = null;
      _selected = null;
    });
    _goNextOrFinish();
  }

  void _goNextOrFinish() {
    if (_index >= _questions.length - 1) {
      _finishQuiz();
    } else {
      _goTo(_index + 1);
    }
  }

  /// Doğru/yanlış/boş sayaçları serbest gezinme bitince `_userAnswers`
  /// üzerinden TEK SEFERDE hesaplanır (artık soru-soru biriktirilmiyor —
  /// kullanıcı cevabını değiştirip geri dönebildiği için).
  void _finishQuiz() {
    _ticker?.cancel();
    int correct = 0, wrong = 0, skipped = 0;
    for (var i = 0; i < _questions.length; i++) {
      final a = _userAnswers[i];
      if (a == null) {
        skipped++;
      } else if (a == _questions[i].correct) {
        correct++;
      } else {
        wrong++;
      }
    }
    final started = _quizStartedAt;
    final elapsed =
        started == null ? 0 : DateTime.now().difference(started).inSeconds;
    setState(() {
      _correctCount = correct;
      _wrongCount = wrong;
      _skippedCount = skipped;
      _totalSec = elapsed;
      _finished = true;
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bg = AppPalette.bg(context);
    // Mid-quiz hardware back / iOS swipe-back → confirm dialog.
    // Loading/hata durumunda direkt pop (cevap riski yok). Finished
    // durumunda DA doğrudan pop VERMİYORUZ: sistem-geri ile çıkışta bile
    // skor sonucu döndürülmeli — yoksa Bilgi Ligi'ne puan hiç yazılmaz.
    final canPopFreely = _loading || _error != null;
    return PopScope(
      canPop: canPopFreely,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (_finished) {
          // Sonuç ekranındayken sistem-geri = "Sıralamayı Gör" butonuyla
          // aynı davranış: skoru döndürerek çık.
          navigator.pop(<String, num>{'score': _finalScore, 'durationSec': _totalSec});
          return;
        }
        final exit = await _confirmExit();
        if (!exit || !mounted) return;
        // Kullanıcı oyunu yarıda bıraktı → kotayı iade et.
        if (_quotaCharged) {
          await UsageQuota.decrement(QuotaKind.arenaQuiz);
          _quotaCharged = false;
        }
        if (mounted) navigator.pop();
      },
      child: Scaffold(
        // Yükleme sırasında loader saf beyaz; Scaffold arka planı da beyaz
        // olsun ki status-bar inset bölgesinde gri/beyaz iki-renk çizgisi olmasın.
        backgroundColor: _loading ? Colors.white : bg,
        // Yüklemede loader TAM-EKRAN gösterilir (özet sayfasındaki dönen logonun
        // birebir aynısı). QuAlsarLoadingWidget kendi iç SafeArea'sını içeriyor;
        // burada dış SafeArea sarmalamak çift-padding'e + logonun aşağı kaymasına
        // yol açıyordu. Diğer durumlarda (oyun/sonuç/hata) normal SafeArea.
        body: _loading
            ? _buildBody(context)
            : SafeArea(child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return _buildLoading(context);
    if (_error != null) return _buildError(context);
    if (_finished) return _buildResult(context);
    return _buildPlaying(context);
  }

  /// Yanlış yapılan soruların review ekranı.
  Future<void> _openWrongQuestionsView() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _WrongQuestionsView(
          questions: _questions,
          userAnswers: _userAnswers,
        ),
      ),
    );
  }

  // Numeric ders anahtarları — domain belirlemek için.
  static const _kNumericSubjectKeys = <String>{
    'math', 'matematik', 'geometry', 'geometri',
    'physics', 'fizik', 'chem', 'chemistry', 'kimya',
    'bio', 'biology', 'biyoloji',
    'stats', 'istatistik', 'informatics', 'bilisim',
  };

  // ── Loading — QuAlsar branded loader (test üretim aşamaları) ──────────────
  Widget _buildLoading(BuildContext context) {
    final isNumeric = _kNumericSubjectKeys
        .contains(widget.subjectKey.toLowerCase());
    final topic = widget.topic ?? widget.subjectName;
    return QuAlsarLoadingWidget(
      type: QuAlsarLoadingType.test,
      topic: topic,
      domain:
          isNumeric ? SubjectDomain.numeric : SubjectDomain.verbal,
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────────
  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 56, color: AppPalette.textSecondary(context)),
          const SizedBox(height: 12),
          Text(
            'Test hazırlanamadı'.tr(),
            style: GoogleFonts.fraunces(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppPalette.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _error ?? '',
            textAlign: TextAlign.center,
            maxLines: 3,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppPalette.textSecondary(context),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text('Geri'.tr()),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _bootstrap,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('Tekrar Dene'.tr()),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Soru ekranı ────────────────────────────────────────────────────────────
  Widget _buildPlaying(BuildContext context) {
    final q = _questions[_index];
    final answered = _userAnswers.where((a) => a != null).length;
    final flagged = _flagged.length;
    final blank = _questions.length - answered;
    return Column(
      children: [
        _buildQuizHeader(context),
        _buildPillNav(context),
        _buildCounterRow(context, answered, flagged, blank),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppPalette.textPrimary(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${'Soru'.tr()} ${_index + 1} / ${_questions.length}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.bg(context),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _toggleFlag,
                      child: Icon(
                        _flagged.contains(_index)
                            ? Icons.flag_rounded
                            : Icons.flag_outlined,
                        size: 22,
                        color: _flagged.contains(_index)
                            ? const Color(0xFFF59E0B)
                            : AppPalette.textSecondary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  q.q,
                  style: GoogleFonts.fraunces(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(context),
                    letterSpacing: -0.2,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                for (int i = 0; i < q.options.length; i++) ...[
                  _OptionTile(
                    label: q.options[i],
                    letter: String.fromCharCode(65 + i),
                    state: _stateFor(i, q),
                    onTap: () => _selectOption(i),
                  ),
                  const SizedBox(height: 8),
                ],
                // Quiz sırasında açıklama göstermiyoruz — kullanıcı tüm soruları
                // bitirdikten sonra "Yanlış Yaptığın Sorular" ekranında görür.
              ],
            ),
          ),
        ),
        _buildBottomBar(context, q),
      ],
    );
  }

  _OptionState _stateFor(int i, _Question q) {
    // Quiz sırasında doğru/yanlış göstermiyoruz — sadece seçim durumu.
    return _selected == i ? _OptionState.selected : _OptionState.idle;
  }

  Widget _buildQuizHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final exit = await _confirmExit();
              if (exit && mounted) {
                navigator.pop();
              }
            },
            icon: Icon(Icons.arrow_back_rounded,
                color: AppPalette.textPrimary(context)),
            tooltip: 'Çık'.tr(),
          ),
          Expanded(
            child: Text(
              widget.subjectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppPalette.textSecondary(context),
              ),
            ),
          ),
          // Periyot rozeti — seçilen filtrenin quiz'i hangi periyot için
          // çözdüğünü kullanıcıya gösterir. Daily/Weekly/Monthly → aynı
          // dilimdeki tüm kullanıcılar AYNI 10 soruyu çözer (deterministik seed).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6A00), Color(0xFFFF8A3C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              widget.period.displayLabel.tr(),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Numaralı soru navigatörü — dokununca doğrudan o soruya atlar.
  /// Siyah = cevaplanmış, turuncu = aktif soru, boş çerçeve = boş,
  /// sarı çerçeve = şüpheli işaretli.
  Widget _buildPillNav(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _questions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final isAnswered = _userAnswers[i] != null;
          final isCurrent = i == _index;
          final isFlagged = _flagged.contains(i);
          final Color bg;
          final Color fg;
          if (isCurrent) {
            bg = const Color(0xFFFF6A00);
            fg = Colors.white;
          } else if (isAnswered) {
            bg = AppPalette.textPrimary(context);
            fg = AppPalette.bg(context);
          } else {
            bg = Colors.transparent;
            fg = AppPalette.textPrimary(context);
          }
          return GestureDetector(
            onTap: () => _goTo(i),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
                border: Border.all(
                  color: isFlagged
                      ? const Color(0xFFF59E0B)
                      : (isCurrent || isAnswered
                          ? Colors.transparent
                          : AppPalette.border(context)),
                  width: isFlagged ? 2 : 1.2,
                ),
              ),
              child: Text(
                '${i + 1}',
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w800, color: fg),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCounterRow(
      BuildContext context, int answered, int flagged, int blank) {
    Widget item(IconData icon, Color color, String label, int n) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              '$n ${label.tr()}',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppPalette.textPrimary(context),
              ),
            ),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          item(Icons.check_circle_rounded, const Color(0xFF22C55E),
              'Cevaplanan', answered),
          item(Icons.flag_rounded, const Color(0xFFF59E0B), 'Şüpheli',
              flagged),
          item(Icons.radio_button_unchecked,
              AppPalette.textSecondary(context), 'Boş', blank),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, _Question q) {
    final isLast = _index >= _questions.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        color: AppPalette.bg(context),
        border: Border(
          top: BorderSide(color: AppPalette.border(context), width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Geri — önceki soruya döner (ilk soruda pasif).
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.textPrimary(context),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(
                        color: AppPalette.border(context), width: 1.2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text('Geri'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              // Atla — cevabı (varsa) siler, boş bırakır ve ilerler.
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _skip,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.textPrimary(context),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(
                        color: AppPalette.border(context), width: 1.2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.fast_forward_rounded, size: 16),
                  label: Text('Atla'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Sonraki Soru / Sonucu Gör — cevaplanmasa da ilerlemeye izin
          // verir (Atla ile aynı sonucu verir; ekstra sürtünme yok).
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _goNextOrFinish,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isLast ? 'Sonucu Gör'.tr() : 'Sonraki Soru'.tr(),
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Testten çık?'.tr()),
        content: Text('İlerlemen kaydedilmeyecek.'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Devam Et'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Çık'.tr()),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // ── Sonuç ekranı ────────────────────────────────────────────────────────────
  Widget _buildResult(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final mute = AppPalette.textSecondary(context);
    final ratio = _correctCount / _questions.length;
    final emoji = ratio >= 0.9
        ? '🏆'
        : ratio >= 0.7
            ? '🥇'
            : ratio >= 0.5
                ? '🥈'
                : ratio >= 0.3
                    ? '🥉'
                    : '🎯';
    final headline = ratio >= 0.9
        ? 'Mükemmel!'.tr()
        : ratio >= 0.7
            ? 'Harika iş!'.tr()
            : ratio >= 0.5
                ? 'Güzel başlangıç!'.tr()
                : ratio >= 0.3
                    ? 'Daha iyisini yapabilirsin'.tr()
                    : 'Tekrar denemelisin'.tr();
    final score = _finalScore;
    final avgSec = (_totalSec / math.max(1, _questions.length)).round();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context)
                .pop(<String, num>{'score': score, 'durationSec': _totalSec}),
              icon: Icon(Icons.arrow_back_rounded, color: ink),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(emoji, style: const TextStyle(fontSize: 64))),
          const SizedBox(height: 10),
          Center(
            child: Text(
              headline,
              style: GoogleFonts.fraunces(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: ink,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              widget.topic == null
                  ? widget.subjectName
                  : '${widget.subjectName} ➔ ${widget.topic}',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: mute,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  '+ ${_formatScore(score)}',
                  style: GoogleFonts.fraunces(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  'Lig Puanı'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Detaylı sonuç kartı — Doğru/Yanlış/Boş + net formülü + puan
          _buildResultBreakdownCard(context),
          const SizedBox(height: 12),
          // Süre kartı (kompakt)
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Ortalama Süre'.tr(),
                  value: '${avgSec}s',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Yanlış yaptığın sorulara bak (sadece yanlışlar varsa görünür)
          if (_wrongCount > 0) ...[
            FilledButton.icon(
              onPressed: () => _openWrongQuestionsView(),
              icon: const Icon(Icons.fact_check_rounded, size: 18),
              label: Text(
                'Yanlış Yaptığın Sorulara Bak ($_wrongCount)'.tr(),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: () => Navigator.of(context)
                .pop(<String, num>{'score': score, 'durationSec': _totalSec}),
            style: FilledButton.styleFrom(
              // Beyaz zemin + siyah yazı (yeni tasarım).
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(
                color: Colors.black.withValues(alpha: 0.15),
                width: 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Sıralamayı Gör'.tr(),
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _bootstrap,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Yeni Test'.tr(),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Detaylı sonuç tablosu kartı ────────────────────────────────────────────
  //   Doğru / Yanlış / Boş satırları + net formülü + 1 net = 1 puan açıklaması.
  Widget _buildResultBreakdownCard(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final mute = AppPalette.textSecondary(context);
    final divisor = _wrongDivisor();
    final net = _net;
    final score = _finalScore;

    // Hesaplama satırı dinamik:
    final formulaLine = divisor == null
        ? 'Net = Doğru sayısı = $_correctCount'
        : 'Net = $_correctCount − ($_wrongCount ÷ $divisor) = ${net.toStringAsFixed(2)}';

    Widget row(String label, String value, {Color? badge}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            if (badge != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: badge, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ],
        ),
      );
    }

    Widget divider() => Container(
          height: 1,
          color: AppPalette.border(context),
          margin: const EdgeInsets.symmetric(vertical: 4),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppPalette.border(context),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                'Sonuç Tablon'.tr(),
                style: GoogleFonts.fraunces(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ink,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 3 ana sayım
          row('Doğru'.tr(), '$_correctCount',
              badge: const Color(0xFF10B981)),
          row('Yanlış'.tr(), '$_wrongCount',
              badge: const Color(0xFFEF4444)),
          row('Boş'.tr(), '$_skippedCount',
              badge: const Color(0xFF9CA3AF)),
          divider(),
          // Hesaplama
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  divisor == null
                      ? 'Hesaplama (yaş grubunda yanlış cezası yok)'.tr()
                      : 'Hesaplama (Doğru − Yanlış ÷ $divisor)'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: mute,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formulaLine,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
          divider(),
          // Net
          row('Net'.tr(), net.toStringAsFixed(2),
              badge: const Color(0xFFFF6A00)),
          divider(),
          // Puan açıklaması
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1 net = 1 puan'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: mute,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Bu testten kazandığın puan: '.tr(),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      TextSpan(
                        text: _formatScore(score),
                        style: GoogleFonts.fraunces(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFFF6A00),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Soru modeli ─────────────────────────────────────────────────────────────
class _Question {
  final String q;
  final List<String> options;
  final int correct;
  final String explanation;

  const _Question({
    required this.q,
    required this.options,
    required this.correct,
    required this.explanation,
  });

  factory _Question.fromMap(Map<String, dynamic> m) {
    return _Question(
      q: (m['q'] ?? '').toString(),
      options: (m['options'] as List).map((e) => e.toString()).toList(),
      correct: (m['correct'] as num).toInt(),
      explanation: (m['explanation'] ?? '').toString(),
    );
  }
}

// ── Şık state'leri ──────────────────────────────────────────────────────────
enum _OptionState { idle, selected, correct, wrong, dim }

class _OptionTile extends StatelessWidget {
  final String label;
  final String letter;
  final _OptionState state;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.letter,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    Color border;
    Color bg;
    Color fg;
    Color letterBg;
    Color letterFg;
    IconData? trailing;

    switch (state) {
      case _OptionState.idle:
        border = AppPalette.border(context);
        bg = AppPalette.card(context);
        fg = ink;
        letterBg = AppPalette.cardMuted(context);
        letterFg = ink;
        trailing = null;
        break;
      case _OptionState.selected:
        border = ink;
        bg = AppPalette.card(context);
        fg = ink;
        letterBg = ink;
        letterFg = AppPalette.bg(context);
        trailing = null;
        break;
      case _OptionState.correct:
        border = const Color(0xFF10B981);
        bg = const Color(0xFF10B981).withValues(alpha: 0.10);
        fg = ink;
        letterBg = const Color(0xFF10B981);
        letterFg = Colors.white;
        trailing = Icons.check_circle_rounded;
        break;
      case _OptionState.wrong:
        border = const Color(0xFFEF4444);
        bg = const Color(0xFFEF4444).withValues(alpha: 0.10);
        fg = ink;
        letterBg = const Color(0xFFEF4444);
        letterFg = Colors.white;
        trailing = Icons.cancel_rounded;
        break;
      case _OptionState.dim:
        border = AppPalette.border(context);
        bg = AppPalette.cardMuted(context);
        fg = AppPalette.textSecondary(context);
        letterBg = AppPalette.cardMuted(context);
        letterFg = AppPalette.textSecondary(context);
        trailing = null;
        break;
    }

    return InkWell(
      onTap: state == _OptionState.dim ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: border,
            width: state == _OptionState.idle ? 1 : 1.6,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: letterBg,
                shape: BoxShape.circle,
              ),
              child: Text(
                letter,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: letterFg,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  height: 1.35,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Icon(trailing, size: 22, color: letterBg),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Sonuç ekranı için stat kart ─────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context), width: 1),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.fraunces(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppPalette.textPrimary(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppPalette.textSecondary(context),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Yanlış Yaptığın Sorular ekranı — quiz bitince review için açılır.
//  Sadece YANLIŞ cevaplanmış sorular listelenir; her bir soruda kullanıcının
//  seçtiği yanlış şık + doğru şık + AI açıklaması gösterilir.
// ═══════════════════════════════════════════════════════════════════════════════
class _WrongQuestionsView extends StatelessWidget {
  final List<_Question> questions;
  final List<int?> userAnswers;
  const _WrongQuestionsView({
    required this.questions,
    required this.userAnswers,
  });

  List<int> get _wrongIndices {
    final out = <int>[];
    for (int i = 0; i < questions.length; i++) {
      final ua = userAnswers[i];
      if (ua == null) continue; // boş = yanlış değil
      if (ua != questions[i].correct) out.add(i);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final wrongIdxs = _wrongIndices;
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back_rounded, color: ink),
                    tooltip: 'Geri'.tr(),
                  ),
                  Expanded(
                    child: Text(
                      'Yanlış Yaptığın Sorular'.tr(),
                      style: GoogleFonts.fraunces(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${wrongIdxs.length}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: wrongIdxs.isEmpty
                  ? _buildEmpty(context)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: wrongIdxs.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (ctx, i) {
                        final qIdx = wrongIdxs[i];
                        return _WrongQuestionCard(
                          number: qIdx + 1,
                          question: questions[qIdx],
                          userAnswer: userAnswers[qIdx]!,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'Hiç yanlış yapmadın!'.tr(),
              style: GoogleFonts.fraunces(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WrongQuestionCard extends StatelessWidget {
  final int number;
  final _Question question;
  final int userAnswer;
  const _WrongQuestionCard({
    required this.number,
    required this.question,
    required this.userAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final mute = AppPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppPalette.border(context),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${'Soru'.tr()} $number',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            question.q,
            style: GoogleFonts.fraunces(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
              height: 1.35,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 12),
          // Şıklar — kullanıcının yanlış seçimi kırmızı, doğru şık yeşil
          for (int i = 0; i < question.options.length; i++) ...[
            _ReviewOption(
              letter: String.fromCharCode(65 + i),
              text: question.options[i],
              isCorrect: i == question.correct,
              isUserChoice: i == userAnswer,
            ),
            if (i < question.options.length - 1) const SizedBox(height: 6),
          ],
          if (question.explanation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppPalette.cardMuted(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppPalette.border(context),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      question.explanation,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${'Doğru cevap'.tr()}: ${String.fromCharCode(65 + question.correct)}',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: mute,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewOption extends StatelessWidget {
  final String letter;
  final String text;
  final bool isCorrect;
  final bool isUserChoice;
  const _ReviewOption({
    required this.letter,
    required this.text,
    required this.isCorrect,
    required this.isUserChoice,
  });

  @override
  Widget build(BuildContext context) {
    Color border;
    Color letterBg;
    Color letterFg;
    IconData? trailing;

    if (isCorrect) {
      border = const Color(0xFF10B981);
      letterBg = const Color(0xFF10B981);
      letterFg = Colors.white;
      trailing = Icons.check_circle_rounded;
    } else if (isUserChoice) {
      border = const Color(0xFFEF4444);
      letterBg = const Color(0xFFEF4444);
      letterFg = Colors.white;
      trailing = Icons.cancel_rounded;
    } else {
      border = AppPalette.border(context);
      letterBg = AppPalette.cardMuted(context);
      letterFg = AppPalette.textPrimary(context);
      trailing = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isCorrect
            ? const Color(0xFF10B981).withValues(alpha: 0.06)
            : isUserChoice
                ? const Color(0xFFEF4444).withValues(alpha: 0.06)
                : AppPalette.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: border, width: (isCorrect || isUserChoice) ? 1.4 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: letterBg, shape: BoxShape.circle),
            child: Text(
              letter,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: letterFg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppPalette.textPrimary(context),
                height: 1.3,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Icon(trailing, size: 18, color: letterBg),
          ],
        ],
      ),
    );
  }
}
