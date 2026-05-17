// ═══════════════════════════════════════════════════════════════════════════════
//  LeagueLocationPicker — Ülke → (Eyalet) → Şehir 3 aşamalı seçici.
//
//  Akış:
//    1) Ülke listesi (LocationCatalog) — arama destekli
//    2) Ülke seçilince:
//       a) Eyalet listesi Gemini'den çekilir
//       b) Eyalet listesi BOŞ ise (üniter ülke) → doğrudan ülke şehirleri
//       c) Eyalet listesi DOLU ise (federasyon) → eyalet seç → eyaletin şehirleri
//    3) Şehir seçilince UserLocation döndürülür ve sheet kapanır.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/runtime_translator.dart';
import '../../theme/app_theme.dart';
import '../leaderboard/data/location_catalog.dart';
import '../leaderboard/domain/user_location.dart';
import 'league_city_resolver.dart';

class LeagueLocationPicker {
  static Future<UserLocation?> show(BuildContext context) {
    return showModalBottomSheet<UserLocation>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LeagueLocationPickerSheet(),
    );
  }
}

enum _Phase { country, subdivision, city }

class _LeagueLocationPickerSheet extends StatefulWidget {
  const _LeagueLocationPickerSheet();

  @override
  State<_LeagueLocationPickerSheet> createState() =>
      _LeagueLocationPickerSheetState();
}

