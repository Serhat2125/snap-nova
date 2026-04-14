import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/locale_service.dart';
import 'premium_screen.dart';

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
  int _themeMode = 0;

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
                    // Profil Fotoğrafı + Rozet — Tıkla → profil bilgileri aç
                    GestureDetector(
                      onTap: () => _showProfileBottomSheet(context),
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
                    // Premium'a Yükselt çerçevesi
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PremiumScreen(),
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF59E0B), Color(0xFFEC4899)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.workspace_premium_rounded,
                                color: Colors.white, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    locale.tr('upgrade_premium'),
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    locale.tr('premium_slogan'),
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(alpha: 0.9),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: Colors.white, size: 22),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ═════════════════════════════════════════════════════════════
              //  2. Uygulama Tercihleri
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
              //  3. Destek ve İletişim
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
                        onTap: () {
                          setState(() => _themeMode = i);
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
                            subject: 'SnapNova - Geri Bildirim',
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
                    _launchEmail(subject: 'SnapNova - İletişim');
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

  Future<void> _launchEmail({String subject = 'SnapNova', String body = ''}) async {
    final params = <String, String>{'subject': subject};
    if (body.isNotEmpty) params['body'] = body;
    final uri = Uri(
      scheme: 'mailto',
      path: 'serhatdsme@gmail.com',
      queryParameters: params,
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) _showSnack('serhatdsme@gmail.com');
    }
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
                                'SnapNova',
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
                            'SnapNova, modern mühendislik disiplinleri ile yapay zekanın sınırsız potansiyelini bir araya getiren hibrit bir teknoloji platformudur.',
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
                              _infoRow('Geliştirici', 'SnapNova Team'),
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
                          'SnapNova\'yı kullanarak, bu şartlara uymayı kabul etmiş sayılırsınız. '
                          'Bu platform, gelişmiş yapay zeka modellerini kullanarak size akademik destek sunan bir araçtır.',
                        ),
                        const SizedBox(height: 12),

                        // 1. Hizmet Kapsamı
                        _termsSectionTitle('1', 'Hizmet Kapsamı ve Yapay Zeka Sorumluluğu'),
                        const SizedBox(height: 8),
                        _termsCard(
                          'SnapNova; ChatGPT-5 Pro, Claude Max, Super Grok ve diğer üçüncü taraf modelleri kullanır. '
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
                          'SnapNova, gizliliğinize en az başarınız kadar önem verir. '
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
                          'SnapNova, kişisel verilerinizi üçüncü taraflara satmaz. '
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
                            'SnapNova © 2026 — Tüm hakları saklıdır.',
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

