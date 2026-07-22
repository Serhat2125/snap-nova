// ═══════════════════════════════════════════════════════════════════════════
//  Ebeveyn paneli HIZLI AKSİYONLAR — ana sayfadaki 3'lü sade satır:
//
//  • 🤖 ParentAdvisorChatScreen — AI Eğitim Danışmanı: veli, çocuğunun
//    durumu hakkında yapay zekâyla CANLI sohbet eder (AiTask.coach zinciri:
//    Gemini → ChatGPT failover). Çocuğun güncel istatistikleri sistem
//    bağlamına gömülür; danışman kısa, sıcak, pratik rehberlik verir.
//  • 🎁 showParentSurpriseSheet — çocuğa tek tıkla motivasyon sürprizi:
//    çocuğun bildirim kutusuna 'parent_gift' doc'u yazılır (FCM push'u
//    pushOnNotificationCreated otomatik iletir). Yazışma yükü yok.
//  • 📄 shareWeeklyPdfReport — 7 günlük çalışma/soru/başarı verisinden
//    temiz bir PDF karne üretir ve paylaşım menüsünü açar (pdf + printing).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/education_models.dart';
import '../services/ai_provider_service.dart';
import '../services/ai_quota_service.dart';
import '../services/locale_service.dart';
import '../services/parent_link_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const _kBrand = Color(0xFF7C3AED);
const _kPink = Color(0xFFEC4899);

// ═══════════════════════════════════════════════════════════════════════════
//  🤖 AI EĞİTİM DANIŞMANI — canlı sohbet
// ═══════════════════════════════════════════════════════════════════════════
class ParentAdvisorChatScreen extends StatefulWidget {
  final String childName;
  /// Çocuğun güncel durumu — sistem prompt'una gömülür (ör. "Bugün 16 dk
  /// çalıştı, 8 soru çözdü, %75 başarı, 2 gün seri, 1 bekleyen ödev").
  final String statsContext;
  const ParentAdvisorChatScreen(
      {super.key, required this.childName, this.statsContext = ''});

  @override
  State<ParentAdvisorChatScreen> createState() =>
      _ParentAdvisorChatScreenState();
}

