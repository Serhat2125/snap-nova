// ═══════════════════════════════════════════════════════════════════════════
//  ForceUpdateGate — zorunlu güncelleme + bakım modu kapısı.
//
//  Neden: Firestore kuralları / Cloud Function'lar değiştikçe ESKİ sürüm
//  APK'lar sessizce kırılıyordu ve kullanıcıyı güncellemeye zorlamanın
//  hiçbir yolu yoktu. Bu kapı MaterialApp builder Stack'inin EN ÜSTÜNDE
//  durur (sidebar + ebeveyn kilidi dahil her şeyi örter):
//
//   • `min_supported_build` (RemoteConfig / config/runtime dokümanı):
//     cihazın build numarası (pubspec `version: x.y.z+N` → N) bundan
//     küçükse tam ekran "Yeni sürüm gerekli" + mağaza butonu gösterilir.
//   • `maintenance_mode: true` → "Bakımdayız" ekranı + Tekrar Dene.
//
//  Değerler cache-first gelir; fetch tamamlanınca RemoteConfigService
//  notifyListeners atar, kapı kendini yeniden değerlendirir. Yani karar
//  için açılış BEKLETİLMEZ — eski istemci en geç fetch bittiğinde kilitlenir.
//
//  Kullanım (main.dart): Stack children'ının SONUNA `ForceUpdateGate()`.
//  Yayın notu: Firestore `config/runtime` dokümanına
//  `{min_supported_build: N}` yazmak N'den eski tüm sürümleri kilitler.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/remote_config_service.dart';
import '../services/runtime_translator.dart';

class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({super.key});

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate> {
  int _build = 0; // 0 = henüz okunamadı → kilitleme YAPMA (asla yanlış kilit)
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    RemoteConfigService.instance.addListener(_recheck);
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _build = int.tryParse(info.buildNumber) ?? 0);
    }).catchError((_) {/* build okunamadı → kapı devre dışı kalır */});
  }

  @override
  void dispose() {
    RemoteConfigService.instance.removeListener(_recheck);
    super.dispose();
  }

  void _recheck() {
    if (mounted) setState(() {});
  }

  bool get _maintenance =>
      RemoteConfigService.instance.getBool('maintenance_mode');

  bool get _needsUpdate {
    if (_build <= 0) return false; // build bilinmiyorsa asla kilitleme
    final min = RemoteConfigService.instance.getInt('min_supported_build');
    return min > 0 && _build < min;
  }

  Future<void> _openStore() async {
    final cfg = RemoteConfigService.instance;
    final url = defaultTargetPlatform == TargetPlatform.iOS
        ? cfg.getString('store_url_ios')
        : cfg.getString('store_url_android');
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {/* mağaza açılamadı — kullanıcı manuel gider */}
  }

  Future<void> _retryMaintenance() async {
    setState(() => _retrying = true);
    await RemoteConfigService.instance.refresh();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_needsUpdate) {
      return _blockingScreen(
        emoji: '🚀',
        title: 'Yeni sürüm gerekli'.tr(),
        body:
            'QuAlsar\'ın bu sürümü artık desteklenmiyor. Devam etmek için uygulamayı en yeni sürüme güncelle.'
                .tr(),
        buttonLabel: 'Şimdi Güncelle'.tr(),
        onPressed: _openStore,
      );
    }
    if (_maintenance) {
      return _blockingScreen(
        emoji: '🛠️',
        title: 'Kısa bir bakım molası'.tr(),
        body:
            'QuAlsar şu anda bakımda. Birkaç dakika sonra tekrar dener misin?'
                .tr(),
        buttonLabel: 'Tekrar Dene'.tr(),
        onPressed: _retrying ? null : _retryMaintenance,
        busy: _retrying,
      );
    }
    // Kilit yok — kapı görünmez, dokunuşları asla yutmaz.
    return const SizedBox.shrink();
  }

  Widget _blockingScreen({
    required String emoji,
    required String title,
    required String body,
    required String buttonLabel,
    required VoidCallback? onPressed,
    bool busy = false,
  }) {
    return Positioned.fill(
      child: Material(
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            buttonLabel,
                            style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
