// ═══════════════════════════════════════════════════════════════════════════════
//  BİLGİ LİGİ
//
//  3 katmanlı sıralama deneyimi:
//
//    [Şehir | Ülke | Dünya]                ← coğrafi kapsam
//    [Ders  | Konu  | Genel]               ← filtre granülerliği
//      Ders  → ders seç → o dersin tüm konularındaki ortalama
//      Konu  → ders + konu seç → sadece o konu
//      Genel → seçim yok, kullanıcının çözdüğü her şeyin ortalaması
//    [Günlük | Haftalık | Aylık | Genel]   ← periyot
//    [Liderlik tablosu]                     ← seçimlere göre filtrelenmiş
//
//  Skorlar `LeagueScores` (SharedPref) üzerinden — her quiz attempt liste
//  olarak saklanır, ortalamalar runtime'da hesaplanır. Backend bağlanınca
//  Firestore'a aynı şema (subjectKey, topic, score, when) ile aktarılır.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/leaderboard/domain/user_location.dart';
import '../features/league/league_leaderboard_service.dart';
import '../features/league/league_location_picker.dart';
import '../features/league/league_scores.dart';
import '../services/analytics.dart';
import '../services/curriculum_catalog.dart';
import '../services/education_profile.dart';
import '../services/exam_catalog.dart';
import '../widgets/exam_mode_widgets.dart';
import '../services/error_logger.dart';
import '../services/runtime_translator.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../services/ai_quota_service.dart';
import '../services/parent_preview.dart';
import 'bilgi_ligi_quiz_screen.dart';
import 'premium_screen.dart';

enum _Scope { city, country, world }

enum _Mode { subject, overall }

extension _ScopeX on _Scope {
  String get label {
    switch (this) {
      case _Scope.city:
        return 'Şehir'.tr();
      case _Scope.country:
        return 'Ülke'.tr();
      case _Scope.world:
        return 'Dünya'.tr();
    }
  }
}

/// (Eski landmark map — şu an scope row'da kullanılmıyor; ileride ihtiyaç
///  olursa hazır kalsın diye duruyor.)
// ignore: unused_element
const Map<String, String> _cityEmojiMap = {
  'istanbul': '🕌',
  'ankara': '🏛️',
  'izmir': '⚓',
  'bursa': '⛰️',
  'antalya': '🌴',
  'adana': '🌶️',
  'konya': '🌷',
  'eskisehir': '🌸',
  'trabzon': '🌊',
  'gaziantep': '🥙',
  'kayseri': '🏔️',
  'samsun': '🚢',
  'mersin': '🍋',
  'diyarbakir': '🏰',
  'sanliurfa': '☀️',
  'mugla': '🏖️',
  'aydin': '🍇',
  'denizli': '🐓',
  'erzurum': '🐎',
  'van': '🐈',
  'new_york': '🗽',
  'london': '🎡',
  'paris': '🗼',
  'tokyo': '🗾',
  'berlin': '🐻',
  'rome': '🏟️',
};

// ignore: unused_element
String _cityEmoji(String? cityCode) =>
    _cityEmojiMap[(cityCode ?? '').toLowerCase()] ?? '🏙️';

extension _ModeX on _Mode {
  String get label {
    switch (this) {
      case _Mode.subject:
        return 'Ders'.tr();
      case _Mode.overall:
        return 'Genel'.tr();
    }
  }

  /// Pill içinde başlığın altına çıkan kısa açıklama.
  // ignore: unused_element
  String get subtitle {
    switch (this) {
      case _Mode.subject:
        return 'Ders bazında sıralama'.tr();
      case _Mode.overall:
        return 'Tüm derslerde sıralama'.tr();
    }
  }

  IconData get icon {
    switch (this) {
      case _Mode.subject:
        return Icons.menu_book_rounded;
      case _Mode.overall:
        return Icons.workspace_premium_rounded;
    }
  }
}

extension _PeriodLabel on LeaguePeriod {
  String get label {
    switch (this) {
      case LeaguePeriod.daily:
        return 'Günlük'.tr();
      case LeaguePeriod.weekly:
        return 'Haftalık'.tr();
      case LeaguePeriod.monthly:
        return 'Aylık'.tr();
      case LeaguePeriod.allTime:
        return 'Genel'.tr();
    }
  }
}

