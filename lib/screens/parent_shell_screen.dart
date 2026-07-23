// ═══════════════════════════════════════════════════════════════════════════
//  ParentShellScreen — Ebeveyn panelinin alt-bar iskeleti.
//
//  TeacherShellScreen ile AYNI tasarım dili: 2 sekme + ortada büyük ➕ FAB:
//
//    [ 👨‍👩‍👧 Çocuklarım ]  ( ➕ )  [ 🎓 Öğrenci Paneli ]
//
//  • Çocuklarım     → öğretmen ana sayfası düzeninde özet + bağlı çocuk
//                     kartları (öğretmen→ebeveyn ve öğrenci→ebeveyn akan
//                     veriler: ödev/karne, duyurular, notlar, kontroller).
//  • ➕             → Hızlı aksiyonlar (merkez FAB): AI Danışman /
//                     Sürpriz Gönder / PDF Karne.
//  • Öğrenci Paneli → HAREKETLİ sekme: çocuğun gördüğü öğrenci deneyimini
//                     salt-izleme modunda açar (ParentPreview) — ebeveyn her
//                     yere son ekrana kadar gider ama özet/soru üretemez,
//                     yarışamaz, ödev teslim edemez.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/feature_flags.dart';
import '../widgets/parent_actions_bar.dart';
import '../widgets/parent_qr_scan_dialog.dart';
import '../widgets/teacher_help_dialog.dart';
import '../widgets/user_avatar.dart';
import '../models/education_models.dart';
import '../services/account_service.dart';
import '../services/analytics.dart';
import '../services/deep_link_service.dart';
import '../services/parent_link_service.dart';
import '../services/parent_preview.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'camera_screen.dart' show CameraScreen;
import 'my_progress_screen.dart';
import 'notifications_inbox_screen.dart';
import 'parent_quick_actions.dart';
import 'parent_child_courses_screen.dart';
import 'profile_screen.dart';

const _kBrand = Color(0xFF7C3AED);
const _kGreen = Color(0xFF10B981);

class ParentShellScreen extends StatefulWidget {
  const ParentShellScreen({super.key});

  @override
  State<ParentShellScreen> createState() => _ParentShellScreenState();
}

class _ParentShellScreenState extends State<ParentShellScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Analytics.logFeatureOpen('parent_panel');
    // WhatsApp veli linkinden geldiyse (cold start / login sonrası) bekleyen
    // kodu tüket — bağlantı burada kurulur. (Bağlanma daveti popup DEĞİL:
    // çocuk kartındaki yanıp sönen "Çocuğunuza bağlanın" etiketiyle yapılır.)
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => consumePendingParentLinkCode(context));
  }

  @override
  Widget build(BuildContext context) {
    const tabs = [
      _ParentHomeTab(),
      ProfileScreen(),
    ];
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: tabs),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
        onPressed: () {
          // Profil sekmesindeyken ➕ → önce ANA SAYFAYA (Çocuklarım) geç;
          // menü kapanınca ebeveyn kendini profilde değil ana sayfada bulur.
          if (_index != 0) setState(() => _index = 0);
          _openCreateMenu(context);
        },
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return BottomAppBar(
      color: AppPalette.card(context),
      elevation: 8,
      shape: const CircularNotchedRectangle(),
      notchMargin: 7,
      height: 62,
      padding: EdgeInsets.zero,
      // Öğretmen barı ile aynı düzen: solda Çocuklarım, ortada ➕, sağda
      // Profil. (Öğrenci Paneli önizlemesi ana sayfadaki Hızlı Erişim'den.)
      child: Row(
        children: [
          // Öğrenci panelindeki "Ebeveyn Paneli" banner'ıyla AYNI aile
          // profil şekli (👨‍👩‍👧) — Çocuklarım sekmesinin ikonu.
          _navItem(
              const Text('👨‍👩‍👧', style: TextStyle(fontSize: 19)),
              'Çocuklarım'.tr(),
              selected: _index == 0,
              onTap: () => setState(() => _index = 0)),
          const SizedBox(width: 48), // ➕ FAB boşluğu (tam ortada)
          _navItem(
              Icon(Icons.account_circle_rounded,
                  size: 22,
                  color: _index == 1
                      ? _kBrand
                      : AppPalette.textSecondary(context)),
              'Profil'.tr(),
              selected: _index == 1,
              onTap: () => setState(() => _index = 1)),
        ],
      ),
    );
  }

  Widget _navItem(Widget icon, String label,
      {required bool selected, required VoidCallback onTap}) {
    final color = selected ? _kBrand : AppPalette.textSecondary(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(opacity: selected ? 1 : 0.55, child: icon),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                )),
          ],
        ),
      ),
    );
  }

  // ── ➕ menüsü — öğretmen panelindekiyle aynı görsel dil ──────────────────
  Future<void> _openCreateMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Sheet'in şeffaf (menü dışı) alanına TEK dokunuş menüyü kapatır —
      // dıştaki GestureDetector pop yapar, menünün kendisi dokunuşu yutar.
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(ctx),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 78, left: 16, right: 16),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: GestureDetector(
                onTap: () {}, // menü içine dokunuş kapanmayı tetiklemesin
                child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                decoration: BoxDecoration(
                  color: AppPalette.card(ctx),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: _kBrand.withValues(alpha: 0.30)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hızlı aksiyonlar — ana sayfadaki 3'lü satırın aynısı
                    // (çocuk bağlı değilse demo/generic davranış).
                    _createChip(ctx, '🤖', 'AI Danışman'.tr(), () async {
                      Navigator.pop(ctx);
                      final child =
                          await _pickChild(context, warnIfEmpty: false);
                      if (!context.mounted) return;
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ParentAdvisorChatScreen(
                              childName: _childLabel(child))));
                    }),
                    _createChip(ctx, '🎁', 'Sürpriz Gönder'.tr(), () async {
                      Navigator.pop(ctx);
                      // Bildirimin GERÇEKTEN gitmesi için bağlı çocuk şart —
                      // yoksa kullanıcıyı bilgilendir (sessiz boş-uid akışı
                      // "gönderildi sanma" yanılgısı yaratıyordu).
                      final child =
                          await _pickChild(context, warnIfEmpty: true);
                      if (child == null || !context.mounted) return;
                      showParentSurpriseSheet(context,
                          realChildUid: child.uid,
                          childName: _childLabel(child));
                    }),
                    _createChip(ctx, '📄', 'PDF Karne'.tr(), () async {
                      Navigator.pop(ctx);
                      final child =
                          await _pickChild(context, warnIfEmpty: false);
                      if (!context.mounted) return;
                      shareWeeklyPdfReport(context,
                          childUid: child?.uid ?? '',
                          childName: _childLabel(child),
                          demo: child == null);
                    }),
                  ],
                ),
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _createChip(
      BuildContext c, String emoji, String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppPalette.bg(c),
        elevation: 0,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _kBrand.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _kBrand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 15)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(c),
                      )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Çocuğun görünen adı — bağlı çocuk yoksa genel etiket.
  String _childLabel(LinkedChild? c) => c == null
      ? 'Çocuğun'.tr()
      : (c.displayName.isEmpty ? '@${c.username}' : c.displayName);

  /// Bağlı (aktif) bir çocuk seçtirir; tekse onu döndürür. Çocuk yoksa
  /// [warnIfEmpty] true iken uyarır, değilse sessizce null döner (aksiyon
  /// demo/generic modda devam eder).
  Future<LinkedChild?> _pickChild(BuildContext context,
      {bool warnIfEmpty = true}) async {
    final all = await ParentLinkService.linkedChildrenStream().first;
    final children = all.where((c) => c.isActive).toList();
    if (!context.mounted) return null;
    if (children.isEmpty) {
      if (warnIfEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          // Eski metin var olmayan bir menüyü tarif ediyordu (➕ menüsünde
          // "Çocuk Bağla" yok) — gerçek giriş noktası tarif edilir.
          content: Text(
              'Önce bir çocuk bağla — Çocuklarım kartındaki "Çocuğunuza bağlanın" düğmesine dokun.'
                  .tr()),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return null;
    }
    if (children.length == 1) return children.first;
    return showModalBottomSheet<LinkedChild>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppPalette.border(ctx),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Çocuk seç'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(ctx),
                  )),
              const SizedBox(height: 14),
              ...children.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: AppPalette.bg(ctx),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx, c),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: AppPalette.border(ctx)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              UserAvatar(
                                  uid: c.uid,
                                  avatar: c.avatar,
                                  size: 28,
                                  emojiSize: 22),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                    c.displayName.isEmpty
                                        ? '@${c.username}'
                                        : c.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppPalette.textPrimary(ctx),
                                    )),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

}

