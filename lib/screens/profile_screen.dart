// ignore_for_file: unused_element

import '../services/account_service.dart';
import '../services/error_logger.dart';
import '../services/parent_link_service.dart';
import '../services/runtime_translator.dart';
import 'delete_account_screen.dart';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'join_class_screen.dart';
import 'notifications_inbox_screen.dart';
import 'onboarding_screen.dart';
import 'student_homeworks_screen.dart';
import '../widgets/parent_invite_banner.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/locale_service.dart';
import '../services/pricing_service.dart';
import '../services/premium_status.dart';
import '../services/referral_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:image/image.dart' as img;
import '../services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../services/app_settings_service.dart';
import '../services/friend_service.dart';
import '../services/preferences_sync_service.dart';
import '../services/user_profile_service.dart';
import '../services/push_service.dart';
import '../services/solutions_storage.dart';
import '../theme/app_theme.dart';
import '../main.dart' show themeService, localeService;
import 'premium_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

// ── Kullanıcı ID yardımcısı (ilk açılışta üret, kalıcı sakla) ──────────────
Future<String> loadOrCreateUserId() async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString('user_id');
  if (id == null || id.isEmpty) {
    final rng = Random.secure();
    id = List.generate(8, (_) => rng.nextInt(10)).join();
    await prefs.setString('user_id', id);
  }
  return id;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ProfileScreen — Modern Soft Design
