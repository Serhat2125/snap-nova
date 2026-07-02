// ═══════════════════════════════════════════════════════════════════════════
//  TeacherCurriculumSelectScreen — Öğretmen ilk girişte not sistemini /
//  müfredatını seçer. Seçim AccountService.gradingCountry'e kaydedilir ve
//  tüm not ekranı (skala, kategoriler, hesaplama) buna göre şekillenir.
//
//  TeacherShellScreen açılışında gradingCountry null ise otomatik açılır.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/account_service.dart';
import '../services/grading_config.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherCurriculumSelectScreen extends StatefulWidget {
  /// Onboarding akışında zorunlu (geri tuşu kapalı); profilden değiştirmede
  /// serbest. Varsayılan: zorunlu.
  final bool mandatory;
  const TeacherCurriculumSelectScreen({super.key, this.mandatory = true});

  @override
  State<TeacherCurriculumSelectScreen> createState() =>
      _TeacherCurriculumSelectScreenState();
}

class _TeacherCurriculumSelectScreenState
    extends State<TeacherCurriculumSelectScreen> {
  String? _selectedProfile;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Mevcut seçim varsa onu işaretle — profileId varsa (aynı ülkede birden
    // fazla profil olabildiği için, ör. US → us/gpa4) o önceliklidir.
    final pid = AccountService.instance.gradingProfile;
    final cc = AccountService.instance.gradingCountry;
    if (pid != null && pid.isNotEmpty) {
      _selectedProfile = pid;
    } else if (cc != null) {
      _selectedProfile = GradingConfigService.forCountry(cc).profileId;
    }
  }

  String _calcDesc(CurriculumConfig c) {
    switch (c.calc) {
      case CalcModel.arithmetic:
        return 'Aritmetik ortalama'.tr();
      case CalcModel.totalPoints:
        return 'Puan toplamı'.tr();
      case CalcModel.weighted:
        return c.weightMode == WeightMode.perCategory
            ? 'Kategori ağırlıklı'.tr()
            : 'Not ağırlıklı (katsayı)'.tr();
    }
  }

  Future<void> _confirm() async {
    final id = _selectedProfile;
    if (id == null || _saving) return;
    setState(() => _saving = true);
    final cfg = GradingConfigService.byProfile(id);
    await AccountService.instance.setGradingCountry(cfg.countryCode);
    await AccountService.instance.setGradingProfile(cfg.profileId);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final profiles = GradingConfigService.pickerProfiles;

    return PopScope(
      canPop: !widget.mandatory,
      child: Scaffold(
        backgroundColor: AppPalette.bg(context),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(context),
          elevation: 0,
          automaticallyImplyLeading: !widget.mandatory,
          title: Text('Not Sistemi'.tr(),
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800, color: ink, fontSize: 17)),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Ülkenin/müfredatının not sistemini seç. Not giriş ekranı '
                  'buna göre (skala, kategoriler, hesaplama) otomatik şekillenir.'
                      .tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, height: 1.4, color: muted),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: profiles.length,
                  itemBuilder: (_, i) {
                    final c = profiles[i];
                    final sel = _selectedProfile == c.profileId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedProfile = c.profileId),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: sel
                                ? _kBrand.withValues(alpha: 0.10)
                                : AppPalette.card(context),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: sel
                                  ? _kBrand
                                  : AppPalette.border(context),
                              width: sel ? 1.6 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(c.flag,
                                  style: const TextStyle(fontSize: 28)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(c.label,
                                        style: GoogleFonts.poppins(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: sel ? _kBrand : ink,
                                        )),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${_calcDesc(c)}  ·  '
                                      '${'Skala'.tr()} ${GradeCalculator.scaleLabel(c)}'
                                      '${c.showPercentageSelector ? '  ·  %' : ''}',
                                      style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: muted),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                sel
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked,
                                color:
                                    sel ? _kBrand : AppPalette.border(context),
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      disabledBackgroundColor: const Color(0xFFE5E7EB),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _selectedProfile == null ? null : _confirm,
                    child: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white))
                        : Text('Devam Et'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 14, fontWeight: FontWeight.w800,
                              color: _selectedProfile == null
                                  ? const Color(0xFF9CA3AF)
                                  : Colors.white,
                            )),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