/// Çocuğun WhatsApp'tan gönderdiği /veli/{kod} linkinden gelen BEKLEYEN kodu
/// tüketir: giriş yapmış VELİ hesabıyla bağlantıyı doğrudan kurar ve sonucu
/// dialog ile bildirir. İki çağıran var:
///   • main.dart — uygulama açıkken link gelirse (warm)
///   • ParentShellScreen.initState — cold start / login sonrası
/// Giriş yoksa kod BEKLETİLİR (temizlenmez); veli girişten sonra shell
/// açılınca tekrar denenir. Veli olmayan hesapta bilgi verilip temizlenir.
Future<void> consumePendingParentLinkCode(BuildContext context) async {
  final code = DeepLinkService.instance.pendingParentLinkCode.value;
  if (code == null || code.isEmpty) return;
  if (FirebaseAuth.instance.currentUser == null) return;
  DeepLinkService.instance.clearParentLinkCode();

  String msg;
  bool ok = false;
  if (!AccountService.instance.isParent) {
    msg = 'Bu bağlantı veli hesapları içindir. Velin, bu linke KENDİ '
        'telefonundaki QuAlsar veli hesabıyla dokunmalı.'.tr();
  } else {
    final res = await ParentLinkService.linkByCode(code);
    ok = res == LinkRequestResult.success ||
        res == LinkRequestResult.alreadyLinked;
    msg = switch (res) {
      LinkRequestResult.success =>
        'Bağlantı kuruldu 🎉 Çocuğunun verileri artık panelinde.'.tr(),
      LinkRequestResult.alreadyLinked => 'Bu çocuk zaten bağlı.'.tr(),
      LinkRequestResult.invalidCode ||
      LinkRequestResult.codeExpired =>
        // Kod TEK KULLANIMLIK: ikinci veli aynı linke dokununca da buraya
        // düşer — mesaj her iki durumu da anlatır.
        'Bağlantı kodu geçersiz: süresi dolmuş ya da daha önce kullanılmış olabilir (her kod TEK veli içindir). Çocuğundan yeni bir kod iste.'
            .tr(),
      LinkRequestResult.selfLink =>
        'Kendi hesabına bağlanamazsın — bu linke velin dokunmalı.'.tr(),
      _ => 'Bağlanamadı. İnterneti kontrol edip linke tekrar dokun.'.tr(),
    };
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppPalette.card(ctx),
      icon: Icon(
          ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          color: ok ? _kGreen : const Color(0xFFF59E0B),
          size: 40),
      content: Text(msg,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppPalette.textPrimary(ctx))),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kBrand),
          onPressed: () => Navigator.pop(ctx),
          child: Text('Tamam'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

/// Çocuğu bağlar — FAB menüsü ve ana sayfadaki pill ➕ ortak kullanır.
/// Birincil yol: çocuğun ekranındaki QR'ı okut → ANINDA bağlanır (onay yok).
/// İkincil yol: çocuğun WhatsApp'tan gönderdiği linke dokunmak (bilgi satırı).
/// Üçüncü yol: kodu elle yaz. QR ve kod ParentLinkService.linkByCode kullanır.
///
/// [intro] true iken panel açılışında kendiliğinden çıkan karşılama
/// çerçevesi olur: "lütfen bağlanın" başlığı + "Daha Sonra" butonu.
Future<void> showLinkChildSheet(BuildContext context,
    {bool intro = false}) async {
    final ctrl = TextEditingController();
    final res = await showDialog<LinkRequestResult>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Row(children: [
          const Text('👨‍👩‍👧', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                (intro ? 'Çocuğunuza Bağlanın' : 'Çocuğunu Bağla').tr(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(ctx))),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                (intro
                        ? 'Paneli kullanabilmek için lütfen bu yollardan '
                            'biriyle çocuğunuza bağlanın:'
                        : 'Bu yollardan biriyle çocuğuna bağlan:')
                    .tr(),
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppPalette.textSecondary(ctx),
                    height: 1.4),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _kGreen,
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final code = await showParentQrScanner(ctx);
                  if (code == null || !ctx.mounted) return;
                  final r = await ParentLinkService.linkByCode(code);
                  if (ctx.mounted) Navigator.pop(ctx, r);
                },
                icon: const Icon(Icons.qr_code_scanner_rounded,
                    color: Colors.white, size: 20),
                label: Text('QR Kodu Okut'.tr(),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
              const SizedBox(height: 5),
              // QR yönteminin hemen altında küçük nasıl-yapılır yazısı.
              Text(
                'Çocuğunun telefonunda Profil → "Veliyi Bağla" ekranını '
                        'açtır, ekrandaki QR kodu okut — anında bağlanır.'
                    .tr(),
                style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    color: AppPalette.textSecondary(ctx),
                    height: 1.35),
              ),
              const SizedBox(height: 10),
              // 2. yol — WhatsApp linki: veli tarafında buton yok, çocuğun
              // gönderdiği linke dokunmak yeterli; burada sadece anlatılır.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF25D366).withValues(alpha: 0.30)),
                ),
                child: Row(children: [
                  const Text('💬', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ya da çocuğun aynı ekrandan WhatsApp ile bağlantı '
                              'linki göndersin — linke dokunman yeterli.'
                          .tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          height: 1.35,
                          color: AppPalette.textSecondary(ctx)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Divider(color: AppPalette.border(ctx))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('veya kodu yaz'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppPalette.textSecondary(ctx))),
                ),
                Expanded(child: Divider(color: AppPalette.border(ctx))),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.characters,
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppPalette.textPrimary(ctx)),
                decoration: InputDecoration(
                  hintText: 'EBEV-XXXXXX',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 5),
              // Kod yönteminin hemen altında küçük nasıl-yapılır yazısı.
              Text(
                'Aynı "Veliyi Bağla" ekranında görünen EBEV-XXXXXX kodunu '
                        'buraya yaz, "Bağla"ya bas.'
                    .tr(),
                style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    color: AppPalette.textSecondary(ctx),
                    height: 1.35),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text((intro ? 'Daha Sonra' : 'Vazgeç').tr(),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kBrand),
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              final r = await ParentLinkService.linkByCode(ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx, r);
            },
            child: Text('Bağla'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (!context.mounted || res == null) return;
    final msg = switch (res) {
      LinkRequestResult.success =>
        'Bağlantı kuruldu 🎉 Çocuğunun verileri artık panelinde.'.tr(),
      LinkRequestResult.alreadyLinked => 'Bu çocuk zaten bağlı.'.tr(),
      LinkRequestResult.invalidCode ||
      LinkRequestResult.codeExpired =>
        'Kod geçersiz ya da süresi dolmuş — çocuğundan yeni kod iste.'.tr(),
      LinkRequestResult.selfLink =>
        'Kendi hesabına bağlanamazsın.'.tr(),
      _ => 'Bağlanamadı. İnterneti kontrol edip tekrar dene.'.tr(),
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), behavior: SnackBarBehavior.floating));
}

// ═══════════════════════════════════════════════════════════════════════════
//  ANA SAYFA — öğretmen ana sayfası düzeninde: başlık + özet istatistik
//  şeridi + çocuk kartları + hızlı erişim.
// ═══════════════════════════════════════════════════════════════════════════
class _ParentHomeTab extends StatefulWidget {
  const _ParentHomeTab();

  @override
  State<_ParentHomeTab> createState() => _ParentHomeTabState();
}

