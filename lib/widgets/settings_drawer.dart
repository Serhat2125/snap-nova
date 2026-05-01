import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show themeService;
import '../services/auth_service.dart';
import '../services/locale_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  SettingsDrawer — sağdan kayan panel + iç sayfa navigasyonu
// ═══════════════════════════════════════════════════════════════════════════════

class SettingsDrawer extends StatefulWidget {
  final VoidCallback onClose;
  const SettingsDrawer({super.key, required this.onClose});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  String? _activePage; // null = ana menü

  void _openPage(String page) => setState(() => _activePage = page);
  void _closePage() => setState(() => _activePage = null);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(28),
        bottomLeft: Radius.circular(28),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xEE08081A), Color(0xF00C0C22)],
            ),
            border: Border(
              left: BorderSide(
                  color: Colors.cyanAccent.withValues(alpha: 0.18), width: 1.2),
            ),
          ),
          child: Stack(
            children: [
              // ── Ana menü ────────────────────────────────────────────
              _MainMenu(
                onOpenPage: _openPage,
                onClose: widget.onClose,
              ),

              // ── Alt sayfalar (sağdan kayarak gelir) ─────────────────
              AnimatedSlide(
                offset: _activePage != null ? Offset.zero : const Offset(1, 0),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _activePage != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: _activePage != null
                      ? _SubPageShell(
                          onBack: _closePage,
                          child: _buildSubPage(_activePage!),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubPage(String page) {
    switch (page) {
      case 'profile':
        return const _ProfilePage();
      case 'language':
        return const _LanguagePage();
      case 'theme':
        return const _ThemePage();
      case 'feedback':
        return const _FeedbackPage();
      case 'faq':
        return const _FaqPage();
      case 'about':
        return const _AboutPage();
      case 'terms':
        return const _TermsPage();
      default:
        return const SizedBox.shrink();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Ana menü listesi
// ═══════════════════════════════════════════════════════════════════════════════

class _MainMenu extends StatelessWidget {
  final void Function(String) onOpenPage;
  final VoidCallback onClose;
  const _MainMenu({required this.onOpenPage, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final locale = LocaleInherited.of(context);
    final tr = locale.tr;

    // Mevcut dil adını bul
    final currentLangName = LocaleService.languages
        .firstWhere((l) => l.$4 == locale.localeCode,
            orElse: () => LocaleService.languages[1])
        .$2;

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
            child: Row(children: [
              Expanded(
                child: Text(tr('settings'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white54, size: 22),
              ),
            ]),
          ),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                // Profil kartı
                _ProfileCard(onTap: () => onOpenPage('profile')),
                const SizedBox(height: 16),

                _label(tr('preferences')),
                const SizedBox(height: 6),
                _Item(
                    icon: Icons.language_rounded,
                    color: const Color(0xFF3B82F6),
                    title: tr('language_options'),
                    subtitle: currentLangName,
                    onTap: () => onOpenPage('language')),
                _Item(
                    icon: Icons.dark_mode_rounded,
                    color: const Color(0xFF8B5CF6),
                    title: tr('theme_appearance'),
                    subtitle: tr('dark_mode'),
                    onTap: () => onOpenPage('theme')),

                const SizedBox(height: 10),
                _divider(),
                const SizedBox(height: 10),
                _label(tr('support')),
                const SizedBox(height: 6),

                _Item(
                    icon: Icons.chat_bubble_outline_rounded,
                    color: const Color(0xFF10B981),
                    title: tr('feedback'),
                    onTap: () => onOpenPage('feedback')),
                _Item(
                    icon: Icons.help_outline_rounded,
                    color: const Color(0xFF0EA5E9),
                    title: tr('help_faq'),
                    onTap: () => onOpenPage('faq')),
                _Item(
                    icon: Icons.info_outline_rounded,
                    color: const Color(0xFF6366F1),
                    title: tr('about_us'),
                    onTap: () => onOpenPage('about')),

                const SizedBox(height: 10),
                _divider(),
                const SizedBox(height: 10),
                _label(tr('legal')),
                const SizedBox(height: 6),

                _Item(
                    icon: Icons.description_outlined,
                    color: const Color(0xFF94A3B8),
                    title: tr('terms_of_use'),
                    onTap: () => onOpenPage('terms')),

                const SizedBox(height: 10),
                _divider(),
                const SizedBox(height: 10),

                _Item(
                    icon: Icons.logout_rounded,
                    color: const Color(0xFFEF4444),
                    title: tr('sign_out'),
                    titleColor: const Color(0xFFEF4444),
                    onTap: () => _showLogout(context)),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 2),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.32),
                letterSpacing: 1.2)),
      );

  static Widget _divider() => Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.10),
            Colors.transparent,
          ]),
        ),
      );

  void _showLogout(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => const _LogoutDialog(),
    );
  }
}