class _LeagueLocationPickerSheetState
    extends State<_LeagueLocationPickerSheet> {
  _Phase _phase = _Phase.country;
  CountryEntry? _country;
  SubdivisionEntry? _state;

  String _query = '';
  final _ctrl = TextEditingController();

  // Async fetch sonuçları
  List<SubdivisionEntry>? _subs;
  List<CityEntry>? _cities;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Filtreleyiciler ────────────────────────────────────────────────────────
  List<CountryEntry> get _filteredCountries {
    if (_query.trim().isEmpty) return LocationCatalog.countries;
    final q = _query.trim().toLowerCase();
    return LocationCatalog.countries
        .where((c) => c.name.toLowerCase().contains(q))
        .toList();
  }

  List<SubdivisionEntry> get _filteredSubs {
    final list = _subs ?? const [];
    if (_query.trim().isEmpty) return list;
    final q = _query.trim().toLowerCase();
    return list.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  List<CityEntry> get _filteredCities {
    final list = _cities ?? const [];
    if (_query.trim().isEmpty) return list;
    final q = _query.trim().toLowerCase();
    return list.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  // ── Akış ────────────────────────────────────────────────────────────────────
  Future<void> _selectCountry(CountryEntry c) async {
    setState(() {
      _country = c;
      _query = '';
      _ctrl.clear();
      _busy = true;
      _subs = null;
      _cities = null;
    });

    // Federasyon mu kontrol et
    final subs = await LeagueCityResolver.resolveSubdivisions(
      countryCode: c.code,
      countryName: c.name,
    );
    if (!mounted) return;

    if (subs.isNotEmpty) {
      // Federasyon → eyalet seçim aşamasına geç
      setState(() {
        _phase = _Phase.subdivision;
        _subs = subs;
        _busy = false;
      });
    } else {
      // Üniter → doğrudan ülke geneli şehir
      final cities = await LeagueCityResolver.resolveCountryCities(
        countryCode: c.code,
        countryName: c.name,
      );
      if (!mounted) return;
      setState(() {
        _phase = _Phase.city;
        _cities = cities;
        _busy = false;
      });
    }
  }

  Future<void> _selectSubdivision(SubdivisionEntry s) async {
    setState(() {
      _state = s;
      _query = '';
      _ctrl.clear();
      _busy = true;
      _cities = null;
    });

    final cities = await LeagueCityResolver.resolveCitiesForState(
      countryCode: _country!.code,
      countryName: _country!.name,
      stateCode: s.code,
      stateName: s.name,
    );
    if (!mounted) return;
    setState(() {
      _phase = _Phase.city;
      _cities = cities;
      _busy = false;
    });
  }

  void _selectCity(CityEntry city) {
    final c = _country!;
    final loc = UserLocation(
      country: c.name,
      countryCode: c.code,
      city: city.name,
      cityCode: city.code,
    );
    Navigator.of(context).pop(loc);
  }

  void _back() {
    setState(() {
      _query = '';
      _ctrl.clear();
      switch (_phase) {
        case _Phase.country:
          break;
        case _Phase.subdivision:
          _phase = _Phase.country;
          _country = null;
          _subs = null;
          break;
        case _Phase.city:
          if (_state != null) {
            // Federasyondan geliyorsak eyalete dön
            _phase = _Phase.subdivision;
            _state = null;
            _cities = null;
          } else {
            // Üniter ülke → ülke listesine dön
            _phase = _Phase.country;
            _country = null;
            _cities = null;
          }
          break;
      }
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF6A00);
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: AppPalette.card(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.border(ctx),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Başlık + breadcrumb
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Row(
                children: [
                  if (_phase != _Phase.country)
                    IconButton(
                      onPressed: _back,
                      icon: Icon(Icons.arrow_back_rounded,
                          color: AppPalette.textPrimary(ctx)),
                      tooltip: 'Geri'.tr(),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.public_rounded,
                          color: accent, size: 22),
                    ),
                  Expanded(child: _buildHeaderText(ctx)),
                ],
              ),
            ),
            // Arama
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _ctrl,
                onChanged: (v) => setState(() => _query = v),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppPalette.textPrimary(ctx),
                ),
                decoration: InputDecoration(
                  hintText: _hintText().tr(),
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppPalette.textSecondary(ctx),
                  ),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: AppPalette.textSecondary(ctx), size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: AppPalette.cardMuted(ctx),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: AppPalette.border(ctx), width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: AppPalette.border(ctx), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: accent, width: 1.6),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildList(scrollCtrl)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderText(BuildContext ctx) {
    String title;
    String? sub;
    switch (_phase) {
      case _Phase.country:
        title = 'Ülke Seç'.tr();
        break;
      case _Phase.subdivision:
        title = 'Eyalet Seç'.tr();
        sub = '${_country!.flag} ${_country!.name}';
        break;
      case _Phase.city:
        title = 'Şehir Seç'.tr();
        sub = _state != null
            ? '${_country!.flag} ${_country!.name} › ${_state!.name}'
            : '${_country!.flag} ${_country!.name}';
        break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.fraunces(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppPalette.textPrimary(ctx),
            letterSpacing: -0.2,
          ),
        ),
        if (sub != null)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppPalette.textSecondary(ctx),
            ),
          ),
      ],
    );
  }

  String _hintText() {
    switch (_phase) {
      case _Phase.country:
        return 'Ülke ara...';
      case _Phase.subdivision:
        return 'Eyalet ara...';
      case _Phase.city:
        return 'Şehir ara...';
    }
  }

  Widget _buildList(ScrollController scrollCtrl) {
    if (_busy) return _buildLoading();
    switch (_phase) {
      case _Phase.country:
        return _buildCountryList(scrollCtrl);
      case _Phase.subdivision:
        return _buildSubList(scrollCtrl);
      case _Phase.city:
        return _buildCityList(scrollCtrl);
    }
  }

  Widget _buildCountryList(ScrollController scrollCtrl) {
    final list = _filteredCountries;
    if (list.isEmpty) return _buildEmpty();
    return ListView.separated(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        final c = list[i];
        return _LocTile(
          leading: c.flag,
          label: c.name,
          onTap: () => _selectCountry(c),
        );
      },
    );
  }

  Widget _buildSubList(ScrollController scrollCtrl) {
    final list = _filteredSubs;
    if (list.isEmpty) return _buildEmpty();
    return ListView.separated(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        final s = list[i];
        return _LocTile(
          leading: '🗺️',
          label: s.name,
          onTap: () => _selectSubdivision(s),
        );
      },
    );
  }

  Widget _buildCityList(ScrollController scrollCtrl) {
    final list = _filteredCities;
    if (list.isEmpty) return _buildEmpty();
    return ListView.separated(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        final c = list[i];
        return _LocTile(
          leading: '🏙️',
          label: c.name,
          onTap: () => _selectCity(c),
        );
      },
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppPalette.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _phase == _Phase.subdivision
                  ? 'Eyaletler yükleniyor…'.tr()
                  : 'Şehirler yükleniyor…'.tr(),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppPalette.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Sonuç bulunamadı'.tr(),
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppPalette.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

class _LocTile extends StatelessWidget {
  final String leading;
  final String label;
  final VoidCallback onTap;
  const _LocTile({
    required this.leading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.border(context), width: 1),
        ),
        child: Row(
          children: [
            Text(leading, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context),
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppPalette.textSecondary(context), size: 20),
          ],
        ),
      ),
    );
  }
}