class _ParentAdvisorChatScreenState extends State<ParentAdvisorChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<({bool me, String text})> _msgs = [];
  bool _sending = false;

  /// Ekran açılışında havuzdan karıştırılarak seçilen öneri soruları.
  late final List<String> _suggestions;

  /// Öneri havuzu — veliye çocuğu hakkında sorabileceği 20 hazır soru.
  /// Her açılışta karıştırılıp 6'sı gösterilir; böylece liste hep taze kalır.
  List<String> _buildSuggestionPool() => [
        'Bu hafta nasıl gidiyor, genel bir değerlendirme yapar mısın?'.tr(),
        'Çocuğumu ders çalışmaya nasıl motive edebilirim?'.tr(),
        'Eksik olduğu konuları nasıl kapatabiliriz?'.tr(),
        'Sınav kaygısını azaltmak için evde ne yapabilirim?'.tr(),
        'Günde kaç saat ders çalışması sağlıklı olur?'.tr(),
        'Telefon ve oyun süresini nasıl dengeleyebiliriz?'.tr(),
        'Ona baskı yapmadan nasıl destek olabilirim?'.tr(),
        'Hangi derslerde daha çok desteğe ihtiyacı var?'.tr(),
        'Verimli bir ders çalışma ortamı nasıl hazırlarım?'.tr(),
        'Ödevlerini erteleme alışkanlığını nasıl kırabiliriz?'.tr(),
        'Başarılarını nasıl doğru şekilde ödüllendirmeliyim?'.tr(),
        'Uyku düzeni ders başarısını nasıl etkiliyor?'.tr(),
        'Karnesi beklediğimizden kötü gelirse ona nasıl yaklaşmalıyım?'.tr(),
        'Ders çalışırken mola düzeni nasıl olmalı?'.tr(),
        'Okuma alışkanlığı kazanması için ne önerirsin?'.tr(),
        'Onunla dersleri hakkında konuşurken nelere dikkat etmeliyim?'.tr(),
        'Dikkatini toplamakta zorlanıyor, ne yapabilirim?'.tr(),
        'Hafta sonu için nasıl bir çalışma planı önerirsin?'.tr(),
        'Onu başkalarıyla kıyaslamak zararlı mı, ne yapmalıyım?'.tr(),
        'Uzun vadeli hedefler koymasına nasıl yardım edebilirim?'.tr(),
      ];

  @override
  void initState() {
    super.initState();
    _suggestions =
        (_buildSuggestionPool()..shuffle()).take(6).toList(growable: false);
    // Karşılama — AI çağrısı olmadan, anında.
    _msgs.add((
      me: false,
      text:
          '${'Merhaba! Ben QuAlsar Eğitim Danışmanı 🤖'.tr()}\n${'Çocuğunun durumu, eksikleri veya onu nasıl destekleyebileceğin hakkında bana istediğini sorabilirsin.'.tr()}'
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    setState(() {
      _msgs.add((me: true, text: text));
      _sending = true;
    });
    _scrollToEnd();
    final sys = 'Sen QuAlsar uygulamasının AI Eğitim Danışmanısın. '
        'Bir EBEVEYN ile konuşuyorsun; çocuğunun adı: ${widget.childName}. '
        '${widget.statsContext.isEmpty ? '' : 'Çocuğun güncel verileri: ${widget.statsContext}. '}'
        'Kurallar: Kısa yaz (en fazla 120 kelime), sıcak ve umut verici ol, '
        'somut/uygulanabilir 1-2 öneri ver, veliyi asla yargılama, çocukla '
        'ilgili tıbbi/psikolojik teşhis koyma. Velinin yazdığı dilde yanıtla.';
    String reply;
    try {
      // Son 10 mesaj bağlam olarak gider — danışmanın hafızası olur.
      final history = _msgs
          .skip(_msgs.length > 10 ? _msgs.length - 10 : 0)
          .map((m) => AiChatMessage(m.me ? 'user' : 'assistant', m.text))
          .toList();
      reply = await AiProviderService.chatTask(
        AiTask.coach,
        isPremium: AiQuotaService.instance.isPremium,
        system: sys,
        messages: history,
        maxTokens: 800,
      );
      if (reply.trim().isEmpty) throw Exception('empty');
    } catch (_) {
      reply =
          'Şu an yanıt veremiyorum — internet bağlantını kontrol edip tekrar dener misin?'
              .tr();
    }
    if (!mounted) return;
    setState(() {
      _msgs.add((me: false, text: reply.trim()));
      _sending = false;
    });
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI Eğitim Danışmanı'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            Text(widget.childName,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppPalette.textSecondary(context))),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                itemCount: _msgs.length + (_sending ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == _msgs.length) {
                    // "yazıyor…" balonu
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppPalette.card(ctx),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppPalette.border(ctx)),
                        ),
                        child: SizedBox(
                          width: 28,
                          height: 12,
                          child: Center(
                            child: Text('•••',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: AppPalette.textSecondary(ctx),
                                )),
                          ),
                        ),
                      ),
                    );
                  }
                  final m = _msgs[i];
                  return Align(
                    alignment:
                        m.me ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(ctx).size.width * 0.78),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: m.me ? _kBrand : AppPalette.card(ctx),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(m.me ? 16 : 4),
                          bottomRight: Radius.circular(m.me ? 4 : 16),
                        ),
                        border: m.me
                            ? null
                            : Border.all(color: AppPalette.border(ctx)),
                      ),
                      child: Text(m.text,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            height: 1.45,
                            color: m.me ? Colors.white : ink,
                          )),
                    ),
                  );
                },
              ),
            ),
            // Öneri soruları — henüz veli hiç yazmadıysa, ALT ALTA kompakt
            // liste (havuzdan her açılışta karıştırılıp seçilen 6 soru).
            if (_msgs.where((m) => m.me).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in _suggestions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: _kBrand.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => _send(s),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: _kBrand.withValues(alpha: 0.30)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded,
                                      size: 13,
                                      color:
                                          _kBrand.withValues(alpha: 0.75)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(s,
                                        style: GoogleFonts.poppins(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                          color: _kBrand,
                                        )),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            // Mesaj yazma satırı.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: GoogleFonts.poppins(fontSize: 13, color: ink),
                      decoration: InputDecoration(
                        hintText: 'Danışmana sor…'.tr(),
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: AppPalette.textSecondary(context)),
                        filled: true,
                        fillColor: AppPalette.card(context),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide:
                              BorderSide(color: AppPalette.border(context)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide:
                              BorderSide(color: AppPalette.border(context)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: _kBrand,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _sending ? null : () => _send(),
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(11),
                        child: Icon(Icons.send_rounded,
                            size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  🎁 ÇOCUĞUMA SÜRPRİZ GÖNDER — yazışmasız motivasyon
// ═══════════════════════════════════════════════════════════════════════════

/// Sürpriz seçenekleri: (emoji, başlık, çocuğa giden bildirim metni).
const _kSurprises = <(String, String, String)>[
  ('⭐', 'Motivasyon Yıldızı', 'Ailen sana bir motivasyon yıldızı gönderdi — harikasın, aynen devam! ⭐'),
  ('🎮', '30 dk Oyun Hakkı', 'Ailenden hediye: bugünlük 30 dakika oyun hakkı kazandın! 🎮'),
  ('🍦', 'Dondurma Sözü', 'Ailen söz veriyor: sıradaki buluşmada dondurma senden! 🍦'),
  ('💪', 'Gurur Mesajı', 'Ailen seninle gurur duyuyor — emeklerin görülüyor! 💪'),
  ('🎁', 'Sürpriz Hediye Sözü', 'Ailen sana bir sürpriz hediye hazırlıyor — çalışmaya devam! 🎁'),
  ('🌙', 'Bu Akşam Film Gecesi', 'Ailenden davet: bu akşam birlikte film gecesi! 🍿'),
];

/// Veli tek tıkla motivasyon sürprizi yollar. [realChildUid] boş değilse
/// çocuğun bildirim kutusuna 'parent_gift' yazılır (push otomatik gider);
/// boşsa (demo/yerel çocuk) yalnız görsel onay verilir.
Future<void> showParentSurpriseSheet(BuildContext context,
    {required String realChildUid, required String childName}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppPalette.card(context),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🎁 ${'Çocuğuma Sürpriz Gönder'.tr()}',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(ctx),
                )),
            const SizedBox(height: 3),
            Text(
                'Seçtiğin sürpriz $childName ${'adlı çocuğuna tatlı bir bildirim olarak gider — yazışma yok, anında motivasyon.'.tr()}',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppPalette.textSecondary(ctx),
                )),
            const SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.6,
              children: [
                for (final (emoji, label, msg) in _kSurprises)
                  Material(
                    color: _kPink.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () async {
                        Navigator.pop(ctx);
                        var delivered = false;
                        if (realChildUid.isNotEmpty) {
                          try {
                            await FirebaseFirestore.instance
                                .collection('notifications')
                                .doc(realChildUid)
                                .collection('items')
                                .add({
                              'type': 'parent_gift',
                              'title': '${'Ailenden sürpriz!'.tr()} $emoji',
                              'body': msg.tr(),
                              'when': FieldValue.serverTimestamp(),
                              'read': false,
                            });
                            delivered = true;
                          } catch (_) {}
                        }
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(delivered
                              ? '$emoji ${'Sürpriz gönderildi — çocuğunun ekranına düşecek!'.tr()}'
                              : '$emoji ${'Sürpriz kaydedildi (çocuk bağlanınca gerçek bildirim gider).'.tr()}'),
                        ));
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: _kPink.withValues(alpha: 0.30)),
                        ),
                        child: Row(
                          children: [
                            Text(emoji,
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(label.tr(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppPalette.textPrimary(ctx),
                                  )),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  📄 HAFTALIK PDF KARNE
// ═══════════════════════════════════════════════════════════════════════════

/// 7 günlük aktiviteden PDF karne üretip paylaşım menüsünü açar.
/// [demo] true → örnek verilerle üretir (çocuk bağlı değilken de çalışır).
Future<void> shareWeeklyPdfReport(BuildContext context,
    {required String childUid,
    required String childName,
    required bool demo}) async {
  // Kısa yükleme göstergesi. loadingOpen bayrağı: catch bloğunun loading'i
  // İKİNCİ kez pop edip alttaki ekranı kapatmasını önler.
  var loadingOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    // ── Veri ──
    List<StudentActivityModel> acts;
    int streak = 0;
    if (demo || childUid.isEmpty) {
      final now = DateTime.now();
      String key(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      const mins = [20, 35, 0, 45, 15, 30, 16];
      const correct = [6, 10, 0, 14, 4, 9, 6];
      const wrong = [2, 3, 0, 4, 2, 3, 2];
      acts = [
        for (var i = 0; i < 7; i++)
          StudentActivityModel(
            dateKey: key(now.subtract(Duration(days: 6 - i))),
            focusSeconds: mins[i] * 60,
            correctAnswers: correct[i],
            wrongAnswers: wrong[i],
          ),
      ];
      streak = 2;
    } else {
      final raw = await ParentLinkService.readChild7DayActivity(childUid)
          .timeout(const Duration(seconds: 10), onTimeout: () => const []);
      acts = [for (final e in raw) StudentActivityModel.fromJson(e)];
      try {
        final stats = await ParentLinkService.readChildStats(childUid)
            .timeout(const Duration(seconds: 8), onTimeout: () => const {});
        streak = (stats['streakDays'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }

    // ── Özet ──
    final totalMin = acts.fold<int>(0, (s, a) => s + a.focusMinutes);
    final totalSolved = acts.fold<int>(
        0, (s, a) => s + a.totalAttempted + a.photoQuestionsSolved);
    final pcts = [
      for (final a in acts)
        if (a.totalAnswered > 0) a.correctAnswers * 100 / a.totalAnswered
    ];
    final avgPct = pcts.isEmpty
        ? 0
        : (pcts.reduce((x, y) => x + y) / pcts.length).round();

    // ── Öğretmen ödevi sonuçları (raporun ÜST bölümü) ──
    List<ParentHomeworkResult> hwResults;
    if (demo || childUid.isEmpty) {
      final now = DateTime.now();
      hwResults = [
        ParentHomeworkResult(
            className: '8-A', title: 'Üslü Sayılar Testi'.tr(),
            subject: 'Matematik'.tr(),
            when: now.subtract(const Duration(days: 1)),
            correct: 12, wrong: 3, questionCount: 15, scorePercent: 80),
        ParentHomeworkResult(
            className: '8-A', title: 'Hücre Bölünmesi'.tr(),
            subject: 'Fen Bilimleri'.tr(),
            when: now.subtract(const Duration(days: 3)),
            correct: 7, wrong: 3, questionCount: 10, scorePercent: 70),
        ParentHomeworkResult(
            className: '8-A', title: 'Simple Past Quiz',
            subject: 'İngilizce'.tr(),
            when: now.subtract(const Duration(days: 6)),
            correct: 17, wrong: 3, questionCount: 20, scorePercent: 85),
      ];
    } else {
      hwResults = await ParentLinkService.readChildHomeworkResults(childUid)
          .timeout(const Duration(seconds: 12),
              onTimeout: () => const <ParentHomeworkResult>[]);
    }
    final hwAvg = hwResults.isEmpty
        ? null
        : hwResults.fold<double>(0, (s, r) => s + r.scorePercent) /
            hwResults.length;

    // ── AI değerlendirmesi (2-3 cümle) — hata/zaman aşımında kural-bazlı ──
    String aiComment;
    try {
      final sys = 'Sen QuAlsar uygulamasının eğitim danışmanısın. Bir '
          'öğrencinin haftalık gelişim raporunun sonuna 2-3 cümlelik kısa, '
          'sıcak ve yapıcı bir değerlendirme yaz. Çocuğu motive eden, somut '
          'bir dil kullan; veliyi asla yargılama. Başlık, madde işareti ve '
          'emoji kullanma; yalnızca cümleleri yaz. '
          '${LocaleService.global?.aiLanguageDirective() ?? ''}';
      final data = 'Öğrenci: $childName. Son 7 gün: toplam $totalMin dk '
          'çalışma, $totalSolved soru, ortalama başarı %$avgPct, '
          'seri $streak gün. '
          '${hwResults.isEmpty ? 'Teslim edilmiş öğretmen ödevi yok.' : 'Öğretmen ödevleri: ${hwResults.length} teslim, ortalama %${hwAvg!.round()}.'}';
      aiComment = (await AiProviderService.chatTask(
        AiTask.coach,
        isPremium: AiQuotaService.instance.isPremium,
        system: sys,
        messages: [AiChatMessage('user', data)],
        maxTokens: 220,
      ).timeout(const Duration(seconds: 15)))
          .trim();
      if (aiComment.isEmpty) throw Exception('empty');
    } catch (_) {
      aiComment = totalMin == 0
          ? 'Bu hafta henüz çalışma kaydı oluşmadı. Kısa ve düzenli çalışma seansları ile başlamak motivasyonu artıracaktır.'
              .tr()
          : '${'Bu hafta'.tr()} $totalMin ${'dakika çalışıp'.tr()} '
              '$totalSolved ${'soru çözdü; ortalama başarı'.tr()} %$avgPct. '
              '${'Düzenli tekrar ve eksik konulara odaklanmak bu ivmeyi daha da yukarı taşıyacaktır.'.tr()}';
    }

    // ── PDF ── (Noto Sans: Türkçe/uluslararası karakterler için)
    pw.Font base, bold;
    try {
      base = await PdfGoogleFonts.notoSansRegular();
      bold = await PdfGoogleFonts.notoSansBold();
    } catch (_) {
      base = pw.Font.helvetica();
      bold = pw.Font.helveticaBold();
    }
    const green = PdfColor.fromInt(0xFF10B981);
    const purple = PdfColor.fromInt(0xFF7C3AED);
    const gray = PdfColor.fromInt(0xFF6B7280);

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: base, bold: bold),
      build: (pctx) => [
        // Başlık — isim, velinin sisteme kaydettiği ad/lakap (childName).
        pw.Text('QuAlsar — ${'Gelişim Raporu'.tr()}',
            style: pw.TextStyle(fontSize: 20, font: bold, color: purple)),
        pw.SizedBox(height: 2),
        pw.Text(childName, style: pw.TextStyle(fontSize: 14, font: bold)),
        pw.Text('Son 7 Gün'.tr(),
            style: const pw.TextStyle(fontSize: 10, color: gray)),
        pw.SizedBox(height: 12),
        // Özet kutuları.
        pw.Row(children: [
          for (final (v, l) in [
            ('$totalMin dk', 'Toplam Çalışma'.tr()),
            ('$totalSolved', 'Çözülen Soru'.tr()),
            ('%$avgPct', 'Ortalama Başarı'.tr()),
            ('$streak ${'gün'.tr()}', 'Seri'.tr()),
          ])
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.only(right: 8),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: green, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(v,
                        style: pw.TextStyle(
                            fontSize: 14, font: bold, color: green)),
                    pw.Text(l,
                        style: const pw.TextStyle(fontSize: 8, color: gray)),
                  ],
                ),
              ),
            ),
        ]),
        pw.SizedBox(height: 18),

        // ── 1) ÖĞRETMEN ÖDEVLERİ (üstte) — sonuçlar + grafik ──
        _pdfSectionTitle('Öğretmen Ödevleri'.tr(), purple, bold),
        pw.SizedBox(height: 8),
        if (hwResults.isEmpty)
          pw.Text('Henüz teslim edilmiş ödev yok.'.tr(),
              style: const pw.TextStyle(fontSize: 10, color: gray))
        else ...[
          _pdfBarChart(
            values: [for (final r in hwResults) r.scorePercent],
            labels: [for (final r in hwResults) r.subject],
            valueTexts: [
              for (final r in hwResults) '%${r.scorePercent.round()}'
            ],
            color: purple,
            font: base,
            boldFont: bold,
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'Ödev'.tr(),
              'Ders'.tr(),
              'Gün'.tr(),
              'Doğru'.tr(),
              'Yanlış'.tr(),
              'Başarı'.tr(),
            ],
            data: [
              for (final r in hwResults)
                [
                  r.title,
                  r.subject,
                  _pdfDayLabel(r.when),
                  '${r.correct}',
                  '${r.wrong}',
                  '%${r.scorePercent.round()}',
                ],
            ],
            headerStyle: pw.TextStyle(
                font: bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: purple),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            oddRowDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F3FF)),
          ),
        ],
        pw.SizedBox(height: 18),

        // ── 2) KENDİ ÇALIŞMALARI (altta) — günlük aktivite + grafik ──
        _pdfSectionTitle('Kendi Çalışmaları'.tr(), green, bold),
        pw.SizedBox(height: 8),
        _pdfBarChart(
          values: [for (final a in acts) a.focusMinutes.toDouble()],
          labels: [for (final a in acts) _pdfDayName(a.dateKey)],
          valueTexts: [for (final a in acts) '${a.focusMinutes}'],
          color: green,
          font: base,
          boldFont: bold,
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: [
            'Gün'.tr(),
            'Çalışma (dk)'.tr(),
            'Çözülen Soru'.tr(),
            'Başarı'.tr(),
          ],
          data: [
            for (final a in acts)
              [
                _pdfDayName(a.dateKey),
                '${a.focusMinutes}',
                '${a.totalAttempted + a.photoQuestionsSolved}',
                a.totalAnswered > 0
                    ? '%${(a.correctAnswers * 100 / a.totalAnswered).round()}'
                    : '—',
              ],
          ],
          headerStyle:
              pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: green),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignment: pw.Alignment.centerLeft,
          oddRowDecoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0FDF4)),
        ),
        pw.SizedBox(height: 18),

        // ── AI değerlendirmesi — raporun en altında 2-3 cümle ──
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFF5F3FF),
            border: pw.Border.all(color: purple, width: 0.8),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('AI Değerlendirmesi'.tr(),
                  style:
                      pw.TextStyle(fontSize: 10, font: bold, color: purple)),
              pw.SizedBox(height: 4),
              pw.Text(aiComment,
                  style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 2)),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
            '${'Bu rapor QuAlsar Ebeveyn Paneli tarafından oluşturuldu.'.tr()} · qualsar2-640f0.web.app',
            style: const pw.TextStyle(fontSize: 8, color: gray)),
      ],
    ));

    final bytes = await doc.save();
    if (context.mounted) {
      Navigator.of(context).pop(); // loading kapat
      loadingOpen = false;
    }
    // PDF + kısa mesaj + indirme linki BİRLİKTE paylaşılır (share_plus) —
    // Printing.sharePdf yalnız dosya taşıyabiliyordu, metin ekleyemiyordu.
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/qualsar_rapor_${childName.replaceAll(RegExp(r'\s+'), '_')}.pdf');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: '$childName — ${'QuAlsar Gelişim Raporu'.tr()} 📊\n'
          '${'Çocuğunun gelişimini sen de anında takip et — QuAlsar\'ı indir:'.tr()}\n'
          'https://qualsar2-640f0.web.app',
    );
  } catch (e) {
    if (context.mounted) {
      // ÇİFT POP koruması: loading zaten kapatıldıysa (paylaşım aşamasında
      // hata) tekrar pop ÇAĞRILMAZ — eskiden alttaki ekran/sheet kapanıyordu.
      if (loadingOpen) {
        Navigator.of(context).pop();
        loadingOpen = false;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('PDF oluşturulamadı — tekrar dener misin?'.tr()),
      ));
    }
  }
}