// ─── Profil kartı ──────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ProfileCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Gerçek kullanıcıdan oku — yoksa "Misafir".
    final user = AuthService.current;
    final displayName = (user?.name?.trim().isNotEmpty == true)
        ? user!.name!.trim().split(' ').first
        : (user?.email?.split('@').first ?? 'Misafir');
    final hasPhoto = (user?.photoUrl ?? '').isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.cyanAccent.withValues(alpha: 0.10),
              const Color(0xFF0070FF).withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: 0.28), width: 1.2),
        ),
        child: Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF0070FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              boxShadow: [
                BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.35),
                    blurRadius: 12)
              ],
              image: hasPhoto
                  ? DecorationImage(
                      image: NetworkImage(user!.photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasPhoto
                ? null
                : const Icon(Icons.person_rounded,
                    color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hoş geldin, $displayName 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('Profilimi Görüntüle',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.cyanAccent.withValues(alpha: 0.80),
                      fontWeight: FontWeight.w500)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.35), size: 20),
        ]),
      ),
    );
  }
}

// ─── Menü öğesi ────────────────────────────────────────────────────────────────

class _Item extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final VoidCallback onTap;
  const _Item(
      {required this.icon,
      required this.color,
      required this.title,
      this.subtitle,
      this.titleColor,
      required this.onTap});

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _p = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _p = true),
      onTapUp: (_) {
        setState(() => _p = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _p = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _p ? widget.color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: _p
              ? Border.all(color: widget.color.withValues(alpha: 0.28), width: 1)
              : null,
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: widget.color.withValues(alpha: 0.25)),
            ),
            child: Icon(widget.icon, color: widget.color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title,
                  style: TextStyle(
                      color: widget.titleColor ?? Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              if (widget.subtitle != null)
                Text(widget.subtitle!,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.38))),
            ]),
          ),
          if (widget.titleColor == null)
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.22), size: 18),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Alt sayfa kabı (başlık + geri butonu)
// ═══════════════════════════════════════════════════════════════════════════════

class _SubPageShell extends StatelessWidget {
  final VoidCallback onBack;
  final Widget child;
  const _SubPageShell({required this.onBack, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF08081A),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Alt sayfa ortak başlık
// ═══════════════════════════════════════════════════════════════════════════════

class _PageHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _PageHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 52, 16, 4),
      child: Row(children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.cyanAccent, size: 20),
        ),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  1. Profil Sayfası
// ═══════════════════════════════════════════════════════════════════════════════

class _ProfilePage extends StatefulWidget {
  const _ProfilePage();
  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  late final StreamSubscription<AppUser?> _sub;

