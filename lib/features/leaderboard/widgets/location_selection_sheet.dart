import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/runtime_translator.dart';
import '../data/location_catalog.dart';
import '../domain/user_location.dart';
import '../providers/location_controller.dart';

import '../../../theme/app_theme.dart';
/// Konum onay / düzenleme paneli.
///
/// İki mod:
///   1) **Onay modu** (default): IP'den otomatik tespit edilen konum
///      kart üzerinde gösterilir. "Evet, Doğru" → Firestore'a yazıp
///      `onConfirm` callback'ini tetikler. "Bilgileri Değiştir" → 2. moda.
///   2) **Düzenleme modu**: ülke + şehir dropdown'ları. "Onayla" ile
///      seçim Firestore'a kaydedilir.
///
/// Modal bottom sheet olarak `LocationSelectionSheet.show(...)` ile açılır.
/// Tüm state Riverpod controller'ında; widget StatelessWidget.
class LocationSelectionSheet extends ConsumerWidget {
  /// Firestore'a yazılacak user ID. Null ise sadece [onConfirm] tetiklenir
  /// (anonim akış).
  final String? userId;

  /// Onay başarılı olduğunda final UserLocation ile çağrılır. Çağıran
  /// taraf burada yarışma akışına devam eder veya sheet'i kapatır.
  final ValueChanged<UserLocation> onConfirm;

  const LocationSelectionSheet({
    super.key,
    this.userId,
    required this.onConfirm,
  });

  /// Modal bottom sheet olarak açar — yarışma sayfasından çağrılan tek nokta.
  /// Geri dönüş: sheet kapanınca tamamlanır.
  static Future<void> show(
    BuildContext context, {
    String? userId,
    required ValueChanged<UserLocation> onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false, // Kullanıcı onaylamadan kapatamasın
      enableDrag: false,
      builder: (_) => LocationSelectionSheet(
        userId: userId,
        onConfirm: onConfirm,
      ),
    );
  }

  static const _navy = Color(0xFF1E3A8A);
  static const _accent = Color(0xFF2D5BFF);
  static const _navySoft = Color(0xFFEFF4FF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(locationControllerProvider(userId));
    final ctrl = ref.read(locationControllerProvider(userId).notifier);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle göstergesi
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.border(context),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            SizedBox(height: 18),
            // Başlık
            Row(
              children: [
                Text('📍', style: TextStyle(fontSize: 26)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Konumunu Onayla'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              'Sıralamaya doğru ülke ve şehirde dahil olabilmen için konumunu doğrulamamız gerekiyor.'
                  .tr(),
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
            SizedBox(height: 18),
            if (state.isLoading && state.detected == null)
              _buildLoading()
            else if (state.isEditing)
              _buildEditMode(context, ref, state, ctrl)
            else
              _buildConfirmMode(context, ref, state, ctrl),
            if (state.error != null) ...[
              SizedBox(height: 12),
              _buildErrorBanner(state.error!),
            ],
          ],
        ),
      ),
    );
  }

  // ── Loading ─────────────────────────────────────────────────────────────
  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: _navy),
          ),
          SizedBox(height: 10),
          Text(
            'Konumun tespit ediliyor…'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF707380),
            ),
          ),
        ],
      ),
    );
  }

  // ── ONAY MODU: tespit edilen konum kartı + 2 buton ──────────────────────
  Widget _buildConfirmMode(
    BuildContext context,
    WidgetRef ref,
    LocationState state,
    LocationController ctrl,
  ) {
    final loc = state.detected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Detection card
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: _navySoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _navy.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seni şurada fark ettik'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textSecondary(context),
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Text(loc.countryFlag,
                      style: TextStyle(fontSize: 32)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.country,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        Text(
                          loc.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 18),
        // Onay butonu — büyük, aksiyona davet edici
        ElevatedButton.icon(
          onPressed: state.isLoading
              ? null
              : () => ctrl.confirm(onConfirm: (loc) {
                    Navigator.of(context).maybePop();
                    onConfirm(loc);
                  }),
          style: ElevatedButton.styleFrom(
            backgroundColor: _navy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 2,
          ),
          icon: state.isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(Icons.check_circle_rounded, size: 18),
          label: Text(
            'Evet, Doğru'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        SizedBox(height: 8),
        // İkincil: Düzenle
        TextButton.icon(
          onPressed: state.isLoading ? null : ctrl.enterEditMode,
          style: TextButton.styleFrom(
            foregroundColor: _accent,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          icon: Icon(Icons.edit_location_alt_rounded, size: 16),
          label: Text(
            'Bilgileri Değiştir'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ── DÜZENLEME MODU: ülke + şehir dropdown ──────────────────────────────
  Widget _buildEditMode(
    BuildContext context,
    WidgetRef ref,
    LocationState state,
    LocationController ctrl,
  ) {
    final draft = state.draft;
    final cityList = draft != null
        ? LocationCatalog.citiesOf(draft.countryCode)
        : const <CityEntry>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ülke'.tr(),
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppPalette.textSecondary(context),
            letterSpacing: 0.4,
          ),
        ),
        SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: draft?.countryCode,
          isExpanded: true,
          decoration: _inputDecoration(),
          items: [
            for (final c in LocationCatalog.countries)
              DropdownMenuItem(
                value: c.code,
                child: Row(
                  children: [
                    Text(c.flag, style: TextStyle(fontSize: 18)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) ctrl.selectCountry(v);
          },
        ),
        SizedBox(height: 14),
        Text(
          'Şehir'.tr(),
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppPalette.textSecondary(context),
            letterSpacing: 0.4,
          ),
        ),
        SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: draft?.cityCode.isNotEmpty == true
              ? draft!.cityCode
              : null,
          isExpanded: true,
          decoration: _inputDecoration(
            hint: cityList.isEmpty
                ? 'Önce ülke seç'.tr()
                : 'Şehir seç'.tr(),
          ),
          items: [
            for (final city in cityList)
              DropdownMenuItem(
                value: city.code,
                child: Text(
                  city.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
          onChanged: cityList.isEmpty
              ? null
              : (v) {
                  if (v != null) ctrl.selectCity(v);
                },
        ),
        SizedBox(height: 18),
        // Onayla butonu
        ElevatedButton.icon(
          onPressed: (state.isLoading ||
                  draft == null ||
                  draft.cityCode.isEmpty)
              ? null
              : () => ctrl.confirm(onConfirm: (loc) {
                    Navigator.of(context).maybePop();
                    onConfirm(loc);
                  }),
          style: ElevatedButton.styleFrom(
            backgroundColor: _navy,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _navy.withValues(alpha: 0.35),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 2,
          ),
          icon: state.isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(Icons.check_circle_rounded, size: 18),
          label: Text(
            'Onayla'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        SizedBox(height: 6),
        TextButton(
          onPressed: state.isLoading ? null : ctrl.cancelEdit,
          child: Text(
            'Vazgeç'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppPalette.textSecondary(context),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Color(0xFFEEEEEE),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            BorderSide(color: Colors.black.withValues(alpha: 0.10)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            BorderSide(color: Colors.black.withValues(alpha: 0.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _accent, width: 1.4),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 16, color: Color(0xFFB91C1C)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF991B1B),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
