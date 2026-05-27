// ═══════════════════════════════════════════════════════════════════════════
//  DeleteAccountScreen — QandA tarzı tam ekran hesap silme onay sayfası.
//
//  Profil → "Hesabımı Sil" → bu ekran → "QuAlsar'dan Ayrıl" → 2. adım yazılı
//  onay dialog'u → onaylanırsa _performAccountDeletion() callback'i çağrılır.
//
//  Apple Guideline 5.1.1(v) + GDPR Article 17 uyumlu silme akışının
//  görsel/duygusal "geri kazanma" katmanıdır — kullanıcıyı sakince düşünmeye
//  iter, hemen silmez. Yazılı SİL onayı ikinci güvenlik kapısıdır.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

class DeleteAccountScreen extends StatelessWidget {
  /// "QuAlsar'dan Ayrıl" butonuna basıldıktan sonra çağrılır (önce yazılı
  /// SİL onayı sorulur, sonra cascade silme akışı yürütülür).
  final Future<void> Function() onConfirmDelete;
  const DeleteAccountScreen({super.key, required this.onConfirmDelete});

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: ink, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Hesabı sil'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ink,
            )),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text('Ayrılmak istediğinizden emin misiniz?'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: ink,
                          height: 1.25,
                          letterSpacing: -0.3,
                        )),
                    const SizedBox(height: 16),
                    Text(
                      "QuAlsar'dan ayrılırsanız kişisel bilgileriniz, çalışma geçmişiniz, ödevleriniz, davet kayıtlarınız ve premium hakkınız dahil hesabınızla ilgili tüm bilgiler kalıcı olarak silinir. Aynı hesapla tekrar oturum açamayacağınızı lütfen unutmayın."
                          .tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        color: muted,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Bizi şimdi terk ederseniz sizi özleyeceğiz. QuAlsar'dan çıkmak istediğinizden emin misiniz?"
                          .tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        color: muted,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(child: _SadCharacter()),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Hâlâ vazgeçebilirsin 💛'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            // ── Alt buton ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6A00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final confirmed =
                        await _showFinalConfirmation(context);
                    if (!confirmed) return;
                    // Çağıran tarafa devret — _performAccountDeletion orada.
                    await onConfirmDelete();
                    if (navigator.canPop()) navigator.pop();
                  },
                  child: Text("QuAlsar'dan Ayrıl".tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// İkinci güvenlik kapısı — kullanıcıdan "SİL" yazmasını ister.
  Future<bool> _showFinalConfirmation(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setS) {
        final canDelete = ctrl.text.trim().toUpperCase() == 'SİL';
        return AlertDialog(
          backgroundColor: AppPalette.card(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 8),
            Text('Son onay'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                )),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bu işlem geri alınamaz. Devam etmek için aşağıya "SİL" yaz:'
                    .tr(),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppPalette.textPrimary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.characters,
                autofocus: true,
                onChanged: (_) => setS(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'SİL',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Vazgeç'.tr()),
            ),
            ElevatedButton(
              onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              child: Text('Sil'.tr()),
            ),
          ],
        );
      }),
    );
    return ok == true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _SadCharacter — QandA'daki "ağlayan turuncu saçlı kız"a benzer minimal
//  CustomPaint illüstrasyon. Asset gerektirmez, tek widget içinde tutulur.
// ═══════════════════════════════════════════════════════════════════════════
class _SadCharacter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200, height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(200, 200),
            painter: _SadGirlPainter(),
          ),
          // Yüz ifadesi — büyük emoji'lerle gözyaşı detayı
          Positioned(
            top: 60,
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('💧',
                        style: TextStyle(fontSize: 18)),
                    SizedBox(width: 22),
                    Text('💧',
                        style: TextStyle(fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('︵',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SadGirlPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Saç (turuncu) — büyük serbest form blob
    final hairPaint = Paint()..color = const Color(0xFFFF6A00);
    final hair = Path()
      ..moveTo(cx - 70, h * 0.30)
      ..quadraticBezierTo(cx - 88, h * 0.55, cx - 76, h * 0.78)
      ..quadraticBezierTo(cx - 56, h * 0.84, cx - 30, h * 0.78)
      ..lineTo(cx - 30, h * 0.42)
      ..quadraticBezierTo(cx, h * 0.30, cx + 30, h * 0.42)
      ..lineTo(cx + 30, h * 0.78)
      ..quadraticBezierTo(cx + 60, h * 0.84, cx + 80, h * 0.74)
      ..quadraticBezierTo(cx + 92, h * 0.50, cx + 70, h * 0.28)
      ..quadraticBezierTo(cx, h * 0.10, cx - 70, h * 0.30)
      ..close();
    canvas.drawPath(hair, hairPaint);

    // Yüz (ten rengi)
    final facePaint = Paint()..color = const Color(0xFFFFE0BD);
    canvas.drawCircle(Offset(cx, h * 0.50), 44, facePaint);

    // Gövde / omuz (beyaz tişört)
    final shirtPaint = Paint()..color = Colors.white;
    final shirt = Path()
      ..moveTo(cx - 60, h * 0.85)
      ..lineTo(cx - 60, h * 0.95)
      ..lineTo(cx + 60, h * 0.95)
      ..lineTo(cx + 60, h * 0.85)
      ..quadraticBezierTo(cx + 30, h * 0.78, cx + 20, h * 0.74)
      ..lineTo(cx - 20, h * 0.74)
      ..quadraticBezierTo(cx - 30, h * 0.78, cx - 60, h * 0.85)
      ..close();
    canvas.drawPath(shirt, shirtPaint);

    // Tişörtün kenar çizgisi (hafif gri)
    final shirtStroke = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(shirt, shirtStroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