  @override
  void initState() {
    super.initState();
    // AuthService.onChange yayını — login/logout'ta sayfa otomatik tazelenir.
    _sub = AuthService.onChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  String _providerLabel(AuthProvider p) => switch (p) {
        AuthProvider.google => 'Google',
        AuthProvider.apple => 'Apple',
        AuthProvider.phone => 'Telefon',
        AuthProvider.email => 'E-posta',
        AuthProvider.guest => 'Misafir',
      };

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_SettingsDrawerState>()!;
    final user = AuthService.current;
    final isGuest = user == null || user.isGuest;
    final name = (user?.name?.trim().isNotEmpty == true)
        ? user!.name!.trim()
        : (isGuest ? 'Misafir Kullanıcı' : 'İsimsiz');
    final email = user?.email ?? (isGuest ? 'Giriş yapılmadı' : '—');
    final photo = user?.photoUrl ?? '';

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _PageHeader(title: 'Profilim', onBack: shell._closePage),
          const SizedBox(height: 8),

          // Avatar + isim
          Center(
            child: Column(children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF0070FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.cyanAccent.withValues(alpha: 0.40),
                        blurRadius: 20)
                  ],
                  image: photo.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(photo), fit: BoxFit.cover)
                      : null,
                ),
                child: photo.isEmpty
                    ? const Icon(Icons.person_rounded,
                        color: Colors.white, size: 44)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(email,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.50),
                      fontSize: 13)),
              if (user != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: Colors.cyanAccent.withValues(alpha: 0.30)),
                  ),
                  child: Text(_providerLabel(user.provider),
                      style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 28),

          _neonField('Ad Soyad', name, Icons.person_outline),
          const SizedBox(height: 12),
          _neonField('E-posta', email, Icons.email_outlined),
          const SizedBox(height: 24),

          _neonBtn('Üyeliğim', Icons.workspace_premium_rounded,
              const Color(0xFFF59E0B)),
          const SizedBox(height: 10),
          if (!isGuest)
            _neonBtn('Hesap Ayarları', Icons.settings_outlined,
                const Color(0xFF8B5CF6)),
          if (!isGuest) const SizedBox(height: 10),
          // Çıkış / Giriş — gerçek auth durumuna göre.
          GestureDetector(
            onTap: () async {
              if (isGuest) {
                // Misafir kullanıcı: oturum açma akışını tetikle.
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Giriş yapmak için Profilim > Üyeliğim > Giriş Yap yolunu kullan.'),
                  backgroundColor: Colors.cyanAccent,
                ));
                return;
              }
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => const _LogoutDialog(),
              );
              if (confirm == true) {
                await AuthService.signOut();
                if (mounted) setState(() {});
              }
            },
            child: _neonBtn(
              isGuest ? 'Giriş Yap' : 'Çıkış Yap',
              isGuest ? Icons.login_rounded : Icons.logout_rounded,
              isGuest ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _neonField(String label, String value, IconData icon) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.cyanAccent.withValues(alpha: 0.22), width: 1.2),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.cyanAccent.withValues(alpha: 0.60), size: 18),
          const SizedBox(width: 12),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ]),
      ),
    ]);
  }

  Widget _neonBtn(String label, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 10)
        ],
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 14),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w700)),
        const Spacer(),
        Icon(Icons.chevron_right_rounded,
            color: color.withValues(alpha: 0.50), size: 18),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  2. Dil Seçenekleri
// ═══════════════════════════════════════════════════════════════════════════════

class _LanguagePage extends StatefulWidget {
  const _LanguagePage();