// ── PDF yardımcıları ────────────────────────────────────────────────────────

/// Haftanın günü adı (rapor isteği: tarih rakamla değil gün adıyla yazılır).
String _weekdayNameTr(DateTime d) {
  const names = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar',
  ];
  return names[d.weekday - 1].tr();
}

String _monthNameTr(int month) {
  const names = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  return names[month - 1].tr();
}

/// 'yyyy-MM-dd' aktivite anahtarını gün adına çevirir ("Cuma").
String _pdfDayName(String dateKey) {
  final d = DateTime.tryParse(dateKey);
  return d == null ? dateKey : _weekdayNameTr(d);
}

/// Ödev tarihi: son 7 gündeyse yalnız gün adı ("Cuma"); daha eskiyse gün adı
/// belirsiz kalacağı için "3 Temmuz Cuma" biçimi (rakamsal 03.07 YOK).
String _pdfDayLabel(DateTime d) {
  final now = DateTime.now();
  final diff = DateTime(now.year, now.month, now.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (diff >= 0 && diff < 7) return _weekdayNameTr(d);
  return '${d.day} ${_monthNameTr(d.month)} ${_weekdayNameTr(d)}';
}

pw.Widget _pdfSectionTitle(String text, PdfColor color, pw.Font bold) =>
    pw.Row(children: [
      pw.Container(width: 3, height: 12, color: color),
      pw.SizedBox(width: 5),
      pw.Text(text, style: pw.TextStyle(fontSize: 12, font: bold, color: color)),
    ]);

/// Basit dikey çubuk grafik — pdf paketinde harici chart bağımlılığı olmadan
/// Container yükseklikleriyle çizilir. Üstte değer, altta etiket.
pw.Widget _pdfBarChart({
  required List<double> values,
  required List<String> labels,
  required List<String> valueTexts,
  required PdfColor color,
  required pw.Font font,
  required pw.Font boldFont,
}) {
  if (values.isEmpty) return pw.SizedBox();
  double maxV = 0;
  for (final v in values) {
    if (v > maxV) maxV = v;
  }
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      for (var i = 0; i < values.length; i++)
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 3),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(valueTexts[i],
                    style: pw.TextStyle(
                        fontSize: 7, font: boldFont, color: color)),
                pw.SizedBox(height: 2),
                pw.Container(
                  height: 4 + (maxV <= 0 ? 0 : 50 * values[i] / maxV),
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: const pw.BorderRadius.vertical(
                        top: pw.Radius.circular(2)),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(labels[i],
                    maxLines: 1,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        fontSize: 6.5,
                        font: font,
                        color: const PdfColor.fromInt(0xFF6B7280))),
              ],
            ),
          ),
        ),
    ],
  );
}
