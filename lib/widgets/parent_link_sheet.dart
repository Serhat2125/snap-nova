// ═══════════════════════════════════════════════════════════════════════════
//  ParentLinkSheet — "Veliyi Bağla" akışının DONMAYAN yeniden tasarımı.
//
//  ESKİ akış (kaldırıldı): karta basınca barrierDismissible:false bir
//  spinner dialog açılıyor, kod üretimi bekleniyor, sonra ikinci bir dialog
//  gösteriliyordu. Kod üretimi herhangi bir nedenle uzarsa/asılı kalırsa
//  kullanıcı KAPATAMADIĞI bir spinner'a hapsoluyordu ("donuk kalıyor").
//
//  YENİ akış: sheet ANINDA açılır; kod üretimi sheet'in İÇİNDE kendi durum
//  makinesiyle yürür (hazırlanıyor → QR+kod → hata+Tekrar Dene). Kapat
//  düğmesi ve sürükleyip kapatma HER AN çalışır — kilitlenme imkânsız.
//
//  Kullanım (öğrenci tarafı, profil + Gelişimim aynı sheet'i açar):
//    await showParentLinkSheet(context);
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../services/deep_link_service.dart';
import '../services/parent_link_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

Future<void> showParentLinkSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ParentLinkSheet(),
  );
}

class ParentLinkSheet extends StatefulWidget {
  const ParentLinkSheet({super.key});

  @override
  State<ParentLinkSheet> createState() => _ParentLinkSheetState();
}

class _ParentLinkSheetState extends State<ParentLinkSheet> {
  ChildLinkCode? _code;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _code = null;
    });
    ChildLinkCode? code;
    try {
      // Tavan süre: ağ/sunucu asılı kalsa bile sheet hata durumuna düşer;
      // kullanıcı zaten her an kapatabilir.
      code = await ParentLinkService.generateChildLinkCode()
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      code = null;
    }
    if (!mounted) return;
    setState(() {
      _code = code;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return SafeArea(
      child: Container(
        margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        decoration: BoxDecoration(
          color: AppPalette.bg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              Row(
                children: [
                  Expanded(
                    child: Text('Veliyi Bağla'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: ink)),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Icon(Icons.close_rounded, size: 22, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Velin yanındaysa: kendi telefonundaki QuAlsar\'da '
                '"QR Kodu Okut" deyip bu kodu okutsun — bağlantı anında '
                'kurulur. Uzaktaysa: WhatsApp\'tan gönder, linke dokunması '
                'yeterli.'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 12, height: 1.4, color: muted),
              ),
              const SizedBox(height: 16),
              if (_loading)
                _buildLoading(muted)
              else if (_code == null)
                _buildError(ink)
              else
                _buildReady(_code!, ink, muted),
            ],
          ),
        ),
      ),
    );
  }

  // Hazırlanıyor — küçük, KAPATILABİLİR bekleme durumu (tam ekran barrier yok).
  Widget _buildLoading(Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          const SizedBox(height: 12),
          Text('Bağlanma kodu hazırlanıyor…'.tr(),
              style: GoogleFonts.poppins(fontSize: 12.5, color: muted)),
        ],
      ),
    );
  }

  Widget _buildError(Color ink) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          const Text('📡', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 8),
          Text(
            'Kod üretilemedi. İnternet bağlantını ve giriş yaptığını kontrol et.'
                .tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 12.5, height: 1.4, color: ink),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _generate,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white, size: 18),
            label: Text('Tekrar Dene'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildReady(ChildLinkCode code, Color ink, Color muted) {
    final link = DeepLinkService.parentLinkFor(code.code);
    return Column(
      children: [
        // QR — beyaz zemin üstünde (koyu temada da okunur olsun).
        Center(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: QrImageView(
              data: link,
              version: QrVersions.auto,
              size: 180,
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: code.code));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Kod kopyalandı'.tr()),
              behavior: SnackBarBehavior.floating,
            ));
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SelectableText(code.code,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: const Color(0xFF10B981),
                  )),
              const SizedBox(width: 8),
              Icon(Icons.copy_rounded, size: 18, color: muted),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('24 saat geçerli.'.tr(),
            style: GoogleFonts.poppins(fontSize: 11, color: muted)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366), // WhatsApp yeşili
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              // Fire-and-forget: paylaşım sheet'i Activity kilidine takılırsa
              // bile buton/sheet asılı kalmaz.
              unawaited(Share.share(
                '${'QuAlsar veli daveti 👨‍👩‍👧'.tr()}\n\n'
                '${'Çocuğunuzun ders gelişimini takip etmek için bu bağlantıya dokunun:'.tr()}\n'
                '$link\n\n'
                '${'Uygulama yüklü değilse önce QuAlsar\'ı indirip veli hesabı oluşturun, sonra bağlantıya tekrar dokunun.'.tr()}',
              ));
            },
            icon: const Icon(Icons.share_rounded,
                color: Colors.white, size: 18),
            label: Text('WhatsApp\'tan Gönder'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