class _ParentHomeTabState extends State<_ParentHomeTab>
    with SingleTickerProviderStateMixin {
  /// Seçili çocuk (chip sırası — aktif çocuklar listesinde index).
  int _selIdx = 0;

  /// Odak modu: bir çipe basılınca diğerleri gizlenir, seçilen çip yatayda
  /// tam genişliğe büyür (büyük profil kartı). Varsayılan AÇIK: panel
  /// açılınca çocuk kartı büyük görünür; sağ üstteki ok ile küçültülür.
  bool _focusMode = true;

  /// "Çocuğunuza bağlanın" etiketi için yanıp sönme animasyonu — çocuk
  /// kartında, henüz kodla bağlı çocuk yokken dikkat çeker.
  late final AnimationController _blinkCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750))
    ..repeat(reverse: true);
  // Yeşil özet kart istatistikleri — "Bugüne hızlı bir bakış": bugünün
  // çalışma dakikası, çözülen soru sayısı, başarı yüzdesi + seri gün.
  String? _statsUid;
  bool _statsLoading = false;
  int _todayMin = 0;
  int _todaySolved = 0;
  int _todayPct = 0;
  int _streak = 0;
  /// Aktif ödev durumu (yeşil karttaki ince ilerleme çubuğu):
  /// bekleyen = teslim edilmemiş + süresi geçmemiş; biten = teslim edilmiş.
  int _hwPending = 0;
  int _hwDone = 0;
  /// Yeşil kartın istatistik bölümü gizli mi (sağ üst göz düğmesi — kalıcı).
  bool _quickHidden = false;

  /// ☰ → "Yeni Çocuk Ekle" ile ebeveynin CİHAZINDA oluşturduğu yerel çocuk
  /// profilleri (kod bağlamadan; ad/foto/durum SharedPreferences'ta).
  /// Kod ile bağlanmış gerçek çocukların ARKASINA çip olarak eklenir.
  List<String> _localIds = const [];
  // Sağ üst aksiyon pill'i (➕/✈️/🎨/?) — Gelişim Paneli'ndekiyle aynı.
  final _shotKey = GlobalKey();
  bool _showPalette = false;
  Color? _bg;

  // ── Renk paleti (Gelişim Paneli'ndeki yüzer panelin AYNISI) ─────────────
  // 24 renk × 2 satır + hedef seçici: önce hedef, sonra renge bas. Seçimler
  // kalıcı (SharedPreferences). 'bg' hedefi mevcut sayfa-rengi sistemini
  // kullanır; diğerleri _ov override haritasına yazılır.
  final Map<String, Color> _ov = {};
  String _colorTarget = 'bg';
  double _paletteTop = 8; // ✛ ile taşınabilir panel dikey konumu
  static const _targets = [
    ['bg', 'Arka plan'],
    ['green', 'Yeşil kart'],
    ['chips', 'Çocuk kartı'],
    ['panels', 'Sekmeler'],
    ['titleText', 'Başlık yazısı'],
    ['bodyText', 'Yazılar'],
  ];
  static const _palette24 = <Color>[
    Colors.white, Color(0xFFF3F4F6), Color(0xFFD1D5DB), Color(0xFF9CA3AF),
    Color(0xFF0F172A), Color(0xFFFFEFD5), Color(0xFFFFD1DC), Color(0xFFFCA5A5),
    Color(0xFFFF6A00), Color(0xFFC8102E), Color(0xFFDB2777), Color(0xFFFBBF24),
    Color(0xFFDCFCE7), Color(0xFF86EFAC), Color(0xFF10B981), Color(0xFFE0F2FE),
    Color(0xFF22D3EE), Color(0xFF2563EB), Color(0xFFE9D5FF), Color(0xFFA855F7),
    Color(0xFF7C3AED), Color(0xFFF5F5DC), Color(0xFFD4A373), Color(0xFF92400E),
  ];

  void _setOv(String id, Color c) {
    if (id == 'bg') {
      _pickBg(c);
      return;
    }
    setState(() => _ov[id] = c);
    SharedPreferences.getInstance()
        .then((p) => p.setInt('parent_ov_$id', c.toARGB32()));
  }

  void _resetOv() {
    setState(() => _ov.clear());
    _pickBg(null);
    SharedPreferences.getInstance().then((p) {
      for (final t in _targets) {
        p.remove('parent_ov_${t[0]}');
      }
    });
  }
  // Sürüklenebilir "Öğrenci Paneli" düğmesi konumu (kalıcı). null → varsayılan
  // (sağ-alt köşe). ValueNotifier: sürüklerken tüm sayfa yerine yalnız
  // düğme yeniden çizilsin (aksi halde kare düşüp sürükleme geride kalıyor).
  final ValueNotifier<Offset?> _studentBtnPos = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    PageBgPrefs.load('parent_home').then((c) {
      if (mounted && c != null) setState(() => _bg = c);
    });
    SharedPreferences.getInstance().then((p) {
      final dx = p.getDouble('parent_student_btn_dx');
      final dy = p.getDouble('parent_student_btn_dy');
      final hidden = p.getBool('parent_quick_hidden') ?? false;
      final locals = p.getStringList('parent_local_children') ?? const [];
      if (!mounted) return;
      if (dx != null && dy != null) _studentBtnPos.value = Offset(dx, dy);
      setState(() {
        _quickHidden = hidden;
        _localIds = locals;
        // Kalıcı renk override'ları ('bg' hariç — o PageBgPrefs'te).
        for (final t in _targets) {
          final v = p.getInt('parent_ov_${t[0]}');
          if (v != null) _ov[t[0]] = Color(v);
        }
      });
    });
  }

  @override
  void dispose() {
    _blinkCtrl.dispose();
    _studentBtnPos.dispose();
    super.dispose();
  }

  // Yüzer düğme ☰ menüye taşındı — konum kaydı şimdilik kullanılmıyor.
  // ignore: unused_element
  void _saveStudentBtnPos() {
    final pos = _studentBtnPos.value;
    if (pos == null) return;
    SharedPreferences.getInstance().then((p) {
      p.setDouble('parent_student_btn_dx', pos.dx);
      p.setDouble('parent_student_btn_dy', pos.dy);
    });
  }

  void _openStudentPreview() {
    ParentPreview.active = true;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const _StudentPreviewShell()))
        .whenComplete(() => ParentPreview.active = false);
  }

  // ── Ebeveyn tarafı çocuk profili düzenlemesi (kalem) ────────────────────
  // Ad-soyad / durum mesajı / fotoğraf EBEVEYNİN CİHAZINDA saklanır
  // (SharedPreferences) — çocuğun gerçek profiline yazılamaz (rules: yalnız
  // sahibi). Çip ve yeşil kart bu değerleri önceler.
  final Map<String, String> _alias = {};
  final Map<String, String> _statusMsg = {};
  final Map<String, String> _photoPath = {};
  final Set<String> _ovLoaded = {};

  void _ensureOverridesLoaded(List<String> uids) {
    final missing =
        uids.where((u) => !_ovLoaded.contains(u)).toList();
    if (missing.isEmpty) return;
    _ovLoaded.addAll(missing);
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        for (final uid in missing) {
          final a = p.getString('child_alias_$uid');
          final s = p.getString('child_status_$uid');
          final f = p.getString('child_photo_$uid');
          if (a != null && a.isNotEmpty) _alias[uid] = a;
          if (s != null && s.isNotEmpty) _statusMsg[uid] = s;
          if (f != null && f.isNotEmpty && File(f).existsSync()) {
            _photoPath[uid] = f;
          }
        }
      });
    });
  }

  /// Çocuk profili düzenleme sayfası — ad, durum mesajı, fotoğraf.
  /// [uid] gerçek çocukta Firebase uid'si, demo çocukta 'demo_N' anahtarıdır
  /// (her ikisi de EBEVEYNİN CİHAZINDA saklanır).
  Future<void> _editChildSheet(String uid, String currentName) async {
    final nameCtrl = TextEditingController(
        text: _alias[uid] ?? (currentName.isEmpty ? '' : currentName));
    final statusCtrl = TextEditingController(text: _statusMsg[uid] ?? '');
    String? newPhoto = _photoPath[uid];
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 14, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: AppPalette.border(ctx),
                    borderRadius: BorderRadius.circular(2)),
              ),
              Text('Çocuk Profilini Düzenle'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.textPrimary(ctx))),
              const SizedBox(height: 14),
              // Fotoğraf — dokununca galeriden seç.
              GestureDetector(
                onTap: () async {
                  try {
                    final x = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 400,
                        maxHeight: 400,
                        imageQuality: 85);
                    if (x == null) return;
                    final dir = await getApplicationDocumentsDirectory();
                    final dest = '${dir.path}/child_photo_$uid.jpg';
                    await File(x.path).copy(dest);
                    setM(() => newPhoto = dest);
                  } catch (_) {}
                },
                child: Stack(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kGreen.withValues(alpha: 0.10),
                        border: Border.all(
                            color: _kGreen.withValues(alpha: 0.45),
                            width: 1.6),
                        image: newPhoto == null
                            ? null
                            : DecorationImage(
                                image: FileImage(File(newPhoto!)),
                                fit: BoxFit.cover),
                      ),
                      alignment: Alignment.center,
                      child: newPhoto == null
                          ? Icon(Icons.person,
                              size: 40,
                              color: AppPalette.textSecondary(ctx))
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: _kGreen),
                        child: const Icon(Icons.photo_camera_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: AppPalette.textPrimary(ctx)),
                decoration: InputDecoration(
                  labelText: 'Ad Soyad'.tr(),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: statusCtrl,
                maxLength: 80,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppPalette.textPrimary(ctx)),
                decoration: InputDecoration(
                  labelText: 'Durum mesajı'.tr(),
                  counterText: '',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _kGreen),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Kaydet'.tr(),
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final p = await SharedPreferences.getInstance();
    final a = nameCtrl.text.trim();
    final s = statusCtrl.text.trim();
    await p.setString('child_alias_$uid', a);
    await p.setString('child_status_$uid', s);
    if (newPhoto != null) {
      await p.setString('child_photo_$uid', newPhoto!);
    }
    if (!mounted) return;
    setState(() {
      a.isEmpty ? _alias.remove(uid) : _alias[uid] = a;
      s.isEmpty ? _statusMsg.remove(uid) : _statusMsg[uid] = s;
      if (newPhoto != null) _photoPath[uid] = newPhoto!;
    });
  }

  void _pickBg(Color? c) {
    setState(() => _bg = c);
    PageBgPrefs.save('parent_home', c);
  }

  /// Yüzer renk paleti paneli — Gelişim Paneli'ndeki tasarımın aynısı:
  /// başlık + Sıfırla + kapat + taşıma tutamacı, 2×3 hedef seçici ve
  /// 24 renk İKİ SATIR halinde (yatay kaydırılabilir).
  Widget _palettePanel(BuildContext context) {
    const accent = Color(0xFFFBBF24);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
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
              Text('🎨 ${'Renk Paleti'.tr()}',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(context),
                  )),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _resetOv,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppPalette.border(context)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded,
                          size: 12, color: AppPalette.textPrimary(context)),
                      const SizedBox(width: 3),
                      Text('Sıfırla'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textPrimary(context),
                          )),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              _hdrBtn(Icons.close_rounded, const Color(0xFFEF4444),
                  () => setState(() => _showPalette = false)),
              const SizedBox(width: 6),
              // ✛ — paneli dikeyde taşı.
              GestureDetector(
                onVerticalDragUpdate: (d) => setState(() {
                  _paletteTop =
                      (_paletteTop + d.delta.dy).clamp(8.0, 420.0);
                }),
                child: _hdrBtnChild(Icons.open_with_rounded, accent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Hedef seçiciler — 2×3, ince satırlar.
          _targetRow(context, 0, accent),
          const SizedBox(height: 6),
          _targetRow(context, 3, accent),
          const SizedBox(height: 10),
          Text('Önce hedefi seç, sonra renge bas.'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppPalette.textSecondary(context),
              )),
          const SizedBox(height: 8),
          // Renkler — 2 satır, yatay kaydırılabilir.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _swatchRow(_palette24.sublist(0, 12)),
                const SizedBox(height: 6),
                _swatchRow(_palette24.sublist(12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hdrBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: _hdrBtnChild(icon, color));

  Widget _hdrBtnChild(IconData icon, Color color) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1.3),
        ),
        child: Icon(icon, color: color, size: 16),
      );

  Widget _targetRow(BuildContext context, int start, Color accent) {
    Widget cell(int i) {
      final t = _targets[i];
      final sel = _colorTarget == t[0];
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = t[0]),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: sel ? accent : AppPalette.bg(context),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(t[1].tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: sel
                      ? const Color(0xFF1A1A1A)
                      : AppPalette.textPrimary(context),
                )),
          ),
        ),
      );
    }

    Widget arrow() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(Icons.arrow_forward_rounded,
              size: 12, color: AppPalette.textSecondary(context)),
        );

    return Row(
      children: [
        cell(start),
        arrow(),
        cell(start + 1),
        arrow(),
        cell(start + 2),
      ],
    );
  }

  Widget _swatchRow(List<Color> colors) {
    // Seçili hedefte o an geçerli renk (bg → sayfa rengi).
    final current = _colorTarget == 'bg' ? _bg : _ov[_colorTarget];
    return Row(
      children: colors.map((col) {
        final sel = current?.toARGB32() == col.toARGB32();
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => _setOv(_colorTarget, col),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: col,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color:
                      sel ? const Color(0xFFFBBF24) : Colors.black26,
                  width: sel ? 2.5 : 1,
                ),
              ),
              child: sel
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Color(0xFF1A1A1A))
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Seçili çocuğun BUGÜNKÜ çalışma dk / çözülen soru / başarı yüzdesi ve
  /// seri gününü yükler (MyProgressScreen ile aynı kaynaklar; 7 günlük
  /// aktivite listesinin son elemanı bugünün kaydıdır).
  Future<void> _loadStats(String uid) async {
    if (_statsUid == uid || _statsLoading) return;
    setState(() {
      _statsLoading = true;
      _statsUid = uid;
    });
    int todayMin = 0, todaySolved = 0, todayPct = 0, streak = 0;
    int hwPending = 0, hwDone = 0;
    try {
      const t = Duration(seconds: 8);
      final acts = await ParentLinkService.readChild7DayActivity(uid)
          .timeout(t, onTimeout: () => const []);
      final stats = await ParentLinkService.readChildStats(uid)
          .timeout(t, onTimeout: () => const {});
      // Ödev tamamlanma çubuğu: aktif ödevlerden teslim edilen/bekleyen.
      try {
        final hws = await ParentLinkService.readChildUpcomingHomeworks(uid)
            .timeout(t, onTimeout: () => const []);
        final now = DateTime.now();
        hwDone = hws.where((h) => h.submitted).length;
        hwPending =
            hws.where((h) => !h.submitted && h.dueAt.isAfter(now)).length;
      } catch (_) {}
      if (acts.isNotEmpty) {
        final today = StudentActivityModel.fromJson(acts.last);
        todayMin = today.focusMinutes;
        // Bugün çözülen soru = test soruları + fotoğrafla çözülenler.
        todaySolved = today.totalAttempted + today.photoQuestionsSolved;
        final answered = today.totalAnswered;
        todayPct = today.successPercent?.round() ??
            (answered > 0
                ? (today.correctAnswers * 100 / answered).round()
                : 0);
      }
      streak = (stats['streakDays'] as num?)?.toInt() ?? 0;
    } catch (_) {/* offline → sıfırlarla göster */}
    if (!mounted || _statsUid != uid) return;
    setState(() {
      _statsLoading = false;
      _todayMin = todayMin;
      _todaySolved = todaySolved;
      _todayPct = todayPct;
      _streak = streak;
      _hwPending = hwPending;
      _hwDone = hwDone;
    });
  }

  // Build içinde her seferinde YENİ snapshots() stream'i üretmek her
  // rebuild'de aboneliği sıfırlıyor, bir frame'lik null-data ile
  // "Çocuğunuza bağlanın" kartı titreyip _selIdx sıfırlanabiliyordu —
  // stream BİR KEZ oluşturulup saklanır.
  late final Stream<List<LinkedChild>> _childrenStream =
      ParentLinkService.linkedChildrenStream();

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return StreamBuilder<List<LinkedChild>>(
      stream: _childrenStream,
      builder: (context, snap) {
        final all = snap.data ?? const <LinkedChild>[];
        final active = all.where((c) => c.isActive).toList();
        // Çocuk bağlı değilken alan Gelişim Paneli'ndeki gibi DEMO
        // önizlemeyle dolar ("1. Çocuk"/"2. Çocuk") — ebeveyn neye
        // benzeyeceğini görür; gerçek çocuk bağlanınca gerçek veri gelir.
        // Demo yalnızca NE bağlı NE yerel çocuk varken VE demo modu açıkken
        // gösterilir. kShowDemoMode=false (prod) → sahte çocuk/istatistik
        // gizlenir; yerine "çocuğunu bağla" boş-durum ekranı gösterilir.
        final demoMode = kShowDemoMode && active.isEmpty && _localIds.isEmpty;
        // Hiç çocuk yok (demo da kapalı) → PLACEHOLDER modu: ana sayfa aynen
        // kurulur; çocuk kartının yerinde "Lütfen çocuğunuzun bilgilerini
        // girin" yazan hazır sekme durur (basınca çocuk ekleme açılır).
        final placeholderMode =
            !demoMode && active.isEmpty && _localIds.isEmpty;
        // Override anahtarı: bağlı çocukta uid, yerel çocukta 'local_N',
        // demo çocukta 'demo_N' — hepsi ad/foto/durum düzenlenebilir.
        // Sıra: önce kodla bağlı çocuklar, sonra yerel eklenenler.
        final uids = demoMode
            ? const <String>['demo_0', 'demo_1']
            : placeholderMode
                ? const <String>['placeholder_0']
                : [...active.map((c) => c.uid), ..._localIds];
        _ensureOverridesLoaded(uids);
        final chipNames = [
          for (var i = 0; i < uids.length; i++)
            _alias[uids[i]] ??
                (demoMode
                    ? '${i + 1}. ${'Çocuk'.tr()}'
                    : (i < active.length
                        ? (active[i].displayName.isEmpty
                            ? '@${active[i].username}'
                            : active[i].displayName)
                        : 'Çocuk'.tr())),
        ];
        if (_selIdx >= chipNames.length) _selIdx = 0;
        // Seçili çocuk yalnızca KODLA BAĞLI ise gerçek veri akar; yerel/
        // demo çocukta istatistikler 0 (bağlantı yok) gösterilir.
        final sel = (!demoMode && _selIdx < active.length)
            ? active[_selIdx]
            : null;
        if (sel != null) _loadStats(sel.uid);
        final selName = chipNames[_selIdx];
        final dispMin = demoMode ? 16 : (sel == null ? 0 : _todayMin);
        final dispSolved = demoMode ? 8 : (sel == null ? 0 : _todaySolved);
        final dispPct = demoMode ? 75 : (sel == null ? 0 : _todayPct);
        final dispStreak = demoMode ? 2 : (sel == null ? 0 : _streak);
        final bg = _bg ?? AppPalette.bg(context);
        return LayoutBuilder(builder: (context, cons) {
          return Stack(
            children: [
              RepaintBoundary(
          key: _shotKey,
          child: ColoredBox(
            color: bg,
            child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
          children: [
            // ── Üst satır: başlık sayfaya TAM ORTALI; en sağda bildirim
            //    + hemen yanında ☰ menü (palet/paylaş/çocuk ekle/yardım).
            SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Başlık tam ortadan BİRAZ SOLA kaydırıldı (kullanıcı isteği).
                  Align(
                    alignment: const Alignment(-0.35, 0),
                    child: Text('Ebeveyn Paneli'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _ov['titleText'] ?? ink,
                        )),
                  ),
                  Positioned(
                    right: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Zil: ebeveyne gelen bildirimler buraya düşer —
                        // okunmamış ebeveyn bildirimi varsa kırmızı sayaç
                        // rozeti; basınca Bildirimler gelen kutusu açılır.
                        _notifBell(context),
                        const SizedBox(width: 8),
                        _hamburgerMenu(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Text('Çocuğunun eğitim yolculuğunu takip et'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: _ov['bodyText'] ??
                      AppPalette.textSecondary(context),
                )),
            const SizedBox(height: 12),
            // ── Çocuk seçici (Gelişim Paneli üst tasarımı): çipe basınca
            //    büyük fotoğraflı profil kartı açılır (odak modu). ─────
            ...[
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: placeholderMode
                    ? _placeholderChildCard(context)
                    : _focusMode
                    ? _focusChildCard(context,
                        names: chipNames,
                        uids: uids,
                        active: active,
                        demoMode: demoMode)
                    : SizedBox(
                        height: 58,
                        // Tek çocuk varsa çip sayfada ORTALANIR; birden
                        // fazlaysa yatay kaydırılabilir liste.
                        child: chipNames.length == 1
                            ? Center(
                                child: _childChip(context, chipNames[0],
                                    selected: true,
                                    photoPath: _photoPath[uids[0]],
                                    onEdit: () => _editChildSheet(uids[0],
                                        !demoMode && active.isNotEmpty
                                            ? active[0].displayName
                                            : ''),
                                    onLongPress: uids[0].startsWith('local_')
                                        ? () => _confirmDeleteLocalChild(
                                            uids[0])
                                        : null,
                                    onTap: () => setState(
                                        () => _focusMode = true)),
                              )
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: chipNames.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                // Ekrana TAM 2 çip sığar: (genişlik -
                                // sayfa dolgusu 32 - ayraç 12) / 2.
                                itemBuilder: (ctx, i) => _childChip(
                                    ctx, chipNames[i],
                                    selected: i == _selIdx,
                                    width: (cons.maxWidth - 44) / 2,
                                    photoPath: _photoPath[uids[i]],
                                    onEdit: () => _editChildSheet(uids[i],
                                        !demoMode && i < active.length
                                            ? active[i].displayName
                                            : ''),
                                    onLongPress: uids[i].startsWith('local_')
                                        ? () => _confirmDeleteLocalChild(
                                            uids[i])
                                        : null,
                                    onTap: () => setState(() {
                                          _selIdx = i;
                                          _focusMode = true;
                                        })),
                              ),
                      ),
              ),
              const SizedBox(height: 12),
              // ── Yeşil özet kart: seçili çocuğun bugünü ──────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _ov['green'],
                  gradient: _ov['green'] != null
                      ? null
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                        ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('⚡', style: TextStyle(fontSize: 15)),
                        const SizedBox(width: 6),
                        // Çocuk adı yerine kartın başlığı burada (ad zaten
                        // üstteki çipte/profil kartında görünüyor).
                        Expanded(
                          child: Text('Bugüne hızlı bir bakış'.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              )),
                        ),
                        if (!demoMode && _statsLoading)
                          const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                        // (Kalem kaldırıldı — profil düzenleme çocuk
                        // kartındaki avatar/kalemden yapılır.)
                        // Göz — istatistikleri gizle/göster (kalıcı).
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 30, minHeight: 30),
                          icon: Icon(
                              _quickHidden
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 17,
                              color: Colors.white),
                          tooltip: _quickHidden
                              ? 'Göster'.tr()
                              : 'Gizle'.tr(),
                          onPressed: () {
                            setState(() => _quickHidden = !_quickHidden);
                            SharedPreferences.getInstance().then((p) =>
                                p.setBool(
                                    'parent_quick_hidden', _quickHidden));
                          },
                        ),
                      ],
                    ),
                    if ((_statusMsg[uids[_selIdx]] ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('“${_statusMsg[uids[_selIdx]]}”',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.white.withValues(alpha: 0.9),
                            )),
                      ),
                    // Gizliyken istatistik satırı kapanır — kart küçülür.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _quickHidden
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _greenStat(
                                          '$dispMin dk', 'Çalışma'.tr()),
                                      _greenStat('$dispSolved',
                                          'Çözülen soru'.tr()),
                                      _greenStat('%$dispPct', 'Başarı'.tr()),
                                      _greenStat(
                                          '🔥 $dispStreak', 'Seri gün'.tr()),
                                    ],
                                  ),
                                  // Ödev tamamlanma durumu — ince çubuk +
                                  // tek satır aksiyon metni.
                                  Builder(builder: (_) {
                                    final done =
                                        demoMode ? 2 : _hwDone;
                                    final pending =
                                        demoMode ? 1 : _hwPending;
                                    final total = done + pending;
                                    if (sel == null && !demoMode ||
                                        total == 0) {
                                      return const SizedBox.shrink();
                                    }
                                    final ratio = done / total;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(top: 10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            child: LinearProgressIndicator(
                                              value: ratio,
                                              minHeight: 5,
                                              backgroundColor: Colors.white
                                                  .withValues(alpha: 0.25),
                                              valueColor:
                                                  const AlwaysStoppedAnimation(
                                                      Colors.white),
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                              pending == 0
                                                  ? '✅ ${'Bugünkü ödevlerin hepsi tamamlandı'.tr()}'
                                                  : '📌 $pending ${'bekleyen ödev var'.tr()}',
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: GoogleFonts.poppins(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white
                                                    .withValues(alpha: 0.95),
                                              )),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // (Hızlı aksiyonlar — AI Danışman/Sürpriz/PDF — ➕ FAB
              //  menüsüne taşındı.)
              // ── Uygulama İçi Çalışmalar — tam genişlik yatay sekme ──
              //    Basınca "Çalıştığı Alanlar" + günlük/haftalık/aylık
              //    özet çerçeveleri (Gelişim Paneli) açılır.
              Material(
                color: Colors.transparent,
                child: InkWell(
                  // Ana sayfada SEÇİLİ çocuğun verisiyle açılır — Gelişim
                  // Paneli'nde o çocuğun sekmesi otomatik seçilir.
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MyProgressScreen(
                          initialChildUid: sel?.uid,
                          initialChildName: selName))),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 20),
                    decoration: BoxDecoration(
                      color:
                          _ov['panels'] ?? _kGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(18),
                      border:
                          Border.all(color: _kGreen.withValues(alpha: 0.40)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _kGreen.withValues(alpha: 0.28),
                                _kGreen.withValues(alpha: 0.12),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                                color: _kGreen.withValues(alpha: 0.35)),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.donut_large_rounded,
                              color: _kGreen, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Uygulama İçi Çalışmalar'.tr(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppPalette.textPrimary(context),
                                  )),
                              const SizedBox(height: 2),
                              Text(
                                  'Çalıştığı alanlar · günlük, haftalık ve '
                                  'aylık özetler'.tr(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    color: AppPalette.textSecondary(context),
                                  )),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: _kGreen, size: 26),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ── Öğretmenin Verdiği Ödevler — ders ders (2'li ızgara) ─
              _widePanel(
                context,
                icon: Icons.assignment_rounded,
                color: _kBrand,
                title: 'Öğretmenin Verdiği Ödevler'.tr(),
                subtitle:
                    'Aldığı dersler ve her dersten verilen ödevler'.tr(),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ParentChildCoursesScreen(
                        childUid: sel?.uid ?? '',
                        childName: selName,
                        demo: demoMode))),
              ),
              const SizedBox(height: 10),
              // ── Öğretmen Mesajları — duyurular + paylaşılan notlar.
              //    Yeni öğretmen mesajı/duyurusu geldiğinde ok yanında
              //    kırmızı okunmamış sayacı belirir (canlı rozet).
              _teacherMessagesPanel(context, sel, selName, demoMode),
            ],
            // (Hızlı Erişim kaldırıldı — Ebeveyn Kontrolleri ➕ menüsünde.)
          ],
            ),
          ),
              ),
              // ── Yüzer renk paleti paneli (☰ → Renk Paletini Değiştir) ─
              if (_showPalette)
                Positioned(
                  left: 0,
                  right: 0,
                  top: _paletteTop,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: _palettePanel(context),
                      ),
                    ),
                  ),
                ),
              // NOT: Yüzer "Öğrenci Paneli" düğmesi kaldırıldı — aynı işlev
              // artık ☰ menüde "Öğrenci Paneli" olarak (Yeni Çocuk Ekle'nin
              // hemen altında) yaşıyor.
            ],
          );
        });
      },
    );
  }

  /// ☰ → "Yeni Çocuk Ekle" — ebeveyn çocuğu CİHAZINA kaydeder (kodla
  /// bağlama DEĞİL): isteğe bağlı fotoğraf + isim (zorunlu) + durum mesajı.
  /// Kaydedilen çocuk çip listesine eklenir; ileride kodla bağlanırsa
  /// gerçek veriler akmaya başlar.
  Future<void> _showAddChildDialog() async {
    final id = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final nameCtrl = TextEditingController();
    final statusCtrl = TextEditingController();
    String? photo;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          backgroundColor: AppPalette.card(ctx),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Başlık satırı: 👶 rozeti + başlık + X.
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _kGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: const Text('👶',
                            style: TextStyle(fontSize: 19)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Yeni Çocuk Ekle'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppPalette.textPrimary(ctx),
                            )),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.close_rounded,
                            color: AppPalette.textPrimary(ctx)),
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Fotoğraf (isteğe bağlı) — basınca galeriden seç.
                  GestureDetector(
                    onTap: () async {
                      try {
                        final x = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 400,
                            maxHeight: 400,
                            imageQuality: 85);
                        if (x == null) return;
                        final dir =
                            await getApplicationDocumentsDirectory();
                        final dest = '${dir.path}/child_photo_$id.jpg';
                        await File(x.path).copy(dest);
                        setD(() => photo = dest);
                      } catch (_) {}
                    },
                    child: _avatarCircle(ctx, photo, 96, camera: true),
                  ),
                  const SizedBox(height: 6),
                  Text('Fotoğraf ekle (isteğe bağlı)'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: AppPalette.textSecondary(ctx),
                      )),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    maxLength: 24,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setD(() {}),
                    style: GoogleFonts.poppins(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary(ctx)),
                    decoration: InputDecoration(
                      labelText: 'İsim'.tr(),
                      hintText: 'Çocuğunun adı'.tr(),
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          color: AppPalette.textSecondary(ctx)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: statusCtrl,
                    maxLength: 40,
                    style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        color: AppPalette.textPrimary(ctx)),
                    decoration: InputDecoration(
                      hintText: 'Durum mesajı (isteğe bağlı)'.tr(),
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 13.5,
                          color: AppPalette.textSecondary(ctx)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _kGreen,
                        disabledBackgroundColor:
                            AppPalette.border(ctx),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: nameCtrl.text.trim().isEmpty
                          ? null
                          : () => Navigator.pop(ctx, true),
                      child: Text('Tamam'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: nameCtrl.text.trim().isEmpty
                                ? AppPalette.textSecondary(ctx)
                                : Colors.white,
                          )),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final name = nameCtrl.text.trim();
    final status = statusCtrl.text.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('child_alias_$id', name);
    if (status.isNotEmpty) await p.setString('child_status_$id', status);
    if (photo != null) await p.setString('child_photo_$id', photo!);
    final list = [..._localIds, id];
    await p.setStringList('parent_local_children', list);
    if (!mounted) return;
    setState(() {
      _localIds = list;
      _alias[id] = name;
      if (status.isNotEmpty) _statusMsg[id] = status;
      if (photo != null) _photoPath[id] = photo!;
      _ovLoaded.add(id);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$name ${'eklendi'.tr()} 🎉'),
        behavior: SnackBarBehavior.floating));
  }

  /// Sağ üst hamburger menü (☰) — basınca hemen altında açılır:
  /// Renk Paletini Değiştir / Gönder / Yeni Çocuk Ekle / Nasıl Çalışır?
  Widget _hamburgerMenu(BuildContext context) {
    return Material(
      color: AppPalette.card(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openHamburgerMenu(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Icon(Icons.menu_rounded,
              size: 20, color: AppPalette.textPrimary(context)),
        ),
      ),
    );
  }

  /// ☰ menü — showGeneralDialog ile açılır: menü çerçevesi DIŞINDA kalan
  /// her şey flu (BackdropFilter blur); boş alana dokununca kapanır.
  Future<void> _openHamburgerMenu(BuildContext context) async {
    Widget item(BuildContext ctx, int v, String emoji, String title) =>
        InkWell(
          onTap: () => Navigator.pop(ctx, v),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Text(title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimary(ctx),
                    )),
              ],
            ),
          ),
        );
    final v = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Menü'.tr(),
      barrierColor: Colors.black.withValues(alpha: 0.10),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, __) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final t = Curves.easeOutCubic.transform(anim.value);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6 * t, sigmaY: 6 * t),
          child: Opacity(
            opacity: t,
            child: Align(
              alignment: Alignment.topRight,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 58, right: 16),
                  child: Material(
                    color: AppPalette.card(ctx),
                    elevation: 8,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppPalette.border(ctx)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          item(ctx, 0, '🎨', 'Renk Paletini Değiştir'.tr()),
                          item(ctx, 1, '✈️', 'Gönder'.tr()),
                          item(ctx, 2, '👶', 'Yeni Çocuk Ekle'.tr()),
                          // Yüzer düğmeden buraya taşındı — salt-izleme
                          // öğrenci deneyimi önizlemesi.
                          item(ctx, 4, '🎓', 'Öğrenci Paneli'.tr()),
                          item(ctx, 3, '❓', 'Nasıl Çalışır?'.tr()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (v == null || !context.mounted) return;
    switch (v) {
      case 0:
        setState(() => _showPalette = !_showPalette);
      case 1:
        sharePageShot(context, _shotKey, '${'Ebeveyn Paneli'.tr()} 📊');
      case 2:
        _showAddChildDialog();
      case 4:
        _openStudentPreview();
      case 3:
        showTeacherHelpDialog(context,
            title: 'Bu sayfa nasıl çalışır?',
            items: const [
              TeacherHelpItem('👶',
                  '☰ menüden "Yeni Çocuk Ekle" ile çocuğunu bağla; çipe basınca profil kartı açılır.'),
              TeacherHelpItem('📊',
                  '"Uygulama İçi Çalışmalar" → çalıştığı alanlar + günlük/haftalık/aylık özetler.'),
              TeacherHelpItem('📚',
                  '"Öğretmenin Verdiği Ödevler" → dersler, ödevler ve teslim durumları.'),
              TeacherHelpItem('📬',
                  '"Öğretmen Mesajları" → tüm öğretmenlerin duyuru, takdir ve notları.'),
              TeacherHelpItem('✈️',
                  '☰ menüden "Gönder" ile ekranı paylaşabilir, "Renk Paletini Değiştir" ile sayfa rengini seçebilirsin.'),
            ]);
    }
  }

  /// Hiç çocuk yokken çocuk kartının YERİNDE duran hazır sekme: soldaki
  /// boş profil dairesi + sağında yeşil ➕ ve "Lütfen çocuğunuzun
  /// bilgilerini girin" yazısı. Görünümü _focusChildCard ile birebir aynı
  /// çerçevede; herhangi bir yerine basınca çocuk ekleme penceresi açılır.
  Widget _placeholderChildCard(BuildContext context) {
    return Material(
      color: _ov['chips'] ?? AppPalette.card(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: _showAddChildDialog,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kGreen, width: 1.4),
          ),
          child: Row(
            children: [
              // Sol: büyük boş avatar — gerçek karttaki ile aynı boyut.
              _avatarCircle(context, null, 76),
              const SizedBox(width: 14),
              // Sağ: yeşil ➕ üstte, altında yönlendirme yazısı.
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kGreen,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(Icons.add_rounded,
                          size: 20, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text('Lütfen çocuğunuzun bilgilerini girin'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          color: AppPalette.textPrimary(context),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Yanıp sönen "Çocuğunuza bağlanın" etiketi — çocuk kartının sağ
  /// tarafında, HENÜZ KODLA BAĞLI ÇOCUK YOKKEN görünür; basınca bağlanma
  /// penceresi (QR / WhatsApp linki / kod) açılır. Bağlantı kurulunca
  /// koşul sağlanmaz ve etiket kaybolur.
  Widget _connectChildLabel(BuildContext context) {
    return GestureDetector(
      onTap: () => showLinkChildSheet(context),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
            CurvedAnimation(parent: _blinkCtrl, curve: Curves.easeInOut)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _kGreen, width: 1.2),
          ),
          child: Text('Çocuğunuza bağlanın'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _kGreen,
              )),
        ),
      ),
    );
  }

  /// Başlık sağındaki zil — ebeveyn bildirim hattının girişi. Okunmamış
  /// ebeveyn-tipi bildirim sayısını Firestore'dan canlı dinler; varsa
  /// zilin köşesinde kırmızı sayaç rozeti gösterir.
  Widget _notifBell(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final bell = _headerIcon(context, Icons.notifications_rounded, () {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const NotificationsInboxScreen()));
    });
    if (uid == null) return bell;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications').doc(uid)
          .collection('items')
          .where('read', isEqualTo: false)
          .limit(30)
          .snapshots(),
      builder: (context, snap) {
        // Kutusuna düşen TÜM okunmamışlar sayılır — gelen kutusu da artık
        // tip süzmeden hepsini gösteriyor (rozet ve liste tutarlı olsun).
        final unread = snap.data?.docs.length ?? 0;
        if (unread == 0) return bell;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            bell,
            Positioned(
              right: -4,
              top: -4,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: AppPalette.card(context), width: 1.5),
                  ),
                  child: Text(unread > 9 ? '9+' : '$unread',
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                      )),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _headerIcon(BuildContext c, IconData icon, VoidCallback onTap) {
    return Material(
      color: AppPalette.card(c),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.border(c)),
          ),
          child: Icon(icon, size: 20, color: AppPalette.textPrimary(c)),
        ),
      ),
    );
  }

  /// Tam genişlik yatay panel sekmesi ("Uygulama İçi Çalışmalar" ile aynı dil).
  Widget _widePanel(BuildContext context,
      {required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      int badge = 0}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: _ov['panels'] ?? color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.40)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withValues(alpha: 0.28),
                          color.withValues(alpha: 0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      border:
                          Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimary(context),
                            )),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              color: AppPalette.textSecondary(context),
                            )),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: color, size: 26),
                ],
              ),
              // Okunmamış sayaç rozeti — çerçevenin SAĞ ÜST köşesinde,
              // çerçevenin İÇİNDE (padding'i kısmen telafi eden ofset).
              if (badge > 0)
                Positioned(
                  top: -12,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(badge > 9 ? '9+' : '$badge',
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        )),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Öğretmen Mesajları" paneli + canlı okunmamış rozeti: öğretmen
  /// kaynaklı bildirimler (not/takdir + duyuru) okunmadıkça sayaç görünür.
  /// Demo modda tanıtım amaçlı 1 gösterilir.
  Widget _teacherMessagesPanel(
      BuildContext context, LinkedChild? sel, String selName, bool demoMode) {
    Widget panel(int badge) => _widePanel(
          context,
          icon: Icons.mark_email_unread_rounded,
          color: const Color(0xFF0EA5E9),
          title: 'Öğretmen Mesajları'.tr(),
          subtitle: 'Tüm öğretmenlerin duyuru ve notları — kim gönderdi '
              'belli'.tr(),
          badge: badge,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ParentTeacherMessagesScreen(
                  childUid: sel?.uid ?? '',
                  childName: selName,
                  demo: demoMode))),
        );
    if (demoMode) return panel(1);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return panel(0);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications').doc(uid)
          .collection('items')
          .where('read', isEqualTo: false)
          .limit(30)
          .snapshots(),
      builder: (context, snap) {
        const teacherMsgTypes = {'teacher_note', 'child_announcement'};
        final n = snap.data?.docs.where((d) {
          final t = (d.data()['type'] ?? '').toString();
          return teacherMsgTypes.contains(t);
        }).length ?? 0;
        return panel(n);
      },
    );
  }

  /// Yuvarlak çocuk avatarı — foto varsa foto, yoksa gri kişi ikonu.
  /// [camera] true ise sağ-alt köşede yeşil kamera rozeti (Gelişim Paneli
  /// büyük kartındaki gibi).
  Widget _avatarCircle(BuildContext c, String? photoPath, double size,
      {bool camera = false}) {
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kGreen.withValues(alpha: 0.06),
        border: Border.all(color: _kGreen.withValues(alpha: 0.35)),
        image: photoPath == null
            ? null
            : DecorationImage(
                image: FileImage(File(photoPath)), fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: photoPath == null
          ? Icon(Icons.person,
              size: size * 0.55, color: AppPalette.textSecondary(c))
          : null,
    );
    if (!camera) return circle;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kGreen,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(Icons.photo_camera_rounded,
                size: 13, color: Colors.white),
          ),
        ),
      ],
    );
  }

  /// ODAK MODU kartı — Gelişim Paneli'ndeki genişletilmiş çocuk kartının
  /// AYNISI: solda büyük avatar (kamera rozetli, basınca profil düzenleme:
  /// isim + fotoğraf + durum mesajı), yanında isim + kalem + durum mesajı
  /// (boşsa "+ Durum mesajı ekle" kısayolu), en sağda diğer çocukların
  /// küçük avatarları (dikey — basınca o çocuğa geçer), sağ üstte küçültme
  /// oku. Demo çocuklarda da düzenleme açıktır (cihazda saklanır).
  Widget _focusChildCard(BuildContext context,
      {required List<String> names,
      required List<String> uids,
      required List<LinkedChild> active,
      required bool demoMode}) {
    final name = names[_selIdx];
    final uid = uids[_selIdx];
    final photo = _photoPath[uid];
    final status = (_statusMsg[uid] ?? '').trim();
    void edit() => _editChildSheet(
        uid,
        !demoMode && _selIdx < active.length
            ? active[_selIdx].displayName
            : '');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: _ov['chips'] ?? AppPalette.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kGreen, width: 1.4),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sol: büyük avatar — basınca profil (foto/ad/durum) düzenle.
              GestureDetector(
                onTap: edit,
                child: _avatarCircle(context, photo, 76, camera: true),
              ),
              const SizedBox(width: 14),
              // Orta: isim + kalem + durum mesajı.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.textPrimary(context),
                              )),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: edit,
                          child: const Icon(Icons.edit_rounded,
                              size: 14, color: _kGreen),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Durum mesajı; yoksa "+ Durum mesajı ekle" kısayolu.
                    status.isNotEmpty
                        ? Text(status,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              color: AppPalette.textSecondary(context),
                            ))
                        : GestureDetector(
                            onTap: edit,
                            child: Text('+ ${'Durum mesajı ekle'.tr()}',
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FontStyle.italic,
                                  color: _kGreen.withValues(alpha: 0.9),
                                )),
                          ),
                    // Henüz kodla bağlı çocuk yoksa: kartın sağ ortasında
                    // yanıp sönen "Çocuğunuza bağlanın" etiketi. Bağlantı
                    // kurulunca (active dolunca) kendiliğinden kaybolur.
                    if (!demoMode && active.isEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _connectChildLabel(context),
                      ),
                    ],
                  ],
                ),
              ),
              // En sağ sütun: üstte KÜÇÜLTME OKU (panel açık → SOLA bakar;
              // kapalı durumun oku çiplerin ucundaki sağa-bakan oktur),
              // altında diğer çocukların profil avatarları (basınca ona
              // geçer) ve ⇄ ipucu — basınca değişeceği anlaşılsın.
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _focusMode = false),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppPalette.bg(context),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: AppPalette.border(context)),
                      ),
                      child: Icon(Icons.chevron_left_rounded,
                          size: 22,
                          color: AppPalette.textSecondary(context)),
                    ),
                  ),
                  if (names.length > 1) ...[
                    const SizedBox(height: 10),
                    for (int i = 0; i < names.length; i++)
                      if (i != _selIdx)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _selIdx = i),
                            child: _avatarCircle(
                                context, _photoPath[uids[i]], 44),
                          ),
                        ),
                    Icon(Icons.swap_horiz_rounded,
                        size: 18,
                        color: AppPalette.textSecondary(context)),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Gelişim Paneli üstündeki çocuk seçici çipin AYNISI: dairede gri kişi
  /// ikonu (ebeveyn foto seçtiyse fotoğraf) + kalın ad; seçili çip açık
  /// yeşil dolgulu + yeşil çerçeveli. [onEdit] verilirse sağ üstte KALEM
  /// rozeti — ebeveyn foto/ad/durum mesajını değiştirebilir.
  /// [width] verilirse çip o genişliğe sabitlenir (ekrana tam 2 çip
  /// sığdırmak için) ve isim taşarsa üç nokta ile kısaltılır.
  /// Yerel eklenen ('local_N') çocuk çipine uzun basınca: onay al, sil.
  /// Kodla bağlı gerçek çocuklarda ÇAĞRILMAZ — onların bağlantısı ayrı
  /// yönetilir. Silinince prefs listesi + ad/foto/durum anahtarları temizlenir.
  Future<void> _confirmDeleteLocalChild(String id) async {
    final name = _alias[id] ?? 'Çocuk'.tr();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        icon: const Icon(Icons.delete_forever_rounded,
            color: Color(0xFFEF4444), size: 40),
        title: Text('Profili Sil'.tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(ctx))),
        content: Text(
            '"$name" ${'profilini silmek istediğine emin misin? Bu profil yalnızca bu cihazda kayıtlı; ad, foto ve durum bilgisi silinir.'.tr()}',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13,
                height: 1.45,
                color: AppPalette.textSecondary(ctx))),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç'.tr(),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final p = await SharedPreferences.getInstance();
    final list = [..._localIds]..remove(id);
    await p.setStringList('parent_local_children', list);
    await p.remove('child_alias_$id');
    await p.remove('child_status_$id');
    await p.remove('child_photo_$id');
    if (!mounted) return;
    setState(() {
      _localIds = list;
      _alias.remove(id);
      _statusMsg.remove(id);
      _photoPath.remove(id);
      _selIdx = 0;
      _focusMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Profil silindi.'.tr()),
        behavior: SnackBarBehavior.floating));
  }

  Widget _childChip(BuildContext c, String name,
      {required bool selected,
      required VoidCallback onTap,
      String? photoPath,
      VoidCallback? onEdit,
      VoidCallback? onLongPress,
      double? width}) {
    final chip = Material(
      color: _ov['chips'] ??
          (selected
              ? _kGreen.withValues(alpha: 0.12)
              : AppPalette.card(c)),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        // Yerel eklenen çocukta uzun basış → silme onayı.
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? _kGreen : AppPalette.border(c),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize:
                width == null ? MainAxisSize.min : MainAxisSize.max,
            children: [
              _avatarCircle(c, photoPath, 40),
              const SizedBox(width: 10),
              width == null
                  ? Text(name,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(c),
                      ))
                  : Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textPrimary(c),
                          )),
                    ),
              const SizedBox(width: 4),
              // Kapalı durumun oku SAĞA bakar — basınca profil açılır.
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppPalette.textSecondary(c)),
            ],
          ),
        ),
      ),
    );
    if (onEdit == null) return chip;
    // Sağ üstte kalem rozeti — profil foto/ad/durum düzenleme.
    // Rozet çip çerçevesinin İÇİNDE kalır (taşma yok).
    return Stack(
      children: [
        chip,
        Positioned(
          right: 3,
          top: 3,
          child: GestureDetector(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kGreen,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.edit_rounded,
                  size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  /// Yeşil kart içi istatistik (sola hizalı, beyaz — Gelişim Paneli deseni).
  /// Rakam ve etiket AYNI sol hizada: uzun etiket ("Çözülen soru") kolona
  /// sığmazsa sarmak/kaymak yerine tek satırda küçülür.
  Widget _greenStat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                )),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label,
                maxLines: 1,
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                )),
          ),
        ],
      ),
    );
  }

}