  @override
  State<_LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<_LanguagePage> {
  String _search = '';
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_SettingsDrawerState>()!;
    final locale = LocaleInherited.of(context);
    final allLangs = LocaleService.languages;

    // Arama filtresi
    final query = _search.toLowerCase().trim();
    final filtered = query.isEmpty
        ? allLangs
        : allLangs.where((lang) {
            final (_, name, englishName, code, _) = lang;
            return name.toLowerCase().contains(query) ||
                englishName.toLowerCase().contains(query) ||
                code.toLowerCase().contains(query);
          }).toList();

    // Seçili dili her zaman en üstte göster
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

    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(title: locale.tr('language_options'), onBack: shell._closePage),

        // ── Arama çubuğu ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              onChanged: (val) => setState(() => _search = val),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: Colors.cyanAccent,
              decoration: InputDecoration(
                hintText: locale.tr('search_language'),
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Colors.white.withValues(alpha: 0.4),
                  size: 20,
                ),
                suffixIcon: _search.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _search = '');
                          _focusNode.unfocus();
                        },
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.4),
                          size: 18,
                        ),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),

        // ── Dil listesi ───────────────────────────────────────────────
        Expanded(
          child: sortedLangs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      locale.tr('no_results'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: sortedLangs.length,
                  itemBuilder: (_, i) {
                    final (flag, name, englishName, code, culture) = sortedLangs[i];
                    final sel = locale.localeCode == code;
                    return GestureDetector(
                      onTap: () {
                        locale.setLocale(code);
                        setState(() {});
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: sel
                              ? Colors.cyanAccent.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: sel
                                  ? Colors.cyanAccent.withValues(alpha: 0.55)
                                  : Colors.white.withValues(alpha: 0.08),
                              width: sel ? 1.4 : 1.0),
                        ),
                        child: Row(children: [
                          Text(flag, style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: TextStyle(
                                          color: sel
                                              ? Colors.cyanAccent
                                              : Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  Text(englishName,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white
                                              .withValues(alpha: 0.38))),
                                ]),
                          ),
                          Text(culture,
                              style: const TextStyle(fontSize: 18)),
                          if (sel) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check_circle_rounded,
                                color: Colors.cyanAccent, size: 20),
                          ],
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  3. Tema
// ═══════════════════════════════════════════════════════════════════════════════

class _ThemePage extends StatefulWidget {
  const _ThemePage();

  @override
  State<_ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends State<_ThemePage> {
  // ThemeService.notifyListeners() dinleyelim — başka yerden değişirse güncelle.
  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_SettingsDrawerState>()!;
    final selected = themeService.index; // 0=dark 1=light 2=system
    final options = [
      (Icons.dark_mode_rounded, 'Koyu Mod', const Color(0xFF8B5CF6)),
      (Icons.light_mode_rounded, 'Açık Mod', const Color(0xFFF59E0B)),
      (Icons.brightness_auto_rounded, 'Sistem Teması', const Color(0xFF3B82F6)),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _PageHeader(title: 'Tema Görünümü', onBack: shell._closePage),
          const SizedBox(height: 8),
          ...options.asMap().entries.map((e) {
            final i = e.key;
            final (icon, label, color) = e.value;
            final sel = selected == i;
            return GestureDetector(
              onTap: () => themeService.setIndex(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: sel
                      ? color.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: sel
                          ? color.withValues(alpha: 0.65)
                          : Colors.white.withValues(alpha: 0.08),
                      width: sel ? 1.6 : 1.0),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                              color: color.withValues(alpha: 0.20),
                              blurRadius: 14)
                        ]
                      : [],
                ),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: sel ? 0.22 : 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Text(label,
                          style: TextStyle(
                              color: sel ? color : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700))),
                  if (sel)
                    Icon(Icons.check_circle_rounded, color: color, size: 22),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  4. Geri Bildirim
// ═══════════════════════════════════════════════════════════════════════════════

class _FeedbackPage extends StatefulWidget {
  const _FeedbackPage();

  @override
  State<_FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<_FeedbackPage> {
  int _stars = 0;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_SettingsDrawerState>()!;
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _PageHeader(title: 'Geri Bildirim', onBack: shell._closePage),
          const SizedBox(height: 12),
          const Text('Deneyiminizi puanlayın',
              style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              return GestureDetector(
                onTap: () => setState(() => _stars = i + 1),
                child: AnimatedScale(
                  scale: _stars >= i + 1 ? 1.2 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      _stars >= i + 1
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: _stars >= i + 1
                          ? const Color(0xFFF59E0B)
                          : Colors.white.withValues(alpha: 0.25),
                      size: 40,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          Text('Mesajınız',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.cyanAccent.withValues(alpha: 0.28), width: 1.2),
            ),
            child: TextField(
              controller: _ctrl,
              maxLines: 5,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Görüşlerinizi yazın...',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.28), fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () async {
              final body = '⭐ $_stars/5\n\n${_ctrl.text}';
              final uri = Uri(
                scheme: 'mailto',
                path: 'serhatdsme@gmail.com',
                queryParameters: {
                  'subject': 'QuAlsar - Geri Bildirim',
                  'body': body,
                },
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('serhatdsme@gmail.com'),
                    backgroundColor: Colors.cyanAccent,
                  ));
                }
              }
            },
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Colors.cyanAccent, Color(0xFF0070FF)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.30),
                      blurRadius: 18)
                ],
              ),
              child: const Center(
                child: Text('Gönder',
                    style: TextStyle(
                        color: Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  5. SSS / Yardım
// ═══════════════════════════════════════════════════════════════════════════════

class _FaqPage extends StatefulWidget {
  const _FaqPage();

  @override
  State<_FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<_FaqPage> {
  int? _open;

  static const _items = [
    ('QuAlsar nasıl çalışır?',
        'Fotoğraf çek veya galeriden seç, yapay zeka soruyu tanıyarak çözüm üretir.'),
    ('Hangi dersler destekleniyor?',
        'Matematik, Fizik, Kimya, Biyoloji, Edebiyat, Tarih ve daha fazlası.'),
    ('AI modeli nasıl seçilir?',
        'Çözüm ekranında ChatGPT, Gemini, Claude veya Grok arasından seçim yapabilirsin.'),
    ('Ücretsiz plan neler içeriyor?',
        'Günlük 10 soru ücretsiz. Premium ile sınırsız çözüm ve video ders.'),
    ('Hesabım silinirse ne olur?',
        'Tüm çözüm geçmişiniz ve aboneliğiniz kalıcı olarak silinir.'),
    ('Gizliliğim nasıl korunuyor?',
        'Fotoğraflarınız işlendikten sonra sunucularımızda saklanmaz.'),
  ];

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_SettingsDrawerState>()!;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(title: 'Yardım / SSS', onBack: shell._closePage),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final (q, a) = _items[i];
              final open = _open == i;
              return GestureDetector(
                onTap: () => setState(() => _open = open ? null : i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: open
                        ? Colors.cyanAccent.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: open
                            ? Colors.cyanAccent.withValues(alpha: 0.40)
                            : Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        child: Row(children: [
                          Expanded(
                            child: Text(q,
                                style: TextStyle(
                                    color: open
                                        ? Colors.cyanAccent
                                        : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                          Icon(
                              open
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: Colors.white.withValues(alpha: 0.40),
                              size: 20),
                        ]),
                      ),
                      if (open)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          child: Text(a,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 12.5,
                                  height: 1.5)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  6. Hakkımızda
// ═══════════════════════════════════════════════════════════════════════════════

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_SettingsDrawerState>()!;
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _PageHeader(title: 'Hakkımızda', onBack: shell._closePage),
          Center(
            child: Column(children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF0070FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 38),
              ),
              const SizedBox(height: 12),
              const Text('QuAlsar',
                  style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 24,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('v1.0.0 — Beta',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.40), fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 24),
          _card(
              'Her derste, her konuda yapay zeka destekli çözüm. '
              'QuAlsar öğrencilerin öğrenme sürecini kişiselleştirerek '
              'daha hızlı ve daha etkili bir eğitim deneyimi sunar.'),
          const SizedBox(height: 16),
          const Text('Sosyal Medya',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _socialBtn(
              Icons.language_rounded, 'qualsar.app', const Color(0xFF3B82F6),
              url: 'https://qualsar.app'),
          const SizedBox(height: 8),
          _socialBtn(
              Icons.camera_alt_outlined, '@qualsar', const Color(0xFFEC4899),
              url: 'https://instagram.com/qualsar'),
          const SizedBox(height: 8),
          _socialBtn(Icons.email_outlined, 'serhatdsme@gmail.com',
              const Color(0xFF10B981),
              url: 'mailto:serhatdsme@gmail.com'),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _card(String text) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Text(text,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 13,
                height: 1.6)),
      );

  Widget _socialBtn(IconData icon, String label, Color color, {String? url}) {
    final btn = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (url != null)
          Icon(Icons.open_in_new_rounded,
              color: color.withValues(alpha: 0.55), size: 14),
      ]),
    );
    if (url == null) return btn;
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: btn,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  7. Kullanım Koşulları
// ═══════════════════════════════════════════════════════════════════════════════

class _TermsPage extends StatelessWidget {
  const _TermsPage();

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_SettingsDrawerState>()!;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(title: 'Kullanım Koşulları', onBack: shell._closePage),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _section('1. Hizmet Kapsamı',
                    'QuAlsar, öğrencilere yapay zeka destekli akademik çözümler sunar. '
                    'Hizmet eğitim amaçlıdır; ticari kullanım yasaktır.'),
                _section('2. Kullanıcı Sorumlulukları',
                    'Kullanıcılar platform üzerinden yanlış, yanıltıcı veya zararlı içerik '
                    'paylaşmamayı kabul eder.'),
                _section('3. Gizlilik',
                    'Yüklenen fotoğraflar yalnızca çözüm üretimi için işlenir ve '
                    'saklanmaz. Kişisel veriler KVKK kapsamında korunur.'),
                _section('4. Abonelik',
                    'Premium abonelikler otomatik yenilenir. İptal en az 24 saat '
                    'öncesinden yapılmalıdır.'),
                _section('5. Değişiklikler',
                    'QuAlsar bu koşulları önceden bildirmeksizin değiştirme hakkını '
                    'saklı tutar.'),
                const SizedBox(height: 8),
                Text('Son güncelleme: Nisan 2026',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.30),
                        fontSize: 11)),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _section(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12.5,
                  height: 1.6)),
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Çıkış onay dialog
// ═══════════════════════════════════════════════════════════════════════════════

class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xEE0C0C22),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.40),
                  width: 1.4),
            ),
            child: Builder(builder: (ctx) {
              final locale = LocaleInherited.of(ctx);
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEF4444).withValues(alpha: 0.14),
                  ),
                  child: const Icon(Icons.logout_rounded,
                      color: Color(0xFFEF4444), size: 28),
                ),
                const SizedBox(height: 18),
                Text(locale.tr('sign_out'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(locale.tr('logout_confirm'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                        height: 1.5)),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, false),
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: Center(
                          child: Text(locale.tr('cancel'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, true),
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.50)),
                        ),
                        child: Center(
                          child: Text(locale.tr('sign_out'),
                              style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}
