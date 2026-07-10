// ═══════════════════════════════════════════════════════════════════════════
//  ParentOnboardingScreen — Ebeveyn hesabı için ilk kurulum.
//
//  Birincil yol: çocuğun ekranındaki QR okutulur → ParentLinkService.linkByCode
//  → bağlantı ANINDA aktif, dashboard'a geçilir (çocuk onayı gerekmez).
//  İkincil yol: EBEV- kodu elle yazılır (aynı linkByCode).
//  "Atla → Dashboard" da mümkün — kullanıcı sonra ekleyebilir.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/parent_link_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../widgets/parent_qr_scan_dialog.dart';
import 'parent_shell_screen.dart';

class ParentOnboardingScreen extends StatefulWidget {
  const ParentOnboardingScreen({super.key});

  @override
  State<ParentOnboardingScreen> createState() => _ParentOnboardingScreenState();
}

class _ParentOnboardingScreenState extends State<ParentOnboardingScreen> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  String? _msg;
  bool _success = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// QR'dan ya da elle girilen koddan DOĞRUDAN bağlar; başarıda kısa bir
  /// onay mesajı gösterip dashboard'a geçer.
  Future<void> _linkWithCode(String rawCode) async {
    if (rawCode.trim().isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _msg = null;
    });
    final res = await ParentLinkService.linkByCode(rawCode);
    if (!mounted) return;
    setState(() => _sending = false);
    switch (res) {
      case LinkRequestResult.success:
      case LinkRequestResult.alreadyLinked:
        setState(() {
          _success = true;
          _msg = 'Bağlantı kuruldu 🎉 Panele geçiliyor...'.tr();
        });
        _ctrl.clear();
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) _skipToDashboard();
        break;
      case LinkRequestResult.pending:
        setState(() => _msg = 'Bu çocuk için bekleyen bir isteğin var.'.tr());
        break;
      case LinkRequestResult.childNotFound:
        setState(() => _msg =
            'Bu koda bağlı öğrenci bulunamadı. Kodu kontrol et.'.tr());
        break;
      case LinkRequestResult.selfLink:
        setState(() => _msg = 'Kendi hesabına bağlanamazsın.'.tr());
        break;
      case LinkRequestResult.notAuthed:
        setState(() => _msg = 'Giriş yapman gerekiyor.'.tr());
        break;
      case LinkRequestResult.invalidCode:
        setState(() => _msg =
            'Kod formatı hatalı. EBEV-XXXXXX şeklinde olmalı.'.tr());
        break;
      case LinkRequestResult.codeExpired:
        setState(() => _msg =
            'Kodun süresi dolmuş. Çocuğun yeni bir kod üretmeli.'.tr());
        break;
      case LinkRequestResult.error:
        setState(() => _msg =
            'Bağlantı kurulamadı. İnternet ve sunucuyu kontrol et.'.tr());
        break;
    }
  }

  Future<void> _scanQr() async {
    final code = await showParentQrScanner(context);
    if (code == null || !mounted) return;
    await _linkWithCode(code);
  }

  Future<void> _request() => _linkWithCode(_ctrl.text);

  void _skipToDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const ParentShellScreen(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Ebeveyn Kurulumu'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800,
              color: AppPalette.textPrimary(context))),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          // Dikey taşma önlemi: içerik uzun çevirilerde / küçük ekranda /
          // klavye açıkken sığmayabilir — üst blok kaydırılabilir.
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
              const SizedBox(height: 12),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                ),
                alignment: Alignment.center,
                child: const Text('👨‍👩‍👧',
                    style: TextStyle(fontSize: 36)),
              ),
              const SizedBox(height: 16),
              Text('Çocuğunun hesabını bağla'.tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 22, fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(context),
                    letterSpacing: -0.3,
                  )),
              const SizedBox(height: 8),
              Text(
                'Çocuğunun telefonunda Profil → "Veliyi Bağla" ekranını '
                'açtır ve çıkan QR kodu okut — bağlantı anında kurulur.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppPalette.textSecondary(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _sending ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded,
                      color: Colors.white, size: 22),
                  label: Text('QR Kodu Okut'.tr(),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      )),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: Divider(color: AppPalette.border(context))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('veya kodu yaz'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppPalette.textSecondary(context))),
                ),
                Expanded(
                    child: Divider(color: AppPalette.border(context))),
              ]),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppPalette.card(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppPalette.border(context)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _request(),
                  style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(context),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'EBEV-XXXXXX'.tr(),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    prefixIcon: Icon(Icons.vpn_key_rounded,
                        color: AppPalette.textSecondary(context), size: 20),
                  ),
                ),
              ),
              if (_msg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _success
                        ? const Color(0xFF10B981).withValues(alpha: 0.08)
                        : const Color(0xFFEF4444).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _success
                          ? const Color(0xFF10B981).withValues(alpha: 0.30)
                          : const Color(0xFFEF4444).withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(_success
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded,
                          color: _success
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                          size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_msg!,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textPrimary(context),
                              height: 1.4,
                            )),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _sending ? null : _request,
                  child: _sending
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Text('Bağla'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          )),
                ),
              ),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: _skipToDashboard,
                child: Text('Daha sonra ekle → Dashboard\'a git'.tr(),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondary(context),
                      decoration: TextDecoration.underline,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