// ── Mock liderlik üretici ───────────────────────────────────────────────────
class _LbEntry {
  final int rank;
  final String name;
  final String avatar;
  final String location;
  final double score;
  final bool isMe;
  const _LbEntry({
    required this.rank,
    required this.name,
    required this.avatar,
    required this.location,
    required this.score,
    this.isMe = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BİLGİ LİGİ — Nasıl Çalışır rehber sayfası
//
//  AppBar'daki "?" butonuna basınca açılır. 6 adım kartı + alttaki büyük
//  CTA buton. Her kart: ikon + başlık + açıklama. Renkler turuncu/mor
//  paletten — Bilgi Ligi ana sayfasıyla aynı dil.
// ═══════════════════════════════════════════════════════════════════════════════
class _BilgiLigiHowItWorksPage extends StatelessWidget {
  const _BilgiLigiHowItWorksPage();

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6A00);
    const purple = Color(0xFF7C3AED);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          color: AppPalette.textPrimary(context),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Nasıl Çalışır?'.tr(),
          style: GoogleFonts.fraunces(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppPalette.textPrimary(context),
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Üst banner — büyük başlık + tek cümlelik özet
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [orange, Color(0xFFFF8A3C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: orange.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 32)),
                  const SizedBox(height: 8),
                  Text(
                    'Bilgi Ligi nedir?'.tr(),
                    style: GoogleFonts.fraunces(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Test çöz, puan kazan, şehrinde-ülkende-dünyada sıralanmaya başla. Her doğru cevap +1 puan; hızlı çözen üst sıraya çıkar.'
                        .tr(),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // 6 adım kartı
            _HowStepCard(
              step: 1,
              icon: Icons.menu_book_rounded,
              title: 'Dersini seç'.tr(),
              desc:
                  'Üstteki "Ders Seç" butonundan bir ders, sonra konu seç.'.tr(),
              accent: purple,
            ),
            _HowStepCard(
              step: 2,
              icon: Icons.quiz_rounded,
              title: '10 soruyu çöz'.tr(),
              desc:
                  'Çoktan seçmeli 10 soru. Süre tutulur — eşit puanda hızlı olan üstte. Yanlış cevaplar net puandan düşülür (ÖSYM tarzı).'.tr(),
              accent: purple,
            ),
            _HowStepCard(
              step: 3,
              icon: Icons.location_on_rounded,
              title: 'Konum seç'.tr(),
              desc:
                  'Hangi şehirde-ülkede sıralandığını görmek için konum seç. Şehir / Ülke / Dünya filtresinden istediğin kapsama geç.'.tr(),
              accent: orange,
            ),
            _HowStepCard(
              step: 4,
              icon: Icons.access_time_rounded,
              title: 'Periyot seç'.tr(),
              desc:
                  'Günlük • Haftalık • Aylık • Genel. Günlük seçersen TÜM kullanıcılar O GÜN için aynı 10 soruyu çözer — adil challenge.'.tr(),
              accent: orange,
            ),
            _HowStepCard(
              step: 5,
              icon: Icons.local_fire_department_rounded,
              title: 'Streak\'i koru'.tr(),
              desc:
                  'Her gün en az 1 test çöz, 🔥 streak göstergesin büyür. 7 gün üst üste = +rozet, ek motivasyon.'.tr(),
              accent: orange,
            ),
            _HowStepCard(
              step: 6,
              icon: Icons.emoji_events_rounded,
              title: 'Podyuma çık'.tr(),
              desc:
                  'İlk 3 sıraya girersen 🥇🥈🥉 podyumda görünürsün. Yakın rakipler kartı kaç puan farkla yükseleceğini söyler.'.tr(),
              accent: purple,
            ),
            const SizedBox(height: 18),
            // İpucu kartı
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: purple.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cloud\'a bağlanamazsan örnek bir liste gösterilir. Test çözünce skorun gerçek sıralamaya yazılır, anında podyuma yansır.'
                          .tr(),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textPrimary(context),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Alt CTA — kapatıp teste başla
            SizedBox(
              width: double.infinity,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [orange, Color(0xFFFF8A3C)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: orange.withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 22),
                        const SizedBox(width: 6),
                        Text(
                          'Anladım, başla'.tr(),
                          style: GoogleFonts.inter(
                            fontSize: 15,
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
      ),
    );
  }
}

class _HowStepCard extends StatelessWidget {
  final int step;
  final IconData icon;
  final String title;
  final String desc;
  final Color accent;
  const _HowStepCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.desc,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numara + ikon kombosu
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent,
                  accent.withValues(alpha: 0.70),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.30),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: accent, width: 1.5),
                    ),
                    child: Text(
                      '$step',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppPalette.textSecondary(context),
                    height: 1.4,
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

// ─── Yakın rakip satırı (1 üst / 1 alt motivasyon kartı içinde) ──────────────
enum _RivalDir { above, below }

class _RivalRow extends StatelessWidget {
  final _RivalDir direction;
  final _LbEntry entry;
  final double diff;
  const _RivalRow({
    required this.direction,
    required this.entry,
    required this.diff,
  });

  @override
  Widget build(BuildContext context) {
    final isAbove = direction == _RivalDir.above;
    final color = isAbove ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    final arrow = isAbove
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;
    final absDiff = diff.abs();
    final diffStr = absDiff == absDiff.truncateToDouble()
        ? absDiff.toInt().toString()
        : absDiff.toStringAsFixed(1);
    final message = isAbove
        ? '$diffStr ${"puan geride · geçmek için bir test daha".tr()}'
        : '$diffStr ${"puan önde · arayı koruyabilirsin".tr()}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(arrow, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            entry.avatar.isEmpty ? '👤' : entry.avatar,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
                Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Text(
            entry.score.toStringAsFixed(0),
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppPalette.textPrimary(context),
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top 3 podyum widget'ı ───────────────────────────────────────────────────
// Liderlik tablosunun üst kısmında — altın/gümüş/bronz görsel kart.
// İlk 3 kullanıcı için podium şeklinde dizilir (1. ortada en yüksek, 2. solda,
// 3. sağda). Kullanıcı kendisi top 3'teyse altın çerçeve highlight'ı alır.
class _LeaderboardPodium extends StatelessWidget {
  final List<_LbEntry> top3;
  const _LeaderboardPodium({required this.top3});

  @override
  Widget build(BuildContext context) {
    if (top3.isEmpty) return const SizedBox.shrink();
    // Sıralama: 2 (sol kısa) — 1 (orta uzun) — 3 (sağ orta)
    final p1 = top3.isNotEmpty ? top3[0] : null;
    final p2 = top3.length > 1 ? top3[1] : null;
    final p3 = top3.length > 2 ? top3[2] : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFF7E6),
            const Color(0xFFFFE4D2),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          bottom: BorderSide(color: AppPalette.border(context), width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _PodiumColumn(entry: p2, place: 2)),
          Expanded(child: _PodiumColumn(entry: p1, place: 1)),
          Expanded(child: _PodiumColumn(entry: p3, place: 3)),
        ],
      ),
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  final _LbEntry? entry;
  final int place; // 1, 2, 3
  const _PodiumColumn({required this.entry, required this.place});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final isFirst = place == 1;
    final medalColor = switch (place) {
      1 => const Color(0xFFFFB300), // altın
      2 => const Color(0xFFB0B7BF), // gümüş
      _ => const Color(0xFFCD7F32), // bronz
    };
    final medalIcon = switch (place) {
      1 => '🥇',
      2 => '🥈',
      _ => '🥉',
    };
    final pedestalHeight = switch (place) {
      1 => 56.0,
      2 => 38.0,
      _ => 28.0,
    };
    final avatarSize = isFirst ? 48.0 : 40.0;
    final isMe = e?.isMe ?? false;

    if (e == null) {
      // Boş slot — siluet
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppPalette.cardMuted(context),
            ),
            alignment: Alignment.center,
            child: Text(medalIcon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(height: 6),
          Text(
            '—',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppPalette.textSecondary(context),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: pedestalHeight,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: medalColor.withValues(alpha: 0.18),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8)),
            ),
            alignment: Alignment.center,
            child: Text(
              '$place',
              style: GoogleFonts.fraunces(
                fontSize: isFirst ? 22 : 18,
                fontWeight: FontWeight.w900,
                color: medalColor,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: isMe ? const Color(0xFFFF6A00) : medalColor,
                  width: isFirst ? 3 : 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: medalColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                e.avatar.isEmpty ? '👤' : e.avatar,
                style: TextStyle(fontSize: isFirst ? 22 : 18),
              ),
            ),
            Positioned(
              top: -8,
              child: Text(medalIcon,
                  style: TextStyle(fontSize: isFirst ? 22 : 18)),
            ),
            if (isMe)
              Positioned(
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6A00),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'SEN'.tr(),
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          e.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: isFirst ? 12 : 11,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          e.score.toStringAsFixed(0),
          style: GoogleFonts.fraunces(
            fontSize: isFirst ? 14 : 12,
            fontWeight: FontWeight.w800,
            color: medalColor,
          ),
        ),
        Container(
          height: pedestalHeight,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                medalColor.withValues(alpha: 0.85),
                medalColor.withValues(alpha: 0.55),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8)),
          ),
          alignment: Alignment.center,
          child: Text(
            '$place',
            style: GoogleFonts.fraunces(
              fontSize: isFirst ? 24 : 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Pinned sliver delegate — `CustomScrollView` içinde sticky filter bar ve
/// sticky kolon başlığı için. Background renk page bg ile aynı tutulur ki
/// scroll edilen içerik altta kaymış olsa da pinned alanın altından görünmesin.
class _PinnedDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Color background;
  final Widget child;
  const _PinnedDelegate({
    required this.height,
    required this.background,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Açık clipping — child taşarsa siyah çerçeve değil, kırpılmış görünsün.
    return ClipRect(
      child: OverflowBox(
        minHeight: 0,
        maxHeight: height,
        alignment: Alignment.topCenter,
        child: Container(
          color: background,
          height: height,
          child: child,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedDelegate old) =>
      old.height != height ||
      old.background != background ||
      old.child != child;
}

/// "Senin Sıran" kartı — her zaman üstte görünür. Listede (top 50) varsa
/// `rank` değerini, yoksa `cloudRankFuture`'dan gelen değeri kullanır
/// (cloud query top 200'e kadar arar). Hiçbiri yoksa "—".
class _MyRankCard extends StatelessWidget {
  final int? rank;
  final Future<int?>? cloudRankFuture;
  final double totalScore;
  final String name;
  final String location;
  final bool hideLocation;
  /// Üst üste quiz çözülen gün sayısı. 0 ise rozet hiç gösterilmez.
  final int streakDays;
  const _MyRankCard({
    required this.rank,
    required this.cloudRankFuture,
    required this.totalScore,
    required this.name,
    required this.location,
    this.hideLocation = false,
    this.streakDays = 0,
  });

  String _fmtScore(double n) {
    if (n == n.truncateToDouble()) {
      final s = n.toInt().toString();
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    return n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    // "Senin Sıran" kartı yeşil tema (kullanıcı talebi).
    const green = Color(0xFF16A34A);
    Widget rankBadge(int? r) {
      final label = r == null ? '—' : '#$r';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: green,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: green.withValues(alpha: 0.30),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
      );
    }

    Widget body(int? resolvedRank) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              green.withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: green.withValues(alpha: 0.40)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            rankBadge(resolvedRank),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'SENİN SIRAN'.tr(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: green,
                          letterSpacing: 0.6,
                        ),
                      ),
                      if (streakDays > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFF6A00),
                                Color(0xFFFF3D00),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '🔥 $streakDays',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (!hideLocation && location.isNotEmpty)
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textSecondary(context),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmtScore(totalScore),
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(context),
                    letterSpacing: -0.6,
                  ),
                ),
                Text(
                  'puan'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6B7280),
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Listede konum biliniyorsa direkt göster. Bilinmiyorsa
    // cloudRankFuture'ı bekle — gelene kadar "—" göster.
    if (rank != null) return body(rank);
    if (cloudRankFuture == null) return body(null);
    return FutureBuilder<int?>(
      future: cloudRankFuture,
      builder: (ctx, snap) => body(snap.data),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
class BilgiLigiScreen extends StatefulWidget {
  const BilgiLigiScreen({super.key});

  @override
  State<BilgiLigiScreen> createState() => _BilgiLigiScreenState();
}

class _BilgiLigiScreenState extends State<BilgiLigiScreen> {
  EduProfile? _profile;
  List<CurriculumSubject> _subjects = const [];
  UserLocation? _location;
  bool _loading = true;

  CurriculumSubject? _subject;
  /// Son seçilen konu adı — Hero CTA'nın "Konu Seç" butonunda etiket olarak
  /// gösterilir; quiz başlatılınca _startQuizFor'a iletilir.
  String? _topic;
  _Scope _scope = _Scope.city;
  _Mode _mode = _Mode.subject;
  LeaguePeriod _period = LeaguePeriod.weekly;

  // Aktif filtreler için kullanıcının kendi skor özeti.
  LeagueScoreSummary _mySummary =
      const LeagueScoreSummary(average: null, best: null, total: 0, attempts: 0);

  /// Üst üste quiz çözülen gün sayısı (streak). 0 ise rozet gizlenir.
  int _streakDays = 0;

  // Liderlik tablosu future'ı — filtre değişince yeniden tetiklenir.
  // Real-time: snapshot stream'inden gelen her güncellemede Future.value()
  // ile yenilenir, FutureBuilder'lar otomatik rebuild olur.
  Future<List<LeagueLeaderRow>>? _leaderboardFuture;
  StreamSubscription<List<LeagueLeaderRow>>? _leaderboardSub;

  // Kullanıcının kendi sıra pozisyonu — top-50 dışına düşerse sticky bar'da
  // gösterilir. Leaderboard refresh ile birlikte tazelenir.
  Future<int?>? _myRankFuture;

  // Anonim mod toggle — leaderboard'da gerçek isim yerine "Öğrenci #abc12"
  // maskesi gösterilir. SharedPreferences'tan yüklenir, profilden değişir.
  bool _anonymousMode = false;
  static const _kAnonModeKey = 'bilgi_ligi_anonymous_mode';

  /// Profil ekranında kullanıcının kaydettiği tam adı (`profile_name`,
  /// ör. "Ali Yılmaz"). Leaderboard'da kullanıcı kendi satırında bu adı
  /// görür; cloud'a yazılan submission da öncelikle bu değeri kullanır.
  String _profileName = '';

  /// Filtre çerçevesinin (gri container) global pozisyonu — tüm anchored
  /// popup'lar bu çerçevenin tam altına yerleştirilir.
  final GlobalKey _filterFrameKey = GlobalKey();

  /// Hangi chip'in popup'ı açık — 0: ders & konu, 1: bölge, 2: zaman.
  /// Açık chip için yeşil çerçeve highlight. null → hiçbiri açık değil.
  int? _activeChipIndex;

  // Hero kartındaki Ders/Konu butonlarının altına yansıyan sayılar.
  // _attemptsBySubject  : "mat" → 5
  // _attemptsByTopic    : "mat|Fonksiyonlar" → 2
  Map<String, int> _attemptsBySubject = const {};
  Map<String, int> _attemptsByTopic = const {};

  @override
  void initState() {
    super.initState();
    Analytics.logFeatureOpen('league');
    _bootstrap();
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    _leaderboardSub?.cancel();
    _leaderboardSub = null;
    super.dispose();
  }

  Future<void> _bootstrap() async {
    EduProfile? prof;
    List<CurriculumSubject> subs = const [];
    UserLocation? loc;
    // Anonim mod + profil adını (isim + soyisim) yükle.
    try {
      final prefs = await SharedPreferences.getInstance();
      _anonymousMode = prefs.getBool(_kAnonModeKey) ?? false;
      _profileName = (prefs.getString('profile_name') ?? '').trim();
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'bilgi_ligi_screen'); }
    try {
      prof = await EduProfile.load();
    } catch (_) {/* yok say */}
    try {
      subs = curriculumFor(prof);
    } catch (_) {
      subs = const [];
    }
    try {
      await LeagueScores.migrateLegacyIfNeeded()
          .timeout(const Duration(seconds: 4));
    } catch (_) {/* migration başarısız → yeni format zaten boş */}
    try {
      loc = await _loadSavedLocation()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      loc = null;
    }

    if (!mounted) return;
    setState(() {
      _profile = prof;
      _subjects = subs;
      _subject = subs.isNotEmpty ? subs.first : null;
      _location = loc;
      _loading = false;
      // _subject null'sa subject filtresi anlamsız → overall'a düş.
      // (Yapım aşamasında ders havuzu yokken bile sayfa açılsın diye.)
      if (_subject == null) {
        _mode = _Mode.overall;
      }
    });

    // setState sonrası süslemeler — UI hazır, isterse arka planda çalışır.
    // 1) Gönderilememiş skorları (outbox) arka planda tekrar dene —
    //    zayıf ağda "kaybolan puan" kalmasın (idempotent, çift sayım yok).
    unawaited(LeagueScores.flushOutbox());
    // 2) Liderlik adını geriye dönük senkronize et — anonim mod veya profil
    //    adı değiştiyse eski kovalarda eski ad kalmasın. Değişiklik yoksa
    //    hiçbir ağ çağrısı yapmaz.
    unawaited(LeagueScores.syncDisplayName(_myDisplayName()));
    try {
      await _refreshMySummary();
    } catch (_) {/* yok say */}
    try {
      _refreshLeaderboard();
    } catch (_) {/* yok say */}
    try {
      await _refreshAttemptCounts();
    } catch (_) {/* yok say */}
    // Otomatik sheet artık AÇILMIYOR — kullanıcı CTA'ya basana kadar bekler.
  }

  /// Konum öncelik sırası:
  ///   1) SharedPref (yerel) — en hızlı, offline garanti
  ///   2) Firestore users/{uid}.location — eski yüklü cihazlardan göç için
  static const _locationPrefKey = 'world_ranking_location_v1';
  Future<UserLocation?> _loadSavedLocation() async {
    // Yerel
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_locationPrefKey);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        return UserLocation.fromJson(json);
      }
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'bilgi_ligi_screen'); }
    // Cloud yedek (eski sürümlerden)
    final fromCloud = await _loadLocationFromFirestore();
    if (fromCloud != null) {
      // Yerele de yaz, bir daha gerek kalmasın
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _locationPrefKey, jsonEncode(fromCloud.toJson()));
      } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'bilgi_ligi_screen'); }
    }
    return fromCloud;
  }

  /// Auth varsa users/{uid}.location'tan okur; yoksa null döner.
  /// Timeout: 4sn — ağ kopukluğunda UI takılmasın.
  Future<UserLocation?> _loadLocationFromFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return null;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 4));
      final data = doc.data();
      if (data == null) return null;
      final raw = data['location'];
      if (raw is Map) {
        return UserLocation.fromJson(raw.cast<String, dynamic>());
      }
    } catch (_) {/* offline / izin / timeout → null */}
    return null;
  }

  // ── Scope/Mode → service enum mapping ──────────────────────────────────────
  LeagueScope get _serviceScope => switch (_scope) {
        _Scope.city => LeagueScope.city,
        _Scope.country => LeagueScope.country,
        _Scope.world => LeagueScope.world,
      };
  LeagueMode get _serviceMode => switch (_mode) {
        // Ders modunda konu seçiliyse (Hero CTA'dan "Konu Seç") sıralama da
        // o konuya daralt — daha önce _topic görmezden gelinip her zaman
        // tüm ders için sıralama gösteriliyordu.
        _Mode.subject => _topic == null ? LeagueMode.subject : LeagueMode.topic,
        _Mode.overall => LeagueMode.overall,
      };

  // Filtre değişimleri art arda yapıldığında her birinde yeni Firestore
  // stream açmamak için 250ms debounce. Hızlı tıklamalarda son seçim aktif.
  Timer? _refreshDebounce;

  void _refreshLeaderboard() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), _doRefresh);
  }

  void _doRefresh() {
    // Önceki stream subscription'ı iptal et — filtre değişince eski abonelik
    // gereksiz yere setState tetiklemesin.
    _leaderboardSub?.cancel();
    _leaderboardSub = null;

    if (_profile == null || _location == null) {
      if (!mounted) return;
      setState(() {
        _leaderboardFuture = Future.value(const []);
        _myRankFuture = Future.value(null);
      });
      return;
    }
    // Real-time: snapshot stream'i kur, her emission'da future'ı güncel
    // listeyle yenile → tüm FutureBuilder'lar otomatik rebuild olur.
    final stream = LeagueLeaderboardService.watch(
      profile: _profile!,
      location: _location!,
      scope: _serviceScope,
      mode: _serviceMode,
      period: _period,
      subjectKey: _mode == _Mode.overall ? null : _subject?.key,
      topic: _mode == _Mode.overall ? null : _topic,
      limit: 50,
    );
    if (!mounted) return;
    setState(() {
      _leaderboardFuture = Future.value(const []);
      _myRankFuture = LeagueLeaderboardService.myRank(
        profile: _profile!,
        location: _location!,
        scope: _serviceScope,
        mode: _serviceMode,
        period: _period,
        subjectKey: _mode == _Mode.overall ? null : _subject?.key,
        topic: _mode == _Mode.overall ? null : _topic,
      );
    });
    _leaderboardSub = stream.listen((rows) {
      if (!mounted) return;
      setState(() {
        _leaderboardFuture = Future.value(rows);
      });
    }, onError: (e) {
      debugPrint('[bilgi_ligi_screen] leaderboard stream error: $e');
    });
  }

  Future<void> _refreshMySummary() async {
    LeagueScoreSummary s;
    String modeKey;
    switch (_mode) {
      case _Mode.overall:
        s = await LeagueScores.overall(period: _period);
        modeKey = 'all';
        break;
      case _Mode.subject:
        if (_subject == null) {
          s = const LeagueScoreSummary(average: null, best: null, total: 0, attempts: 0);
          modeKey = 'all';
        } else if (_topic != null) {
          // Konu seçiliyse özet de o konuya daralt — aksi halde "Senin
          // Sıran" kartı hep tüm dersin ortalamasını gösteriyordu.
          s = await LeagueScores.forTopic(
            subjectKey: _subject!.key,
            topic: _topic!,
            period: _period,
          );
          modeKey = 't:${_subject!.key}|$_topic';
        } else {
          s = await LeagueScores.forSubject(
            subjectKey: _subject!.key,
            period: _period,
          );
          modeKey = 's:${_subject!.key}';
        }
        break;
    }
    // BULUT DOĞRULAMA: "Senin Sıran" kartı, liderlik tablosunun okuduğu
    // league_totals dokümanıyla AYNI kaynağı göstersin. Yerel kayıt
    // (yeniden kurulum, ikinci cihaz, offline dönem) buluttan sapmış
    // olabilir — bulut varsa toplam/deneme sayısı oradan alınır.
    try {
      final cloud = await LeagueScores.myCloudTotal(
        modeKey: modeKey,
        period: _period,
      );
      if (cloud != null && cloud.attempts > 0) {
        s = LeagueScoreSummary(
          average: cloud.score / cloud.attempts,
          best: s.best, // tekil en-iyi yalnız yerelde tutuluyor
          total: cloud.score,
          attempts: cloud.attempts,
        );
      }
    } catch (_) {/* offline → yerel özet zaten elimizde */}
    int streak = 0;
    try {
      streak = await LeagueScores.currentStreak();
    } catch (_) {/* yok say */}
    if (!mounted) return;
    setState(() {
      _mySummary = s;
      _streakDays = streak;
    });
  }

  /// Kullanıcının daha önce test çözdüğü dersleri (LeagueScores'tan).
  /// Liste, mevcut müfredat dersleriyle eşleşenleri içerir.
  Future<List<CurriculumSubject>> _loadPlayedSubjects() async {
    final attempts = await LeagueScores.loadAll();
    final keys = attempts.map((a) => a.subjectKey).toSet();
    return _subjects.where((s) => keys.contains(s.key)).toList();
  }

  /// Tüm attempts'lerden ders/konu bazlı sayıları çıkar.
  Future<void> _refreshAttemptCounts() async {
    final attempts = await LeagueScores.loadAll();
    final bySubject = <String, int>{};
    final byTopic = <String, int>{};
    for (final a in attempts) {
      bySubject[a.subjectKey] = (bySubject[a.subjectKey] ?? 0) + 1;
      final t = a.topic;
      if (t != null && t.isNotEmpty) {
        final key = '${a.subjectKey}|$t';
        byTopic[key] = (byTopic[key] ?? 0) + 1;
      }
    }
    if (!mounted) return;
    setState(() {
      _attemptsBySubject = bySubject;
      _attemptsByTopic = byTopic;
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Çerçevelerin DIŞINDA kalan zemin — gri (telefon kenarı ile çerçeve arası).
    const bg = Color(0xFFEAEBEE);
    final isDark = AppPalette.isDark(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // NOT: Eskiden _subjects.isEmpty || _subject == null durumunda tam-sayfa
    // "Önce eğitim profilini seçmelisin" ekranı dönüyordu. Sayfayı bloke
    // ediyordu. Şimdi:
    //   • _subject null ise bootstrap'ta _mode = overall'a düşülür
    //   • Sayfa her zaman açılır, mock leaderboard görünür
    //   • Hero CTA'daki "Ders Seç" butonu kullanıcıyı ders seçmeye yönlendirir

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const SizedBox(height: 0),
            Expanded(
              // CustomScrollView ile iki sticky bölge:
              //   • Filtre çerçevesi (ders/bölge/zaman) → hero kayıp olunca üstte yapışır
              //   • Tablo sütun başlıkları (NO/KULLANICI/PUAN) → filtrenin altına yapışır
              // Kullanıcı satırları aralarında özgürce kayar.
              child: _buildScrollableContent(context, bg, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollableContent(
      BuildContext context, Color bg, bool isDark) {
    // Filtre çerçevesi yüksekliği — _buildFilterFrame ölçümü:
    //   container padding 8+10=18 + Column(14+38) = ~70; +üst/alt padding 12 → 100
    const filterBarHeight = 100.0;
    // NO/KULLANICI/PUAN başlık — krem zemin + 8+8 vertical padding + 14 text → ~36
    const columnHeaderHeight = 36.0;
    return CustomScrollView(
      slivers: [
        // ── Hero CTA (scroll'da kaybolur) ─────────────────────────────
        SliverToBoxAdapter(child: _buildHeroCta(context)),
        // ── Sınav Modu girişi — sadece ülkesi için sınav kataloğu tanımlıysa ──
        if (examGroupsFor(_profile?.country) != null) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverToBoxAdapter(child: _buildExamModeCta(context)),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        // ── Pinned filtre çerçevesi ───────────────────────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedDelegate(
            height: filterBarHeight,
            background: bg,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: _buildFilterFrame(context),
            ),
          ),
        ),
        // ── "Konumunu seç" banner kaldırıldı — kullanıcı onboarding'de
        //     şehrini zaten seçiyor; banner gereksiz yer kaplıyordu.
        // ── "Bu hafta X öğrenci katıldı" sosyal kanıt bar kaldırıldı —
        //     mock veri olmadan boş kalıyordu, kafa karıştırıyordu.
        // ── MyRank kartı (scroll'da kaybolur) ─────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: _buildMyRankCard(context),
          ),
        ),
        // ── Yakın rakipler kartı (1 üst + 1 alt + fark mesajı) ────────
        SliverToBoxAdapter(child: _buildNearbyRivalsCard(context)),
        // ── Pinned NO/KULLANICI/PUAN sütun başlığı ────────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedDelegate(
            height: columnHeaderHeight,
            background: bg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: const Color(0xFF111111).withValues(alpha: 0.10),
                      ),
                      left: BorderSide(
                        color: const Color(0xFF111111).withValues(alpha: 0.10),
                      ),
                      right: BorderSide(
                        color: const Color(0xFF111111).withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  child: _buildLeaderboardHeader(context),
                ),
              ),
            ),
          ),
        ),
        // ── Liderlik satırları (scroll) ───────────────────────────────
        SliverToBoxAdapter(child: _buildLeaderboardRowsCard(context)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  /// Liderlik satırları — beyaz konteyner, üst köşeleri düz (pinned header
  /// rounded-top'u taşıyor), alt köşeleri rounded.
  Widget _buildLeaderboardRowsCard(BuildContext context) {
    return FutureBuilder<List<LeagueLeaderRow>>(
      future: _leaderboardFuture,
      builder: (ctx, snap) {
        // Her zaman gerçek bulut verisi — boşsa boş gösterilir.
        final visibleEntries = _toLbEntries(snap.data ?? const []);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            decoration: BoxDecoration(
              color: AppPalette.card(context),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border(
                left: BorderSide(color: AppPalette.border(context)),
                right: BorderSide(color: AppPalette.border(context)),
                bottom: BorderSide(color: AppPalette.border(context)),
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header altı 1px ince ayraç
                Container(
                  height: 1,
                  color: AppPalette.border(context),
                ),
                // "İlk sıralamayı sen başlat / Teste Başla" CTA kaldırıldı —
                // kullanıcı Kütüphanem'den teste girebiliyor; bu sekmede
                // tekrar gösterilmesine gerek yok.
                // Podyum (Top 3) — liste boş değilse en üste yerleşir.
                if (visibleEntries.isNotEmpty)
                  _LeaderboardPodium(
                    top3: visibleEntries.take(3).toList(),
                  ),
                for (int i = 3; i < visibleEntries.length; i++)
                  _LeaderboardRow(
                    entry: visibleEntries[i],
                    isLast: i == visibleEntries.length - 1,
                    hideLocation: _scope == _Scope.city,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// MyRank kartını (her durumda göster) tek widget döndürür — slivers
  /// içinde kullanılır. FutureBuilder ile listedeki/cloud'daki sıra
  /// senkronize.
  Widget _buildMyRankCard(BuildContext context) {
    return FutureBuilder<List<LeagueLeaderRow>>(
      future: _leaderboardFuture,
      builder: (ctx, snap) {
        final entries = _toLbEntries(snap.data ?? const []);
        int? myRankInList;
        for (int i = 0; i < entries.length; i++) {
          if (entries[i].isMe) {
            myRankInList = i + 1;
            break;
          }
        }
        return _MyRankCard(
          rank: myRankInList,
          cloudRankFuture: _myRankFuture,
          totalScore: _mySummary.total,
          name: _myDisplayName(),
          location: _scope == _Scope.world
              ? (_location?.country ?? '')
              : (_location?.city ?? ''),
          hideLocation: _scope == _Scope.city,
          streakDays: _streakDays,
        );
      },
    );
  }

  /// Kullanıcının 1 üstündeki ve 1 altındaki rakipler — motivasyon kartı.
  /// Liste boşsa veya kullanıcı listede yoksa hiç gösterilmez.
  Widget _buildNearbyRivalsCard(BuildContext context) {
    return FutureBuilder<List<LeagueLeaderRow>>(
      future: _leaderboardFuture,
      builder: (ctx, snap) {
        final entries = _toLbEntries(snap.data ?? const []);
        int? myIdx;
        for (int i = 0; i < entries.length; i++) {
          if (entries[i].isMe) {
            myIdx = i;
            break;
          }
        }
        if (myIdx == null) return const SizedBox.shrink();
        if (entries.length < 2) return const SizedBox.shrink();

        final myScore = entries[myIdx].score;
        final above = myIdx > 0 ? entries[myIdx - 1] : null;
        final below = myIdx < entries.length - 1 ? entries[myIdx + 1] : null;
        if (above == null && below == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppPalette.card(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.border(context)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flash_on_rounded,
                        size: 14, color: Color(0xFF7C3AED)),
                    const SizedBox(width: 4),
                    Text(
                      'YAKIN RAKİPLER'.tr(),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF7C3AED),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (above != null)
                  _RivalRow(
                    direction: _RivalDir.above,
                    entry: above,
                    diff: above.score - myScore,
                  ),
                if (above != null && below != null)
                  const SizedBox(height: 6),
                if (below != null)
                  _RivalRow(
                    direction: _RivalDir.below,
                    entry: below,
                    diff: myScore - below.score,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Header (ortalanmış başlık) ──────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gerçek dünya görseli — stilize ikon yerine kıtalı dünya.
                const Text('🌍', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Dünya Sıralaması'.tr().toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.arrow_back_rounded,
                    color: AppPalette.textPrimary(context)),
                tooltip: 'Geri'.tr(),
              ),
              const Spacer(),
              // Yardım butonu — "Nasıl Çalışır?" rehberini açar. Yeni
              // kullanıcı sayfayı tanımak için tek tıkla turuncu kart
              // listesini görür.
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const _BilgiLigiHowItWorksPage(),
                    fullscreenDialog: true,
                  ));
                },
                icon: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF6A00).withValues(alpha: 0.15),
                    border: Border.all(
                      color: const Color(0xFFFF6A00).withValues(alpha: 0.50),
                      width: 1.5,
                    ),
                  ),
                  child: const Text(
                    '?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFF6A00),
                      height: 1.0,
                    ),
                  ),
                ),
                tooltip: 'Nasıl çalışır?'.tr(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Şehir | Ülke | Dünya — eski inline pill düzeni + üstte başlık ────────
  //   Şehir: 📍 (sabit, evrensel yer simgesi)
  //   Ülke:  bayrak (UserLocation.countryFlag)
  //   Dünya: 🌍
  // NOT: Yeni chip bar tasarımından sonra UI'dan kalktı; ileride başka bir
  // ekrana gömülmek için saklı tutuluyor.
  // ignore: unused_element
  Widget _buildScopeRow(BuildContext context) {
    const cityE = '📍';
    final countryE = _location?.countryFlag ?? '🏳️';
    final cityLabel = (_location?.city.isNotEmpty ?? false)
        ? _location!.city
        : _Scope.city.label;
    final countryLabel = (_location?.country.isNotEmpty ?? false)
        ? _location!.country
        : _Scope.country.label;
    final ink = AppPalette.textPrimary(context);
    const orange = Color(0xFFFF6A00);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, 'Hangi bölgeden sıralamayı yapalım?'.tr()),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: _ScopePill(
                  emoji: cityE,
                  label: cityLabel,
                  active: _scope == _Scope.city,
                  accent: orange,
                  inkColor: ink,
                  onTap: () {
                    setState(() => _scope = _Scope.city);
                    _refreshLeaderboard();
                  },
                ),
              ),
              Expanded(
                child: _ScopePill(
                  emoji: countryE,
                  label: countryLabel,
                  active: _scope == _Scope.country,
                  accent: orange,
                  inkColor: ink,
                  onTap: () {
                    setState(() => _scope = _Scope.country);
                    _refreshLeaderboard();
                  },
                ),
              ),
              Expanded(
                child: _ScopePill(
                  emoji: '🌍',
                  label: _Scope.world.label,
                  active: _scope == _Scope.world,
                  accent: orange,
                  inkColor: ink,
                  onTap: () async {
                    setState(() {
                      _scope = _Scope.world;
                      // Dünya scope'unda Günlük periyot anlamsız (zaman
                      // dilimi farkı) → otomatik haftalığa düşür.
                      if (_period == LeaguePeriod.daily) {
                        _period = LeaguePeriod.weekly;
                      }
                    });
                    await _refreshMySummary();
                    _refreshLeaderboard();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Koyu gri 3 sütunlu filtre barı (görsele uygun) ───────────────────────
  // Tek koyu container, içinde 3 dikey sütun: üstte uppercase başlık,
  // altta beyaz pill içinde emoji + mevcut seçim + chevron. Tap → bottom
  // sheet. Görseldeki "DERS & KONU · BÖLGE · ZAMAN" düzenini yansıtır.
  Widget _buildFilterFrame(BuildContext context) {
    final cityName = (_location?.city.isNotEmpty ?? false)
        ? _location!.city
        : _Scope.city.label;
    final countryName = (_location?.country.isNotEmpty ?? false)
        ? _location!.country
        : _Scope.country.label;
    final countryE = _location?.countryFlag ?? '🏳️';
    String scopeLabel;
    String scopeEmoji = '';
    IconData? scopeIcon;
    switch (_scope) {
      case _Scope.city:
        scopeLabel = cityName;
        // Klasik damla şekilli pin (Material) — kırmızı top emoji yerine.
        scopeIcon = Icons.location_on_rounded;
        break;
      case _Scope.country:
        scopeLabel = countryName;
        scopeEmoji = countryE;
        break;
      case _Scope.world:
        scopeLabel = _Scope.world.label;
        scopeEmoji = '🌍';
        break;
    }
    final modeLabel = _mode == _Mode.overall
        ? 'Tüm Dersler'.tr()
        : _topic != null
            ? '${_subject?.displayName ?? ''} ➔ $_topic'
            : (_subject?.displayName ?? 'Ders Seç'.tr());
    final modeEmoji = _mode == _Mode.overall ? '🌟' : (_subject?.emoji ?? '📖');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: KeyedSubtree(
        key: _filterFrameKey,
        child: Container(
          decoration: BoxDecoration(
            // Tema uyumlu çerçeve — koyu modda koyu kart + uygun border.
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppPalette.border(context),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _FilterColumn(
                  header: 'DERS'.tr(),
                  emoji: modeEmoji,
                  label: modeLabel,
                  selected: _activeChipIndex == 0,
                  onTap: _openModeFilterSheet,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _FilterColumn(
                  header: 'BÖLGE'.tr(),
                  emoji: scopeEmoji,
                  icon: scopeIcon,
                  label: scopeLabel,
                  selected: _activeChipIndex == 1,
                  onTap: _openScopeFilterSheet,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _FilterColumn(
                  header: 'ZAMAN'.tr(),
                  // Chip ikonu: kum saati — periyot popup'taki emojilerden
                  // farklı, "zaman" temasını net yansıtır.
                  emoji: '⏳',
                  label: _period.label,
                  selected: _activeChipIndex == 2,
                  onTap: _openPeriodFilterSheet,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter bottom sheet'leri ─────────────────────────────────────────────
  // Ortak iskelet: drag handle + başlık + dikey liste. Seçim sonrası
  // sheet pop edilir, leaderboard yenilenir.

  /// Filtre çerçevesinin (gri container) ekran üzerindeki konumunu döndürür:
  /// (bottomY, leftX, width). Popup'ları bu konumun hemen altına yerleştirmek
  /// için kullanılır. Başarısızsa null döner.
  ({double top, double left, double width})? _anchoredPopupRect() {
    final box =
        _filterFrameKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return null;
    final tl = box.localToGlobal(Offset.zero, ancestor: overlay);
    return (top: tl.dy + box.size.height + 6, left: tl.dx, width: box.size.width);
  }

  /// Ortak başlık satırı — tüm popup'ların üstünde ortalanmış uppercase.
  Widget _popupHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF4B5563),
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  /// Anchored popup iskeleti — başlık + içerik, filter frame'in altında.
  /// Active chip index'ini set/clear eder ki chip yeşil border alsın.
  Future<void> _showAnchoredPopup({
    required int chipIndex,
    required String headerText,
    required Widget Function(BuildContext ctx) builder,
  }) async {
    // Filtre çerçevesi ekranın altındaysa popup'a yer kalmıyor — önce sayfayı
    // yukarı kaydırıp çerçeveyi üste getir, sonra konumu ölç.
    final frameCtx = _filterFrameKey.currentContext;
    if (frameCtx != null) {
      await Scrollable.ensureVisible(
        frameCtx,
        alignment: 0.02,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      if (!mounted) return;
    }
    final rect = _anchoredPopupRect();
    if (rect == null) return;
    setState(() => _activeChipIndex = chipIndex);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black.withValues(alpha: 0.20),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, a1, a2) {
        final screen = MediaQuery.of(ctx).size;
        // Popup ekran dışına taşmasın: çapanın altında kalan gerçek alanla
        // sınırla — içerik zaten kendi içinde kaydırılıyor.
        final availBelow = screen.height -
            rect.top -
            MediaQuery.of(ctx).padding.bottom -
            12;
        final maxHeight =
            availBelow.clamp(220.0, screen.height * 0.62).toDouble();
        return Stack(
          children: [
            Positioned(
              top: rect.top,
              left: rect.left,
              width: rect.width,
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppPalette.card(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppPalette.border(context),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppPalette.shadow(context),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _popupHeader(headerText),
                          const SizedBox(height: 8),
                          Flexible(child: builder(ctx)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    if (mounted) setState(() => _activeChipIndex = null);
  }

  /// Ders/Konu popup'ı — frame altında açılır. "Tüm Dersler" + 2 sütunlu ders
  /// grid. Ana dersler (Matematik, Fizik, Kimya, Biyoloji, Tarih, Coğrafya,
  /// Edebiyat, Felsefe) en üstte; sonra kullanıcı favorileri; en sonda
  /// alfabetik. Sığmayanlar grid içinde dikey kaydırılır.
  Future<void> _openModeFilterSheet() async {
    const mainKeys = <String>[
      'math', 'physics', 'chem', 'bio',
      'history', 'geography', 'literature', 'philosophy',
    ];
    int priorityIndex(String k) {
      final i = mainKeys.indexOf(k);
      return i == -1 ? mainKeys.length : i;
    }
    final ordered = List<CurriculumSubject>.from(_subjects)
      ..sort((a, b) {
        final pa = priorityIndex(a.key);
        final pb = priorityIndex(b.key);
        if (pa != pb) return pa.compareTo(pb);
        final ca = _attemptsBySubject[a.key] ?? 0;
        final cb = _attemptsBySubject[b.key] ?? 0;
        if (ca != cb) return cb.compareTo(ca);
        return a.displayName.compareTo(b.displayName);
      });
    String query = '';
    await _showAnchoredPopup(
      chipIndex: 0,
      headerText: 'DERS'.tr(),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? ordered
              : ordered
                  .where((s) => s.displayName.toLowerCase().contains(q))
                  .toList();
          // "Tüm Dersler" satırı sadece arama boşken görünür.
          final showAll = q.isEmpty;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Arama kutusu — 55+ dersli müfredatta net hızlı erişim.
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppPalette.cardMuted(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.border(context)),
                ),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setLocal(() => query = v),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: InputBorder.none,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    hintText: 'Ders ara…'.tr(),
                    hintStyle: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppPalette.textSecondary(context),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: filtered.isEmpty && !showAll
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'Ders bulunamadı'.tr(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textSecondary(context),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 2.6,
                          children: [
                            if (showAll)
                              _modePopupTile(
                                ctx: ctx,
                                emoji: '🌟',
                                label: 'Tüm Dersler'.tr(),
                                selected: _mode == _Mode.overall,
                                onTap: () async {
                                  Navigator.of(ctx).pop();
                                  setState(() => _mode = _Mode.overall);
                                  await _refreshMySummary();
                                  _refreshLeaderboard();
                                },
                              ),
                            for (final s in filtered)
                              _modePopupTile(
                                ctx: ctx,
                                emoji: s.emoji,
                                label: s.displayName,
                                selected: _mode == _Mode.subject &&
                                    _subject?.key == s.key,
                                onTap: () async {
                                  Navigator.of(ctx).pop();
                                  setState(() {
                                    _subject = s;
                                    _topic = null;
                                    _mode = _Mode.subject;
                                  });
                                  await _refreshMySummary();
                                  _refreshLeaderboard();
                                },
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Popup içindeki ders tile'ı — kompakt emoji + isim. Seçili olunca
  /// turuncu border + soft turuncu zemin.
  Widget _modePopupTile({
    required BuildContext ctx,
    required String emoji,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    const orange = Color(0xFFFF6A00);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? orange.withValues(alpha: 0.10)
              : const Color(0xFFEDEFF2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? orange
                : const Color(0xFF111111).withValues(alpha: 0.06),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? orange : const Color(0xFF111111),
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Anchored popup başarısız olursa (RenderBox yok) eski bottom sheet'e düş.
  /// Şu an `_showAnchoredPopup` tüm 3 chip için kullanılıyor; bu fallback
  /// gelecekteki olası senaryolar için saklı.
  // ignore: unused_element
  Future<void> _openModeFilterAsSheet() async {
    final ordered = List<CurriculumSubject>.from(_subjects)
      ..sort((a, b) {
        final ca = _attemptsBySubject[a.key] ?? 0;
        final cb = _attemptsBySubject[b.key] ?? 0;
        if (ca != cb) return cb.compareTo(ca);
        return a.displayName.compareTo(b.displayName);
      });
    await _showFilterSheet(
      title: 'Hangi dersten sıralayalım?'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _filterRow(
            emoji: '🌟',
            label: 'Tüm Dersler'.tr(),
            selected: _mode == _Mode.overall,
            onTap: () async {
              Navigator.of(context).pop();
              setState(() => _mode = _Mode.overall);
              await _refreshMySummary();
              _refreshLeaderboard();
            },
          ),
          for (final s in ordered)
            _filterRow(
              emoji: s.emoji,
              label: s.displayName,
              attemptCount: _attemptsBySubject[s.key] ?? 0,
              selected:
                  _mode == _Mode.subject && _subject?.key == s.key,
              onTap: () async {
                Navigator.of(context).pop();
                setState(() {
                  _subject = s;
                  _topic = null;
                  _mode = _Mode.subject;
                });
                await _refreshMySummary();
                _refreshLeaderboard();
              },
            ),
        ],
      ),
    );
  }

  /// Bölge popup'ı — frame'in altında, ortalı başlık + 3 satırlı seçim.
  Future<void> _openScopeFilterSheet() async {
    final cityName = (_location?.city.isNotEmpty ?? false)
        ? _location!.city
        : _Scope.city.label;
    final countryName = (_location?.country.isNotEmpty ?? false)
        ? _location!.country
        : _Scope.country.label;
    final countryE = _location?.countryFlag ?? '🏳️';
    await _showAnchoredPopup(
      chipIndex: 1,
      headerText: 'BÖLGE'.tr(),
      builder: (ctx) => SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _filterRow(
              emoji: '',
              icon: Icons.location_on_rounded,
              label: cityName,
              selected: _scope == _Scope.city,
              onTap: () async {
                Navigator.of(ctx).pop();
                setState(() => _scope = _Scope.city);
                await _refreshMySummary();
                _refreshLeaderboard();
              },
            ),
            _filterRow(
              emoji: countryE,
              label: countryName,
              selected: _scope == _Scope.country,
              onTap: () async {
                Navigator.of(ctx).pop();
                setState(() => _scope = _Scope.country);
                await _refreshMySummary();
                _refreshLeaderboard();
              },
            ),
            _filterRow(
              emoji: '🌍',
              label: _Scope.world.label,
              selected: _scope == _Scope.world,
              onTap: () async {
                Navigator.of(ctx).pop();
                setState(() {
                  _scope = _Scope.world;
                  // Dünya scope'unda günlük periyot anlamsız → haftalığa düş.
                  if (_period == LeaguePeriod.daily) {
                    _period = LeaguePeriod.weekly;
                  }
                });
                await _refreshMySummary();
                _refreshLeaderboard();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Periyot için mantıklı emoji — her zaman aralığı kendi simgesini taşır.
  ///   Günlük  → ☀️  (tek gün, gündüz döngüsü)
  ///   Haftalık → 📅  (klasik takvim sayfası)
  ///   Aylık    → 📆  (yapraklı takvim, ay sembolü)
  ///   Genel    → 🏆  (tüm zamanların toplamı, başarı kupası)
  String _periodEmoji(LeaguePeriod p) {
    switch (p) {
      case LeaguePeriod.daily:
        return '☀️';
      case LeaguePeriod.weekly:
        return '📅';
      case LeaguePeriod.monthly:
        return '📆';
      case LeaguePeriod.allTime:
        return '🏆';
    }
  }

  /// Zaman popup'ı — frame'in altında, ortalı başlık + periyot listesi.
  /// Her periyot kendi anlamlı emojisiyle gösterilir.
  /// Dünya scope'unda Günlük gizli.
  Future<void> _openPeriodFilterSheet() async {
    final periods = _scope == _Scope.world
        ? LeaguePeriod.values
            .where((p) => p != LeaguePeriod.daily)
            .toList()
        : LeaguePeriod.values;
    // Günlük lig tüm dünyada AYNI anda (UTC gece yarısı) sıfırlanır —
    // kullanıcının kendi saat diliminde bunun kaça denk geldiğini göster.
    final nowUtc = LeagueScores.correctedNow().toUtc();
    final nextUtcMidnight =
        DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day)
            .add(const Duration(days: 1));
    final resetLocal = nextUtcMidnight.toLocal();
    final resetLabel =
        '${resetLocal.hour.toString().padLeft(2, '0')}:${resetLocal.minute.toString().padLeft(2, '0')}';
    await _showAnchoredPopup(
      chipIndex: 2,
      headerText: 'ZAMAN'.tr(),
      builder: (ctx) => SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in periods)
              _filterRow(
                emoji: _periodEmoji(p),
                label: p.label,
                selected: _period == p,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  setState(() => _period = p);
                  await _refreshMySummary();
                  _refreshLeaderboard();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(
                '${'Sıralamalar tüm dünyada aynı anda yenilenir — senin saatinle her gün'.tr()} $resetLabel',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textSecondary(context),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Ortak bottom sheet iskeleti.
  Future<void> _showFilterSheet({
    required String title,
    required Widget child,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppPalette.border(ctx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.textPrimary(ctx),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filterRow({
    required String emoji,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int? attemptCount,
    IconData? icon,
  }) {
    const orange = Color(0xFFFF6A00);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: selected
              ? orange.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (icon != null)
              Icon(
                icon,
                size: 20,
                color: selected
                    ? orange
                    : AppPalette.textPrimary(context),
              )
            else
              Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color:
                      selected ? orange : AppPalette.textPrimary(context),
                  letterSpacing: -0.1,
                ),
              ),
            ),
            if (attemptCount != null && attemptCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF1F6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$attemptCount',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111111),
                  ),
                ),
              ),
            ],
            if (selected)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child:
                    Icon(Icons.check_rounded, size: 16, color: orange),
              ),
          ],
        ),
      ),
    );
  }

  // ── Ders | Genel — eski inline pill düzeni + üstte küçük başlık ──────────
  // NOT: Yeni chip bar tasarımından sonra UI'dan kalktı; ileride başka bir
  // ekrana gömülmek için saklı tutuluyor.
  // ignore: unused_element
  Widget _buildModeRow(BuildContext context) {
    const orange = Color(0xFFFF6A00);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, 'Hangi dersten sıralayalım?'.tr()),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          child: Row(
            children: [
              for (final m in _Mode.values)
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      if (m == _Mode.subject) {
                        final picked = await _openSubjectPickerDialog();
                        if (picked != null) {
                          setState(() {
                            _subject = picked;
                            _topic = null;
                            _mode = _Mode.subject;
                          });
                          await _refreshMySummary();
                          _refreshLeaderboard();
                        }
                      } else {
                        setState(() => _mode = m);
                        await _refreshMySummary();
                        _refreshLeaderboard();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _mode == m ? orange : Colors.transparent,
                          width: _mode == m ? 1.6 : 0,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            m.icon,
                            size: 18,
                            color: _mode == m
                                ? orange
                                : const Color(0xFF111111),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            // Subject mode'da ders seçilmişse direkt o dersin
                            // adını göster; aksi halde "Ders" generic etiketi.
                            m == _Mode.subject && _subject != null
                                ? '${_subject!.emoji} ${_subject!.displayName}'
                                : m.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _mode == m
                                  ? orange
                                  : const Color(0xFF111111),
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tüm bölüm başlıkları için ortak küçük header ──────────────────────────
  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF6B7280),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── Ders seçici dialog (sıralama filtresi) ─────────────────────────────────
  //   Sadece kullanıcının daha önce test ÇÖZDÜĞÜ dersleri listeler.
  //   Boş ise "henüz test çözmedin" mesajı + üst grid'i kullan ipucu.
  //   NOT: Yeni birleşik expandable selector geldikten sonra UI'dan kalktı;
  //   ileride başka bir akıştan yeniden ihtiyaç olabilir diye saklı tutuluyor.
  // ignore: unused_element
  Future<CurriculumSubject?> _openSubjectPickerDialog() async {
    final accent = const Color(0xFF7C3AED);
    final played = await _loadPlayedSubjects();
    if (!mounted) return null;
    return showDialog<CurriculumSubject>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppPalette.card(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_rounded, size: 22, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hangi dersten sıralamayı öğrenmek istersin?'.tr(),
                        style: GoogleFonts.fraunces(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(ctx),
                          letterSpacing: -0.2,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (played.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Column(
                      children: [
                        Icon(Icons.quiz_outlined,
                            size: 40,
                            color: AppPalette.textSecondary(ctx)),
                        const SizedBox(height: 10),
                        Text(
                          'Henüz hiç test çözmedin.'.tr(),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textPrimary(ctx),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Yukarıdan bir derse basıp ilk testi başlat.'.tr(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppPalette.textSecondary(ctx),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.6,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (final s in played)
                            _SubjectGridCard(
                              subject: s,
                              active: s.key == _subject?.key,
                              onTap: () => Navigator.of(ctx).pop(s),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'İptal'.tr(),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textSecondary(ctx),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  // ── Aktif seçimin özet barı (artık UI'da kullanılmıyor; ileride
  //     başka bir yere taşımak için saklı tutuluyor) ────────────────────────
  // ignore: unused_element
  Widget _buildSelectionBar(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final mute = AppPalette.textSecondary(context);

    String title;
    String subtitle;
    switch (_mode) {
      case _Mode.overall:
        title = 'Genel Sıralama'.tr();
        subtitle = '${_mySummary.attempts} ${'test çözüldü'.tr()}';
        break;
      case _Mode.subject:
        title = '${_subject!.emoji} ${_subject!.displayName}';
        subtitle = '${_mySummary.attempts} ${'test çözüldü'.tr()}';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border(context), width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ink,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: mute,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _mySummary.average == null
                      ? '—'
                      : _mySummary.average.toString(),
                  style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Ortalama'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: mute,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero CTA — tema uyumlu zemin, ortalanmış metin + Ders/Konu seç ────────
  Widget _buildHeroCta(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppPalette.border(context),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Test Çöz Sıralamanı Yükselt'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppPalette.textPrimary(context),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Dersini seç, soruları çöz ve aynı seviyedeki öğrenciler arasında nerede olduğunu keşfet. Şehrinde, ülkende ve dünyada yükselmeye başla.'
                  .tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            // İki turuncu buton — sol: seçili ders (yoksa "Ders Seç"),
            // sağ: seçili konu (yoksa "Konu Seç"). Görsele uygun:
            // turuncu zemin + beyaz ikon + beyaz yazı.
            Row(
              children: [
                Expanded(
                  child: _HeroButton(
                    icon: Icons.menu_book_rounded,
                    label: _subject == null
                        ? 'Ders Seç'.tr()
                        : _subject!.displayName,
                    onTap: _openSubjectPickForQuiz,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeroButton(
                    icon: Icons.topic_rounded,
                    label: _topic == null || _topic!.isEmpty
                        ? 'Konu Seç'.tr()
                        : _topic!,
                    onTap: _subject == null ? null : _openTopicPickForQuiz,
                    disabled: _subject == null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Sınav Modu — LGS/YKS(TYT-AYT)/DGS/KPSS gibi resmi sınavlara göre
  //    ders + konu seçip AI'a o sınavın formatına uygun soru ürettirir.
  //    Ülkesi için tanımlı sınav kataloğu yoksa bu kart hiç gösterilmez.
  //    Kaydedilmiş (kalıcı) bir sınav varsa doğrudan onun kısayolu gösterilir
  //    (lib/widgets/exam_mode_widgets.dart — Arena/Sınav Soruları Oluştur ile
  //    ortak, tekilleştirilmiş bileşen).
  Widget _buildExamModeCta(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: ExamModeSection(
        countryCode: _profile?.country,
        onSelected: _startExamModeQuiz,
      ),
    );
  }

  /// Sınav Modu seçimi (sınav → ders → konu, kaydedilmiş sınav kısayolu
  /// dahil) tamamlanınca Bilgi Ligi'nin AYNI quiz akışını başlatır.
  Future<void> _startExamModeQuiz(ExamModeSelection picked) async {
    // Bu (sınav × ders) ikilisine özgü senkron anahtar/etiket — normal
    // müfredat derslerinden AYRI bir "ders" olarak sıralamaya girer, böylece
    // "LGS Türkçe" başarın "TYT Türkçe"den veya genel "Türkçe"den ayrı takip
    // edilir ama AYNI Bilgi Ligi liderlik tablosu mekanizmasını kullanır.
    final synthetic = examSyntheticSubject(picked.exam, picked.subject);
    setState(() {
      _subject = synthetic;
      _topic = picked.topic;
      _mode = _Mode.subject;
    });
    await _startQuizFor(synthetic,
        topic: picked.topic,
        examLabel: picked.exam.displayName,
        optionCount: picked.exam.optionCount);
  }

  /// Tek CTA → ders + (varsa) konu seçimi zincirleme + quiz başlatma.
  /// NOT: Tek-buton tasarımdan görseldeki iki-butona dönüldükten sonra
  /// artık çağrılmıyor; ileride başka akış için saklı.
  // ignore: unused_element
  Future<void> _runFullQuizFlow() async {
    // 1) Ders seç (mevcut dialog — `_subjects` listesinden grid).
    final picked = await showDialog<CurriculumSubject>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _QuizPickerDialog(
        title: 'Hangi dersten test çözmek istersin?'.tr(),
        items: [
          for (final s in _subjects)
            _QuizPickerItem(
              emoji: s.emoji,
              label: s.displayName,
              attemptCount: _attemptsBySubject[s.key] ?? 0,
              value: s,
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _subject = picked;
      _topic = null;
      _mode = _Mode.subject;
    });
    await _refreshMySummary();
    _refreshLeaderboard();
    // 2) Konu seç (mevcut konu seçim akışı). Konusuz dersler için direkt quiz.
    if (!mounted) return;
    await _openTopicPickForQuiz();
  }

  // ── Quiz: ders seç dialog'u (kart grid + test sayıları) ────────────────────
  Future<void> _openSubjectPickForQuiz() async {
    final picked = await showDialog<CurriculumSubject>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _QuizPickerDialog(
        title: 'Hangi dersten test çözmek istersin?'.tr(),
        items: [
          for (final s in _subjects)
            _QuizPickerItem(
              emoji: s.emoji,
              label: s.displayName,
              attemptCount: _attemptsBySubject[s.key] ?? 0,
              value: s,
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _subject = picked;
      // Yeni ders seçildi → eski konu adı (varsa) artık geçersiz.
      _topic = null;
      _mode = _Mode.subject;
    });
    await _refreshMySummary();
    _refreshLeaderboard();
  }

  // ── Quiz: konu seç dialog'u (kart grid + test sayıları) ────────────────────
  Future<void> _openTopicPickForQuiz() async {
    final s = _subject;
    if (s == null) return;
    // Tek satırlı virgülle ayrılmış konu stringini ayır (international_*
    // entries için: "Algebra, functions, trigonometry"). Aynı zamanda
    // yinelenenleri eler.
    final topics = _expandTopics(s.topics);
    // Konusu olmadan da dialog'u göster — kullanıcı "Konu Seç" tuşuna basıp
    // hiç UI görmemesini istemiyoruz. Liste boşsa sadece "Tüm Konular"
    // gösteririz ve altında bilgilendirme satırı ekleriz.
    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _TopicPickerSheet(
        subjectEmoji: s.emoji,
        subjectName: s.displayName,
        topics: [
          _TopicEntry(
            label: 'Tüm Konular'.tr(),
            value: '__ALL__',
            attemptCount: _attemptsBySubject[s.key] ?? 0,
            highlighted: true,
          ),
          for (final t in topics)
            _TopicEntry(
              label: t,
              value: t,
              attemptCount: _attemptsByTopic['${s.key}|$t'] ?? 0,
            ),
        ],
      ),
    );
    if (picked == null) return;
    final topic = picked == '__ALL__' ? null : picked;
    // Seçilen konu state'e yansır → hero CTA'da o ad görünür.
    // "Tüm Konular" seçilirse _topic null kalır (etiket "Konu Seç" döner).
    setState(() => _topic = topic);
    await _startQuizFor(s, topic: topic);
  }

  /// Müfredat kataloğunda bazı ders kayıtları tek bir virgülle ayrılmış
  /// uzun string içeriyor (örn. international_high.math). Konu picker'da
  /// bunu okunabilir tek tek satır olarak göstermek için parçalara böler.
  /// Aynı zamanda yinelenenleri (case-insensitive) eler.
  List<String> _expandTopics(List<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final entry in raw) {
      final parts = entry.split(',');
      for (final p in parts) {
        final trimmed = p.trim();
        if (trimmed.isEmpty) continue;
        final key = trimmed.toLowerCase();
        if (seen.add(key)) out.add(trimmed);
      }
    }
    return out;
  }

  // ignore: unused_element
  Future<CurriculumSubject?> _pickSubjectForQuiz() async {
    const accent = Color(0xFF7C3AED);
    return showDialog<CurriculumSubject>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.card(ctx),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.menu_book_rounded, size: 22, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hangi dersten test çözmek istersin?'.tr(),
                      style: GoogleFonts.fraunces(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(ctx),
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.6,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final s in _subjects)
                        _SubjectGridCard(
                          subject: s,
                          active: false,
                          onTap: () => Navigator.of(ctx).pop(s),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'İptal'.tr(),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondary(ctx),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Konu seç dialog'u — "Tüm konular" + ders konularının listesi.
  /// Dönüşler: 'ALL' (tüm konular), 'CANCELLED' (iptal), veya konu adı.
  // ignore: unused_element
  Future<String> _pickTopicForQuiz(CurriculumSubject subject) async {
    const accent = Color(0xFF7C3AED);
    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.card(ctx),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(subject.emoji,
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${subject.displayName} • ${'Konu Seç'.tr()}',
                      style: GoogleFonts.fraunces(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(ctx),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // "Tüm konular" satırı
              InkWell(
                onTap: () => Navigator.of(ctx).pop('ALL'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent, width: 1.4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.dashboard_rounded,
                          size: 18, color: accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tüm konular'.tr(),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final t in subject.topics)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(t),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppPalette.border(ctx),
                                    width: 1),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.topic_rounded,
                                      size: 18,
                                      color:
                                          AppPalette.textPrimary(ctx)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      t,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            AppPalette.textPrimary(ctx),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop('CANCELLED'),
                  child: Text(
                    'İptal'.tr(),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondary(ctx),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return picked ?? 'CANCELLED';
  }

  // ── Periyot — eski inline pill düzeni + üstte başlık ─────────────────────
  //   Dünya scope'unda Günlük gizlenir (zaman dilimi farklılığı nedeniyle
  //   anlamlı sıralama çıkmaz; otomatik haftalığa düşülür).
  // NOT: Yeni chip bar tasarımından sonra UI'dan kalktı; saklı.
  // ignore: unused_element
  Widget _buildPeriodRow(BuildContext context) {
    const orange = Color(0xFFFF6A00);
    final periods = _scope == _Scope.world
        ? LeaguePeriod.values
            .where((p) => p != LeaguePeriod.daily)
            .toList()
        : LeaguePeriod.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
            context, 'Hangi zaman aralığında sıralama yapalım?'.tr()),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          child: Row(
            children: [
              for (final p in periods)
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      setState(() => _period = p);
                      await _refreshMySummary();
                      _refreshLeaderboard();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _period == p ? orange : Colors.transparent,
                          width: _period == p ? 1.6 : 0,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        p.label,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _period == p
                              ? orange
                              : const Color(0xFF111111),
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Konum seçilmemiş kullanıcıyı tetikleyen mini banner.
  /// NOT: Eski `_buildLeaderboard` düzeni kaldırıldı; ileride ilk-kurulum
  /// akışı için saklı tutuluyor.
  // ignore: unused_element
  Widget _buildLocationHintBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _openLocationSheet,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF6A00).withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 18, color: Color(0xFFFF6A00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Konumunu seç → kendi şehrindeki sıralamaya katıl'.tr(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFB45309),
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Görünür "Seç" CTA pill'i — kullanıcı sadece chevron'a
                // güvenmesin, net buton görsün.
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6A00), Color(0xFFFF8A3C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6A00)
                            .withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Seç'.tr(),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded,
                          size: 16, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Liderlikte görünen kendi adım. AnonymousMode aktifse maskeli; aksi
  /// halde kullanıcı adı → profil ad+soyad → FirebaseAuth display adı →
  /// "Sen" sırasıyla fallback.
  String _myDisplayName() {
    if (_anonymousMode) {
      final u = FirebaseAuth.instance.currentUser?.uid;
      return u != null && u.length >= 5 ? 'Öğrenci #${u.substring(0, 5)}' : 'Sen';
    }
    // Username öncelikli — sıralamada herkes kullanıcı adı ile gözükür.
    final uname = UserProfileService.instance.username;
    if (uname.isNotEmpty) return uname;
    if (_profileName.isNotEmpty) return _profileName;
    final dn = (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
    return dn.isEmpty ? 'Sen' : dn;
  }

  List<_LbEntry> _toLbEntries(List<LeagueLeaderRow> rows) {
    return [
      for (int i = 0; i < rows.length; i++)
        _LbEntry(
          rank: i + 1,
          // Kullanıcının kendi satırı için profil ekranındaki ad+soyad
          // tercih edilir; eski submission'larda Auth displayName yazılmış
          // olabilir, lokal `profile_name` daha güncel ve tutarlı.
          name: rows[i].isMe && !_anonymousMode
              ? _myDisplayName() // kullanıcı adı öncelikli
              : (rows[i].displayName.isEmpty
                  ? (rows[i].isMe ? 'Sen'.tr() : 'Anonim'.tr())
                  : rows[i].displayName),
          avatar: rows[i].avatar.isEmpty ? '🙂' : rows[i].avatar,
          location: rows[i].location,
          score: rows[i].score,
          isMe: rows[i].isMe,
        ),
    ];
  }

  // ── Konum istemi (location null iken büyük tam-sayfa istemi) ─────────────
  // NOT: Mock leaderboard her durumda gösterildiğinden artık doğrudan
  // kullanılmıyor; yerini inline `_buildLocationHintBanner` aldı. İleride
  // bir "ilk kurulum" akışı için saklı tutuluyor.
  // ignore: unused_element
  Widget _buildLocationPrompt(BuildContext context) {
    final accent = const Color(0xFF7C3AED);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        children: [
          Icon(Icons.location_on_outlined,
              size: 48, color: AppPalette.textSecondary(context)),
          const SizedBox(height: 10),
          Text(
            'Şehrini ve ülkeni seç'.tr(),
            style: GoogleFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppPalette.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Aynı bölge ve seviyedeki kullanıcılarla yarışmak için konumunu kaydet.'
                .tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppPalette.textSecondary(context),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _openLocationSheet,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text('Konumu Belirle'.tr()),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLocationSheet() async {
    final loc = await LeagueLocationPicker.show(context);
    if (loc == null) return;
    if (!mounted) return;
    setState(() => _location = loc);

    // Yerele yaz (kalıcı, offline-first)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_locationPrefKey, jsonEncode(loc.toJson()));
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'bilgi_ligi_screen'); }

    // Cloud'a yaz (auth varsa)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'location': loc.toJson(),
          'isLocationSet': true,
          'locationSetAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {/* offline → bir sonraki açılışta tekrar denenir */}
    }
    _refreshLeaderboard();
  }

  Widget _buildLeaderboardHeader(BuildContext context) {
    final headerStyle = GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w900,
      color: AppPalette.textPrimary(context),
      letterSpacing: 0.6,
    );
    return Container(
      color: AppPalette.cardMuted(context),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              'NO'.tr(),
              textAlign: TextAlign.center,
              style: headerStyle,
            ),
          ),
          const SizedBox(width: 17),
          // Kullanıcı yazısı — NO sütunundan sonra hafif sağa kaydırıldı.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                'KULLANICI'.tr(),
                style: headerStyle,
              ),
            ),
          ),
          Text(
            'PUAN'.tr(),
            style: headerStyle,
          ),
        ],
      ),
    );
  }

  // ── Quiz başlat (hero CTA → ders + opsiyonel konu seçimi sonrası) ─────────
  Future<void> _startQuizFor(CurriculumSubject subject,
      {String? topic, String? examLabel, int optionCount = 4}) async {
    // Ebeveyn önizlemesi: quiz/yarışma başlatılamaz.
    if (ParentPreview.guard(context)) return;
    final profile = _profile;
    if (profile == null) return;

    // Ücretsiz kullanıcı: günde 1 lig testi — HER kapsamda. Eskiden kontrol
    // yalnızca Dünya sekmesi açıkken yapılıyordu; oysa her test sonucu şehir
    // + ülke + dünya sıralamalarının ÜÇÜNE birden yazılır. Şehir sekmesinden
    // sınırsız test çözen ücretsiz kullanıcının puanları dünya sıralamasına
    // da aktığı için kapı fiilen çalışmıyordu. Sayaç da artık silinebilen
    // prefs bayrağı değil — bugünkü gerçek deneme kayıtlarından sayılır.
    if (!AiQuotaService.instance.isPremium) {
      int playedToday = 0;
      try {
        playedToday =
            await LeagueScores.attemptsInBucket(period: LeaguePeriod.daily);
      } catch (_) {/* yerel okuma hatası → engelleme, oynasın */}
      if (playedToday >= 1) {
        if (!mounted) return;
        _showWorldPremiumGate();
        return;
      }
    }
    if (!mounted) return;

    final result = await Navigator.of(context).push<Map<String, num>>(
      MaterialPageRoute(
        builder: (_) => BilgiLigiQuizScreen(
          profile: profile,
          subjectKey: subject.key,
          subjectName: subject.displayName,
          subjectEmoji: subject.emoji,
          topic: topic,
          period: _period,
          examLabel: examLabel,
          optionCount: optionCount,
        ),
      ),
    );
    if (result == null) return;
    // Günlük hak sayacı ayrı tutulmuyor — LeagueScores.add() ile yazılan
    // deneme kaydının kendisi sayaçtır (attemptsInBucket ile sayılır).
    final score = (result['score'] ?? 0).toDouble();
    final durationSec = (result['durationSec'] ?? 0).toInt();
    final user = FirebaseAuth.instance.currentUser;

    // Skor submission + leaderboard refresh ZİNCİRİ uzun (1-3sn).
    // Bu sürede UI'ya intermediate rebuild gelirse race (eski tablo yeni
    // skor gelmeden render olur). Modal loading overlay ile blokla.
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            margin: EdgeInsets.symmetric(horizontal: 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 2.4),
                  SizedBox(height: 14),
                  Text(
                    'Skorun kaydediliyor…'.tr(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    bool dialogShown = true;
    void dismissDialog() {
      if (dialogShown && mounted) {
        dialogShown = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    try {
      // Anonim mod'a göre paylaşılan displayName (cloud yazımına etkir).
      // Tam ad+soyad: önce profil ekranındaki `profile_name`, yoksa
      // FirebaseAuth.displayName. Anonim modda her durumda maskeli.
      final cloudDisplayName = _anonymousMode
          ? () {
              final u = user?.uid ?? '';
              return u.length >= 5
                  ? 'Öğrenci #${u.substring(0, 5)}'
                  : 'Anonim';
            }()
          // DAİMA kullanıcı adı; boşsa profil adı, o da boşsa Auth adı.
          : (UserProfileService.instance.username.isNotEmpty
              ? UserProfileService.instance.username
              : (_profileName.isNotEmpty
                  ? _profileName
                  : user?.displayName));
      await LeagueScores.add(
        LeagueAttempt(
          subjectKey: subject.key,
          topic: topic,
          score: score,
          durationSec: durationSec,
          // Sunucu-düzeltmeli zaman — yerel kova hesapları (günlük hak,
          // tekrar tespiti, kart özeti) liderlik kovasıyla aynı güne düşer.
          when: LeagueScores.correctedNow(),
          countryCodeSnapshot: _location?.countryCode,
          cityCodeSnapshot: _location?.cityCode,
        ),
        profile: profile,
        location: _location,
        displayName: cloudDisplayName,
        avatar: '',
      );
      if (!mounted) {
        dismissDialog();
        return;
      }
      setState(() {
        _subject = subject;
        _mode = _Mode.subject;
      });
      await _refreshMySummary();
      _refreshLeaderboard();
      await _refreshAttemptCounts();
      // Yeni leaderboard query'sinin sonucunu bekleyelim ki kullanıcı
      // güncel tabloyu görsün — sonsuz beklemesin diye 6sn cap.
      try {
        await _leaderboardFuture
            ?.timeout(const Duration(seconds: 6));
      } catch (_) {/* timeout/error → cap, snapshot zaten dönecek */}
    } finally {
      dismissDialog();
    }
  }

  void _showWorldPremiumGate() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFFFF6A00), Color(0xFF7C3AED)]),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.public_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 16),
            Text('Günlük Hakkın Doldu'.tr(),
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(context))),
            const SizedBox(height: 8),
            Text(
              'Bilgi Ligi\'nde günde 1 ücretsiz test hakkın var; sonucun şehir, ülke ve dünya sıralamalarının hepsine işlenir.\nYarın tekrar katılabilir veya Premium\'a geçerek sınırsız yarışabilirsin.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: AppPalette.textSecondary(context), height: 1.5),
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
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Tamam'.tr(),
                  style: GoogleFonts.poppins(fontSize: 13, color: AppPalette.textSecondary(context))),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
//  Yardımcı widget'lar
// ──────────────────────────────────────────────────────────────────────────────

class _SubjectGridCard extends StatelessWidget {
  final CurriculumSubject subject;
  final bool active;
  final VoidCallback onTap;
  const _SubjectGridCard({
    required this.subject,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    const accent = Color(0xFF7C3AED);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: 0.08)
              : AppPalette.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? accent : AppPalette.border(context),
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(subject.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 5),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  subject.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: active ? accent : ink,
                    letterSpacing: -0.1,
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

// ── Scope segment (Şehir/Ülke/Dünya) — outer pill içinde border-only aktif ─
class _ScopePill extends StatelessWidget {
  final String emoji;
  final String label;
  final bool active;
  final Color accent;   // Aktif border + metin rengi
  final Color inkColor; // Pasif metin rengi
  final VoidCallback onTap;
  const _ScopePill({
    required this.emoji,
    required this.label,
    required this.active,
    required this.accent,
    required this.inkColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: active ? accent : Colors.transparent,
            width: active ? 1.6 : 0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                  color: active ? accent : inkColor,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _SegmentTab extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? emoji;
  final bool active;
  final VoidCallback onTap;
  const _SegmentTab({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.emoji,
  }) : assert(icon != null || emoji != null,
            'Either icon or emoji must be provided');

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final hl = ink;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? hl : AppPalette.border(context),
            width: active ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null)
              Text(emoji!, style: const TextStyle(fontSize: 16))
            else
              Icon(icon!, size: 18, color: ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                  color: ink,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _PillTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PillTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? ink.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? ink : AppPalette.border(context),
            width: active ? 1.4 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: ink,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final _LbEntry entry;
  final bool isLast;
  final bool hideLocation;
  const _LeaderboardRow({
    required this.entry,
    this.isLast = false,
    this.hideLocation = false,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final mute = AppPalette.textSecondary(context);
    final isTop3 = entry.rank <= 3;
    final medal = entry.rank == 1
        ? '🥇'
        : entry.rank == 2
            ? '🥈'
            : entry.rank == 3
                ? '🥉'
                : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: entry.isMe
            ? const Color(0xFFFF6A00).withValues(alpha: 0.06)
            : Colors.transparent,
        // Son satırda alt çizgi yok — çerçeve sınırına kapalı uçla biter.
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: AppPalette.border(context),
                  width: 0.6,
                ),
              ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 32,
            child: isTop3
                ? Text(medal,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18))
                : Text(
                    '${entry.rank}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: mute,
                    ),
                  ),
          ),
          // Rank ile profil arası dikey ince çizgi
          Container(
            width: 1,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: AppPalette.border(context),
          ),
          // Avatar
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppPalette.cardMuted(context),
              shape: BoxShape.circle,
            ),
            child: Text(entry.avatar, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          // Ad + konum
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight:
                        entry.isMe ? FontWeight.w800 : FontWeight.w700,
                    color: ink,
                  ),
                ),
                if (!hideLocation) ...[
                  const SizedBox(height: 1),
                  Text(
                    entry.location,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: mute,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Skor
          Text(
            _fmt(entry.score),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ink,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Skoru görsel olarak formatla. Tam sayı ise binlik nokta, ondalık ise
  /// 2 hane ile gösterim ("3.75", "1.234,50").
  String _fmt(double n) {
    if (n == n.truncateToDouble()) {
      // Tam sayı — binlik ayraç
      final s = n.toInt().toString();
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    // Ondalıklı — 2 basamak
    return n.toStringAsFixed(2);
  }
}

// ── Koyu gri bardaki tek sütun — üstte uppercase başlık, altta beyaz pill
//    içinde emoji + seçim + chevron. Görseldeki "DERS & KONU / BÖLGE / ZAMAN"
//    sütun düzenini yansıtır.
class _FilterColumn extends StatelessWidget {
  final String header;
  final String emoji;
  final String label;
  final VoidCallback onTap;
  /// Popup'ı açık olan chip — yeşil glow border highlight'ı.
  final bool selected;
  /// Emoji yerine Material IconData render et — örn. konum chip'inde
  /// klasik damla şekilli pin için. null ise `emoji` kullanılır.
  final IconData? icon;
  const _FilterColumn({
    required this.header,
    required this.emoji,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    // Aktif chip için yeşil vurgu (border + soft halo).
    const green = Color(0xFF22C55E);
    final ink = AppPalette.textPrimary(context);
    final mute = AppPalette.textSecondary(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Üstteki uppercase başlık — koyu/aydınlık temaya göre yumuşak gri.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            header,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: selected ? green : mute,
              letterSpacing: 0.6,
            ),
          ),
        ),
        // Alt pill — basılınca popup açılır. Selected → yeşil border + glow.
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? green.withValues(alpha: 0.10)
                  : AppPalette.card(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? green : AppPalette.border(context),
                width: selected ? 1.8 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: green.withValues(alpha: 0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null)
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? green : ink,
                  )
                else
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: selected ? green : ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                Icon(Icons.expand_more_rounded,
                    size: 15,
                    color: selected ? green : mute),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Hero butonları (Ders Seç / Konu Seç) ────────────────────────────────────
class _HeroButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool disabled;
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF6A00);
    final color = disabled ? const Color(0xFFB5B5BA) : accent;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ── Quiz seçim dialog'u — başlık + grid kartlar + iptal ─────────────────────
// ─── Topic picker — ders seçimi sonrası "Hangi konudan yarışmak istersin?" ──
class _TopicEntry {
  final String label;
  final String value;
  final int attemptCount;
  final bool highlighted;
  const _TopicEntry({
    required this.label,
    required this.value,
    required this.attemptCount,
    this.highlighted = false,
  });
}

class _TopicPickerSheet extends StatelessWidget {
  final String subjectEmoji;
  final String subjectName;
  final List<_TopicEntry> topics;
  const _TopicPickerSheet({
    required this.subjectEmoji,
    required this.subjectName,
    required this.topics,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7C3AED);
    const orange = Color(0xFFFF6A00);
    return Dialog(
      backgroundColor: AppPalette.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Üst başlık — küçük ders adı + emoji
            Row(
              children: [
                Text(subjectEmoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subjectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondary(context),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Büyük soru — kullanıcıya direkt seslenen başlık
            Text(
              'Hangi konudan yarışmak istersin?'.tr(),
              style: GoogleFonts.fraunces(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
                letterSpacing: -0.3,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            // Beyaz oval pill listesi — tek tek konular
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final t in topics) ...[
                      _TopicPill(
                        entry: t,
                        accent: t.highlighted ? orange : accent,
                        onTap: () => Navigator.of(context).pop(t.value),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'İptal'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context),
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

class _TopicPill extends StatelessWidget {
  final _TopicEntry entry;
  final Color accent;
  final VoidCallback onTap;
  const _TopicPill({
    required this.entry,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            // Beyaz çerçeve içinde her konu — tam beyaz zemin
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: entry.highlighted
                  ? accent
                  : accent.withValues(alpha: 0.25),
              width: entry.highlighted ? 1.8 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.10),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Sol işaret — highlight'lı (Tüm Konular) için "🟢", konu için
              // küçük accent dot.
              if (entry.highlighted)
                const Text('🟢', style: TextStyle(fontSize: 14))
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111111),
                        letterSpacing: -0.1,
                        height: 1.25,
                      ),
                    ),
                    if (entry.attemptCount > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${entry.attemptCount} ${"test çözüldü".tr()}',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuizPickerItem<T> {
  final String emoji;
  final String label;
  final int attemptCount;
  final T value;
  final bool highlighted;
  const _QuizPickerItem({
    required this.emoji,
    required this.label,
    required this.attemptCount,
    required this.value,
    this.highlighted = false,
  });
}

class _QuizPickerDialog<T> extends StatelessWidget {
  final String title;
  final List<_QuizPickerItem<T>> items;
  const _QuizPickerDialog({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppPalette.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: GoogleFonts.fraunces(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
                letterSpacing: -0.2,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.95,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final it in items)
                      _QuizPickerCard<T>(
                        item: it,
                        onTap: () => Navigator.of(context).pop(it.value),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'İptal'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context),
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

class _QuizPickerCard<T> extends StatelessWidget {
  final _QuizPickerItem<T> item;
  final VoidCallback onTap;
  const _QuizPickerCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7C3AED);
    final ink = AppPalette.textPrimary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: item.highlighted
              ? accent.withValues(alpha: 0.08)
              : AppPalette.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: item.highlighted ? accent : AppPalette.border(context),
            width: item.highlighted ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(item.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: item.highlighted ? accent : ink,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.attemptCount == 0
                  ? 'Henüz test çözülmedi'.tr()
                  : '${item.attemptCount} ${'test çözüldü'.tr()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
