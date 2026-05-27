// ═══════════════════════════════════════════════════════════════════════════
//  ParentInviteBanner — Çocuk hesabında ana sayfada gösterilen banner.
//
//  Eğer bekleyen ebeveyn isteği varsa banner görünür, kullanıcı kabul/red
//  butonlarıyla cevap verir. Hiç istek yoksa banner gizli (SizedBox.shrink).
//
//  CameraScreen / AcademicPlanner gibi ana ekranlarda en üste eklenir.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/parent_link_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

class ParentInviteBanner extends StatelessWidget {
  const ParentInviteBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ParentInvite>>(
      stream: ParentLinkService.incomingInvitesStream(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final list = snap.data!;
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          children: list.map((inv) => _Item(invite: inv)).toList(),
        );
      },
    );
  }
}

class _Item extends StatefulWidget {
  final ParentInvite invite;
  const _Item({required this.invite});

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ParentLinkService.acceptInvite(widget.invite.parentUid);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ebeveyn bağlantısı onaylandı.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ParentLinkService.rejectInvite(widget.invite.parentUid);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final inv = widget.invite;
    final who = inv.parentDisplayName.isEmpty
        ? '@${inv.parentUsername}'
        : '${inv.parentDisplayName} (@${inv.parentUsername})';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10B981).withValues(alpha: 0.10),
            const Color(0xFF06B6D4).withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.35), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('👨‍👩‍👧', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ebeveyn bağlantı isteği'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF065F46),
                          letterSpacing: 0.5,
                        )),
                    Text(who,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Çalışma sürelerini, çözümlerini ve başarını görmesine izin veriyor musun?'
                .tr(),
            style: GoogleFonts.poppins(
              fontSize: 12, color: AppPalette.textSecondary(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _busy ? null : _accept,
                  child: Text('İzin Ver'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      )),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppPalette.border(context)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _busy ? null : _reject,
                  child: Text('Reddet'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context),
                      )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