// ═══════════════════════════════════════════════════════════════════════════
//  ÖĞRENCİ PANELİ ÖNİZLEMESİ — çocuğun gördüğü ANA SAYFA (CameraScreen,
//  alt sekmeli kök) + altta "Ebeveyn Paneli"ne dönüş çipi.
//  ParentPreview.active bu rota açıkken true; üretim/yarışma eylemleri her
//  ekranda ParentPreview.guard ile kapalı.
// ═══════════════════════════════════════════════════════════════════════════
class _StudentPreviewShell extends StatefulWidget {
  const _StudentPreviewShell();

  @override
  State<_StudentPreviewShell> createState() => _StudentPreviewShellState();
}

class _StudentPreviewShellState extends State<_StudentPreviewShell> {
  // İÇ İÇE Navigator: önizlemede açılan TÜM sayfalar bu navigator'a push
  // edilir — dönüş çipi Stack'in üstünde olduğundan hangi sayfaya girilirse
  // girilsin görünür kalır (eskiden kök navigator'a push edilip çipi
  // örtüyordu).
  final _navKey = GlobalKey<NavigatorState>();
  // Dönüş çipi SÜRÜKLENEBİLİR — basılı tutup istediğin yere taşı.
  Offset? _chipPos;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      const chipW = 250.0, chipH = 46.0;
      // Varsayılan konum alt sekme çubuğunun ÜSTÜ — çip, öğrenci panelindeki
      // alt gezinme sekmelerini kapatmasın (istenirse sürüklenip taşınır).
      final pos = _chipPos ??
          Offset((cons.maxWidth - chipW) / 2, cons.maxHeight - chipH - 150);
      return Stack(
        children: [
          NavigatorPopHandler(
            // Sistem geri tuşu önce İÇTEKİ sayfaları kapatsın; içeride sayfa
            // kalmayınca önizleme rotasının kendisi kapanır.
            onPopWithResult: (_) => _navKey.currentState?.maybePop(),
            child: Navigator(
              key: _navKey,
              onGenerateRoute: (settings) =>
                  MaterialPageRoute(builder: (_) => CameraScreen()),
            ),
          ),
          // Dönüş çipi — HER sayfada görünür; sürüklenerek taşınabilir.
          Positioned(
            left: pos.dx.clamp(4.0, math.max(4.0, cons.maxWidth - chipW)),
            top: pos.dy.clamp(4.0, math.max(4.0, cons.maxHeight - chipH)),
            child: GestureDetector(
              onPanUpdate: (d) =>
                  setState(() => _chipPos = (_chipPos ?? pos) + d.delta),
              child: Material(
                color: _kBrand,
                borderRadius: BorderRadius.circular(999),
                elevation: 6,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.drag_indicator_rounded,
                            size: 15, color: Colors.white70),
                        const SizedBox(width: 4),
                        const Icon(Icons.family_restroom_rounded,
                            size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text('Ebeveyn paneline geri dön'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}