// ═══════════════════════════════════════════════════════════════════════════════

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // 0 = Dark, 1 = Light, 2 = System
  int get _themeMode => themeService.index;

  // Profil bilgileri
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _membershipCtrl = TextEditingController();
  String? _profileImagePath;

  // Premium durumu — DAVET kartını gizlemek / Premium banner'ı koşullu
  // göstermek için.
  PremiumStatusSnapshot _premium = PremiumStatusSnapshot.inactive;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _refreshPremium();
    // Premium statusu değişince (örn arka planda referral ödülü grant
    // edilirse) UI rebuild olsun.
    PremiumStatus.revision.addListener(_refreshPremium);
  }

  @override
  void dispose() {
    PremiumStatus.revision.removeListener(_refreshPremium);
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _membershipCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshPremium() async {
    final s = await PremiumStatus.read();
    if (!mounted) return;
    setState(() => _premium = s);
  }

  /// Öğrenci: ebeveynini bağlamak için kod üretir ve gösterir. Ebeveyn bu kodu
  /// kendi uygulamasında (Kütüphanem üstündeki panele basıp) girer; ardından
  /// öğrenciye gelen onay banner'ından (ParentInviteBanner) onaylanır.
  Future<void> _showParentLinkCode() async {
    final code = await ParentLinkService.generateChildLinkCode();
    if (!mounted) return;
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Kod üretilemedi. Giriş yaptığından emin ol.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Ebeveyn Bağlanma Kodu'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Bu kodu ebeveynine ver. Ebeveynin, kendi uygulamasında '
                'ebeveyn hesabıyla girip Kütüphanem sayfasının üstündeki '
                'panele basıp bu kodu yazsın. Sonra sana gelen istekten '
                'onayla — bağlantı kurulur.'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppPalette.textSecondary(ctx))),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code.code));
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text('Kod kopyalandı'.tr()),
                  behavior: SnackBarBehavior.floating,
                ));
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SelectableText(code.code,
                      style: GoogleFonts.poppins(
                        fontSize: 28, fontWeight: FontWeight.w900,
                        letterSpacing: 2, color: const Color(0xFF10B981),
                      )),
                  const SizedBox(width: 8),
                  Icon(Icons.copy_rounded, size: 20,
                      color: AppPalette.textSecondary(ctx)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('15 dakika geçerli.'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppPalette.textSecondary(ctx))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Kapat'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text = prefs.getString('profile_name') ?? '';
      _emailCtrl.text = prefs.getString('profile_email') ?? '';
      _membershipCtrl.text = prefs.getString('profile_membership') ?? '';
      _profileImagePath = prefs.getString('profile_image');
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name', _nameCtrl.text);
    await prefs.setString('profile_email', _emailCtrl.text);
    await prefs.setString('profile_membership', _membershipCtrl.text);
    if (_profileImagePath != null) {
      await prefs.setString('profile_image', _profileImagePath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = LocaleInherited.of(context);
    final tr = locale.tr;
    // Hesap tipine göre öğrenciye özgü bölümleri gizle / öğretmene branş ekle.
    final isStudent = AccountService.instance.isStudent;
    final isTeacher = AccountService.instance.isTeacher;
    final teacherBranch = AccountService.instance.teacherBranch;

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          child: Column(
            children: [
              // Bekleyen ebeveyn istek bildirimi (varsa).
              const ParentInviteBanner(),
              SizedBox(height: 20),

              // ═════════════════════════════════════════════════════════════
              //  1. Profil Üst Bilgisi (Header) — Tıklanabilir Avatar
              // ═════════════════════════════════════════════════════════════
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // Profil Fotoğrafı + Rozet — Tıkla → tam sayfa profil düzenle
                    GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileEditPage(),
                          ),
                        );
                        await _loadProfile();
                        if (mounted) setState(() {});
                      },
                      child: SizedBox(
                        width: 90,
                        height: 90,
                        child: Stack(
                          children: [
                            Center(
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF00E5FF),
                                      Color(0xFF6B21F2)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0xFF00E5FF)
                                          .withValues(alpha: 0.3),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(3),
                                child: _profileImagePath != null
                                    ? CircleAvatar(
                                        radius: 37,
                                        backgroundImage:
                                            FileImage(File(_profileImagePath!)),
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
            color: AppPalette.card(context),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.person_rounded,
                                          size: 40,
                                          color: Color(0xFF00C2D4),
                                        ),
                                      ),
                              ),
                            ),
                            // Sağ alt köşe kalem rozet
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
            color: AppPalette.card(context),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.12),
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Color(0xFF00E5FF)
                                        .withValues(alpha: 0.4),
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.edit_rounded,
                                  size: 14,
                                  color: Color(0xFF00C2D4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    // İsim — controller'dan okur, boşsa placeholder
                    Text(
                      _nameCtrl.text.isEmpty ? tr('username') : _nameCtrl.text,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context),
                        letterSpacing: -0.5,
                      ),
                    ),
                    // Kullanıcı adı + kopyala — UserProfileService canlı dinler.
                    AnimatedBuilder(
                      animation: UserProfileService.instance,
                      builder: (ctx, _) {
                        final uname =
                            UserProfileService.instance.username;
                        if (uname.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                uname,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      AppPalette.textSecondary(context),
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  await Clipboard.setData(
                                      ClipboardData(text: uname));
                                  if (!mounted) return;
                                  messenger.showSnackBar(SnackBar(
                                    content: Text(
                                        'Kullanıcı adın kopyalandı'.tr()),
                                    behavior:
                                        SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 2),
                                  ));
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.content_copy_rounded,
                                    size: 14,
                                    color: AppPalette.textSecondary(
                                        context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    SizedBox(height: 12),
                    // Premium'a Yükselt — gösterim kuralları:
                    //   1) Yaptırım altındaki ülkelerde gizli (Apple/Google
                    //      ödeme alamıyor).
                    //   2) Zaten Premium kullanıcıda gizli — yerine "Premium
                    //      durumu" kartı gösteriliyor.
                    if (!PricingService.isSanctionedCountry(
                        PricingService.countryFromLang(localeService.localeCode)))
                      _premium.isActive
                          ? _PremiumActiveCard(snapshot: _premium)
                          : _PremiumBanner(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PremiumScreen(),
                                  ),
                                );
                                _refreshPremium();
                              },
                            ),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // ═════════════════════════════════════════════════════════════
              //  2. Davet — HER ZAMAN görünür (kullanıcı talebi).
              //  Eskiden `!_premium.isActive` koşuluyla premium olunca
              //  veya 3 davet tamamlanınca sekme kayboluyordu; artık
              //  premium olsa veya 3+ davet bitse bile görünmeye devam eder.
              //  Yaptırımlı ülkelerde hâlâ gizli (ödeme alamıyoruz).
              //  Öğretmende gizli — öğretmenin arkadaş davet etmesine gerek yok.
              // ═════════════════════════════════════════════════════════════
              if (!isTeacher && !PricingService.isSanctionedCountry(
                      PricingService.countryFromLang(
                          localeService.localeCode))) ...[
                _buildSectionTitle('Davet'.tr().toUpperCase()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InvitePage(),
                        ),
                      );
                      _refreshPremium();
                    },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF9A4D), Color(0xFFFF6A00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Color(0xFFFFD9B8),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFFF6A00).withValues(alpha: 0.28),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: -6,
                          right: -6,
                          // Emoji universal — .tr() gereksiz, RuntimeTranslator'a
                          // gönderince "yıldız" gibi metne çevirebilir.
                          child: Text('✨',
                              style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white
                                      .withValues(alpha: 0.9))),
                        ),
                        Positioned(
                          bottom: -4,
                          left: -2,
                          child: Text('🎉',
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white
                                      .withValues(alpha: 0.85))),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  width: 1.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text('🎁',
                                  style: TextStyle(fontSize: 26)),
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    localeService.tr('invite_friends_title'),
                                    style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppPalette.textPrimary(context),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    localeService.tr('invite_card_subtitle'),
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppPalette.textPrimary(context),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                ),
                SizedBox(height: 24),
              ], // ← DAVET section'ı bitti

              // ═════════════════════════════════════════════════════════════
              //  Ebeveyn Paneli — DAVET ile alakası yok, kendi bölümünde.
              //  PIN/matematik doğrulamasından sonra ParentReportPage açılır.
              //  Sadece ÖĞRENCİ hesabında — öğretmen/ebeveyn için anlamsız.
              // ═════════════════════════════════════════════════════════════
              if (isStudent) ...[
              _buildSectionTitle('Aile'.tr().toUpperCase()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GestureDetector(
                  onTap: _showParentLinkCode,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(
                      color: AppPalette.card(context),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Color(0xFF1E3A8A).withValues(alpha: 0.30),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Color(0xFF1E3A8A).withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Color(0xFF1E3A8A).withValues(alpha: 0.30),
                              width: 1.2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.link_rounded,
                            size: 28,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ebeveyni Bağla'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.textPrimary(context),
                                  letterSpacing: 0.2,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Kod üret, ebeveynine ver — gelişimini takip etsin'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppPalette.textSecondary(context),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: AppPalette.textSecondary(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(height: 24),
              ],

              // ═════════════════════════════════════════════════════════════
              //  3. Uygulama Tercihleri
              // ═════════════════════════════════════════════════════════════
              _buildSectionTitle(tr('app_preferences')),
              _buildOvalMenuItem(
                emoji: '🌐',
                title: tr('language_selection'),
                trailing: _buildCurrentLanguageChip(locale),
                onTap: () => _showLanguageBottomSheet(context),
              ),
              SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '🌗',
                title: tr('appearance'),
                trailing: _buildCurrentThemeChip(locale),
                onTap: () => _showThemeBottomSheet(context),
              ),
              SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '🔔',
                title: 'Bildirim Ayarları'.tr(),
                onTap: () => _showNotificationsBottomSheet(context),
              ),
              SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '⚙️',
                title: 'Uygulama Ayarları'.tr(),
                onTap: () => _showAppSettingsBottomSheet(context),
              ),
              // Öğretmen: branşı salt-okunur göster.
              if (isTeacher && teacherBranch != null &&
                  teacherBranch.trim().isNotEmpty) ...[
                SizedBox(height: 10),
                _buildOvalMenuItem(
                  emoji: '🎓',
                  title: 'Branşım'.tr(),
                  trailing: Text(
                    teacherBranch,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondary(context),
                    ),
                  ),
                ),
              ],
              // Sınıfa Katıl + Sınıf Ödevlerim — sadece ÖĞRENCİ.
              if (isStudent) ...[
                SizedBox(height: 10),
                _buildOvalMenuItem(
                  emoji: '🏫',
                  title: 'Sınıfa Katıl'.tr(),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const JoinClassScreen(),
                  )),
                ),
                SizedBox(height: 10),
                _buildOvalMenuItem(
                  emoji: '📋',
                  title: 'Sınıf Ödevlerim'.tr(),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const StudentHomeworksScreen(),
                  )),
                ),
              ],
              SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '🔔',
                title: 'Bildirimler'.tr(),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NotificationsInboxScreen(),
                )),
              ),

              SizedBox(height: 24),

              // ═════════════════════════════════════════════════════════════
              //  4. Destek ve İletişim
              // ═════════════════════════════════════════════════════════════
              _buildSectionTitle(tr('support_contact')),
              _buildOvalMenuItem(
                emoji: '⭐',
                title: tr('send_feedback'),
                onTap: () => _showFeedbackBottomSheet(context),
              ),
              SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '✉️',
                title: tr('contact_us'),
                onTap: () => _showContactBottomSheet(context),
              ),
              SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '❓',
                title: 'Yardım Merkezi / SSS'.tr(),
                onTap: () => _showHelpCenter(context),
              ),

              SizedBox(height: 24),

              // ═════════════════════════════════════════════════════════════
              //  4. Bilgi
              // ═════════════════════════════════════════════════════════════
              _buildSectionTitle(tr('information')),
              _buildOvalMenuItem(
                emoji: 'ℹ️',
                title: tr('about_us'),
                onTap: () => _showAboutDialog(),
              ),
              SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '📄',
                title: tr('terms_privacy'),
                onTap: () => _showTermsPrivacySheet(context),
              ),
              SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '📚',
                title: 'Açık Kaynak Lisansları'.tr(),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _CenteredLicensesScreen(),
                  ),
                ),
              ),
              SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '🏷️',
                title: 'Sürüm'.tr(),
                trailing: FutureBuilder<String>(
                  future: _appVersionLine(),
                  builder: (_, snap) {
                    final v = snap.data ?? '';
                    return Text(
                      v,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textSecondary(context),
                      ),
                    );
                  },
                ),
                onTap: () => _showVersionDialog(context),
              ),

              SizedBox(height: 32),

              // ═════════════════════════════════════════════════════════════
              //  5. Oturum Kapat + Hesabımı Sil
              //  Apple Guideline 5.1.1(v): kullanıcı hesabı silebilmeli.
              // ═════════════════════════════════════════════════════════════
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  onTap: () => _showLogoutDialog(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 20),
                    decoration: BoxDecoration(
                      color: AppPalette.card(context),
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: AppPalette.shadow(context),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🚪', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 12),
                        Text(
                          tr('logout'),
                          style: GoogleFonts.poppins(
                            color: Color(0xFFEF4444),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(height: 12),

              // Hesabımı Sil — Apple Guideline 5.1.1(v) zorunlu.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  onTap: () => _openDeleteAccountScreen(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 20),
                    decoration: BoxDecoration(
                      color: AppPalette.card(context),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.40),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.delete_forever_rounded,
                            size: 20, color: Color(0xFFB91C1C)),
                        const SizedBox(width: 10),
                        Text(
                          'Hesabımı Sil'.tr(),
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFB91C1C),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Profile yeni metotları: Bildirim ayarları, Yardım merkezi, Sürüm,
  //  Hesap silme. Bunlar profile sekmesinde yeni eklemeler.
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _appVersionLine() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } catch (_) {
      return '';
    }
  }

  void _showVersionDialog(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Sürüm bilgisi'.tr(),
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _versionRow('Uygulama'.tr(), info.appName),
            _versionRow('Paket adı'.tr(), info.packageName),
            _versionRow('Sürüm'.tr(), info.version),
            _versionRow('Yapı numarası'.tr(), info.buildNumber),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Tamam'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _versionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppPalette.textSecondary(context),
              )),
          Expanded(
            child: Text(value,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context),
                )),
          ),
        ],
      ),
    );
  }

  void _showNotificationsBottomSheet(BuildContext context) =>
      showNotificationSettingsSheet(context);

  void _showAppSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _AppSettingsSheet(),
    );
  }

  void _showHelpCenter(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => Container(
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Yardım Merkezi / SSS'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: sc,
                  children: [
                    // ── Öğretmene özgü SSS ──
                    if (AccountService.instance.isTeacher) ...[
                      _faqTile(
                        'Nasıl sınıf oluştururum?'.tr(),
                        'Sınıflar sekmesindeki ➕ butonuna bas → "Yeni Sınıf '
                                'Oluştur". Eğitim seviyesi, okul ve sınıf adını '
                                'gir; sana 5 haneli bir katılma kodu verilir.'
                            .tr(),
                      ),
                      _faqTile(
                        'Öğrencilerimi sınıfa nasıl eklerim?'.tr(),
                        'Sınıf kartındaki katılma kodunu öğrencilerinle '
                                'paylaş — onlar Profil → "Sınıfa Katıl"dan kodu '
                                'girer. Ayrıca ➕ → "Öğrenci Davet Et" ile '
                                'kullanıcı adından arayıp davet gönderebilirsin.'
                            .tr(),
                      ),
                      _faqTile(
                        'AI ile nasıl ödev oluştururum?'.tr(),
                        'Bir sınıf aç → Ödevler → AI Ödev Üreticisi. Konu, '
                                'soru tipi ve adedini seç; yapay zeka soruları '
                                'üretir, önizleyip düzenleyip sınıfa gönderirsin. '
                                'Branş otomatik olarak senin branşındır.'
                            .tr(),
                      ),
                      _faqTile(
                        'Öğrenci performansını nereden görürüm?'.tr(),
                        'Sınıflar sekmesinde bir sınıfa bas → öğrenci → ödev → '
                                'teslim detayı (doğru/yanlış/boş, aktif/pasif '
                                'süre, AI değerlendirmesi). Nasıl göründüğünü '
                                'denemek için "Demo veri ekle"yi kullanabilirsin.'
                            .tr(),
                      ),
                    ] else ...[
                      _faqTile(
                        'Davet kodum çalışmıyor, ne yapmalıyım?'.tr(),
                        'Davet kodu QUALS-XXXXXX formatında olmalıdır. '
                                'Kendi kodunu kullanamazsın ve her cihazda '
                                'bir kez kullanılabilir.'
                            .tr(),
                      ),
                      _faqTile(
                        'Çocuk hesabımı koruyabilir miyim?'.tr(),
                        'Aile bölümündeki "Ebeveyn Paneli"ne bas. PIN veya '
                                'matematik doğrulamasından sonra çocuğunun '
                                'çalışma raporunu görebilir, sınırlar '
                                'koyabilirsin.'
                            .tr(),
                      ),
                    ],
                    // ── Herkese ortak ──
                    _faqTile(
                      'Premium aboneliğimi nasıl iptal ederim?'.tr(),
                      'iOS: Ayarlar → Apple Kimliği → Abonelikler. '
                              'Android: Google Play → Hesabım → Abonelikler. '
                              'İptal mevcut dönem sonunda etkin olur.'
                          .tr(),
                    ),
                    _faqTile(
                      'Satın aldığım Premium başka cihazda görünmüyor.'.tr(),
                      'Premium sekmesinde alt kısımdaki "Satın Alımları '
                              'Geri Yükle" düğmesine bas. App Store / Play '
                              'Store hesabınla bağlı satın alımlar geri '
                              'yüklenir.'
                          .tr(),
                    ),
                    _faqTile(
                      'Hesabımı sildiğimde ne olur?'.tr(),
                      'Hesabın ve tüm kişisel verilerin (profil, davet '
                              'kayıtları, çalışma geçmişi) kalıcı olarak '
                              'silinir. Aktif aboneliklerin App Store / '
                              'Play Store üzerinden ayrıca iptal edilmelidir.'
                          .tr(),
                    ),
                    _faqTile(
                      'Dilimi nasıl değiştiririm?'.tr(),
                      'Profil → Uygulama Tercihleri → Dil Seçimi. '
                              '53 dilde kullanılabilir.'
                          .tr(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _faqTile(String q, String a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppPalette.bg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text(
            q,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppPalette.textPrimary(context),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                a,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: AppPalette.textSecondary(context),
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hesap silme akışı — Apple Guideline 5.1.1(v) zorunlu.
  /// QandA tarzı tam ekran açar: önce duygusal/açıklayıcı sayfa, alttaki
  /// "QuAlsar'dan Ayrıl" butonu bastıktan sonra ikinci güvenlik kapısı
  /// (yazılı "SİL" onayı) DeleteAccountScreen içinde sorulur — onaylanırsa
  /// onConfirmDelete callback'i (_performAccountDeletion) çağrılır.
  void _openDeleteAccountScreen() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DeleteAccountScreen(
        onConfirmDelete: _performAccountDeletion,
      ),
    ));
  }

  Future<void> _performAccountDeletion() async {
    if (!mounted) return;
    // Hesap silme süreci — Cloud Function ile FULL CASCADE delete.
    //   1) Cloud Function `deleteAccount` çağrısı (Auth admin SDK ile
    //      Firestore'daki TÜM ilişkili veriyi cascade siler + Auth user'ı siler)
    //   2) FCM token cihazdan kaldır
    //   3) Lokal SharedPreferences + image cache temizle
    //   4) Onboarding'e geri at
    // Apple Guideline 5.1.1(v) + GDPR Article 17 uyumu için kritik.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            margin: EdgeInsets.symmetric(horizontal: 60),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16))),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text(
                    'Hesabın siliniyor…',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // 1) Cloud Function — server-side cascade delete
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('deleteAccount',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 60),
              ));
      final result = await callable.call();
      debugPrint('[Profile] deleteAccount result: ${result.data}');
    } catch (e) {
      debugPrint('[Profile] deleteAccount Cloud Function fail: $e');
      // Devam et — local cleanup yine de yapılsın. Auth tarafında zaten
      // delete denemesi yapıldı; başarısız olursa user oturum açık kalır.
    }
    // 2) FCM token bu cihazdan kaldır — push gönderilmesin
    try {
      await PushService.clearTokenOnLogout();
    } catch (_) {}
    // 3) Local auth sign out + prefs clear
    try {
      await AuthService.signOut();
    } catch (_) {/* network olabilir */}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'profile_screen'); }
    if (!mounted) return;
    Navigator.of(context).pop(); // loading dialog
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Hesabın ve tüm verilerin silindi.'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Ortak Widget Builders
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppPalette.textSecondary(context),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildOvalMenuItem({
    required String emoji,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: AppPalette.shadow(context),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(emoji, style: TextStyle(fontSize: 24)),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
              ),
              if (trailing != null)
                trailing
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppPalette.textSecondary(context),
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  1) Profil Bottom Sheet — Düzenlenebilir Alanlar + Şifre + Kaydet
  // ═══════════════════════════════════════════════════════════════════════════

  void _showProfileBottomSheet(BuildContext context) {
    final locale = LocaleInherited.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              decoration: BoxDecoration(
            color: AppPalette.card(context),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                physics: BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppPalette.border(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(height: 20),

                    // Mini avatar (tıklanabilir — profil düzenleme sayfasını aç).
                    // Doğrudan galeri seçici yerine ProfileEditPage'e gider:
                    // oradaki foto değişimi BULUTA da senkronlanır (avatar
                    // arkadaş kartları/leaderboard'da güncellenir). Eski
                    // doğrudan yol cloud-sync yapmıyordu.
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(ctx);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ProfileEditPage()),
                        );
                        await _loadProfile();
                        if (mounted) setState(() {});
                      },
                      child: Stack(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFF00E5FF).withValues(alpha: 0.25),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(2.5),
                            child: _profileImagePath != null
                                ? CircleAvatar(
                                    radius: 34,
                                    backgroundImage:
                                        FileImage(File(_profileImagePath!)),
                                  )
                                : Container(
                                    decoration: BoxDecoration(
            color: AppPalette.card(context),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.person_rounded,
                                        size: 36, color: Color(0xFF00C2D4)),
                                  ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Color(0xFF00E5FF),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Icon(Icons.camera_alt_rounded,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),

                    // Ad Soyad
                    _editableField(
                      controller: _nameCtrl,
                      icon: Icons.person_outline_rounded,
                      label: locale.tr('full_name'),
                    ),
                    SizedBox(height: 10),

                    // E-posta
                    _editableField(
                      controller: _emailCtrl,
                      icon: Icons.email_outlined,
                      label: locale.tr('email'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: 10),

                    // Üyeliğim
                    _editableField(
                      controller: _membershipCtrl,
                      icon: Icons.workspace_premium_rounded,
                      label: locale.tr('membership'),
                      readOnly: true,
                    ),

                    SizedBox(height: 18),

                    // Şifre Değiştir
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _showPasswordBottomSheet(context);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Color(0xFF3B82F6).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: Color(0xFF3B82F6).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                color: Color(0xFF3B82F6), size: 18),
                            SizedBox(width: 8),
                            Text(
                              locale.tr('change_password'),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 10),

                    // Kaydet butonu
                    GestureDetector(
                      onTap: () async {
                        await _saveProfile();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          setState(() {});
                          _showSnack(locale.tr('profile_saved'));
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                          ),
                          borderRadius: BorderRadius.circular(50),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF00E5FF).withValues(alpha: 0.25),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              locale.tr('save'),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _editableField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppPalette.textSecondary(context)),
          SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
              keyboardType: keyboardType,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: readOnly
                    ? Color(0xFFF59E0B)
                    : Color(0xFF333333),
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: label,
                hintStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Color(0xFFBBBBCC),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Şifre Değiştirme Bottom Sheet (Validasyonlu)
  // ═══════════════════════════════════════════════════════════════════════════

  void _showPasswordBottomSheet(BuildContext context) {
    final locale = LocaleInherited.of(context);
    final formKey = GlobalKey<FormState>();
    final oldPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final confirmPwCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              decoration: BoxDecoration(
            color: AppPalette.card(context),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppPalette.border(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
                        child: Row(
                          children: [
                            Text('🔒'.tr(), style: TextStyle(fontSize: 22)),
                            SizedBox(width: 10),
                            Text(
                              locale.tr('change_password'),
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: AppPalette.border(context)),
                      SizedBox(height: 16),

                      // Eski Şifre
                      _passwordField(
                        controller: oldPwCtrl,
                        label: locale.tr('old_password'),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return locale.tr('password_required');
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 12),

                      // Yeni Şifre
                      _passwordField(
                        controller: newPwCtrl,
                        label: locale.tr('new_password'),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return locale.tr('password_required');
                          }
                          if (v.length < 8) return locale.tr('password_min');
                          if (!v.contains(RegExp(r'[A-Z]'))) {
                            return locale.tr('password_upper');
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 12),

                      // Yeni Şifre Tekrar
                      _passwordField(
                        controller: confirmPwCtrl,
                        label: locale.tr('confirm_password'),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return locale.tr('password_required');
                          }
                          if (v != newPwCtrl.text) {
                            return locale.tr('password_mismatch');
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 20),

                      // Şifreyi Güncelle butonu
                      GestureDetector(
                        onTap: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.pop(ctx);
                            _showSnack(locale.tr('profile_saved'));
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF6B21F2)],
                            ),
                            borderRadius: BorderRadius.circular(50),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF3B82F6).withValues(alpha: 0.25),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_rounded,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                locale.tr('update_password'),
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      oldPwCtrl.dispose();
      newPwCtrl.dispose();
      confirmPwCtrl.dispose();
    });
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      validator: validator,
      style: GoogleFonts.poppins(
        fontSize: 14,
        color: AppPalette.textPrimary(context),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: AppPalette.textSecondary(context),
        ),
        filled: true,
        fillColor: Color(0xFFF7F8FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(color: AppPalette.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(color: AppPalette.border(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(color: Color(0xFF3B82F6), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        errorStyle: GoogleFonts.poppins(
          fontSize: 11,
          color: Color(0xFFEF4444),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Icon(Icons.lock_outline_rounded,
              size: 20, color: AppPalette.textSecondary(context)),
        ),
        prefixIconConstraints:
            BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Dil Seçim Penceresi
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCurrentLanguageChip(LocaleService locale) {
    final current = LocaleService.languages.firstWhere(
      (l) => l.$4 == locale.localeCode,
      orElse: () => LocaleService.languages[1],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Color(0xFF3B82F6).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(0xFF3B82F6), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(current.$1, style: TextStyle(fontSize: 16)),
          SizedBox(width: 4),
          Text(
            current.$4.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3B82F6),
            ),
          ),
          SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded,
              color: Color(0xFF3B82F6), size: 16),
        ],
      ),
    );
  }

  void _showLanguageBottomSheet(BuildContext context) {
    final locale = LocaleInherited.of(context);
    String searchQuery = '';
    final searchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              // Arama filtresi
              final query = searchQuery.toLowerCase().trim();
              final allLangs = LocaleService.languages;
              final filtered = query.isEmpty
                  ? allLangs
                  : allLangs.where((lang) {
                      final (_, name, englishName, code, _) = lang;
                      return name.toLowerCase().contains(query) ||
                          englishName.toLowerCase().contains(query) ||
                          code.toLowerCase().contains(query);
                    }).toList();

              // Seçili dili en üstte göster
              final selectedCode = locale.localeCode;
              final sortedLangs = <(String, String, String, String, String)>[];
              (String, String, String, String, String)? selectedLang;
              for (final lang in filtered) {
                if (lang.$4 == selectedCode) {
                  selectedLang = lang;
                } else {
                  sortedLangs.add(lang);
                }
              }
              if (selectedLang != null) sortedLangs.insert(0, selectedLang);

              return Container(
                height: MediaQuery.of(context).size.height * 0.75,
                decoration: BoxDecoration(
                  color: AppPalette.cardMuted(context),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppPalette.border(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                      child: Row(
                        children: [
                          Text('🌐'.tr(),
                              style: TextStyle(fontSize: 22)),
                          SizedBox(width: 10),
                          Text(
                            locale.tr('select_language'),
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Arama çubuğu ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppPalette.cardMuted(context),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: searchController,
                          onChanged: (val) =>
                              setSheetState(() => searchQuery = val),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: AppPalette.textPrimary(context),
                          ),
                          cursorColor: Color(0xFF3B82F6),
                          decoration: InputDecoration(
                            hintText: locale.tr('search_language'),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 14,
                              color: AppPalette.textSecondary(context),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: AppPalette.textSecondary(context),
                              size: 20,
                            ),
                            suffixIcon: searchQuery.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      searchController.clear();
                                      setSheetState(
                                          () => searchQuery = '');
                                    },
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: AppPalette.textSecondary(context),
                                      size: 18,
                                    ),
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),

                    Divider(height: 1, color: AppPalette.border(context)),

                    // ── Dil listesi ───────────────────────────────────
                    Expanded(
                      child: sortedLangs.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  locale.tr('no_results'),
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: AppPalette.textSecondary(context),
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              physics: BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              itemCount: sortedLangs.length,
                              itemBuilder: (_, i) {
                                final (flag, name, englishName, code, culture) =
                                    sortedLangs[i];
                                final isSelected =
                                    locale.localeCode == code;

                                return GestureDetector(
                                  onTap: () {
                                    locale.setLocale(code);
                                    if (mounted) setState(() {});
                                    Navigator.pop(ctx);
                                  },
                                  child: AnimatedContainer(
                                    duration:
                                        Duration(milliseconds: 200),
                                    margin:
                                        const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Color(0xFF3B82F6)
                                              .withValues(alpha: 0.08)
                                          : Colors.transparent,
                                      borderRadius:
                                          BorderRadius.circular(24),
                                      border: Border.all(
                                        color: isSelected
                                            ? Color(0xFF3B82F6)
                                            : Color(0xFFE5E7EB),
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(flag,
                                            style: TextStyle(
                                                fontSize: 26)),
                                        SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 15,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color: isSelected
                                                      ? Color(
                                                          0xFF3B82F6)
                                                      : Color(
                                                          0xFF333333),
                                                ),
                                              ),
                                              Text(
                                                englishName,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 11,
                                                  color: Color(
                                                      0xFF9CA3AF),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(culture,
                                            style: TextStyle(
                                                fontSize: 22)),
                                        if (isSelected) ...[
                                          SizedBox(width: 10),
                                          Icon(
                                            Icons.check_circle_rounded,
                                            color: Color(0xFF3B82F6),
                                            size: 24,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Tema Seçimi
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCurrentThemeChip(LocaleService locale) {
    final labels = [
      locale.tr('dark_mode'),
      locale.tr('light_mode'),
      locale.tr('system_default')
    ];
    final icons = [
      Icons.dark_mode_rounded,
      Icons.light_mode_rounded,
      Icons.brightness_auto_rounded,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Color(0xFF8B5CF6).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(0xFF8B5CF6), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icons[_themeMode],
              size: 14, color: Color(0xFF8B5CF6)),
          SizedBox(width: 4),
          Text(
            labels[_themeMode],
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8B5CF6),
            ),
          ),
          SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded,
              color: Color(0xFF8B5CF6), size: 16),
        ],
      ),
    );
  }

  void _showThemeBottomSheet(BuildContext context) {
    final locale = LocaleInherited.of(context);

    final options = [
      (Icons.dark_mode_rounded, locale.tr('dark_mode'),
          Color(0xFF8B5CF6)),
      (Icons.light_mode_rounded, locale.tr('light_mode'),
          Color(0xFFF59E0B)),
      (Icons.brightness_auto_rounded, locale.tr('system_default'),
          Color(0xFF3B82F6)),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              return Container(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                decoration: BoxDecoration(
                  color: AppPalette.card(context),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppPalette.border(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 18, 4, 12),
                      child: Row(
                        children: [
                          Text('🌗'.tr(),
                              style: TextStyle(fontSize: 22)),
                          SizedBox(width: 10),
                          Text(
                            locale.tr('select_theme'),
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: AppPalette.border(context)),
                    SizedBox(height: 12),
                    ...List.generate(options.length, (i) {
                      final (icon, label, color) = options[i];
                      final isSelected = _themeMode == i;
                      return GestureDetector(
                        onTap: () async {
                          await themeService.setIndex(i);
                          if (mounted) setState(() {});
                          setSheetState(() {});
                        },
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? color.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isSelected
                                  ? color
                                  : AppPalette.border(context),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color.withValues(
                                      alpha: isSelected ? 0.18 : 0.08),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child:
                                    Icon(icon, color: color, size: 24),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  label,
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? color
                                        : AppPalette.textPrimary(context),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    color: color, size: 24),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Geri Bildirim Bottom Sheet
  // ═══════════════════════════════════════════════════════════════════════════

  void _showFeedbackBottomSheet(BuildContext context) {
    final locale = LocaleInherited.of(context);
    final controller = TextEditingController();
    bool sent = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  decoration: BoxDecoration(
            color: AppPalette.card(context),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tutma çubuğu
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppPalette.border(context),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
                        child: Row(
                          children: [
                            Text('⭐', style: TextStyle(fontSize: 22)),
                            SizedBox(width: 10),
                            Text(
                              locale.tr('send_feedback'),
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: AppPalette.border(context)),
                      SizedBox(height: 16),

                      // Yazı yazma alanı
                      Container(
                        decoration: BoxDecoration(
                          color: Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppPalette.border(context)),
                        ),
                        child: TextField(
                          controller: controller,
                          maxLines: 6,
                          minLines: 4,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: AppPalette.textPrimary(context),
                          ),
                          cursorColor: Color(0xFF00C2D4),
                          decoration: InputDecoration(
                            hintText: locale.tr('feedback_desc'),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Color(0xFFB0B7C3),
                            ),
                            hintMaxLines: 4,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),

                      SizedBox(height: 20),

                      // Gönder butonu — hem Firestore'a yaz (kalıcı kayıt)
                      // hem de email aç (kullanıcıya hızlı feedback).
                      // Rate limit: son 1 dakikada max 3 gönderim.
                      GestureDetector(
                        onTap: () async {
                          final text = controller.text.trim();
                          if (text.isEmpty) return;
                          // Rate limit kontrolü
                          final prefs = await SharedPreferences.getInstance();
                          final lastTimes = prefs.getStringList(
                                  'feedback_last_send_v1') ??
                              const <String>[];
                          final nowMs =
                              DateTime.now().millisecondsSinceEpoch;
                          final fresh = lastTimes
                              .map(int.tryParse)
                              .whereType<int>()
                              .where((t) => nowMs - t < 60 * 1000)
                              .toList();
                          if (fresh.length >= 3) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                content: Text(
                                    'Çok sık gönderim. 1 dk sonra tekrar dene.'
                                        .tr()),
                              ));
                            }
                            return;
                          }
                          fresh.add(nowMs);
                          await prefs.setStringList(
                              'feedback_last_send_v1',
                              fresh
                                  .map((t) => t.toString())
                                  .toList(growable: false));
                          // 1) Firestore'a yaz (anonim auth ok, rules zaten
                          //    `allow create: if true` — sadece admin okur)
                          var firestoreOk = false;
                          try {
                            await FirebaseFirestore.instance
                                .collection('feedback')
                                .add({
                              'text': text,
                              'userId': AuthService.current?.id ?? 'anonymous',
                              'userEmail':
                                  AuthService.current?.email ?? '',
                              'platform': Platform.isIOS
                                  ? 'ios'
                                  : (Platform.isAndroid ? 'android' : 'other'),
                              'appVersion': await _appVersionLine(),
                              'locale': locale.localeCode,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                            firestoreOk = true;
                          } catch (e) {
                            debugPrint('[Feedback] firestore write fail: $e');
                          }
                          if (firestoreOk) {
                            // Başarı — "Teşekkürler" göster, sheet kapansın.
                            setSheetState(() => sent = true);
                            Future.delayed(Duration(milliseconds: 1200), () {
                              if (ctx.mounted) Navigator.pop(ctx);
                            });
                          } else {
                            // Firestore başarısız (ağ yok vb.) → e-posta
                            // fallback'i aç; kullanıcı oradan gönderebilsin.
                            // "Gönderildi" DEME — gerçekte iletilmedi.
                            _launchEmail(
                              subject: 'QuAlsar - Geri Bildirim',
                              body: text,
                            );
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                content: Text(
                                    'Şu an gönderilemedi — açılan e-postadan iletebilirsin.'
                                        .tr()),
                                behavior: SnackBarBehavior.floating,
                              ));
                            }
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: sent
                                  ? [Color(0xFF22C55E), Color(0xFF16A34A)]
                                  : [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                            ),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                sent ? Icons.check_circle_rounded : Icons.send_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                sent ? locale.tr('feedback_thanks') : locale.tr('send'),
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Bize Ulaşın Bottom Sheet
  // ═══════════════════════════════════════════════════════════════════════════

  void _showContactBottomSheet(BuildContext context) {
    final locale = LocaleInherited.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            decoration: BoxDecoration(
            color: AppPalette.card(context),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.border(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
                  child: Row(
                    children: [
                      Text('✉️'.tr(), style: TextStyle(fontSize: 22)),
                      SizedBox(width: 10),
                      Text(
                        locale.tr('contact_us'),
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppPalette.border(context)),
                SizedBox(height: 16),

                // Açıklama metni — basılı tutarak kopyalanabilir
                SelectableText(
                  locale.tr('contact_desc'),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppPalette.textSecondary(context),
                    height: 1.6,
                  ),
                ),

                SizedBox(height: 20),

                // E-posta satırı
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _launchEmail(subject: 'QuAlsar - İletişim');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Color(0xFF00C2D4).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: Color(0xFF00C2D4).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.email_outlined,
                            size: 20, color: Color(0xFF00C2D4)),
                        SizedBox(width: 12),
                        Expanded(
                          child: SelectableText(
                            locale.tr('contact_email'),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF00C2D4),
                            ),
                          ),
                        ),
                        Icon(Icons.open_in_new_rounded,
                            size: 16, color: Color(0xFF00C2D4)),
                      ],
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

  // ═══════════════════════════════════════════════════════════════════════════
  //  E-posta & Yardımcı Metodlar
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _launchEmail({String subject = 'QuAlsar', String body = ''}) async {
    const email = 'serhatdsme@gmail.com';
    final query = <String>[];
    query.add('subject=${Uri.encodeComponent(subject)}');
    if (body.isNotEmpty) query.add('body=${Uri.encodeComponent(body)}');
    final uri = Uri.parse('mailto:$email?${query.join('&')}');

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'profile_screen'); }

    await Clipboard.setData(ClipboardData(text: email));
    if (mounted) _showSnack('$email kopyalandı');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppPalette.textPrimary(context),
          ),
        ),
        backgroundColor: AppPalette.card(context),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50)),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Hakkımızda & Çıkış Dialogları
  // ═══════════════════════════════════════════════════════════════════════════

  void _showAboutDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: AppPalette.bg(context),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // Tutma çubuğu
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.border(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // İçerik
                Expanded(
                  child: SingleChildScrollView(
                    physics: BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Logo + Başlık ────────────────────────────────
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0xFF00E5FF).withValues(alpha: 0.3),
                                      blurRadius: 20,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Icon(Icons.auto_awesome_rounded,
                                    size: 36, color: Colors.white),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'QuAlsar',
                                style: GoogleFonts.poppins(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: AppPalette.textPrimary(context),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Color(0xFF3B82F6).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  localeService.tr('future_ai_ecosystem'),
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF3B82F6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 24),

                        // ── Vizyon Açıklaması ────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
            color: AppPalette.card(context),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            localeService.tr('about_vision_desc'),
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              color: AppPalette.textSecondary(context),
                              height: 1.7,
                            ),
                          ),
                        ),
                        SizedBox(height: 24),

                        // ── Öğretmenler İçin (sadece öğretmen hesabında) ──
                        if (AccountService.instance.isTeacher) ...[
                          _aboutSectionTitle('👨‍🏫', 'Öğretmenler İçin'.tr()),
                          SizedBox(height: 12),
                          _aboutFeatureCard(
                            icon: Icons.class_rounded,
                            color: Color(0xFF7C3AED),
                            title: 'Sınıf Yönetimi'.tr(),
                            desc:
                                'Sınıf oluştur, 5 haneli kodla öğrencilerini ekle, hepsini tek yerden yönet.'
                                    .tr(),
                          ),
                          SizedBox(height: 10),
                          _aboutFeatureCard(
                            icon: Icons.auto_awesome_rounded,
                            color: Color(0xFFEC4899),
                            title: 'AI ile Ödev Üretimi'.tr(),
                            desc:
                                'Branşına ve müfredata özel soruları yapay zeka üretir; önizleyip düzenleyip sınıfa gönderirsin.'
                                    .tr(),
                          ),
                          SizedBox(height: 10),
                          _aboutFeatureCard(
                            icon: Icons.insights_rounded,
                            color: Color(0xFF10B981),
                            title: 'Performans Analizi'.tr(),
                            desc:
                                'Öğrenci · ödev · soru bazında doğru/yanlış/boş, aktif-pasif süre ve AI değerlendirmesi.'
                                    .tr(),
                          ),
                          SizedBox(height: 20),
                        ],

                        // ── 1. Yapay Zeka Destekli Çözüm ─────────────────
                        _aboutSectionTitle('📷', 'Kamera ile Soru Çözümü'.tr()),
                        SizedBox(height: 12),
                        _aboutFeatureCard(
                          icon: Icons.bolt_rounded,
                          color: Color(0xFFF59E0B),
                          title: 'Hızlı Çözüm'.tr(),
                          desc:
                              'Kamerayı soruya doğrult — Gemini AI saniyeler içinde adım adım çözüm sunar.'
                                  .tr(),
                        ),
                        SizedBox(height: 10),
                        _aboutFeatureCard(
                          icon: Icons.list_alt_rounded,
                          color: Color(0xFF3B82F6),
                          title: 'Adım Adım Açıklama'.tr(),
                          desc:
                              'Her çözüm sınıf seviyene ve müfredatına özel yazılır; formüller LaTeX ile temiz görünür.'
                                  .tr(),
                        ),
                        SizedBox(height: 10),
                        _aboutFeatureCard(
                          icon: Icons.record_voice_over_rounded,
                          color: Color(0xFFEC4899),
                          title: 'Sesli Komut Modu'.tr(),
                          desc:
                              'Soruyu yazmadan, mikrofonla anlat — AI sesini metne çevirip çözer.'
                                  .tr(),
                        ),
                        SizedBox(height: 20),

                        // ── 2. Müfredat Tabanlı Eğitim ───────────────────
                        _aboutSectionTitle('🌍', 'Dünya Genelinde Müfredat'.tr()),
                        SizedBox(height: 12),
                        _aboutFeatureCard(
                          icon: Icons.public_rounded,
                          color: Color(0xFF22D3EE),
                          title: '131 Ülke, 53 Dil'.tr(),
                          desc:
                              'ABD, Çin, Hindistan, Türkiye dahil 131 ülkenin tüm sınıfları için gerçek müfredat. Uygulama 53 dilde çalışır.'
                                  .tr(),
                        ),
                        SizedBox(height: 10),
                        _aboutFeatureCard(
                          icon: Icons.menu_book_rounded,
                          color: Color(0xFF8B5CF6),
                          title: 'Ülke Özel Dersler & Konular'.tr(),
                          desc:
                              'Fransa\'da Mathématiques, Almanya\'da Mathematik, Çin\'de 数学 — her ülkenin kendi resmî müfredatı, kendi dilinde.'
                                  .tr(),
                        ),
                        SizedBox(height: 20),

                        // ── 3. Çalışma & Pekiştirme ──────────────────────
                        _aboutSectionTitle('🎯', 'Aktif Öğrenme'.tr()),
                        SizedBox(height: 12),
                        _aboutFeatureCard(
                          icon: Icons.school_rounded,
                          color: Color(0xFFF59E0B),
                          title: 'AI Özet ve Test Üretimi'.tr(),
                          desc:
                              'Her ders, her konu için anlık özet + çift doğrulamalı test soruları üretilir.'
                                  .tr(),
                        ),
                        SizedBox(height: 10),
                        _aboutFeatureCard(
                          icon: Icons.leaderboard_rounded,
                          color: Color(0xFF10B981),
                          title: 'Bilgi Ligi'.tr(),
                          desc:
                              'Şehrin, ülkende ve dünyada sıralamana bak — kendi seviyendeki öğrencilerle yarış, ders/konu bazında ölçül.'
                                  .tr(),
                        ),
                        SizedBox(height: 10),
                        // AI Koç — kişisel çalışma asistanı (Yeni!)
                        _aboutFeatureCard(
                          icon: Icons.auto_awesome_rounded,
                          color: Color(0xFF7C3AED),
                          title: 'AI Koç'.tr(),
                          desc:
                              'Geçmiş çözümlerinden, testlerinden ve özet çalışmalarından zayıf konularını tespit eder; her güne özel çalışma planı önerir.'
                                  .tr(),
                        ),
                        SizedBox(height: 10),
                        _aboutFeatureCard(
                          icon: Icons.timer_rounded,
                          color: Color(0xFF06B6D4),
                          title: 'Çalışma Planlayıcı'.tr(),
                          desc:
                              'Sınav günlerin, hedeflerin, günlük çalışma saatlerin — hepsi tek ekranda.'
                                  .tr(),
                        ),
                        SizedBox(height: 24),

                        // ── Teknoloji ────────────────────────────────────
                        _aboutSectionTitle('🧠', 'Teknoloji'.tr()),
                        SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppPalette.card(context),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Google Gemini 2.5 Flash',
                                style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.textPrimary(context),
                                  height: 1.6,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'QuAlsar, Google\'ın Gemini 2.5 Flash modeli üzerine kurulu; cevap gelmezse otomatik olarak ChatGPT, DeepSeek gibi sağlayıcılara geçer. Test/sınav sorusu üretiminde çift AI doğrulama (üretici + denetçi) ile soru kalitesi artar; her ders ve konuda müfredata uygun, güvenilir içerik üretilir.'
                                    .tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: AppPalette.textSecondary(context),
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 24),

                        // ── Bilgi satırları ──────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppPalette.card(context),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              FutureBuilder<String>(
                                future: _appVersionLine(),
                                builder: (_, snap) {
                                  return _infoRow(localeService.tr('version'),
                                      snap.data?.split('•').first.trim() ?? '1.0.0');
                                },
                              ),
                              _infoRow('Geliştirici'.tr(), 'QuAlsar Team'),
                              _infoRow('AI Modeli'.tr(), 'Gemini 2.5 Flash'),
                              _infoRow('Müfredat Kapsamı'.tr(),
                                  '131 ülke • 53 dil'),
                              _infoRow('Kuruluş'.tr(), '2026'),
                              _infoRow('İletişim'.tr(),
                                  'serhatdsme@gmail.com'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // ═══════════════════════════════════════════════════
                        //  MİSYON & DEĞERLER
                        // ═══════════════════════════════════════════════════
                        _aboutSectionTitle('🎯', 'Misyon'.tr()),
                        const SizedBox(height: 8),
                        Text(
                          'Her öğrencinin kendi seviyesinde, kendi dilinde, kendi cebinde bir özel öğretmene erişmesini sağlamak. AI\'ı eğitimde demokratikleştirmek.'
                              .tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: AppPalette.textPrimary(context),
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _aboutSectionTitle('💎', 'Değerler'.tr()),
                        const SizedBox(height: 8),
                        _valueLine('🌍', 'Erişilebilirlik'.tr(),
                            'Her dile, her seviyeye, her ülkeye'.tr()),
                        _valueLine('🛡️', 'Gizlilik'.tr(),
                            'Verilerin senin; sattığımız ürün değil'.tr()),
                        _valueLine('📚', 'Doğruluk'.tr(),
                            'Müfredata uygun, çift AI doğrulamalı içerik'.tr()),
                        _valueLine('⚡', 'Hız'.tr(),
                            'Saniyeler içinde cevap, yapay zeka destekli'.tr()),
                        const SizedBox(height: 20),
                        // ═══════════════════════════════════════════════════
                        //  WEB & SOSYAL MEDYA
                        // ═══════════════════════════════════════════════════
                        _aboutSectionTitle('🌐', 'Web ve Bağlantılar'.tr()),
                        const SizedBox(height: 10),
                        _socialLink(
                          icon: Icons.language_rounded,
                          label: 'qualsar.app',
                          color: const Color(0xFF3B82F6),
                          url: 'https://qualsar.app',
                        ),
                        const SizedBox(height: 8),
                        _socialLink(
                          icon: Icons.mail_outline_rounded,
                          label: 'serhatdsme@gmail.com',
                          color: const Color(0xFFEC4899),
                          url:
                              'mailto:serhatdsme@gmail.com?subject=QuAlsar',
                        ),
                        const SizedBox(height: 8),
                        _socialLink(
                          icon: Icons.privacy_tip_rounded,
                          label: 'Gizlilik Politikası'.tr(),
                          color: const Color(0xFF10B981),
                          url: 'https://qualsar.app/privacy',
                        ),
                        const SizedBox(height: 8),
                        _socialLink(
                          icon: Icons.description_rounded,
                          label: 'Kullanım Koşulları'.tr(),
                          color: const Color(0xFF8B5CF6),
                          url: 'https://qualsar.app/terms',
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            '© ${DateTime.now().year} QuAlsar. Tüm hakları saklıdır.'.tr(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppPalette.textSecondary(context).withValues(alpha: 0.70),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
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

  /// Değer satırı — emoji + başlık + kısa açıklama.
  Widget _valueLine(String emoji, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context))),
                Text(desc,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppPalette.textSecondary(context),
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sosyal link — tıklanınca url_launcher ile açar.
  Widget _socialLink({
    required IconData icon,
    required String label,
    required Color color,
    required String url,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            final ok = await launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            );
            if (!ok && context.mounted) {
              messenger.showSnackBar(
                SnackBar(content: Text('Link açılamadı'.tr())),
              );
            }
          } catch (_) {
            await Clipboard.setData(ClipboardData(text: url));
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text('Link panoya kopyalandı'.tr())),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary(context))),
              ),
              Icon(Icons.open_in_new_rounded, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aboutSectionTitle(String emoji, String title) {
    return Row(
      children: [
        Text(emoji, style: TextStyle(fontSize: 26)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppPalette.textPrimary(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _aboutFeatureCard({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  desc,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: AppPalette.textSecondary(context),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppPalette.textSecondary(context),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppPalette.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Kullanım Koşulları ve Gizlilik Politikası
  // ═══════════════════════════════════════════════════════════════════════════

  void _showTermsPrivacySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: BoxDecoration(
              color: AppPalette.bg(context),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // Tutma çubuğu
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.border(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // İçerik
                Expanded(
                  child: SingleChildScrollView(
                    physics: BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Tam ve GÜNCEL politikalar web'de. Aşağıdaki metin
                        //    özettir; bağlayıcı/güncel sürüm bu linktedir.
                        GestureDetector(
                          onTap: () async {
                            try {
                              await launchUrl(
                                Uri.parse('https://qualsar.app/privacy'),
                                mode: LaunchMode.externalApplication,
                              );
                            } catch (_) {}
                          },
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 18),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF3B82F6).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFF3B82F6)
                                      .withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.open_in_new_rounded,
                                    color: Color(0xFF3B82F6), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Tam ve güncel Gizlilik Politikası & Kullanım Koşulları (web)'
                                        .tr(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppPalette.textPrimary(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // ══════════════════════════════════════════════════
                        //  KULLANIM KOŞULLARI
                        // ══════════════════════════════════════════════════
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: Color(0xFF3B82F6).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              localeService.tr('terms_header'),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),

                        // Giriş
                        _termsCard(localeService.tr('terms_intro')),
                        SizedBox(height: 12),

                        // 1. Hizmet Kapsamı
                        _termsSectionTitle('1', localeService.tr('service_scope_title')),
                        SizedBox(height: 8),
                        _termsCard(localeService.tr('service_scope_body')),
                        SizedBox(height: 12),

                        // 2. Kullanım Amacı
                        _termsSectionTitle('2', localeService.tr('usage_purpose_title')),
                        SizedBox(height: 8),
                        _termsCard(localeService.tr('usage_purpose_body')),
                        SizedBox(height: 12),

                        // 3. Abonelik ve Ödemeler
                        _termsSectionTitle('3', localeService.tr('subscription_title')),
                        SizedBox(height: 8),
                        _termsCard(localeService.tr('subscription_body')),
                        SizedBox(height: 28),

                        // ══════════════════════════════════════════════════
                        //  GİZLİLİK POLİTİKASI
                        // ══════════════════════════════════════════════════
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: Color(0xFF10B981).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              localeService.tr('privacy_header'),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),

                        // Giriş
                        _termsCard(localeService.tr('privacy_intro')),
                        SizedBox(height: 12),

                        // 1. Toplanan Veriler
                        _termsSectionTitle('1', localeService.tr('data_collection_title')),
                        SizedBox(height: 8),
                        _termsCard(localeService.tr('privacy_data_types')),
                        SizedBox(height: 12),

                        // 2. Veri Paylaşımı
                        _termsSectionTitle('2', localeService.tr('data_sharing_title')),
                        SizedBox(height: 8),
                        _termsCard(localeService.tr('data_sharing_body')),
                        SizedBox(height: 12),

                        // 3. Kullanıcı Hakları
                        _termsSectionTitle('3', localeService.tr('user_rights_title')),
                        SizedBox(height: 8),
                        _termsCard(localeService.tr('user_rights_body')),
                        SizedBox(height: 24),

                        // Alt bilgi
                        Center(
                          child: Text(
                            // Telif yılı dinamik: gömülü "2026" yerine içinde
                            // bulunulan yıl gösterilir (çevirileri düzenlemeye gerek yok).
                            localeService
                                .tr('copyright_footer')
                                .replaceAll('2026', DateTime.now().year.toString()),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                        ),
                      ],
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

  Widget _termsSectionTitle(String number, String title) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Color(0xFF3B82F6).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              number,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF3B82F6),
              ),
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppPalette.textPrimary(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _termsCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          color: AppPalette.textSecondary(context),
          height: 1.7,
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    final locale = LocaleInherited.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(context),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(0xFFEF4444).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.logout_rounded,
                color: Color(0xFFEF4444),
                size: 20,
              ),
            ),
            SizedBox(width: 12),
            Text(
              locale.tr('logout'),
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppPalette.textPrimary(context),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locale.tr('logout_confirm'),
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppPalette.textSecondary(context),
              ),
            ),
            // Premium aktif uyarısı — abonelik bilgisi cihazda kalır;
            // tekrar giriş yapınca senkronize edilir.
            if (_premium.isActive) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  border: Border.all(color: const Color(0xFFFFC107)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Color(0xFFB28704)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Aktif Premium aboneliğin var. Çıkış yaptıktan sonra tekrar giriş yapınca senkronize olur. Aboneliğini iptal etmek için App Store / Play Store kullan.'
                            .tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: const Color(0xFF6F4F00),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              locale.tr('cancel'),
              style: GoogleFonts.poppins(
                color: AppPalette.textSecondary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                // FCM token önce — auth çıktıktan sonra uid null, silinemez
                await PushService.clearTokenOnLogout();
                await AuthService.signOut();
                // Çıkış sonrası onboarding'i tekrar göster — yeni kullanıcı
                // veya tekrar giriş için ilk açılış akışı (ülke + dil seç).
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove(OnboardingScreen.prefKey);
                await prefs.remove('mini_test_grade');
              } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'profile_screen'); }
              if (!mounted) return;
              _showSnack(locale.tr('logged_out'));
              _refreshPremium();
              // Tüm stack'i temizleyip Onboarding'e geç — Camera/profile
              // arkada kalmasın.
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  (r) => false,
                );
              }
            },
            child: Text(
              locale.tr('sign_out'),
              style: GoogleFonts.poppins(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Premium Banner — shimmer animasyonlu, büyük vurgulu
// ═════════════════════════════════════════════════════════════════════════════

class _PremiumBanner extends StatefulWidget {
  final VoidCallback onTap;
  const _PremiumBanner({required this.onTap});

  @override
  State<_PremiumBanner> createState() => _PremiumBannerState();
}

class _PremiumBannerState extends State<_PremiumBanner>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Yumuşak nefes alma döngüsü (~3.5sn). App background'a alınırsa
    // pil tasarrufu için durur, foreground'da tekrar başlar.
    _controller = AnimationController(
      duration: Duration(milliseconds: 3500),
      vsync: this,
    )..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      if (_controller.isAnimating) _controller.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF4C1D95), // derin mor
              Color(0xFFDB2777), // canlı pembe
              Color(0xFFF59E0B), // sıcak turuncu
            ],
            stops: [0.0, 0.55, 1.0],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Color(0xFFDB2777).withValues(alpha: 0.35),
              blurRadius: 22,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Dekoratif parlama — sağ üst
              Positioned(
                right: -30,
                top: -40,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Dekoratif parlama — sol alt
              Positioned(
                left: -20,
                bottom: -30,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.14),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Nefes alan yumuşak pulse — kartın kendi renginde (pembe/turuncu)
              AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  // 0 ↔ 1 arası sinüs benzeri yumuşak geçiş
                  final t = (_controller.value * 2 - 1).abs(); // 0→1→0
                  final intensity = 0.05 + t * 0.10; // 0.05 – 0.15 arası
                  return Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(0.6, -0.4),
                            radius: 1.1,
                            colors: [
                              Color(0xFFFFC4A0)
                                  .withValues(alpha: intensity),
                              Color(0xFFDB2777)
                                  .withValues(alpha: intensity * 0.5),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // İçerik
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // PRO rozeti + "Sınırlı teklif"
                    Row(
                      children: [
                        _proBadge(),
                        SizedBox(width: 8),
                        _limitedChip(),
                      ],
                    ),
                    SizedBox(height: 14),
                    // Büyük başlık
                    Text(
                      localeService.tr('unlimited_power_title'),
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 6),
                    // Punch subtitle
                    Text(
                      localeService.tr('unlimited_power_subtitle'),
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 18),
                    // CTA — Ücretsiz deneme vurgusu
                    Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
            color: AppPalette.card(context),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ShaderMask(
                            shaderCallback: (r) => LinearGradient(
                              colors: [
                                Color(0xFF4C1D95),
                                Color(0xFFDB2777),
                              ],
                            ).createShader(r),
                            child: Text(
                              localeService.tr('try_7days_free'),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFF4C1D95),
                            size: 17,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _proBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded,
              color: Color(0xFFFFE44D), size: 13),
          SizedBox(width: 4),
          Text(
            'PRO',
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _limitedChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Color(0xFFFFE44D).withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Color(0xFFFFE44D).withValues(alpha: 0.45),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded,
              color: Color(0xFFFFE44D), size: 13),
          SizedBox(width: 4),
          Text(
            localeService.tr('limited_offer'),
            style: GoogleFonts.poppins(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ProfileEditPage — Tam Sayfa Profil Düzenleme
// ═══════════════════════════════════════════════════════════════════════════════

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _nameCtrl = TextEditingController();
  final _statusCtrl = TextEditingController();
  String? _profileImagePath;
  String? _educationLevel;
  String _userId = '';
  String? _nameError;
  String? _statusError;
  // Debounce — kullanıcı her karakter girince cloud'a yazma yapmasın.
  Timer? _nameDebounce;
  Timer? _statusDebounce;
  static const _maxNameLen = 30;
  static const _maxStatusLen = 120;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = await loadOrCreateUserId();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = prefs.getString('profile_name') ?? '';
      _statusCtrl.text = prefs.getString('profile_status_message') ?? '';
      _profileImagePath = prefs.getString('profile_image');
      _educationLevel = prefs.getString('profile_education_level');
      _userId = id;
    });
    // Yerel boşsa cloud'dan restore — telefon değişti senaryosu.
    if (_nameCtrl.text.isEmpty &&
        _statusCtrl.text.isEmpty &&
        _profileImagePath == null) {
      unawaited(_restoreFromCloud());
    }
  }

  /// users/{uid} doc'undan displayName + statusMessage + avatarData oku.
  /// Yerel SharedPreferences'a yaz + UI'yı güncelle.
  Future<void> _restoreFromCloud() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final me = await FriendService.getUserByUid(uid);
      if (me == null || !mounted) return;
      final prefs = await SharedPreferences.getInstance();
      if (me.displayName.isNotEmpty) {
        await prefs.setString('profile_name', me.displayName);
      }
      if (me.statusMessage.isNotEmpty) {
        await prefs.setString('profile_status_message', me.statusMessage);
      }
      // Avatar — base64 data URL ise dosyaya yaz, yerel path SharedPref'e
      String? imgPath;
      if (me.avatarData.startsWith('data:image/')) {
        try {
          final commaIdx = me.avatarData.indexOf(',');
          if (commaIdx > 0) {
            final b64 = me.avatarData.substring(commaIdx + 1);
            final bytes = base64Decode(b64);
            final dir = await getApplicationDocumentsDirectory();
            final path = '${dir.path}/profile_avatar.jpg';
            await File(path).writeAsBytes(bytes);
            imgPath = path;
            await prefs.setString('profile_image', path);
          }
        } catch (e) {
          debugPrint('[Profile] avatar restore fail: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        if (me.displayName.isNotEmpty) _nameCtrl.text = me.displayName;
        if (me.statusMessage.isNotEmpty) _statusCtrl.text = me.statusMessage;
        if (imgPath != null) _profileImagePath = imgPath;
      });
    } catch (e) {
      debugPrint('[Profile] cloud restore fail: $e');
    }
  }

  String? _validateName(String name) {
    if (name.isEmpty) return null; // boş bırakmak serbest
    if (name.length < 2) {
      return localeService.tr('name_too_short');
    }
    if (name.length > _maxNameLen) {
      return localeService.tr('name_too_long');
    }
    // Sadece harf, rakam, boşluk, alt çizgi, nokta, tire. Emoji+özel kabul.
    if (RegExp(r'[<>/\\{}|]').hasMatch(name)) {
      return localeService.tr('name_invalid_chars');
    }
    return null;
  }

  String? _validateStatus(String s) {
    if (s.length > _maxStatusLen) {
      return localeService.tr('status_too_long');
    }
    return null;
  }

  Future<void> _saveName() async {
    final raw = _nameCtrl.text.trim();
    final err = _validateName(raw);
    if (mounted) setState(() => _nameError = err);
    if (err != null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name', raw);
    _nameDebounce?.cancel();
    _nameDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_syncToCloud());
    });
  }

  Future<void> _saveStatus() async {
    final raw = _statusCtrl.text.trim();
    final err = _validateStatus(raw);
    if (mounted) setState(() => _statusError = err);
    if (err != null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_status_message', raw);
    _statusDebounce?.cancel();
    _statusDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_syncToCloud());
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final savedPath = '${dir.path}/profile_avatar.jpg';
      await File(picked.path).copy(savedPath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_image', savedPath);
      if (mounted) setState(() => _profileImagePath = savedPath);
      // Cloud sync — küçük thumbnail (100x100) base64 → Firestore'a yedek.
      // Firebase Storage maliyetinden kaçınıyoruz; ~5-8KB doc'a sığar.
      unawaited(_uploadAvatarThumbnail(picked.path));
    } catch (e) {
      debugPrint('[Profile] image pick fail: $e');
    }
  }

  /// 100x100 thumbnail base64 üret → FriendService.upsertMyProfile ile
  /// users/{uid}.avatarData'ya yaz. Arkadaş kartlarında bu görünür.
  Future<void> _uploadAvatarThumbnail(String srcPath) async {
    try {
      final bytes = await File(srcPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;
      final thumb = img.copyResize(
        decoded,
        width: 100,
        height: 100,
        interpolation: img.Interpolation.average,
      );
      final jpeg = img.encodeJpg(thumb, quality: 70);
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
      // Limit kontrolü: 15KB üstü cloud'a yazma (Firestore doc 1MB cap'i koru)
      if (dataUrl.length > 15 * 1024) {
        debugPrint(
            '[Profile] thumbnail too big (${dataUrl.length}B), skip cloud');
        return;
      }
      await _syncToCloud(overrideAvatarData: dataUrl);
    } catch (e) {
      debugPrint('[Profile] thumbnail upload fail: $e');
    }
  }

  /// Tüm profil alanlarını FriendService üzerinden Firestore'a senkronize et.
  /// Arkadaş arama, davet, leaderboard görünümleri bu doc'tan beslenir.
  Future<void> _syncToCloud({String? overrideAvatarData}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      // Username (handle) — auth_service _writePublicProfile'da üretilmiş
      // olan handle'ı kullan; profile_name DISPLAYNAME'dir, ayrı.
      final savedUsername = prefs.getString('user_username_v1') ?? '';
      final username = savedUsername.isNotEmpty
          ? savedUsername
          : (email.contains('@')
              ? email.substring(0, email.indexOf('@'))
              : 'user${_userId.substring(_userId.length - 6)}');
      final displayName = _nameCtrl.text.trim();
      final status = _statusCtrl.text.trim();
      await FriendService.upsertMyProfile(
        username: username,
        displayName: displayName.isEmpty ? username : displayName,
        avatar: '👤',
        email: email,
        statusMessage: status,
        avatarData: overrideAvatarData,
      );
    } catch (e) {
      debugPrint('[Profile] cloud sync fail: $e');
    }
  }

  @override
  void dispose() {
    _saveName();
    _saveStatus();
    _nameDebounce?.cancel();
    _statusDebounce?.cancel();
    _nameCtrl.dispose();
    _statusCtrl.dispose();
    super.dispose();
  }

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
        title: Text(
          'Profil',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppPalette.textPrimary(context),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar — ortada penguen veya kullanıcı resmi
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF00E5FF).withValues(alpha: 0.25),
                            blurRadius: 22,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(3.5),
                      child: _profileImagePath != null
                          ? CircleAvatar(
                              radius: 56,
                              backgroundImage:
                                  FileImage(File(_profileImagePath!)),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: Color(0xFFEAF6FF),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '🐱',
                                style: TextStyle(fontSize: 64),
                              ),
                            ),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
            color: AppPalette.card(context),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(Icons.camera_alt_rounded,
                            color: Color(0xFF00C2D4), size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 28),

            // Sekme 1 — Kullanıcı Adı
            _LabeledCard(
              label: localeService.tr('username'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    maxLength: _maxNameLen,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textPrimary(context),
                    ),
                    decoration: InputDecoration(
                      hintText: localeService.tr('your_name_hint'),
                      hintStyle: GoogleFonts.poppins(
                        color: AppPalette.textSecondary(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                      errorText: _nameError,
                      errorStyle: GoogleFonts.poppins(
                        fontSize: 11,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                    onChanged: (_) => _saveName(),
                  ),
                  SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      if (_userId.isEmpty) return;
                      await Clipboard.setData(ClipboardData(text: _userId));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: Color(0xFF1F2937),
                          content: Text(
                            localeService.tr('id_copied'),
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Icon(Icons.badge_outlined,
                            size: 14,
                            color: Colors.grey.shade500),
                        SizedBox(width: 4),
                        Text(
                          'ID: $_userId',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.copy_rounded,
                            size: 12, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 18),

            // Sekme 2 — Durum Mesajı
            _LabeledCard(
              label: localeService.tr('status_message_label'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: _statusCtrl,
                    maxLength: _maxStatusLen,
                    maxLines: 2,
                    minLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textPrimary(context),
                    ),
                    decoration: InputDecoration(
                      hintText: localeService.tr('write_something_hint'),
                      hintStyle: GoogleFonts.poppins(
                        color: AppPalette.textSecondary(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                      errorText: _statusError,
                      errorStyle: GoogleFonts.poppins(
                        fontSize: 11,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                    onChanged: (_) => _saveStatus(),
                  ),
                  // Karakter sayacı — kullanıcı sınırı görsün
                  Text(
                    '${_statusCtrl.text.length}/$_maxStatusLen',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: AppPalette.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 18),

            // Sekme 3 — Öğrenci Bilgileri
            _LabeledCard(
              label: localeService.tr('student_info'),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentInfoPage(),
                  ),
                );
                await _load();
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _educationLevel ?? localeService.tr('select_education_level'),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _educationLevel == null
                            ? Color(0xFF9CA3AF)
                            : Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: AppPalette.textSecondary(context), size: 22),
                ],
              ),
            ),
            SizedBox(height: 28),

            // Kaydet butonu — turuncu, basınca önceki sayfaya dön
            GestureDetector(
              onTap: () async {
                await _saveName();
                await _saveStatus();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF8A3D), Color(0xFFFF6A00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFFF6A00).withValues(alpha: 0.32),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  localeService.tr('save'),
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.4,
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

// ── Etiketli kart — başlık kartın ÜSTÜNDE, içerik kartın içinde ────────────
class _LabeledCard extends StatelessWidget {
  final String label;
  final Widget child;
  final VoidCallback? onTap;

  const _LabeledCard({
    required this.label,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppPalette.textSecondary(context),
              letterSpacing: 0.2,
            ),
          ),
        ),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
            color: AppPalette.card(context),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  StudentInfoPage — Eğitim Seviyesi Seçimi
// ═══════════════════════════════════════════════════════════════════════════════

class StudentInfoPage extends StatefulWidget {
  const StudentInfoPage({super.key});

  @override
  State<StudentInfoPage> createState() => _StudentInfoPageState();
}

class _StudentInfoPageState extends State<StudentInfoPage> {
  List<String> _levels() => [
        localeService.tr('edu_primary'),
        localeService.tr('edu_middle'),
        localeService.tr('edu_high'),
        localeService.tr('edu_uni'),
        localeService.tr('edu_master'),
        localeService.tr('edu_phd'),
      ];

  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _selected = prefs.getString('profile_education_level'));
  }

  Future<void> _save(String level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_education_level', level);
    setState(() => _selected = level);
  }

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
        title: Text(
          localeService.tr('student_info'),
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppPalette.textPrimary(context),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localeService.tr('current_edu_level'),
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 8),
            Text(
              localeService.tr('edu_info_helper'),
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
            SizedBox(height: 22),
            ..._levels().map((lvl) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LevelTile(
                    label: lvl,
                    selected: _selected == lvl,
                    onTap: () => _save(lvl),
                  ),
                )),
            SizedBox(height: 18),
            GestureDetector(
              onTap: _selected == null ? null : () => Navigator.pop(context),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 180),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _selected == null
                        ? [Color(0xFFFFB380), Color(0xFFFFCFAE)]
                        : [Color(0xFFFF8A3D), Color(0xFFFF6A00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFFF6A00).withValues(
                          alpha: _selected == null ? 0.12 : 0.32),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'Tamam',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.4,
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

// ═══════════════════════════════════════════════════════════════════════════════
//  InvitePage — Arkadaşlarını Davet Et (3 kişi)
// ═══════════════════════════════════════════════════════════════════════════════

class InvitePage extends StatefulWidget {
  const InvitePage({super.key});

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  // Davet altyapısı: Firestore tabanlı ReferralService.
  ReferralStats _stats = ReferralStats.empty;
  PremiumStatusSnapshot _premium = PremiumStatusSnapshot.inactive;
  bool _loading = true;
  bool _refreshing = false;
  // Real-time listener — arkadaş kodu kullandığı an slot yeşillensin.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _referralSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _premiumSub;

  int get _invitedCount => _stats.invitedUsers.length;
  int get _maxInvites => _stats.targetCount;
  bool get _premiumUnlocked =>
      _premium.isActive && _premium.source == 'referral_complete';

  @override
  void initState() {
    super.initState();
    _load();
    _attachLiveListeners();
  }

  @override
  void dispose() {
    _referralSub?.cancel();
    _premiumSub?.cancel();
    super.dispose();
  }

  /// Firestore snapshot listener'ları kur — arkadaş davet kodunu kullandığı an
  /// `referrals/{myUid}.invitedUsers` array büyür → bu listener tetiklenir →
  /// slot anında yeşil olur, progress bar uzar.
  /// Cloud Function 3. davette 30 gün Premium yazınca `users/{myUid}/premium/state`
  /// değişir → premium listener tetiklenir → "Premium kazandın" kartı görünür.
  void _attachLiveListeners() {
    // Web simülasyonunda Firebase başlatılmaz; singleton'lara dokunma.
    if (Firebase.apps.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _referralSub = FirebaseFirestore.instance
        .collection('referrals')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final data = snap.data() ?? const <String, dynamic>{};
      final raw = (data['invitedUsers'] as List?) ?? const [];
      final invited = raw
          .whereType<Map>()
          .map((m) => InvitedUser.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      setState(() {
        _stats = ReferralStats(
          myCode: (data['code'] as String?) ?? _stats.myCode,
          invitedUsers: invited,
          targetCount: _stats.targetCount,
        );
      });
    }, onError: (e) => debugPrint('[InvitePage] referral stream: $e'));

    _premiumSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('premium')
        .doc('state')
        .snapshots()
        .listen((snap) async {
      if (!mounted || !snap.exists) return;
      final fresh = await PremiumStatus.read();
      if (!mounted) return;
      setState(() => _premium = fresh);
    }, onError: (e) => debugPrint('[InvitePage] premium stream: $e'));
  }

  Future<void> _load() async {
    setState(() => _refreshing = true);
    // Referral kodu garanti et + stats'i çek paralel
    final code = await ReferralService.getOrCreateMyCode();
    final stats = await ReferralService.myStats();
    final premium = await PremiumStatus.read();
    if (!mounted) return;
    setState(() {
      // Eğer Firestore'dan kod gelmediyse cache'deki ile UI yine de açılsın
      _stats = ReferralStats(
        myCode: stats.myCode.isNotEmpty
            ? stats.myCode
            : (code ?? ''),
        invitedUsers: stats.invitedUsers,
        targetCount: stats.targetCount,
      );
      _premium = premium;
      _loading = false;
      _refreshing = false;
    });
  }

  Future<void> _copyCode() async {
    if (_stats.myCode.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _stats.myCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Kod panoya kopyalandı'.tr()),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareCode() async {
    // Kod hazır mı? Yoksa sessizce yeniden yüklemeyi dene (snackbar yok —
    // kart üstündeki "Davet kodu yüklenemedi" hata UI'sı zaten kullanıcıya
    // gerekli geri bildirimi veriyor, çift mesaj kafa karıştırır).
    var code = _stats.myCode;
    if (code.isEmpty) {
      await _load();
      code = _stats.myCode;
      // Hala boşsa yine sessizce çık — kart kullanıcıya "Tekrar dene"
      // butonunu zaten gösteriyor.
      if (code.isEmpty) return;
    }
    // Sade mesaj — uygulama tanıtımı WhatsApp link önizleme kartının
    // og:description'ında görünür (hosting/davet.html). Burada sadece
    // hediye satırı + kod + link.
    final gift = '🎁 Sana 7 gün QuAlsar Premium hediyem var.'.tr();
    final cta = 'Davet kodum:'.tr();
    final inviteUrl = 'https://qualsar.app/i/$code';
    final msg = '$gift\n\n'
        '$cta $code\n\n'
        '$inviteUrl';

    if (!mounted) return;
    // iPad popover origin — sistem share için, async gap öncesi yakala.
    Rect? origin;
    try {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.attached) {
        origin = box.localToGlobal(Offset.zero) & box.size;
      }
    } catch (_) {}

    // Özel kanal sheet'i — sıralama: WhatsApp, Telegram, SMS, E-posta,
    // Instagram, TikTok, X, Daha fazla. Brand renkleri, sade dairesel
    // ikon, extra çerçeve yok. Sistem share'i sıralama yapamadığı için
    // bu özel sheet ile kontrol ediyoruz.
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareChannelSheet(message: msg, origin: origin),
    );
  }

  /// Kod string'ini parçalayıp "Al" hecesini kırmızı TextSpan olarak döndürür.
  /// "QuAl-XXXXXX" → [Qu, **Al** (kırmızı), -XXXXXX].
  /// "Al" geçmeyen eski/legacy formatlar tek parça döner.
  List<InlineSpan> _buildCodeSpans(String code) {
    final idx = code.indexOf('Al');
    if (idx < 0) return [TextSpan(text: code)];
    return [
      if (idx > 0) TextSpan(text: code.substring(0, idx)),
      TextSpan(
        text: 'Al',
        style: const TextStyle(color: Color(0xFFE53935)),
      ),
      if (idx + 2 < code.length) TextSpan(text: code.substring(idx + 2)),
    ];
  }

  /// Davet kodu kartı — büyük tipografi + kopya butonu.
  Widget _buildCodeCard() {
    final code = _stats.myCode;
    if (_loading) {
      return Container(
        height: 84,
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppPalette.border(context)),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (code.isEmpty) {
      // Auth yok veya Firestore erişimi başarısız. Tekrar dene CTA.
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded,
                color: const Color(0xFFEF4444), size: 28),
            const SizedBox(height: 6),
            Text(
              'Davet kodu yüklenemedi. İnternet bağlantını kontrol et.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _refreshing ? null : _load,
              icon: Icon(Icons.refresh_rounded,
                  size: 18, color: const Color(0xFF1A73E8)),
              label: Text('Tekrar dene'.tr(),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A73E8),
                    fontSize: 13,
                  )),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF6A00).withValues(alpha: 0.30),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6A00).withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6A00).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('🎟️', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SENİN DAVET KODUN'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textSecondary(context),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                // Kod render: "Qu" + "Al" (kırmızı) + "-XXXXXX". Kullanıcı
                // talebi gereği "Al" hecesi daima kırmızı görünür.
                SelectableText.rich(
                  TextSpan(
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.textPrimary(context),
                      letterSpacing: 1.5,
                    ),
                    children: _buildCodeSpans(code),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _copyCode,
            tooltip: 'Kopyala'.tr(),
            icon: const Icon(Icons.copy_rounded, size: 20),
            color: const Color(0xFFFF6A00),
          ),
        ],
      ),
    );
  }

  /// Alt sabit CTA — duruma göre Paylaş / Tamamlandı.
  Widget _buildBottomCta() {
    final isDone = _invitedCount >= _maxInvites;
    final colors = isDone
        ? const [Color(0xFF22C55E), Color(0xFF16A34A)]
        : const [Color(0xFFFF8A3D), Color(0xFFFF6A00)];
    final shadowColor =
        isDone ? const Color(0xFF22C55E) : const Color(0xFFFF6A00);
    return GestureDetector(
      onTap: isDone ? null : _shareCode,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: shadowColor.withValues(alpha: 0.32),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDone ? Icons.check_circle_rounded : Icons.share_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              isDone
                  ? 'Tamamlandı — Premium kazandın'.tr()
                  : localeService.tr('share_with_friends'),
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        title: Text(
          localeService.tr('invite_event_title'),
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppPalette.textPrimary(context),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      // Asset eksikse renkli fallback gösterelim (eski sürümde
                      // bu çağrı runtime'da exception fırlatabilirdi).
                      child: Image.asset(
                        'lib/assets/invite_hero.jpeg',
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: double.infinity,
                          height: 180,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFF9A4D),
                                Color(0xFFFF6A00),
                              ],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '🎁',
                            style: TextStyle(fontSize: 72),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
            // Başlık + alt başlık — ortalı
            Text(
              localeService.tr('invite_friends_title'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppPalette.textPrimary(context),
                height: 1.2,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Her davet ettiğin arkadaşın 7 gün Premium kazanır. 3 arkadaşın uygulamayı kodunla indirdiğinde sen 30 gün ücretsiz Premium kazanırsın.'
                  .tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
                height: 1.4,
                letterSpacing: -0.1,
              ),
            ),
            SizedBox(height: 18),

            // ══════════════════════════════════════════════════════════
            //  DAVET KODU — büyük, kopya butonu, paylaşılabilir.
            // ══════════════════════════════════════════════════════════
            _buildCodeCard(),
            SizedBox(height: 20),
            SizedBox(height: 20),

            // Davetlerim başlık — ortalı
            Text(
              '${localeService.tr('my_invites_counter')} ($_invitedCount/$_maxInvites)',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: List.generate(_maxInvites, (i) {
                final filled = i < _invitedCount;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == _maxInvites - 1 ? 0 : 10,
                    ),
                    child: _InviteSlot(index: i, filled: filled),
                  ),
                );
              }),
            ),
            SizedBox(height: 14),

            // Görev tamamlama çizgisi — %33 / %66 / %100
            LayoutBuilder(
              builder: (context, c) {
                final progress = _invitedCount / _maxInvites;
                return Stack(
                  children: [
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppPalette.border(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    AnimatedContainer(
                      duration: Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      height: 10,
                      width: c.maxWidth * progress,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF10B981),
                            Color(0xFF3B82F6),
                            Color(0xFF8B5CF6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: progress > 0
                            ? [
                                BoxShadow(
                                  color: Color(0xFF8B5CF6)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                )
                              ]
                            : [],
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: 8),
            Text(
              '%${(_invitedCount * 100 / _maxInvites).round()} ${localeService.tr('percent_completed_suffix')}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppPalette.textSecondary(context),
              ),
            ),
            SizedBox(height: 22),

            // Ödül durumu
            if (_premiumUnlocked)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8A3D)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFFF8A3D).withValues(alpha: 0.3),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text('🎉'.tr(), style: TextStyle(fontSize: 32)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localeService.tr('reward_1month_title'),
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            localeService.tr('reward_1month_body'),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFFB26B), Color(0xFFFF6A00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Color(0xFFFFE4B5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFFF6A00).withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.6),
                              width: 1.4,
                            ),
                          ),
                          child: Text('🎁',
                              style: TextStyle(fontSize: 30)),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localeService.tr('offer_1month_title'),
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  letterSpacing: 1.4,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                localeService.tr('offer_1month_body'),
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Süs — köşelere yıldız/parlaklık
                  Positioned(
                    top: -10,
                    right: 14,
                    child: Transform.rotate(
                      angle: 0.4,
                      child: Text('✨', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  Positioned(
                    bottom: -8,
                    left: 18,
                    child: Transform.rotate(
                      angle: -0.3,
                      child: Text('⭐',
                          style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: -6,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color(0xFFFFE44D),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFFFE44D)
                                .withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
                      SizedBox(height: 26),

                      // ══════════════════════════════════════════════════════
                      //  SİSTEM NASIL ÇALIŞIR?
                      // ══════════════════════════════════════════════════════
                      Text(
                        localeService.tr('how_to_join'),
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                      SizedBox(height: 12),
                      _HowItWorksStep(
                        index: 1,
                        title: localeService.tr('share_invite_code'),
                        body: localeService.tr('invite_step1_desc'),
                      ),
                      _HowItWorksStep(
                        index: 2,
                        title: localeService.tr('friends_download_app'),
                        body: localeService.tr('invite_step2_desc'),
                      ),
                      _HowItWorksStep(
                        index: 3,
                        title: localeService.tr('three_friends_complete'),
                        body: localeService.tr('invite_step3_desc'),
                      ),
                      _HowItWorksStep(
                        index: 4,
                        title: localeService.tr('reward_active_when_full'),
                        body: localeService.tr('reward_active_desc'),
                        isLast: true,
                      ),

                      SizedBox(height: 26),

                      // ══════════════════════════════════════════════════════
                      //  ÖNEMLİ NOTLAR
                      // ══════════════════════════════════════════════════════
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
            color: AppPalette.card(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppPalette.border(context),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
            color: AppPalette.card(context),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppPalette.border(context),
                                ),
                              ),
                              child: Text(
                                localeService.tr('important_notes'),
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.textPrimary(context),
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                            _NoteItem(text: localeService.tr('invite_note_1')),
                            _NoteItem(text: localeService.tr('invite_note_2')),
                            _NoteItem(text: localeService.tr('invite_note_3')),
                            _NoteItem(
                              text: localeService.tr('invite_note_4'),
                              isLast: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
          // ════════════════════════════════════════════════════════════════
          //  SABIT ALT — Paylaş butonu / "Tamamlandı" state
          //  Eski sürümde 3 davet sonrası bile aktif kalıyordu, kullanıcı
          //  boşuna paylaşırdı. Şimdi:
          //    • _invitedCount < 3  → "Arkadaşlarınla paylaş" (turuncu)
          //    • _invitedCount >= 3 → "Tamamlandı 🎉" (yeşil, devre dışı)
          // ════════════════════════════════════════════════════════════════
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: _buildBottomCta(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Arkadaş Davet Hero — görsel tam oranda + telefon ekranı dile göre ─────
class _InviteHero extends StatelessWidget {
  static const _wonTxt = <String, String>{
    'tr': 'Üyelik\nKazandınız',
    'en': 'Membership\nUnlocked',
    'es': 'Membresía\nGanada',
    'fr': 'Abonnement\nGagné',
    'de': 'Mitgliedschaft\nFreigeschaltet',
    'it': 'Abbonamento\nSbloccato',
    'pt': 'Assinatura\nDesbloqueada',
    'ru': 'Подписка\nАктивирована',
    'zh': '会员\n已激活',
    'ja': 'メンバーシップ\n獲得',
    'ko': '멤버십\n획득',
    'ar': 'تم تفعيل\nالعضوية',
    'hi': 'सदस्यता\nमिली',
    'nl': 'Lidmaatschap\nVrijgespeeld',
    'pl': 'Członkostwo\nOdblokowane',
    'sv': 'Medlemskap\nLåst Upp',
    'id': 'Keanggotaan\nTerbuka',
    'vi': 'Mở Khóa\nThành Viên',
    'el': 'Συνδρομή\nΞεκλειδώθηκε',
    'uk': 'Підписка\nРозблокована',
    'fa': 'عضویت\nباز شد',
    'ms': 'Keahlian\nDibuka',
  };

  static const _premiumTxt = <String, String>{
    'ru': 'Премиум',
    'zh': '高级',
    'ja': 'プレミアム',
    'ko': '프리미엄',
    'ar': 'مميز',
    'hi': 'प्रीमियम',
    'el': 'Πρέμιουμ',
    'uk': 'Преміум',
    'fa': 'پرمیوم',
  };

  @override
  Widget build(BuildContext context) {
    final code = LocaleInherited.of(context).localeCode;
    final wonText = _wonTxt[code] ?? _wonTxt['en']!;
    final premiumText = _premiumTxt[code] ?? 'Premium';

    return AspectRatio(
      // Görsel orijinal en/boy oranı — tam sığar, kırpılmaz
      aspectRatio: 1.6,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          // Telefon ekranı (beyaz iç alan) — görseldeki konuma oran olarak
          final screenLeft = w * 0.595;
          final screenTop = h * 0.22;
          final screenW = w * 0.205;
          final screenH = h * 0.63;

          return Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'lib/assets/Gemini_Generated_Image_iepbkmiepbkmiepb.png',
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                left: screenLeft,
                top: screenTop,
                width: screenW,
                height: screenH,
                child: Container(color: AppPalette.card(context),
                  padding: EdgeInsets.symmetric(
                    horizontal: screenW * 0.08,
                    vertical: screenH * 0.08,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.poppins(
                              fontSize: screenW * 0.19,
                              fontWeight: FontWeight.w900,
                              color: AppPalette.textPrimary(context),
                              height: 1.0,
                              letterSpacing: -0.3,
                            ),
                            children: const [
                              TextSpan(text: 'Qu'),
                              TextSpan(
                                text: 'Al',
                                style: TextStyle(color: Color(0xFFE11D48)),
                              ),
                              TextSpan(text: 'sar'),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: screenH * 0.05),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          premiumText,
                          style: GoogleFonts.poppins(
                            fontSize: screenW * 0.14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFF6A00),
                            height: 1.0,
                          ),
                        ),
                      ),
                      SizedBox(height: screenH * 0.05),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          wonText,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: screenW * 0.11,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textPrimary(context),
                            height: 1.15,
                          ),
                        ),
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
}

// ── Önemli Notlar — tek madde ─────────────────────────────────────────────
class _NoteItem extends StatelessWidget {
  final String text;
  final bool isLast;

  const _NoteItem({required this.text, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: AppPalette.textSecondary(context),
          height: 1.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _ShareChannelSheet — Davet kodu paylaşımı için sıralı kanal seçici.
//
//  Kullanıcı talebi: "önce WhatsApp, Telegram ve en çok kullanılan mesajlaşma
//  / sosyal medya hesapları çıksın". Android sistem share sheet'i sıralamayı
//  kendi belirlediği için kontrol edemeyiz; bu yüzden curated bir sheet.
//
//  Sıralama: WhatsApp · Telegram · SMS · E-posta · Instagram · TikTok · X
//            · Daha fazla (sistem share fallback)
//
//  Davranış:
//   • Text prefill destekleyen kanallar (WhatsApp/Telegram/SMS/Email/X) →
//     direkt deep link açılır, mesaj önceden dolu gelir.
//   • Prefill desteklemeyen (Instagram/TikTok) → mesaj panoya kopyalanır,
//     uygulama açılır, kullanıcıya "yapıştır" toast gösterilir.
//   • "Daha fazla" → sistem share sheet (yüklü tüm uygulamalar orijinal logolu).
// ═══════════════════════════════════════════════════════════════════════════
class _ShareChannelSheet extends StatelessWidget {
  final String message;
  final Rect? origin;
  const _ShareChannelSheet({required this.message, this.origin});

  /// Bir URI'yi platform external olarak aç. Başarısızsa snackbar.
  Future<void> _openUri(BuildContext context, Uri uri, String label) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!context.mounted) return;
      if (!ok) {
        messenger.showSnackBar(SnackBar(
          content: Text('$label açılamadı — uygulamayı yükle veya başka bir kanal seç'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[ShareChannel] $label fail: $e');
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('$label yüklü değil'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Text prefill desteklemeyen uygulamalar için: mesajı panoya kopyala +
  /// uygulamayı aç + kullanıcıya yapıştır toast'u göster.
  Future<void> _copyAndOpen(BuildContext context, Uri uri, String label) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: message));
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text('Mesaj kopyalandı — $label\'da yapıştır'.tr()),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _systemShare(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Share.share(
        message,
        subject: 'QuAlsar davet kodum',
        sharePositionOrigin: origin,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[ShareChannel] system share fail: $e');
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Sistem paylaşımı açılamadı'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final encoded = Uri.encodeComponent(message);
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.border(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Hangisiyle göndermek istersin?'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
              children: [
                _channelTile(context,
                    icon: FontAwesomeIcons.whatsapp,
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    onTap: () => _openUri(context,
                        Uri.parse('https://wa.me/?text=$encoded'), 'WhatsApp')),
                _channelTile(context,
                    icon: FontAwesomeIcons.telegram,
                    label: 'Telegram',
                    color: const Color(0xFF229ED9),
                    onTap: () => _openUri(context,
                        Uri.parse('tg://msg?text=$encoded'), 'Telegram')),
                _channelTile(context,
                    icon: Icons.sms_rounded,
                    label: 'SMS',
                    color: const Color(0xFF7C3AED),
                    onTap: () => _openUri(
                        context, Uri.parse('sms:?body=$encoded'), 'SMS')),
                _channelTile(context,
                    icon: Icons.email_rounded,
                    label: 'E-posta'.tr(),
                    color: const Color(0xFFEA4335),
                    onTap: () => _openUri(
                        context,
                        Uri.parse(
                            'mailto:?subject=QuAlsar%20davet%20kodum&body=$encoded'),
                        'E-posta'.tr())),
                _channelTile(context,
                    icon: FontAwesomeIcons.instagram,
                    label: 'Instagram',
                    gradient: const [Color(0xFFFEDA77), Color(0xFFE1306C), Color(0xFF833AB4)],
                    onTap: () => _copyAndOpen(context,
                        Uri.parse('instagram://app'), 'Instagram')),
                _channelTile(context,
                    icon: FontAwesomeIcons.tiktok,
                    label: 'TikTok',
                    color: const Color(0xFF111111),
                    onTap: () => _copyAndOpen(context,
                        Uri.parse('https://www.tiktok.com/'), 'TikTok')),
                _channelTile(context,
                    icon: FontAwesomeIcons.xTwitter,
                    label: 'X',
                    color: const Color(0xFF111111),
                    onTap: () => _openUri(
                        context,
                        Uri.parse('https://twitter.com/intent/tweet?text=$encoded'),
                        'X')),
                _channelTile(context,
                    icon: Icons.more_horiz_rounded,
                    label: 'Daha fazla'.tr(),
                    color: const Color(0xFFFF6A00),
                    onTap: () => _systemShare(context)),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _channelTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? color,
    List<Color>? gradient,
    required VoidCallback onTap,
  }) {
    final bg = gradient != null
        ? BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          )
        : BoxDecoration(shape: BoxShape.circle, color: color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: bg,
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppPalette.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Nasıl Katılırsın — tek adım satırı ────────────────────────────────────
class _HowItWorksStep extends StatelessWidget {
  final int index;
  final String title;
  final String body;
  final bool isLast;

  const _HowItWorksStep({
    required this.index,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppPalette.border(context),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF8A3D), Color(0xFFFF6A00)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFFFF6A00).withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '$index',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    body,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppPalette.textSecondary(context),
                      height: 1.45,
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

// ── Davet slotu — dolu olanlar her biri farklı renk paleti ────────────────
class _InviteSlot extends StatelessWidget {
  final int index;
  final bool filled;

  const _InviteSlot({required this.index, required this.filled});

  // Her dolu slot için aynı yeşil gradient — "her biri yeşil olsun"
  // (kullanıcı isteği). 3 davet tamamlanınca 3 yeşil tik yan yana.
  static const _greenGrad = <Color>[Color(0xFF10B981), Color(0xFF059669)];

  @override
  Widget build(BuildContext context) {
    if (!filled) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppPalette.border(context),
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.person_add_alt_1_rounded,
              color: Colors.grey.shade400,
              size: 26,
            ),
            SizedBox(height: 6),
            Text(
              '${localeService.tr('friend_slot_label')} ${index + 1}',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppPalette.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _greenGrad,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _greenGrad.first.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.verified_rounded,
            color: Colors.white,
            size: 28,
          ),
          SizedBox(height: 6),
          Text(
            localeService.tr('joined'),
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LevelTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? Color(0xFF00C2D4)
                : Colors.transparent,
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? Color(0xFF00E5FF).withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: selected ? 14 : 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary(context),
                ),
              ),
            ),
            AnimatedContainer(
              duration: Duration(milliseconds: 180),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: selected
                    ? LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                      )
                    : null,
                color: selected ? null : Color(0xFFE5E7EB),
              ),
              child: selected
                  ? Icon(Icons.check_rounded,
                      color: Colors.white, size: 18)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Premium Aktif Kartı — kullanıcı zaten premium ise gösterilir.
//  "Sınırsız Güce Geç" banner'ı yerine geçer. Kaynağa göre farklı badge
//  gösterir: abonelik / davet ödülü / test.
// ═══════════════════════════════════════════════════════════════════════════════
class _PremiumActiveCard extends StatelessWidget {
  final PremiumStatusSnapshot snapshot;
  const _PremiumActiveCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final source = snapshot.source ?? '';
    final isReferral = snapshot.isFromReferral;
    final isSub = snapshot.isFromSubscription;
    final days = snapshot.daysRemaining;
    String sourceLabel;
    IconData sourceIcon;
    if (isSub) {
      sourceLabel = 'Abonelik'.tr();
      sourceIcon = Icons.workspace_premium_rounded;
    } else if (source == 'referral_complete') {
      sourceLabel = 'Davet ödülü'.tr();
      sourceIcon = Icons.card_giftcard_rounded;
    } else if (source == 'referral_redeem') {
      sourceLabel = 'Hoşgeldin ödülü'.tr();
      sourceIcon = Icons.celebration_rounded;
    } else {
      sourceLabel = 'Premium'.tr();
      sourceIcon = Icons.workspace_premium_rounded;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1F2937),
            Color(0xFF6B21F2),
            Color(0xFFDB2777),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF6B21F2).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(sourceIcon, color: Colors.white, size: 26),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'PREMIUM',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.amber.shade200,
                        letterSpacing: 1.4,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        sourceLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  isReferral
                      ? 'Davet ödülün aktif — keyfini çıkar'.tr()
                      : 'Tüm özellikler aktif'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  days > 0
                      ? '${'Kalan'.tr()}: $days ${'gün'.tr()}'
                      : 'Yakında sona eriyor'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.92),
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

// ═══════════════════════════════════════════════════════════════════════════════
//  Uygulama Ayarları Sheet — uygulama açılış davranışı + diğer tercihler
//  SharedPreferences key: `startup_screen` → 'camera' (varsayılan) | 'library'
// ═══════════════════════════════════════════════════════════════════════════════
class _AppSettingsSheet extends StatefulWidget {
  const _AppSettingsSheet();

  @override
  State<_AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<_AppSettingsSheet> {
  String _startupScreen = 'library';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _startupScreen = prefs.getString('startup_screen') ?? 'library';
      _loaded = true;
    });
  }

  Future<void> _setStartupScreen(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('startup_screen', value);
    if (!mounted) return;
    setState(() => _startupScreen = value);
    // Cloud sync — diğer cihazda da geçerli olsun
    unawaited(PreferencesSyncService.syncFromLocal());
  }

  /// Cache temizleme — geçici resim/ses dosyaları, runtime translator cache,
  /// soru havuzu local index. SharedPreferences ve kritik veriler korunur.
  Future<void> _clearCache() async {
    final messenger = ScaffoldMessenger.of(context);
    // Onay dialogu
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Önbelleği temizle?'.tr()),
        content: Text(
          'Geçici dosyalar silinir. Çözümlerin, özetlerin ve profil bilgilerin SİLİNMEZ.'
              .tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            child: Text('Temizle'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    int sizeMb = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        // Toplam boyut hesabı (info amaçlı, fail olursa da temizle)
        try {
          int total = 0;
          await for (final ent in tempDir.list(recursive: true)) {
            if (ent is File) {
              try {
                total += await ent.length();
              } catch (_) {}
            }
          }
          sizeMb = (total / (1024 * 1024)).round();
        } catch (_) {}
        // İçeriği temizle (klasörü silme, sadece içini)
        await for (final ent in tempDir.list()) {
          try {
            await ent.delete(recursive: true);
          } catch (_) {/* tek dosya başarısızsa sonrakine geç */}
        }
      }
      // Çözüm orphan resimlerini temizle (cleanOrphans çağrısı)
      try {
        await SolutionsStorage.cleanOrphans();
      } catch (_) {}
    } catch (e) {
      debugPrint('[Profile] cache clear fail: $e');
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(sizeMb > 0
          ? '$sizeMb MB önbellek temizlendi'
          : 'Önbellek temizlendi'.tr()),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Parmak izi / Face ID açılırken: cihazda biyometrik kayıtlı mı kontrol et,
  /// kullanıcıdan canlı doğrulama iste. Başarılıysa setting ON yapılır;
  /// cihazda biyometrik yoksa kullanıcı sistem ayarlarına yönlendirilir.
  Future<void> _enableBiometric() async {
    final s = AppSettingsService.instance;
    final messenger = ScaffoldMessenger.of(context);
    final auth = LocalAuthentication();
    try {
      final canCheck = await auth.canCheckBiometrics;
      final supported = await auth.isDeviceSupported();
      if (!canCheck || !supported) {
        messenger.showSnackBar(SnackBar(
          content: Text(
              'Bu cihaz biyometrik doğrulamayı desteklemiyor.'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      final available = await auth.getAvailableBiometrics();
      if (available.isEmpty) {
        // Cihaz destekliyor ama kullanıcı parmak izi/Face ID kaydetmemiş.
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (dCtx) => AlertDialog(
            backgroundColor: AppPalette.card(dCtx),
            title: Text('Parmak izi kayıtlı değil'.tr()),
            content: Text(
              'Bu özelliği kullanmak için cihazının ayarlarından parmak izi veya yüz tanıma eklemen gerekir.'
                  .tr(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(false),
                child: Text('İptal'.tr()),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dCtx).pop(true),
                child: Text('Ayarları aç'.tr()),
              ),
            ],
          ),
        );
        if (go == true) {
          await ph.openAppSettings();
        }
        return;
      }
      final ok = await auth.authenticate(
        localizedReason:
            'Parmak izi / Face ID ile uygulamayı kilitlemeyi etkinleştir.'
                .tr(),
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (!mounted) return;
      if (ok) {
        await s.setBiometric(true);
        messenger.showSnackBar(SnackBar(
          content: Text('Biyometrik doğrulama aktif'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text('Biyometrik doğrulama başarısız'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('[Profile] biometric enable fail: $e');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Biyometrik doğrulama açılamadı'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettingsService.instance;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => AnimatedBuilder(
        animation: s,
        builder: (ctx, _) => Container(
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: !_loaded
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              : ListView(
                  controller: sc,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppPalette.border(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Uygulamayı Kişiselleştir'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ═══ 🎯 Çalışma ─────────────────────────────────
                    // Başlangıç ekranı (Kamera/Kütüphanem) öğrenciye özgü —
                    // öğretmen hep öğretmen paneline açılır, gizlenir.
                    if (AccountService.instance.isStudent) ...[
                      _sectionTitle('🎯', 'Çalışma'.tr(),
                          const Color(0xFFFF6A00)),
                      _StartupOptionRow(
                        emoji: '📷',
                        title: 'Kamera ekranı'.tr(),
                        subtitle: 'Soru tarama doğrudan açılır'.tr(),
                        selected: _startupScreen == 'camera',
                        color: const Color(0xFFFF6A00),
                        onTap: () => _setStartupScreen('camera'),
                      ),
                      const SizedBox(height: 8),
                      _StartupOptionRow(
                        emoji: '📚',
                        title: 'Kütüphanem ekranı'.tr(),
                        subtitle: 'Dersler, testler, özetler açılır'.tr(),
                        selected: _startupScreen == 'library',
                        color: const Color(0xFF8B5CF6),
                        onTap: () => _setStartupScreen('library'),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // ═══ 🔇 Sessiz Saatler ──────────────────────────
                    _sectionTitle('🔇', 'Sessiz Saatler'.tr(),
                        const Color(0xFF6366F1)),
                    _toggleRow(
                      icon: Icons.do_not_disturb_on_rounded,
                      title: 'Sessiz saatleri aç'.tr(),
                      subtitle:
                          'Belirlediğin aralıkta hiç bildirim gelmez.'.tr(),
                      color: const Color(0xFF6366F1),
                      value: s.quietEnabled,
                      onChanged: (v) => s.setQuiet(v,
                          startMin: s.quietStartMin,
                          endMin: s.quietEndMin),
                    ),
                    if (s.quietEnabled) ...[
                      const SizedBox(height: 8),
                      _timeRangePicker(
                        startMin: s.quietStartMin,
                        endMin: s.quietEndMin,
                        onChanged: (start, end) => s.setQuiet(true,
                            startMin: start, endMin: end),
                      ),
                    ],
                    const SizedBox(height: 18),

                    // ═══ 🌙 Otomatik Karanlık Mod ───────────────────
                    _sectionTitle('🌙', 'Otomatik Karanlık Mod'.tr(),
                        const Color(0xFF8B5CF6)),
                    _toggleRow(
                      icon: Icons.brightness_4_rounded,
                      title: 'Saat tabanlı karanlık'.tr(),
                      subtitle:
                          'Gece otomatik karanlık, sabah aydınlık moda geçer.'
                              .tr(),
                      color: const Color(0xFF8B5CF6),
                      value: s.autoDarkEnabled,
                      onChanged: (v) => s.setAutoDark(v,
                          startMin: s.autoDarkStartMin,
                          endMin: s.autoDarkEndMin),
                    ),
                    if (s.autoDarkEnabled) ...[
                      const SizedBox(height: 8),
                      _timeRangePicker(
                        startMin: s.autoDarkStartMin,
                        endMin: s.autoDarkEndMin,
                        startLabel: 'Karanlık başlangıç'.tr(),
                        endLabel: 'Aydınlık başlangıç'.tr(),
                        onChanged: (start, end) => s.setAutoDark(true,
                            startMin: start, endMin: end),
                      ),
                    ],
                    const SizedBox(height: 18),

                    // ═══ 🔊 Ses & Titreşim ─────────────────────────
                    // İkon chip'ine dokununca efekt anında önizlenir; toggle
                    // açılınca da bir kez çalar — kullanıcı çalıştığını duyar.
                    _sectionTitle('🔊', 'Ses ve Titreşim'.tr(),
                        const Color(0xFF06B6D4)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'İpucu: Soldaki renkli simgeye dokunarak sesi/titreşimi test edebilirsin.'
                            .tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          color: AppPalette.textSecondary(context)
                              .withValues(alpha: 0.8),
                          height: 1.3,
                        ),
                      ),
                    ),
                    _toggleRow(
                      icon: Icons.touch_app_rounded,
                      title: 'Buton tıklama sesi'.tr(),
                      subtitle: 'Dokun ve dinle.'.tr(),
                      color: const Color(0xFF3B82F6),
                      value: s.clickSound,
                      onPreview: s.previewClick,
                      onChanged: (v) {
                        s.setClickSound(v);
                        if (v) s.previewClick();
                      },
                    ),
                    _toggleRow(
                      icon: Icons.celebration_rounded,
                      title: 'Başarı sesi'.tr(),
                      subtitle: 'Test tamamlandığında çalar — dokun, dinle.'
                          .tr(),
                      color: const Color(0xFF10B981),
                      value: s.successSound,
                      onPreview: s.previewSuccess,
                      onChanged: (v) {
                        s.setSuccessSound(v);
                        if (v) s.previewSuccess();
                      },
                    ),
                    _toggleRow(
                      icon: Icons.error_outline_rounded,
                      title: 'Hata sesi'.tr(),
                      subtitle: 'Yanlış cevapta çalar — dokun, dinle.'.tr(),
                      color: const Color(0xFFEF4444),
                      value: s.errorSound,
                      onPreview: s.previewError,
                      onChanged: (v) {
                        s.setErrorSound(v);
                        if (v) s.previewError();
                      },
                    ),
                    _toggleRow(
                      icon: Icons.vibration_rounded,
                      title: 'Titreşim (haptic)'.tr(),
                      subtitle: 'Dokun ve hisset.'.tr(),
                      color: const Color(0xFFF59E0B),
                      value: s.haptic,
                      onPreview: s.previewHaptic,
                      onChanged: (v) {
                        s.setHaptic(v);
                        if (v) s.previewHaptic();
                      },
                    ),
                    _toggleRow(
                      icon: Icons.headset_off_rounded,
                      title: 'Test sırasında sessiz'.tr(),
                      subtitle:
                          'Sınav simülasyonu için ses/titreşim kapanır.'.tr(),
                      color: const Color(0xFF64748B),
                      value: s.testSilent,
                      onChanged: s.setTestSilent,
                    ),
                    const SizedBox(height: 18),

                    // ═══ 🔐 Uygulama Kilidi ────────────────────────
                    _sectionTitle('🔐', 'Uygulama Kilidi'.tr(),
                        const Color(0xFF14B8A6)),
                    _toggleRow(
                      icon: Icons.lock_rounded,
                      title: 'Uygulama kilidini aç'.tr(),
                      subtitle: s.hasAppLockPin
                          ? 'PIN aktif. Devre dışı bırakmak için kapat.'.tr()
                          : 'PIN belirleyerek uygulamayı kilitle.'.tr(),
                      color: const Color(0xFF14B8A6),
                      value: s.appLockEnabled,
                      onChanged: (v) async {
                        if (v) {
                          await _setupAppLockPin();
                        } else {
                          await s.clearAppLock();
                        }
                      },
                    ),
                    if (s.appLockEnabled && s.hasAppLockPin) ...[
                      _toggleRow(
                        icon: Icons.fingerprint_rounded,
                        title: 'Parmak izi / Face ID'.tr(),
                        subtitle:
                            'PIN yerine biyometrik ile aç.'.tr(),
                        color: const Color(0xFF06B6D4),
                        value: s.appLockBiometric,
                        onChanged: (v) async {
                          if (v) {
                            await _enableBiometric();
                          } else {
                            await s.setBiometric(false);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 18),

                    // ═══ 🎯 Kişiselleştirme Verisi ─────────────────
                    _sectionTitle('🎯', 'Kişiselleştirme'.tr(),
                        const Color(0xFFA855F7)),
                    _toggleRow(
                      icon: Icons.auto_awesome_rounded,
                      title: 'AI Koç önerileri'.tr(),
                      subtitle:
                          'Geçmişine göre günlük plan üret. Kapatırsan veri toplanmaz.'
                              .tr(),
                      color: const Color(0xFFA855F7),
                      value: s.aiCoachData,
                      onChanged: s.setAiCoachData,
                    ),
                    _toggleRow(
                      icon: Icons.groups_rounded,
                      title: 'Topluluk önerileri'.tr(),
                      subtitle:
                          'Diğer öğrencilerin özet/test havuzunu kullan.'.tr(),
                      color: const Color(0xFF22D3EE),
                      value: s.communityData,
                      onChanged: s.setCommunityData,
                    ),
                    const SizedBox(height: 18),

                    // ═══ 📱 Yönlendirme ─────────────────────────────
                    _sectionTitle('📱', 'Yönlendirme'.tr(),
                        const Color(0xFF3B82F6)),
                    _segmentedRow(
                      icon: Icons.screen_rotation_rounded,
                      label: 'Ekran yönlendirme'.tr(),
                      color: const Color(0xFF3B82F6),
                      options: const [
                        ('portrait', 'Sadece dikey'),
                        ('system', 'Sistem'),
                      ],
                      value: s.orientationMode,
                      onChanged: (v) => s.setOrientationMode(v),
                    ),
                    const SizedBox(height: 18),

                    // ═══ 🗑️ Önbellek ───────────────────────────────
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _clearCache,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.30),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Text('🗑️',
                                  style: TextStyle(fontSize: 22)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Önbelleği Temizle'.tr(),
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFFEF4444),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Geçici dosyalar — çözümlerin ve özetlerin korunur.'
                                          .tr(),
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: AppPalette.textSecondary(
                                            context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: Color(0xFFEF4444), size: 22),
                            ],
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

  // ── UI helpers ────────────────────────────────────────────────────────────
  Widget _sectionTitle(String emoji, String text, [Color? accent]) {
    final c = accent ?? const Color(0xFF8B5CF6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: AppPalette.textPrimary(context),
                letterSpacing: 0.3,
              )),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color color = const Color(0xFF3B82F6),
    VoidCallback? onPreview,
  }) {
    final chip = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: value ? 0.20 : 0.10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon,
          size: 20,
          color: value ? color : color.withValues(alpha: 0.6)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Önizleme varsa ikon chip'ine dokunulabilir (sesi/titreşimi test et).
          if (onPreview != null)
            GestureDetector(onTap: onPreview, child: chip)
          else
            chip,
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimary(context),
                    )),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppPalette.textSecondary(context),
                          height: 1.35,
                        )),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: color,
          ),
        ],
      ),
    );
  }

  Widget _segmentedRow({
    required IconData icon,
    required String label,
    required List<(String, String)> options,
    required String value,
    required ValueChanged<String> onChanged,
    Color color = const Color(0xFF3B82F6),
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 9),
              Text(label,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(context),
                  )),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppPalette.cardMuted(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                for (final opt in options)
                  Expanded(
                    child: InkWell(
                      onTap: () => onChanged(opt.$1),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: value == opt.$1
                              ? color
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          opt.$2.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: value == opt.$1
                                ? Colors.white
                                : AppPalette.textPrimary(context),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeRangePicker({
    required int startMin,
    required int endMin,
    String? startLabel,
    String? endLabel,
    required void Function(int start, int end) onChanged,
  }) {
    String fmt(int m) {
      final h = (m ~/ 60).toString().padLeft(2, '0');
      final mm = (m % 60).toString().padLeft(2, '0');
      return '$h:$mm';
    }

    Future<void> pick(bool isStart) async {
      final cur = isStart ? startMin : endMin;
      final res = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
        helpText: isStart
            ? (startLabel ?? 'Başlangıç saati'.tr())
            : (endLabel ?? 'Bitiş saati'.tr()),
      );
      if (res == null) return;
      final mins = res.hour * 60 + res.minute;
      onChanged(isStart ? mins : startMin, isStart ? endMin : mins);
    }

    return Padding(
      padding: const EdgeInsets.only(left: 28, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => pick(true),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppPalette.cardMuted(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 14,
                        color: AppPalette.textSecondary(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${startLabel ?? "Başlangıç".tr()}: ${fmt(startMin)}',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => pick(false),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppPalette.cardMuted(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 14,
                        color: AppPalette.textSecondary(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${endLabel ?? "Bitiş".tr()}: ${fmt(endMin)}',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.textPrimary(context),
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
    );
  }

  /// PIN belirleme akışı — 2 adım: önce gir + tekrar. Eşleşirse kaydet.
  Future<void> _setupAppLockPin() async {
    final s = AppSettingsService.instance;
    final firstCtrl = TextEditingController();
    final secondCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          String? err;
          return AlertDialog(
            title: Text('PIN belirle'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('4-6 haneli rakam. Açılışta isteyeceğiz.'.tr(),
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                TextField(
                  controller: firstCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'PIN'.tr(),
                    counterText: '',
                  ),
                ),
                TextField(
                  controller: secondCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'PIN (tekrar)'.tr(),
                    counterText: '',
                    errorText: err,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('İptal'.tr()),
              ),
              TextButton(
                onPressed: () async {
                  final a = firstCtrl.text.trim();
                  final b = secondCtrl.text.trim();
                  if (a.length < 4 || a.length > 6 ||
                      !RegExp(r'^\d+$').hasMatch(a)) {
                    setSt(() => err = '4-6 haneli rakam gir.'.tr());
                    return;
                  }
                  if (a != b) {
                    setSt(() => err = 'PIN\'ler eşleşmiyor.'.tr());
                    return;
                  }
                  try {
                    await s.setAppLockPin(a);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    setSt(() => err = e.toString());
                  }
                },
                child: Text('Kaydet'.tr()),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Uygulama kilidi aktif.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

/// Uygulama açılış seçeneği satırı — sol: emoji + başlık/altyazı,
/// sağ: radio benzeri seçim göstergesi. Tüm satır tıklanabilir.
class _StartupOptionRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _StartupOptionRow({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.10)
              : AppPalette.cardMuted(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.65)
                : AppPalette.border(context),
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: selected ? 0.20 : 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary(context))),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: AppPalette.textSecondary(context))),
              ],
            ),
          ),
          // Radio benzeri seçim göstergesi (sağ)
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? color
                    : AppPalette.border(context),
                width: 2,
              ),
              color: selected ? color : Colors.transparent,
            ),
            child: selected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : null,
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Bildirim Ayarları Sheet — renkli ikonlu, bölümlere ayrılmış 9 kategori.
//
//  Tercihler PreferencesSyncService üzerinden saklanır (notif_<key>) ve
//  buluta senkronlanır → kullanıcı yeni cihazda ayarlarını bulur.
// ═══════════════════════════════════════════════════════════════════════════════

/// Bildirim ayarları sheet'ini açar. Hem profil ekranı hem de ayarlar
/// çekmecesi (settings_drawer) aynı kanonik UI'yı kullanır.
void showNotificationSettingsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NotificationsSettingsSheet(),
  );
}

/// Tek bir bildirim kategorisinin sunum verisi.
class _NotifCat {
  final String key;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _NotifCat(
      this.key, this.icon, this.color, this.title, this.subtitle);
}

/// Bir başlık altında gruplanmış kategoriler.
class _NotifGroup {
  final String title;
  final List<_NotifCat> items;
  const _NotifGroup(this.title, this.items);
}

class _NotificationsSettingsSheet extends StatefulWidget {
  @override
  State<_NotificationsSettingsSheet> createState() =>
      _NotificationsSettingsSheetState();
}

class _NotificationsSettingsSheetState
    extends State<_NotificationsSettingsSheet> {
  Map<String, bool> _prefs = {};
  bool _loading = true;

  // Bölüm + kategori tanımları (renkli ikonlar).
  static const List<_NotifGroup> _groups = [
    _NotifGroup('Sosyal', [
      _NotifCat('friend_request', Icons.group_rounded, Color(0xFF8B5CF6),
          'Arkadaşlık istekleri', 'Yeni arkadaşlık isteği ve kabulleri.'),
      _NotifCat('duello_invite', Icons.bolt_rounded, Color(0xFFEF4444),
          'Düello davetleri', '1v1 yarışmaya davet edildiğinde haber ver.'),
      _NotifCat('league_update', Icons.leaderboard_rounded, Color(0xFF3B82F6),
          'Sıralama & Bilgi Ligi', 'Sıralaman değiştiğinde ve yarışmalarda.'),
    ]),
    _NotifGroup('Çalışma', [
      _NotifCat('study_reminder', Icons.menu_book_rounded, Color(0xFF10B981),
          'Çalışma hatırlatıcıları', 'Günlük hedef ve çalışma planı uyarıları.'),
      _NotifCat('streak_alert', Icons.local_fire_department_rounded,
          Color(0xFFF97316), 'Seri (streak) uyarıları',
          'Çalışma serini kaçırmaman için hatırlatma.'),
      _NotifCat('exam_countdown', Icons.event_available_rounded,
          Color(0xFF06B6D4), 'Sınav geri sayımı',
          'Yaklaşan sınavlar için geri sayım bildirimi.'),
      _NotifCat('achievement', Icons.emoji_events_rounded, Color(0xFFFBBF24),
          'Başarı & rozetler', 'Yeni rozet ve başarı kazandığında.'),
    ]),
    _NotifGroup('Diğer', [
      _NotifCat('premium_offer', Icons.local_offer_rounded, Color(0xFFEC4899),
          'Premium teklifler', 'Sınırlı süreli indirim ve kampanyalar.'),
      _NotifCat('newsletter', Icons.mail_outline_rounded, Color(0xFF64748B),
          'Bülten & haberler', 'Yeni özellikler ve uygulama haberleri.'),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await PreferencesSyncService.readNotificationPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _loading = false;
    });
  }

  bool _val(String key) => _prefs[key] ?? true;
  bool get _master => _val('master');

  Future<void> _save(String key, bool v) async {
    setState(() => _prefs[key] = v);
    // PreferencesSyncService canonical yol — notif_<key> + cloud sync.
    await PreferencesSyncService.setNotificationPref(key, v);
  }

  /// Test bildirim — kullanıcı ayarlarını değiştirdikten sonra çalıştığını
  /// görsün. PushService.showLocal → flutter_local_notifications.
  /// Android 13+ runtime permission gerekirse iste.
  Future<void> _sendTestNotification() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // iOS + Android izin akışı — eski cihazda izin yoksa burada iste
      final settings =
          await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!granted) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
          content: Text(
              'Bildirim izni verilmedi. Sistem ayarlarından izin ver.'.tr()),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Ayarlar'.tr(),
            onPressed: () {
              ph.openAppSettings();
            },
          ),
        ));
        return;
      }
      await PushService.showLocal(
        title: '🔔 Test bildirimi',
        body:
            'Tebrikler! Bildirimler düzgün çalışıyor. Bu mesajı sistem tepsisinde görmen lazım.',
        id: 0xFA999,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Test bildirimi gönderildi'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Test başarısız: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.border(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF22D3EE), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.notifications_active_rounded,
                      color: Colors.white, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Bildirim Ayarları'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Expanded(
                child: ListView(
                  controller: sc,
                  children: [
                    _masterCard(),
                    const SizedBox(height: 10),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _master ? 1.0 : 0.45,
                      child: IgnorePointer(
                        ignoring: !_master,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final g in _groups) ...[
                              _groupHeader(g.title),
                              ...g.items.map(_catRow),
                              const SizedBox(height: 6),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _testButton(),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Bazı bildirimler cihazının sistem ayarlarına da bağlıdır.'
                            .tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppPalette.textSecondary(context)
                              .withValues(alpha: 0.7),
                          height: 1.4,
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

  /// Üstteki büyük "Tüm bildirimler" ana anahtarı (gradient kart).
  Widget _masterCard() {
    final on = _master;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: on
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x3322D3EE), Color(0x338B5CF6)],
              )
            : null,
        color: on ? null : AppPalette.cardMuted(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: on
              ? const Color(0xFF22D3EE).withValues(alpha: 0.45)
              : AppPalette.border(context),
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: on ? 0.16 : 0.06),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              on
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: on ? const Color(0xFF22D3EE) : AppPalette.textSecondary(context),
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tüm bildirimler'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  on
                      ? 'Bildirimler açık — türleri aşağıdan ayarla.'.tr()
                      : 'Kapalı — hiçbir bildirim almazsın.'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: AppPalette.textSecondary(context),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: on,
            activeThumbColor: const Color(0xFF22D3EE),
            onChanged: (v) => _save('master', v),
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        title.tr().toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppPalette.textSecondary(context),
        ),
      ),
    );
  }

  /// Renkli ikonlu kategori satırı.
  Widget _catRow(_NotifCat c) {
    final on = _val(c.key);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: on
            ? c.color.withValues(alpha: 0.08)
            : AppPalette.cardMuted(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: on
              ? c.color.withValues(alpha: 0.28)
              : AppPalette.border(context),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.color.withValues(alpha: on ? 0.20 : 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(c.icon,
                color: on ? c.color : c.color.withValues(alpha: 0.55),
                size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.title.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  c.subtitle.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppPalette.textSecondary(context),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Switch.adaptive(
            value: on,
            activeThumbColor: c.color,
            onChanged: (v) => _save(c.key, v),
          ),
        ],
      ),
    );
  }

  /// Test bildirim butonu — kullanıcı bildirimlerin çalıştığını görür.
  Widget _testButton() {
    const accent = Color(0xFF1A73E8);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _sendTestNotification,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: accent.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.send_rounded,
                    color: accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Test bildirimi gönder'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: accent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}



// ═══════════════════════════════════════════════════════════════════════════════
//  _CenteredLicensesScreen — Açık Kaynak Lisansları (tüm metinler ortalı)
//
//  Flutter'ın varsayılan showLicensePage()'i sol hizalı. Burada
//  LicenseRegistry.licenses stream'ini doğrudan okuyup tüm metinleri
//  ortalanmış halde gösteriyoruz.
// ═══════════════════════════════════════════════════════════════════════════════

class _CenteredLicensesScreen extends StatefulWidget {
  const _CenteredLicensesScreen();

  @override
  State<_CenteredLicensesScreen> createState() => _CenteredLicensesScreenState();
}

class _CenteredLicensesScreenState extends State<_CenteredLicensesScreen> {
  final List<LicenseEntry> _licenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLicenses();
  }

  Future<void> _loadLicenses() async {
    await for (final license in LicenseRegistry.licenses) {
      if (!mounted) return;
      _licenses.add(license);
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Açık Kaynak Lisansları'.tr(),
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppPalette.textPrimary(context),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded,
              size: 18, color: AppPalette.textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: AppPalette.textPrimary(context),
              ),
            )
          : SafeArea(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // Üst başlık — QuAlsar bilgisi
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppPalette.card(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'QuAlsar',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppPalette.textPrimary(context),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '© ${DateTime.now().year} QuAlsar. Tüm hakları saklıdır.'.tr(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: AppPalette.textSecondary(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Bu uygulama aşağıdaki açık kaynak paketleri ve içerikleri kullanır:'
                              .tr(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppPalette.textSecondary(context),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Her lisans — kart. Paket adları Wrap ile satır sığdırma,
                  // lisans metni softWrap + word-break tolerant, indent kaldırıldı
                  // (ortalı düzende indent metni ekrandan dışarı itiyordu).
                  for (int i = 0; i < _licenses.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                        decoration: BoxDecoration(
                          color: AppPalette.card(context),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Paket adları — Wrap ile uzun isimler alt satıra
                            // geçsin (eskiden join('·') tek satırda taşıyordu).
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final pkg in _licenses[i].packages)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppPalette.cardMuted(context),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      pkg,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color:
                                            AppPalette.textPrimary(context),
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Lisans metni — softWrap default, indent yok
                            // (ortalı düzende sol padding metni ekrandan
                            // dışarı taşırıyordu). Uzun URL/karakterler için
                            // SelectableText ile kullanıcı kopyalayabilir.
                            for (final p in _licenses[i].paragraphs) ...[
                              SelectableText(
                                p.text,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: AppPalette.textSecondary(context),
                                  height: 1.55,
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
