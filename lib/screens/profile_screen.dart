import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/locale_service.dart';
import '../main.dart' show themeService;
import 'premium_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadProfile();
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

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512);
    if (picked == null) return;

    // Kalıcı dizine kopyala
    final dir = await getApplicationDocumentsDirectory();
    final savedPath = '${dir.path}/profile_avatar.jpg';
    await File(picked.path).copy(savedPath);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_image', savedPath);
    if (mounted) setState(() => _profileImagePath = savedPath);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _membershipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = LocaleInherited.of(context);
    final tr = locale.tr;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 20),

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
                            builder: (_) => const ProfileEditPage(),
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
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF00E5FF),
                                      Color(0xFF6B21F2)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF)
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
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
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
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.12),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: const Color(0xFF00E5FF)
                                        .withValues(alpha: 0.4),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
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
                    const SizedBox(height: 8),
                    // İsim — controller'dan okur, boşsa placeholder
                    Text(
                      _nameCtrl.text.isEmpty ? tr('username') : _nameCtrl.text,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF333333),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Premium'a Yükselt — animasyonlu shimmer + büyük vurgulu
                    _PremiumBanner(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PremiumScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ═════════════════════════════════════════════════════════════
              //  2. Davet
              // ═════════════════════════════════════════════════════════════
              _buildSectionTitle('DAVET'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InvitePage(),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9A4D), Color(0xFFFF6A00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFFFFD9B8),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6A00).withValues(alpha: 0.28),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: -6,
                          right: -6,
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
                              child: const Text('🎁',
                                  style: TextStyle(fontSize: 26)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Arkadaşlarını Davet Et',
                                    style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'İkiniz de premium üyelik kazanın, her şeye sınırsız erişin.',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
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

              const SizedBox(height: 24),

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
              const SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '🌗',
                title: tr('appearance'),
                trailing: _buildCurrentThemeChip(locale),
                onTap: () => _showThemeBottomSheet(context),
              ),

              const SizedBox(height: 24),

              // ═════════════════════════════════════════════════════════════
              //  4. Destek ve İletişim
              // ═════════════════════════════════════════════════════════════
              _buildSectionTitle(tr('support_contact')),
              _buildOvalMenuItem(
                emoji: '⭐',
                title: tr('send_feedback'),
                onTap: () => _showFeedbackBottomSheet(context),
              ),
              const SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '✉️',
                title: tr('contact_us'),
                onTap: () => _showContactBottomSheet(context),
              ),

              const SizedBox(height: 24),

              // ═════════════════════════════════════════════════════════════
              //  4. Bilgi
              // ═════════════════════════════════════════════════════════════
              _buildSectionTitle(tr('information')),
              _buildOvalMenuItem(
                emoji: 'ℹ️',
                title: tr('about_us'),
                onTap: () => _showAboutDialog(),
              ),
              const SizedBox(height: 10),
              _buildOvalMenuItem(
                emoji: '📄',
                title: tr('terms_privacy'),
                onTap: () => _showTermsPrivacySheet(context),
              ),

              const SizedBox(height: 32),

              // ═════════════════════════════════════════════════════════════
              //  5. Oturumu Kapat
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🚪', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Text(
                          tr('logout'),
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFEF4444),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
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
            color: const Color(0xFF6B7280),
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
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF333333),
                  ),
                ),
              ),
              if (trailing != null)
                trailing
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9CA3AF),
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

  // ignore: unused_element
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
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Mini avatar (tıklanabilir — galeri)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickProfileImage();
                      },
                      child: Stack(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
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
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.person_rounded,
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
                                color: const Color(0xFF00E5FF),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Ad Soyad
                    _editableField(
                      controller: _nameCtrl,
                      icon: Icons.person_outline_rounded,
                      label: locale.tr('full_name'),
                    ),
                    const SizedBox(height: 10),

                    // E-posta
                    _editableField(
                      controller: _emailCtrl,
                      icon: Icons.email_outlined,
                      label: locale.tr('email'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),

                    // Üyeliğim
                    _editableField(
                      controller: _membershipCtrl,
                      icon: Icons.workspace_premium_rounded,
                      label: locale.tr('membership'),
                      readOnly: true,
                    ),

                    const SizedBox(height: 18),

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
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_outline_rounded,
                                color: Color(0xFF3B82F6), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              locale.tr('change_password'),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

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
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                          ),
                          borderRadius: BorderRadius.circular(50),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.save_rounded,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 8),
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
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF9CA3AF)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
              keyboardType: keyboardType,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: readOnly
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF333333),
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: label,
                hintStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  color: const Color(0xFFBBBBCC),
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
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
                        child: Row(
                          children: [
                            const Text('🔒', style: TextStyle(fontSize: 22)),
                            const SizedBox(width: 10),
                            Text(
                              locale.tr('change_password'),
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF333333),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      const SizedBox(height: 16),

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
                      const SizedBox(height: 12),

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
                      const SizedBox(height: 12),

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
                      const SizedBox(height: 20),

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
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF6B21F2)],
                            ),
                            borderRadius: BorderRadius.circular(50),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF3B82F6).withValues(alpha: 0.25),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.lock_rounded,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
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
        color: const Color(0xFF333333),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: const Color(0xFF9CA3AF),
        ),
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        errorStyle: GoogleFonts.poppins(
          fontSize: 11,
          color: const Color(0xFFEF4444),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 16, right: 8),
          child: Icon(Icons.lock_outline_rounded,
              size: 20, color: Color(0xFF9CA3AF)),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
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
        color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(current.$1, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 4),
          Text(
            current.$4.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
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
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F4F6),
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
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                      child: Row(
                        children: [
                          const Text('🌐',
                              style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 10),
                          Text(
                            locale.tr('select_language'),
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF333333),
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
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: searchController,
                          onChanged: (val) =>
                              setSheetState(() => searchQuery = val),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: const Color(0xFF333333),
                          ),
                          cursorColor: const Color(0xFF3B82F6),
                          decoration: InputDecoration(
                            hintText: locale.tr('search_language'),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 14,
                              color: const Color(0xFF9CA3AF),
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF9CA3AF),
                              size: 20,
                            ),
                            suffixIcon: searchQuery.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      searchController.clear();
                                      setSheetState(
                                          () => searchQuery = '');
                                    },
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: Color(0xFF9CA3AF),
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

                    const Divider(height: 1, color: Color(0xFFE5E7EB)),

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
                                    color: const Color(0xFF9CA3AF),
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(),
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
                                        const Duration(milliseconds: 200),
                                    margin:
                                        const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF3B82F6)
                                              .withValues(alpha: 0.08)
                                          : Colors.transparent,
                                      borderRadius:
                                          BorderRadius.circular(24),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF3B82F6)
                                            : const Color(0xFFE5E7EB),
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(flag,
                                            style: const TextStyle(
                                                fontSize: 26)),
                                        const SizedBox(width: 14),
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
                                                      ? const Color(
                                                          0xFF3B82F6)
                                                      : const Color(
                                                          0xFF333333),
                                                ),
                                              ),
                                              Text(
                                                englishName,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 11,
                                                  color: const Color(
                                                      0xFF9CA3AF),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(culture,
                                            style: const TextStyle(
                                                fontSize: 22)),
                                        if (isSelected) ...[
                                          const SizedBox(width: 10),
                                          const Icon(
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
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF8B5CF6), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icons[_themeMode],
              size: 14, color: const Color(0xFF8B5CF6)),
          const SizedBox(width: 4),
          Text(
            labels[_themeMode],
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8B5CF6),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
              color: Color(0xFF8B5CF6), size: 16),
        ],
      ),
    );
  }

  void _showThemeBottomSheet(BuildContext context) {
    final locale = LocaleInherited.of(context);

    final options = [
      (Icons.dark_mode_rounded, locale.tr('dark_mode'),
          const Color(0xFF8B5CF6)),
      (Icons.light_mode_rounded, locale.tr('light_mode'),
          const Color(0xFFF59E0B)),
      (Icons.brightness_auto_rounded, locale.tr('system_default'),
          const Color(0xFF3B82F6)),
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
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
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
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 18, 4, 12),
                      child: Row(
                        children: [
                          const Text('🌗',
                              style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 10),
                          Text(
                            locale.tr('select_theme'),
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    const SizedBox(height: 12),
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
                          duration: const Duration(milliseconds: 200),
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
                                  : const Color(0xFFE5E7EB),
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
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  label,
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? color
                                        : const Color(0xFF333333),
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
                  decoration: const BoxDecoration(
                    color: Colors.white,
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
                            color: const Color(0xFFD1D5DB),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
                        child: Row(
                          children: [
                            const Text('⭐', style: TextStyle(fontSize: 22)),
                            const SizedBox(width: 10),
                            Text(
                              locale.tr('send_feedback'),
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF333333),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      const SizedBox(height: 16),

                      // Yazı yazma alanı
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: TextField(
                          controller: controller,
                          maxLines: 6,
                          minLines: 4,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: const Color(0xFF333333),
                          ),
                          cursorColor: const Color(0xFF00C2D4),
                          decoration: InputDecoration(
                            hintText: locale.tr('feedback_desc'),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 13,
                              color: const Color(0xFFB0B7C3),
                            ),
                            hintMaxLines: 4,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Gönder butonu
                      GestureDetector(
                        onTap: () {
                          if (controller.text.trim().isEmpty) return;
                          _launchEmail(
                            subject: 'QuAlsar - Geri Bildirim',
                            body: controller.text.trim(),
                          );
                          setSheetState(() => sent = true);
                          Future.delayed(const Duration(milliseconds: 1200), () {
                            if (ctx.mounted) Navigator.pop(ctx);
                          });
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: sent
                                  ? [const Color(0xFF22C55E), const Color(0xFF16A34A)]
                                  : [const Color(0xFF00E5FF), const Color(0xFF6B21F2)],
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
                              const SizedBox(width: 8),
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
            decoration: const BoxDecoration(
              color: Colors.white,
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
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
                  child: Row(
                    children: [
                      const Text('✉️', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Text(
                        locale.tr('contact_us'),
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF333333),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                const SizedBox(height: 16),

                // Açıklama metni — basılı tutarak kopyalanabilir
                SelectableText(
                  locale.tr('contact_desc'),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFF6B7280),
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 20),

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
                      color: const Color(0xFF00C2D4).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: const Color(0xFF00C2D4).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.email_outlined,
                            size: 20, color: Color(0xFF00C2D4)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SelectableText(
                            locale.tr('contact_email'),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF00C2D4),
                            ),
                          ),
                        ),
                        const Icon(Icons.open_in_new_rounded,
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
    } catch (_) {}

    await Clipboard.setData(const ClipboardData(text: email));
    if (mounted) _showSnack('$email kopyalandı');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: const Color(0xFF333333),
          ),
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50)),
        duration: const Duration(seconds: 2),
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
            decoration: const BoxDecoration(
              color: Color(0xFFEEEFF3),
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
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // İçerik
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
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
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.auto_awesome_rounded,
                                    size: 36, color: Colors.white),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'QuAlsar',
                                style: GoogleFonts.poppins(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1A1A2E),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Geleceğin Yapay Zeka Ekosistemi',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF3B82F6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Vizyon Açıklaması ────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'QuAlsar, modern mühendislik disiplinleri ile yapay zekanın sınırsız potansiyelini bir araya getiren hibrit bir teknoloji platformudur.',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              color: const Color(0xFF6B7280),
                              height: 1.7,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Esnek Çözüm Metodolojileri ───────────────────
                        _aboutSectionTitle('⚡', 'Esnek Çözüm Metodolojileri'),
                        const SizedBox(height: 12),
                        _aboutFeatureCard(
                          icon: Icons.bolt_rounded,
                          color: const Color(0xFFF59E0B),
                          title: 'Pratik Çözüm Modu',
                          desc: 'Zamanın kısıtlı olduğunda, en doğru sonuca en hızlı algoritma ile ulaşmanı sağlar.',
                        ),
                        const SizedBox(height: 10),
                        _aboutFeatureCard(
                          icon: Icons.list_alt_rounded,
                          color: const Color(0xFF3B82F6),
                          title: 'Adım Adım Çözüm Analizi',
                          desc: 'Her problemin mantıksal katmanlarını parçalara ayırarak, çözümün "nasıl" ve "neden" gerçekleştiğini derinlemesine öğretir.',
                        ),
                        const SizedBox(height: 10),
                        _aboutFeatureCard(
                          icon: Icons.school_rounded,
                          color: const Color(0xFFEC4899),
                          title: 'AI Öğretmen',
                          desc: 'İsmi öğretmen olsa da, o aslında senin en iyi arkadaşın! Soruları seninle konuşarak, samimi bir dille anlatır. Küçük ipuçlarıyla cevabı senin keşfetmeni sağlar.',
                        ),
                        const SizedBox(height: 20),

                        // ── Dünyanın En Güçlü Zekaları ──────────────────
                        _aboutSectionTitle('🧠', 'Dünyanın En Güçlü Zekaları'),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ChatGPT-5 Pro · Claude Max · Gemini Pro\nSuper Grok · DeepSeek',
                                style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1A1A2E),
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Dünyanın en iyi ve en gelişmiş yapay zeka modellerini sınırsız bir şekilde hizmetine sunar. Bu devasa modellerin birleşen gücüyle, her soruda en kaliteli ve en akıllı yanıtı alacağın bir deneyim seni bekliyor.',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: const Color(0xFF6B7280),
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Aktif Öğrenme ve Pekiştirme ──────────────────
                        _aboutSectionTitle('🎯', 'Aktif Öğrenme ve Pekiştirme'),
                        const SizedBox(height: 12),
                        _aboutFeatureCard(
                          icon: Icons.shuffle_rounded,
                          color: const Color(0xFF8B5CF6),
                          title: 'Dinamik Soru Varyasyonu',
                          desc: 'Öğrenilen bilgiyi pekiştirmek için, çözülen her soru için anlık olarak benzer yeni sorular türetilir.',
                        ),
                        const SizedBox(height: 10),
                        _aboutFeatureCard(
                          icon: Icons.style_rounded,
                          color: const Color(0xFF06B6D4),
                          title: 'Akıllı Bilgi Kartları',
                          desc: 'Sorulan her soruyu derinlemesine analiz ederek ilgili konunun temel kavramlarını, formüllerini ve en kritik bilgilerini tarar; ardından bu verileri derli toplu maddeler halinde sunan dijital kartlar oluşturur. Böylece konunun özünü tek bakışta kavrar, tekrar etmen gereken noktaları anında görürsün.',
                        ),
                        const SizedBox(height: 10),
                        _aboutFeatureCard(
                          icon: Icons.emoji_events_rounded,
                          color: const Color(0xFF10B981),
                          title: 'Oyunlaştırılmış Öğrenme',
                          desc: 'Edinilen bilgiyi interaktif oyunlaştırma teknikleri ile birleştirerek, süreci akılda kalıcı ve rekabetçi bir eğlenceye dönüştürür.',
                        ),
                        const SizedBox(height: 24),

                        // ── Bilgi satırları ──────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              _infoRow('Versiyon', '0.1.0'),
                              _infoRow('Geliştirici', 'QuAlsar Team'),
                              _infoRow('AI Model', 'Gemini 2.0 Flash'),
                            ],
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

  Widget _aboutSectionTitle(String emoji, String title) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A1A2E),
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
        color: Colors.white,
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF6B7280),
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
              color: const Color(0xFF9CA3AF),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF333333),
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
            decoration: const BoxDecoration(
              color: Color(0xFFEEEFF3),
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
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // İçerik
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ══════════════════════════════════════════════════
                        //  KULLANIM KOŞULLARI
                        // ══════════════════════════════════════════════════
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '📋 Kullanım Şartları ve Koşulları',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF3B82F6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Giriş
                        _termsCard(
                          'QuAlsar\'yı kullanarak, bu şartlara uymayı kabul etmiş sayılırsınız. '
                          'Bu platform, gelişmiş yapay zeka modellerini kullanarak size akademik destek sunan bir araçtır.',
                        ),
                        const SizedBox(height: 12),

                        // 1. Hizmet Kapsamı
                        _termsSectionTitle('1', 'Hizmet Kapsamı ve Yapay Zeka Sorumluluğu'),
                        const SizedBox(height: 8),
                        _termsCard(
                          'QuAlsar; ChatGPT-5 Pro, Claude Max, Super Grok ve diğer üçüncü taraf modelleri kullanır. '
                          'Yapay zeka tarafından üretilen yanıtlar %100 doğruluk garantisi taşımaz. '
                          'Sunulan çözümler birer "öneri" niteliğindedir; akademik kararlarınızda son sorumluluk kullanıcıya aittir.',
                        ),
                        const SizedBox(height: 12),

                        // 2. Kullanım Amacı
                        _termsSectionTitle('2', 'Kullanım Amacı'),
                        const SizedBox(height: 8),
                        _termsCard(
                          'Uygulama, öğrenmeyi kolaylaştırmak için tasarlanmıştır. '
                          'Sınav güvenliğini ihlal edecek şekilde kullanımı veya platformun tersine mühendislik yöntemleriyle kopyalanması kesinlikle yasaktır.',
                        ),
                        const SizedBox(height: 12),

                        // 3. Abonelik ve Ödemeler
                        _termsSectionTitle('3', 'Abonelik ve Ödemeler'),
                        const SizedBox(height: 8),
                        _termsCard(
                          'Premium abonelikler, uygulama içi satın alma kurallarına tabidir. '
                          'Satın alma işlemi gerçekleştikten sonra iade süreçleri Apple App Store ve Google Play Store politikaları üzerinden yürütülür.',
                        ),
                        const SizedBox(height: 28),

                        // ══════════════════════════════════════════════════
                        //  GİZLİLİK POLİTİKASI
                        // ══════════════════════════════════════════════════
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '🔐 Gizlilik ve Veri Güvenliği Bildirimi',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Giriş
                        _termsCard(
                          'QuAlsar, gizliliğinize en az başarınız kadar önem verir. '
                          'Verilerinizin nasıl işlendiğini şeffaf bir şekilde aşağıda açıklıyoruz.',
                        ),
                        const SizedBox(height: 12),

                        // 1. Toplanan Veriler
                        _termsSectionTitle('1', 'Toplanan Veriler'),
                        const SizedBox(height: 8),
                        _termsCard(
                          '📸 Görsel Veriler: Çözülmesi için yüklediğiniz fotoğraflar sadece ilgili yapay zeka modeline analiz için gönderilir ve işlem bittikten sonra güvenli bir şekilde işlenir.\n\n'
                          '📊 Kullanım Verileri: Deneyiminizi iyileştirmek için anonim kullanım istatistikleri toplanabilir.',
                        ),
                        const SizedBox(height: 12),

                        // 2. Veri Paylaşımı
                        _termsSectionTitle('2', 'Veri Paylaşımı ve Güvenliği'),
                        const SizedBox(height: 8),
                        _termsCard(
                          'QuAlsar, kişisel verilerinizi üçüncü taraflara satmaz. '
                          'Verileriniz, dünya standartlarındaki ChatGPT-5 Pro ve Gemini Pro API\'ları üzerinden yüksek güvenlikli şifreleme protokolleri ile iletilir.',
                        ),
                        const SizedBox(height: 12),

                        // 3. Kullanıcı Hakları
                        _termsSectionTitle('3', 'Kullanıcı Hakları'),
                        const SizedBox(height: 8),
                        _termsCard(
                          'Dilediğiniz zaman hesabınızı ve yüklediğiniz tüm geçmiş çözümleri uygulama içerisinden kalıcı olarak silme hakkına sahipsiniz.',
                        ),
                        const SizedBox(height: 24),

                        // Alt bilgi
                        Center(
                          child: Text(
                            'QuAlsar © 2026 — Tüm hakları saklıdır.',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: const Color(0xFF9CA3AF),
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
            color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              number,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          color: const Color(0xFF6B7280),
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFEF4444),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              locale.tr('logout'),
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF333333),
              ),
            ),
          ],
        ),
        content: Text(
          locale.tr('logout_confirm'),
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: const Color(0xFF6B7280),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              locale.tr('cancel'),
              style: GoogleFonts.poppins(
                color: const Color(0xFF9CA3AF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showSnack(locale.tr('logged_out'));
            },
            child: Text(
              locale.tr('sign_out'),
              style: GoogleFonts.poppins(
                color: const Color(0xFFEF4444),
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Yumuşak nefes alma döngüsü (~3.5sn)
    _controller = AnimationController(
      duration: const Duration(milliseconds: 3500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
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
          gradient: const LinearGradient(
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
              color: const Color(0xFFDB2777).withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 6),
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
                            center: const Alignment(0.6, -0.4),
                            radius: 1.1,
                            colors: [
                              const Color(0xFFFFC4A0)
                                  .withValues(alpha: intensity),
                              const Color(0xFFDB2777)
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
                        const SizedBox(width: 8),
                        _limitedChip(),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Büyük başlık
                    Text(
                      'Sınırsız Güce Geç',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Punch subtitle
                    Text(
                      'Her soru saniyede çözülsün.\nReklamsız, sınırsız, adım adım çözüm.',
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // CTA — Ücretsiz deneme vurgusu
                    Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ShaderMask(
                            shaderCallback: (r) => const LinearGradient(
                              colors: [
                                Color(0xFF4C1D95),
                                Color(0xFFDB2777),
                              ],
                            ).createShader(r),
                            child: Text(
                              '7 Gün Ücretsiz Dene',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
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
          const Icon(Icons.bolt_rounded,
              color: Color(0xFFFFE44D), size: 13),
          const SizedBox(width: 4),
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
        color: const Color(0xFFFFE44D).withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFFE44D).withValues(alpha: 0.45),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: Color(0xFFFFE44D), size: 13),
          const SizedBox(width: 4),
          Text(
            'SINIRLI TEKLİF',
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
  }

  Future<void> _saveName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name', _nameCtrl.text.trim());
  }

  Future<void> _saveStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_status_message', _statusCtrl.text.trim());
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512);
    if (picked == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final savedPath = '${dir.path}/profile_avatar.jpg';
    await File(picked.path).copy(savedPath);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_image', savedPath);
    if (mounted) setState(() => _profileImagePath = savedPath);
  }

  @override
  void dispose() {
    _saveName();
    _saveStatus();
    _nameCtrl.dispose();
    _statusCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F2F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF333333), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profil',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF333333),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
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
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
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
                              decoration: const BoxDecoration(
                                color: Color(0xFFEAF6FF),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Text(
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
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Color(0xFF00C2D4), size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Sekme 1 — Kullanıcı Adı
            _LabeledCard(
              label: 'Kullanıcı Adı',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1F2937),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Adınızı yazın',
                      hintStyle: GoogleFonts.poppins(
                        color: const Color(0xFF9CA3AF),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => _saveName(),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      if (_userId.isEmpty) return;
                      await Clipboard.setData(ClipboardData(text: _userId));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: const Color(0xFF1F2937),
                          content: Text(
                            'ID kopyalandı',
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Icon(Icons.badge_outlined,
                            size: 14,
                            color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          'ID: $_userId',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.copy_rounded,
                            size: 12, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Sekme 2 — Durum Mesajı
            _LabeledCard(
              label: 'Durum Mesajı',
              child: TextField(
                controller: _statusCtrl,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1F2937),
                ),
                decoration: InputDecoration(
                  hintText: 'Bir şeyler yazın…',
                  hintStyle: GoogleFonts.poppins(
                    color: const Color(0xFF9CA3AF),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => _saveStatus(),
              ),
            ),
            const SizedBox(height: 18),

            // Sekme 3 — Öğrenci Bilgileri
            _LabeledCard(
              label: 'Öğrenci Bilgileri',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StudentInfoPage(),
                  ),
                );
                await _load();
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _educationLevel ?? 'Eğitim seviyenizi seçin',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _educationLevel == null
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: Color(0xFF9CA3AF), size: 22),
                ],
              ),
            ),
            const SizedBox(height: 28),

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
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8A3D), Color(0xFFFF6A00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6A00).withValues(alpha: 0.32),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'Kaydet',
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
              color: const Color(0xFF6B7280),
              letterSpacing: 0.2,
            ),
          ),
        ),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
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
  static const _levels = <String>[
    'İlkokul',
    'Ortaokul',
    'Lise',
    'Üniversite (Lisans)',
    'Yüksek Lisans',
    'Doktora',
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
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F2F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF333333), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Öğrenci Bilgileri',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF333333),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Şu anki eğitim seviyeniz nedir?',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1F2937),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vereceğiniz bilgilere dayanarak size özel içerik hazırlayacağız.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF9CA3AF),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            ..._levels.map((lvl) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LevelTile(
                    label: lvl,
                    selected: _selected == lvl,
                    onTap: () => _save(lvl),
                  ),
                )),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _selected == null ? null : () => Navigator.pop(context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _selected == null
                        ? [const Color(0xFFFFB380), const Color(0xFFFFCFAE)]
                        : [const Color(0xFFFF8A3D), const Color(0xFFFF6A00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6A00).withValues(
                          alpha: _selected == null ? 0.12 : 0.32),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
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
  static const _maxInvites = 3;
  String _userId = '';
  int _invitedCount = 0;
  bool _premiumUnlocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = await loadOrCreateUserId();
    final count = prefs.getInt('invited_count') ?? 0;
    var unlocked = prefs.getBool('invite_premium_unlocked') ?? false;

    if (count >= _maxInvites && !unlocked) {
      final until = DateTime.now().add(const Duration(days: 30));
      await prefs.setBool('is_premium', true);
      await prefs.setString('premium_until', until.toIso8601String());
      await prefs.setBool('invite_premium_unlocked', true);
      unlocked = true;
    }

    if (!mounted) return;
    setState(() {
      _userId = id;
      _invitedCount = count;
      _premiumUnlocked = unlocked;
    });
  }

  Future<void> _shareCode() async {
    final msg =
        'QuAlsar\'yı denemeni istiyorum! AI destekli ödev asistanı. '
        'Uygulamayı indir, kaydolurken benim davet kodumu gir: $_userId';
    await Share.share(msg);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F2F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF333333), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Arkadaş Davet Etkinliği',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF333333),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'lib/assets/invite_hero.jpeg',
                        width: double.infinity,
                        fit: BoxFit.cover,
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
              'Arkadaşlarını davet et',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1F2937),
                height: 1.2,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'İkinizde premium üyelik kazanın.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1F2937),
                height: 1.2,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 20),

            // Davetlerim başlık — ortalı
            Text(
              'Davetlerim ($_invitedCount/$_maxInvites)',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1F2937),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 14),

            // Görev tamamlama çizgisi — %33 / %66 / %100
            LayoutBuilder(
              builder: (context, c) {
                final progress = _invitedCount / _maxInvites;
                return Stack(
                  children: [
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      height: 10,
                      width: c.maxWidth * progress,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
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
                                  color: const Color(0xFF8B5CF6)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : [],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              '%${(_invitedCount * 100 / _maxInvites).round()} tamamlandı',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 22),

            // Ödül durumu
            if (_premiumUnlocked)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8A3D)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF8A3D).withValues(alpha: 0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Text('🎉', style: TextStyle(fontSize: 32)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '1 Aylık Premium Kazandınız!',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '3 arkadaşını başarıyla davet ettin.',
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
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB26B), Color(0xFFFF6A00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFFFFE4B5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6A00).withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
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
                          child: const Text('🎁',
                              style: TextStyle(fontSize: 30)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '1 AY PREMIUM SENI BEKLIYOR',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '3 arkadaşın kaydolduğunda ödülün aktif olur.',
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
                      child: const Text('✨', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  Positioned(
                    bottom: -8,
                    left: 18,
                    child: Transform.rotate(
                      angle: -0.3,
                      child: const Text('⭐',
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
                        color: const Color(0xFFFFE44D),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFE44D)
                                .withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
                      const SizedBox(height: 26),

                      // ══════════════════════════════════════════════════════
                      //  SİSTEM NASIL ÇALIŞIR?
                      // ══════════════════════════════════════════════════════
                      Text(
                        'Nasıl Katılırsın?',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _HowItWorksStep(
                        index: 1,
                        title: 'Davet kodunu paylaş',
                        body:
                            'Kendi davet kodunu WhatsApp, SMS veya sosyal medyadan arkadaşlarına gönder.',
                      ),
                      _HowItWorksStep(
                        index: 2,
                        title: 'Arkadaşların uygulamayı indirsin',
                        body:
                            'Arkadaşın QuAlsar\'ı indirip kaydolurken davet kodunu girsin. Kodu giren arkadaşın anında 1 hafta ücretsiz premium kazanır.',
                      ),
                      _HowItWorksStep(
                        index: 3,
                        title: '3 arkadaş tamamlansın',
                        body:
                            '3 arkadaşın kaydoldukça ikonlar yeşile döner ve çizgi %33, %66, %100 olarak dolar.',
                      ),
                      _HowItWorksStep(
                        index: 4,
                        title: 'Tam dolunca ödülün aktif olur',
                        body:
                            'Çizgi tam dolduğunda hesabına otomatik 1 aylık premium tanımlanır. Ara kazanç yoktur, ödül hedef tamamlandığında verilir.',
                        isLast: true,
                      ),

                      const SizedBox(height: 26),

                      // ══════════════════════════════════════════════════════
                      //  ÖNEMLİ NOTLAR
                      // ══════════════════════════════════════════════════════
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFE5E7EB),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Text(
                                'Önemli Notlar',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _NoteItem(
                              text:
                                  'Davetlerin sayılabilmesi ve ödüllerin hesabına işlenebilmesi için internet bağlantın açık olmalıdır.',
                            ),
                            _NoteItem(
                              text:
                                  'Kazandığın ücretsiz premium günleri süresi bittiğinde kendiliğinden yenilenmez.',
                            ),
                            _NoteItem(
                              text:
                                  'Davet ettiğin arkadaş sonradan hesabını silse de kazandığın premium kuponu geri alınmaz.',
                            ),
                            _NoteItem(
                              text:
                                  'Arkadaş davet ederek elde ettiğin premium günler ayrıca jeton veya kredi içermez.',
                              isLast: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          // ════════════════════════════════════════════════════════════════
          //  SABIT ALT — Paylaş butonu (scroll ile kaybolmaz)
          // ════════════════════════════════════════════════════════════════
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: GestureDetector(
                onTap: _shareCode,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8A3D), Color(0xFFFF6A00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6A00).withValues(alpha: 0.32),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.share_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Arkadaşlarınla Paylaş',
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
              ),
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
                child: Container(
                  color: Colors.white,
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
                              color: const Color(0xFF111827),
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
                            color: const Color(0xFFFF6A00),
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
                            color: const Color(0xFF374151),
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
          color: const Color(0xFF6B7280),
          height: 1.5,
        ),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
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
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF8A3D), Color(0xFFFF6A00)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6A00).withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF6B7280),
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

  static const _palettes = <List<Color>>[
    [Color(0xFF10B981), Color(0xFF059669)], // yeşil
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // mavi
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // mor
  ];

  @override
  Widget build(BuildContext context) {
    if (!filled) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
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
            const SizedBox(height: 6),
            Text(
              'Arkadaş ${index + 1}',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      );
    }

    final colors = _palettes[index % _palettes.length];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(height: 6),
          Text(
            'Katıldı',
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
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFF00C2D4)
                : Colors.transparent,
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? const Color(0xFF00E5FF).withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: selected ? 14 : 8,
              offset: const Offset(0, 2),
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
                  color: const Color(0xFF1F2937),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: selected
                    ? const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
                      )
                    : null,
                color: selected ? null : const Color(0xFFE5E7EB),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 18)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

