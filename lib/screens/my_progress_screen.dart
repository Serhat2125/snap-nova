// ═══════════════════════════════════════════════════════════════════════════
//  MyProgressScreen — "Gelişim Paneli" / öğrencinin çalışma istatistikleri.
//
//  Ebeveyn/öğretmen tarafından da okunabildiği için metinler öğrenci adıyla
//  yazılır (birinci tekil değil). Veri MEVCUT kullanıcının kendi verisidir.
//
//  Üstte 6 kategori sekmesi (2 sıra × 3):
//    Konu Özetleri · Test Soruları · Foto Soru
//    3D Eğitim · Sıralama Yarışması · Pomodoro
//  Sekmeye basınca o kategorinin bu HAFTASI (Pzt→Paz) gün gün dökülür:
//  günlük süre grafiği + ders dağılımı + (test) doğru/yanlış + gün listesi.
//
//  Premium GEREKMEZ; sadece istatistik gösterir, premium tüketmez.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:math' show pi;
import 'dart:ui' show ImageFilter;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/education_models.dart';
import '../services/analytics.dart';
import '../services/parent_link_service.dart';
import 'parent_child_homeworks_screen.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'academic_planner.dart'
    show
        readLocalActivityLast7Days,
        readLocalWeekEntries,
        readLocalActivityLastNDays,
        readLocalEntriesLastNDays;

/// Kategori tanımı — sekme + filtre tipi.
class _ProgressCat {
  final String key;
  final String type; // _ActivityStore type ('özet','soru','3d','yarisma',...)
  final String label;
  final IconData icon;
  final Color color;
  final bool isCount; // true → süre değil, adet (foto soru)
  const _ProgressCat(
      this.key, this.type, this.label, this.icon, this.color,
      {this.isCount = false});
}

const _cats = <_ProgressCat>[
  _ProgressCat('summary', 'özet', 'Konu Özetleri',
      Icons.auto_stories_rounded, Color(0xFF2563EB)),
  _ProgressCat('test', 'soru', 'Test Soruları',
      Icons.quiz_rounded, Color(0xFFFF6A00)),
  _ProgressCat('photo', 'foto', 'Foto Soru',
      Icons.camera_alt_rounded, Color(0xFF3B82F6), isCount: true),
  _ProgressCat('edu3d', '3d', '3D Eğitim',
      Icons.view_in_ar_rounded, Color(0xFF06B6D4)),
  _ProgressCat('contest', 'yarisma', 'Sıralama Yarışması',
      Icons.emoji_events_rounded, Color(0xFF7C3AED)),
  _ProgressCat('pomodoro', 'pomodoro', 'Pomodoro',
      Icons.rocket_launch_rounded, Color(0xFFFF6A3C)),
];

const _weekdayLabels = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

class MyProgressScreen extends StatefulWidget {
  const MyProgressScreen({super.key});

  @override
  State<MyProgressScreen> createState() => _MyProgressScreenState();
}

class _MyProgressScreenState extends State<MyProgressScreen> {
  // _activity her atandığında türetilmiş cache'ler geçersiz kılınır
  // (getter'lar build'de onlarca kez çağrıldığından her seferinde yeniden
  //  inşa pahalıydı).
  List<StudentActivityModel> _activityRaw = [];
  List<StudentActivityModel> get _activity => _activityRaw;
  set _activity(List<StudentActivityModel> v) {
    _activityRaw = v;
    _activityByDateCache = null;
  }

  Map<String, StudentActivityModel>? _activityByDateCache;
  // Foto var mı? Senkron existsSync() build'den çıkarıldı; profil yüklenince
  // / foto değişince bir kez hesaplanır.
  final Map<int, bool> _photoExists = {};

  Map<String, dynamic> _baseStats = const {};
  List<Map<String, dynamic>> _weekEntries = []; // {dateKey,weekday,type,subject,topic,sec}
  // Aylık rapor — son 30 gün
  List<StudentActivityModel> _monthActivity = [];
  List<Map<String, dynamic>> _monthEntries = [];
  static const int _monthDays = 30;
  String _selected = 'summary';
  bool _loading = true;

  // ── Çocuk profilleri (dinamik sayı; isim/foto/durum düzenlenebilir) ─────
  int _childCount = 2; // toplam çocuk sekmesi sayısı (1..6)
  int _childSlot = 1; // hangi çocuk seçili
  bool _profileExpanded = false; // seçili profil genişletilmiş mi
  final Map<int, String> _names = {1: '', 2: ''};
  final Map<int, String> _photos = {1: '', 2: ''};
  final Map<int, String> _statuses = {1: '', 2: ''};
  // Uzaktan bağlama: slot → bağlı çocuğun uid'i ('' = bağlı değil).
  final Map<int, String> _childUids = {1: '', 2: ''};
  bool _pending = false; // seçili slot bağlı ama çocuk henüz onaylamadı
  bool _demo = false; // gerçek veri yok → örnek (demo) veri gösteriliyor
  bool _loadError = false; // bağlı çocuk verisi okunamadı (offline/izin)

  // Renk paleti — Kütüphanem "Renk Seç" ile aynı renk seti.
  // Renkler paletten SÜRÜKLENİP çerçeveli öğelere (arka plan, çocuk
  // sekmeleri, kategori kutuları, özet grafikleri) bırakılır.
  // _ov: öğe-id → renk override. 'bg' = sayfa arka planı.
  bool _showPalette = false;
  final Map<String, Color> _ov = {};
  // Hedef-bazlı renklendirme: önce hedef seç, sonra renge bas.
  // Hedefler: bg(Arka plan) · header(Başlık) · labels(Etiketler) ·
  //           infopanel(Bilgi paneli) · titleText(Başlık yazısı) · bodyText(Yazılar)
  String _colorTarget = 'bg';
  double _paletteTop = 8; // taşınabilir palet dikey konumu (✛ ile)
  final GlobalKey _shotKey = GlobalKey(); // ekran görüntüsü (paylaşım) için

  // Ekranın görüntüsünü alıp paylaşım sayfasını açar (WhatsApp/Instagram/...).
  Future<void> _shareScreenshot() async {
    try {
      // Mevcut çerçeve bitmeden toImage() çağrılırsa hata verir — bir frame bekle.
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;

      final boundary =
          _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) {
        _snack('Ekran henüz hazır değil, tekrar dene.'.tr());
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        _snack('Görüntü oluşturulamadı.'.tr());
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/gelisim_paneli.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '$_studentName — ${"Gelişim Paneli".tr()} 📈',
      );
    } catch (e) {
      if (mounted) _snack('${"Paylaşım başarısız".tr()}: $e');
    }
  }

  Color? _ovColor(String id) => _ov[id];
  // Çerçeve çizgisi rengi — aydınlıkta net siyah, karanlıkta yumuşak gri.
  Color _frame(BuildContext c) =>
      AppPalette.isDark(c) ? const Color(0xFF4A4A4A) : Colors.black;

  // Derse özgü renk — isim karmasından sabit renk dizisi.
  static const _subjPalette = [
    Color(0xFF2563EB), Color(0xFFDB2777), Color(0xFF10B981),
    Color(0xFFFF6A00), Color(0xFF7C3AED), Color(0xFFFBBF24),
    Color(0xFF22D3EE), Color(0xFFEF4444), Color(0xFF92400E),
    Color(0xFF6B7280),
  ];
  Color _subjectColor(String name) =>
      _subjPalette[name.hashCode.abs() % _subjPalette.length];
  // 3 karakterlik kısaltma: "Matematik" → "Mat"
  String _subjAbbr(String name) {
    final t = name.trim();
    return t.isEmpty ? '' : t.substring(0, t.length.clamp(0, 3));
  }
  Color _titleColor(BuildContext c) =>
      _ovColor('titleText') ?? AppPalette.textPrimary(c);
  Color _bodyColor(BuildContext c) =>
      _ovColor('bodyText') ?? AppPalette.textSecondary(c);

  // Öncelik: öğreye özel (sürükle) override → hedef (tıkla) override → default.
  Color _resolve(List<String> ids, Color def) {
    for (final id in ids) {
      final c = _ov[id];
      if (c != null) return c;
    }
    return def;
  }

  // Renk bırakma hedefi — sürüklenen renk bırakılınca o öğenin rengini ayarlar.
  // Üzerine renk gelince turuncu vurgu çerçevesi belirir.
  Widget _drop(String id, Widget child, {double radius = 14}) {
    return DragTarget<Color>(
      onAcceptWithDetails: (d) => _setOv(id, d.data),
      builder: (ctx, cand, rej) {
        if (cand.isEmpty) return child;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFFFF6A00), width: 2.5),
          ),
          child: child,
        );
      },
    );
  }
  static const _palette = <Color>[
    Colors.white, Color(0xFFF3F4F6), Color(0xFFD1D5DB), Color(0xFF9CA3AF),
    Color(0xFF0F172A), Color(0xFFFFEFD5), Color(0xFFFFD1DC), Color(0xFFFCA5A5),
    Color(0xFFFF6A00), Color(0xFFC8102E), Color(0xFFDB2777), Color(0xFFFBBF24),
    Color(0xFFDCFCE7), Color(0xFF86EFAC), Color(0xFF10B981), Color(0xFFE0F2FE),
    Color(0xFF22D3EE), Color(0xFF2563EB), Color(0xFFE9D5FF), Color(0xFFA855F7),
    Color(0xFF7C3AED), Color(0xFFF5F5DC), Color(0xFFD4A373), Color(0xFF92400E),
  ];

  @override
  void initState() {
    super.initState();
    Analytics.logFeatureOpen('parent_panel');
    _load();
  }

  Future<void> _loadProfiles() async {
    final p = await SharedPreferences.getInstance();
    _childCount = (p.getInt('progress_child_count') ?? 2).clamp(1, 6);
    if (_childSlot > _childCount) _childSlot = _childCount;
    _names.clear();
    _photos.clear();
    _statuses.clear();
    _childUids.clear();
    for (int n = 1; n <= _childCount; n++) {
      _names[n] = p.getString('progress_child_${n}_name') ?? '';
      _photos[n] = p.getString('progress_child_${n}_photo') ?? '';
      _statuses[n] = p.getString('progress_child_${n}_status') ?? '';
      _childUids[n] = p.getString('progress_child_${n}_uid') ?? '';
    }
    _refreshPhotoExists();
    // Renk override'ları (öğe-id → argb int) JSON olarak saklanır.
    _ov.clear();
    final raw = p.getString('progress_color_ov');
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        m.forEach((k, v) {
          if (v is num) _ov[k] = Color(v.toInt());
        });
      } catch (_) {}
    }
  }

  Future<void> _saveOv() async {
    final p = await SharedPreferences.getInstance();
    if (_ov.isEmpty) {
      await p.remove('progress_color_ov');
    } else {
      final m = <String, int>{};
      _ov.forEach((k, c) => m[k] = c.toARGB32());
      await p.setString('progress_color_ov', jsonEncode(m));
    }
  }

  void _setOv(String id, Color c) {
    setState(() => _ov[id] = c);
    _saveOv();
  }

  void _clearOv() {
    setState(() => _ov.clear());
    _saveOv();
  }

  Future<void> _load() async {
    // Hiçbir hata _loading'i sonsuz true bırakmasın — panel her durumda açılır.
    try {
      await _loadProfiles();
      await _loadForSlot(_childSlot);
    } catch (e) {
      debugPrint('[Progress] load fail: $e');
      if (mounted) {
        _injectDemo();
        setState(() {
          _demo = true;
          _pending = false;
          _loading = false;
        });
      }
    }
  }

  // Seçili slot'un verisini yükler.
  //  • Bağlı çocuk (aktif)  → UZAKTAN gerçek veri
  //  • Bağlı ama onaysız    → _pending (onay bekleniyor kartı)
  //  • Bağlı değil + veri yok → DEMO veri (panel canlı görünsün)
  Future<void> _loadForSlot(int slot) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = false;
      });
    }
    final ownUid = FirebaseAuth.instance.currentUser?.uid;
    final linkedUid = (_childUids[slot] ?? '').trim();
    final isSelf = linkedUid.isEmpty && slot == 1;

    // ── Bağlı çocuk yolu ──────────────────────────────────────────────
    if (linkedUid.isNotEmpty) {
      try {
        // Offline'da stream emit etmeyebilir → timeout ile kilitlenmeyi önle.
        final linked = await ParentLinkService.linkedChildrenStream().first
            .timeout(const Duration(seconds: 6),
                onTimeout: () => const <LinkedChild>[]);
        final active = linked.any((c) => c.uid == linkedUid && c.isActive);
        if (!active) {
          if (mounted) {
            setState(() {
              _pending = true;
              _demo = false;
              _activity = [];
              _weekEntries = [];
              _monthActivity = [];
              _monthEntries = [];
              _baseStats = {};
              _loading = false;
            });
          }
          return;
        }
        // Bağımsız okumalar paralel başlatılır (ardışık beklemeyi önle).
        // Her biri timeout'lu → ağ takılırsa panel sonsuz beklemez.
        const t = Duration(seconds: 8);
        final fCloud = ParentLinkService.readChild7DayActivity(linkedUid)
            .timeout(t, onTimeout: () => const []);
        final fStats = ParentLinkService.readChildStats(linkedUid)
            .timeout(t, onTimeout: () => const {});
        final fWeek = ParentLinkService.readChildWeekEntries(linkedUid)
            .timeout(t, onTimeout: () => const []);
        final fMAct = ParentLinkService.readChildActivityDays(linkedUid, _monthDays)
            .timeout(t, onTimeout: () => const []);
        final fMEnt = ParentLinkService.readChildEntriesDays(linkedUid, _monthDays)
            .timeout(t, onTimeout: () => const []);
        final cloud = await fCloud;
        final stats = await fStats;
        final week = await fWeek;
        final mAct = await fMAct;
        final mEnt = await fMEnt;
        if (!mounted) return;
        setState(() {
          _pending = false;
          _demo = false;
          _activity = cloud.map(StudentActivityModel.fromJson).toList();
          _weekEntries = week;
          _monthActivity = mAct.map(StudentActivityModel.fromJson).toList();
          _monthEntries = mEnt;
          _baseStats = stats;
          _loading = false;
        });
      } catch (_) {
        // Hata → ESKİ ÇOCUĞUN verisi kalmasın (gizlilik), hata durumu göster.
        if (mounted) {
          setState(() {
            _pending = false;
            _demo = false;
            _activity = [];
            _weekEntries = [];
            _monthActivity = [];
            _monthEntries = [];
            _baseStats = {};
            _loadError = true;
            _loading = false;
          });
        }
      }
      return;
    }

    // ── Bağlı değil → kendi verisi (slot 1) veya demo ─────────────────
    try {
      List<StudentActivityModel> acts = [];
      List<Map<String, dynamic>> week = [];
      List<StudentActivityModel> mAct = [];
      List<Map<String, dynamic>> mEnt = [];
      if (isSelf && ownUid != null) {
        // ── KÖK ÇÖZÜM: YEREL veri ağ gerektirmez → paneli ANINDA göster.
        //    Cloud okumaları (yavaş kısım) arka planda zenginleştirir.
        final fLocal = readLocalActivityLast7Days();
        final fWeek = readLocalWeekEntries();
        final fLocal30 = readLocalActivityLastNDays(_monthDays);
        final fEnt = readLocalEntriesLastNDays(_monthDays);
        final localWeek = await fLocal;
        week = await fWeek;
        final localMonth = await fLocal30;
        mEnt = await fEnt;
        acts = localWeek.map(StudentActivityModel.fromJson).toList();
        mAct = localMonth.map(StudentActivityModel.fromJson).toList();

        final localTotal = acts.fold<int>(
            0,
            (s, a) =>
                s + a.focusSeconds + a.totalAttempted + a.photoQuestionsSolved);
        final localHasData = week.isNotEmpty || localTotal > 0;

        // KÖK ÇÖZÜM: isSelf'te cloud HİÇ beklenmez. Yerel veri varsa gerçek
        // panel, yoksa demo — her durumda paneli ANINDA aç. Cloud (stats +
        // diğer cihaz kayıtları) arka planda gelince güncellenir.
        if (!mounted) return;
        if (localHasData) {
          setState(() {
            _demo = false;
            _pending = false;
            _activity = acts;
            _weekEntries = week;
            _monthActivity = mAct;
            _monthEntries = mEnt;
            _loading = false;
          });
        } else {
          _injectDemo();
          setState(() {
            _demo = true;
            _pending = false;
            _loading = false;
          });
        }
        unawaited(_enrichFromCloud(ownUid, localWeek, localMonth));
        return;
      }
      // isSelf değil + linkedUid boş (slot>1, bağlanmamış) → demo.
      _injectDemo();
      if (!mounted) return;
      setState(() {
        _demo = true;
        _pending = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      _injectDemo();
      setState(() {
        _demo = true;
        _pending = false;
        _loading = false;
      });
    }
  }

  // Panel yerel veriyle açıldıktan SONRA cloud'u arka planda merge eder
  // (streak/stats + farklı cihazdaki kayıtlar). Spinner göstermez; sessizce
  // günceller. Hata olursa yerel veri olduğu gibi kalır.
  Future<void> _enrichFromCloud(String uid,
      List<Map<String, dynamic>> localWeek,
      List<Map<String, dynamic>> localMonth) async {
    try {
      final fCloud = ParentLinkService.readChild7DayActivity(uid);
      final fCloud30 = ParentLinkService.readChildActivityDays(uid, _monthDays);
      final fStats = ParentLinkService.readChildStats(uid);
      final cloud = await fCloud;
      final cloud30 = await fCloud30;
      final stats = await fStats;
      if (!mounted || _childSlot != 1 || _childUids[1]?.isNotEmpty == true) {
        return; // bu sırada başka slota geçildiyse güncelleme.
      }
      final mergedWeek = _mergeActivity(cloud, localWeek)
          .map(StudentActivityModel.fromJson)
          .toList();
      final mergedMonth = _mergeActivity(cloud30, localMonth)
          .map(StudentActivityModel.fromJson)
          .toList();
      final realTotal = mergedWeek.fold<int>(
          0,
          (s, a) =>
              s + a.focusSeconds + a.totalAttempted + a.photoQuestionsSolved);
      final hasReal = realTotal > 0;
      setState(() {
        // Gerçek veri yoksa demo görünümü BOZMA (paneli boşaltma).
        if (hasReal) {
          _demo = false;
          _activity = mergedWeek;
          _monthActivity = mergedMonth;
        }
        if (stats.isNotEmpty) _baseStats = stats;
      });
    } catch (_) {/* yerel veri zaten gösterildi */}
  }

  // Demo veri — gerçek veri yokken panel "çalışan bir çocuk" gibi dolu görünür.
  // Bu haftanın günlerine (Pzt→Paz) hizalı sabit örnek dağılım.
  void _injectDemo() {
    final keys = _weekDateKeys;
    // [type, ders, konu, dakika]
    final plan = <List<List<Object>>>[
      [['özet', 'Matematik', 'Üslü Sayılar', 20],
       ['soru', 'Matematik', 'Üslü Sayılar', 15],
       ['pomodoro', 'Pomodoro', 'Odak Seansı', 25]],
      [['3d', 'Fen Bilimleri', 'Hücre', 12],
       ['soru', 'Fen Bilimleri', 'Hücre', 18]],
      [['özet', 'Türkçe', 'Paragraf', 16],
       ['yarisma', 'Bilgi Yarışı', 'Genel', 10]],
      [['soru', 'Matematik', 'Problemler', 22],
       ['pomodoro', 'Pomodoro', 'Odak Seansı', 25]],
      [['özet', 'Fen Bilimleri', 'Kuvvet ve Hareket', 14],
       ['3d', 'Fen Bilimleri', 'Kuvvet ve Hareket', 10]],
      [['yarisma', 'Bilgi Yarışı', 'Genel', 12],
       ['soru', 'Türkçe', 'Sözcükte Anlam', 8]],
      [['özet', 'Matematik', 'Oran Orantı', 10]],
    ];
    final correct = [8, 6, 7, 9, 5, 7, 4];
    final wrong = [2, 3, 2, 1, 2, 2, 1];
    final photo = [3, 1, 2, 0, 2, 1, 0];
    final summ = [1, 0, 1, 0, 1, 0, 1];

    final week = <Map<String, dynamic>>[];
    final acts = <StudentActivityModel>[];
    for (int i = 0; i < 7; i++) {
      final subs = <String, int>{};
      int focus = 0;
      String testSubj = '';
      for (final e in plan[i]) {
        final sec = (e[3] as int) * 60;
        focus += sec;
        final subj = e[1] as String;
        subs[subj] = (subs[subj] ?? 0) + sec;
        if (e[0] == 'soru' && testSubj.isEmpty) testSubj = subj;
        week.add({
          'dateKey': keys[i],
          'weekday': i + 1,
          'type': e[0] as String,
          'subject': subj,
          'topic': e[2] as String,
          'sec': sec,
        });
      }
      // Günün doğru/yanlışını o günkü test dersine ata (demo).
      final subC = <String, int>{};
      final subW = <String, int>{};
      if (testSubj.isNotEmpty) {
        subC[testSubj] = correct[i];
        subW[testSubj] = wrong[i];
      }
      acts.add(StudentActivityModel(
        dateKey: keys[i],
        focusSeconds: focus,
        subjectDurations: subs,
        correctAnswers: correct[i],
        wrongAnswers: wrong[i],
        blankAnswers: 1,
        photoQuestionsSolved: photo[i],
        summariesCreated: summ[i],
        testsSolved: 1,
        subjectCorrect: subC,
        subjectWrong: subW,
      ));
    }
    // ── Aylık demo (son 30 gün): haftalık deseni döngüyle çoğalt ─────────
    final now = DateTime.now();
    String keyFor(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final mEnt = <Map<String, dynamic>>[];
    final mAct = <StudentActivityModel>[];
    for (int d = _monthDays - 1; d >= 0; d--) {
      final day = DateTime(now.year, now.month, now.day - d);
      final dk = keyFor(day);
      final p = plan[day.weekday - 1]; // haftanın gününe göre desen
      final idx = day.weekday - 1;
      final subs = <String, int>{};
      int focus = 0;
      String testSubj = '';
      // Hafif dalgalanma için günün gününe göre çarpan.
      for (final e in p) {
        final sec = (e[3] as int) * 60;
        focus += sec;
        final subj = e[1] as String;
        subs[subj] = (subs[subj] ?? 0) + sec;
        if (e[0] == 'soru' && testSubj.isEmpty) testSubj = subj;
        mEnt.add({
          'dateKey': dk,
          'type': e[0] as String,
          'subject': subj,
          'topic': e[2] as String,
          'sec': sec,
        });
      }
      final subC = <String, int>{};
      final subW = <String, int>{};
      if (testSubj.isNotEmpty) {
        subC[testSubj] = correct[idx];
        subW[testSubj] = wrong[idx];
      }
      mAct.add(StudentActivityModel(
        dateKey: dk,
        focusSeconds: focus,
        subjectDurations: subs,
        correctAnswers: correct[idx],
        wrongAnswers: wrong[idx],
        blankAnswers: 1,
        photoQuestionsSolved: photo[idx],
        summariesCreated: summ[idx],
        testsSolved: 1,
        subjectCorrect: subC,
        subjectWrong: subW,
      ));
    }

    final nm = (_names[_childSlot] ?? '').trim();
    _weekEntries = week;
    _activity = acts;
    _monthActivity = mAct;
    _monthEntries = mEnt;
    _baseStats = {
      'displayName': nm.isNotEmpty ? nm : 'Ahmet',
      'streakDays': 5,
    };
  }

  void _selectSlot(int n) {
    setState(() => _childSlot = n);
    _loadForSlot(n);
  }

  // Yeni çocuk ekle — ortada blur arka planlı modal (✕ ile kapat).
  Future<void> _addChild() async {
    if (_childCount >= 6) {
      _snack('En fazla 6 çocuk eklenebilir.'.tr());
      return;
    }
    final nameCtrl = TextEditingController();
    final statusCtrl = TextEditingController();
    String draftPhoto = '';
    const accent = Color(0xFF10B981);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat'.tr(),
      barrierColor: Colors.black.withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Align(
            alignment: const Alignment(0, -0.35),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Material(
                color: Colors.transparent,
                child: StatefulBuilder(
                  builder: (ctx, setLocal) {
                    final hasName = nameCtrl.text.trim().isNotEmpty;
                    final hasPhoto =
                        draftPhoto.isNotEmpty && File(draftPhoto).existsSync();
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      decoration: BoxDecoration(
                        color: AppPalette.card(ctx),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _frame(ctx), width: 1),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 24),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.child_care_rounded,
                                    size: 20, color: Color(0xFF10B981)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('Yeni Çocuk Ekle'.tr(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 16, fontWeight: FontWeight.w800,
                                      color: AppPalette.textPrimary(ctx),
                                    )),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.pop(ctx),
                                child: Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(
                                    color: AppPalette.cardMuted(ctx),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.close_rounded,
                                      size: 18,
                                      color: AppPalette.textPrimary(ctx)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Avatar — galeriden foto (isteğe bağlı)
                          GestureDetector(
                            onTap: () async {
                              final p = await _pickPhotoTemp();
                              if (p != null) setLocal(() => draftPhoto = p);
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 76, height: 76,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppPalette.cardMuted(ctx),
                                    border: Border.all(
                                        color: accent.withValues(alpha: 0.4),
                                        width: 1.5),
                                    image: hasPhoto
                                        ? DecorationImage(
                                            image: FileImage(File(draftPhoto)),
                                            fit: BoxFit.cover)
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: hasPhoto
                                      ? null
                                      : Icon(Icons.person_rounded,
                                          size: 38,
                                          color:
                                              AppPalette.textSecondary(ctx)),
                                ),
                                Positioned(
                                  right: -2, bottom: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: const BoxDecoration(
                                        shape: BoxShape.circle, color: accent),
                                    child: const Icon(Icons.camera_alt_rounded,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('Fotoğraf ekle (isteğe bağlı)'.tr(),
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: AppPalette.textSecondary(ctx),
                              )),
                          const SizedBox(height: 14),
                          TextField(
                            controller: nameCtrl,
                            autofocus: true,
                            maxLength: 24,
                            onChanged: (_) => setLocal(() {}),
                            decoration: InputDecoration(
                              labelText: 'İsim'.tr(),
                              hintText: 'Çocuğunun adı'.tr(),
                            ),
                          ),
                          TextField(
                            controller: statusCtrl,
                            maxLength: 40,
                            decoration: InputDecoration(
                              labelText: 'Durum mesajı (isteğe bağlı)'.tr(),
                              hintText: 'örn. 8. sınıf, LGS hazırlık'.tr(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: hasName
                                  ? () async {
                                      Navigator.pop(ctx);
                                      await _commitNewChild(
                                          nameCtrl.text.trim(),
                                          statusCtrl.text.trim(),
                                          draftPhoto);
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    hasName ? accent : AppPalette.border(ctx),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppPalette.border(ctx),
                                disabledForegroundColor:
                                    AppPalette.textSecondary(ctx),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text('Tamam'.tr(),
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w800)),
                            ),
                          ),
                          if (!hasName) ...[
                            const SizedBox(height: 6),
                            Text('Devam etmek için çocuğun adını gir.'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: AppPalette.textSecondary(ctx),
                                )),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Galeriden geçici (taslak) foto seç → kalıcı dizine kopyalar, yolu döner.
  Future<String?> _pickPhotoTemp() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.gallery, maxWidth: 512, imageQuality: 85);
      if (picked == null) return null;
      final dir = await getApplicationDocumentsDirectory();
      final saved = '${dir.path}/progress_child_draft.jpg';
      await File(picked.path).copy(saved);
      return saved;
    } catch (_) {
      return null;
    }
  }

  // "Tamam"a basınca yeni çocuğu oluştur (yeni slot, sona eklenir).
  Future<void> _commitNewChild(
      String name, String status, String draftPhoto) async {
    if (_childCount >= 6) return;
    final n = _childCount + 1;
    final p = await SharedPreferences.getInstance();
    String photoPath = '';
    if (draftPhoto.isNotEmpty && File(draftPhoto).existsSync()) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        photoPath = '${dir.path}/progress_child_${n}_avatar.jpg';
        await File(draftPhoto).copy(photoPath);
      } catch (_) {
        photoPath = '';
      }
    }
    await p.setInt('progress_child_count', n);
    await p.setString('progress_child_${n}_name', name);
    await p.setString('progress_child_${n}_status', status);
    if (photoPath.isNotEmpty) {
      await p.setString('progress_child_${n}_photo', photoPath);
    }
    if (!mounted) return;
    setState(() {
      _childCount = n;
      _names[n] = name;
      _statuses[n] = status;
      _photos[n] = photoPath;
      _childUids[n] = '';
      _childSlot = n;
      _profileExpanded = true;
      _refreshPhotoExists();
    });
    _loadForSlot(n);
  }

  // Uzun basınca: çocuğu (profilini + verisini) sil — onay ister.
  Future<void> _confirmRemoveChild(int n) async {
    if (_childCount <= 1) {
      _snack('Tek çocuk silinemez.'.tr());
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Çocuğu sil'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(ctx))),
        content: Text(
            '${_slotName(n)} ${"profilini ve tüm verilerini silmek istiyor musun? Bu geri alınamaz.".tr()}',
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppPalette.textSecondary(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white),
            child: Text('Sil'.tr()),
          ),
        ],
      ),
    );
    if (ok == true) _removeChild(n);
  }

  // Bir çocuğu kaldır — sonraki slotları bir aşağı kaydırır (yeniden indeksleme).
  Future<void> _removeChild(int slot) async {
    if (_childCount <= 1) return;
    final p = await SharedPreferences.getInstance();
    final linkedUid = (_childUids[slot] ?? '').trim();
    if (linkedUid.isNotEmpty) {
      // Uzaktan bağlıysa bağlantıyı da kopar.
      await ParentLinkService.unlinkChild(linkedUid);
    }
    for (int i = slot; i < _childCount; i++) {
      _names[i] = _names[i + 1] ?? '';
      _photos[i] = _photos[i + 1] ?? '';
      _statuses[i] = _statuses[i + 1] ?? '';
      _childUids[i] = _childUids[i + 1] ?? '';
      await p.setString('progress_child_${i}_name', _names[i]!);
      await p.setString('progress_child_${i}_photo', _photos[i]!);
      await p.setString('progress_child_${i}_status', _statuses[i]!);
      await p.setString('progress_child_${i}_uid', _childUids[i]!);
    }
    final last = _childCount;
    _names.remove(last);
    _photos.remove(last);
    _statuses.remove(last);
    _childUids.remove(last);
    await p.remove('progress_child_${last}_name');
    await p.remove('progress_child_${last}_photo');
    await p.remove('progress_child_${last}_status');
    await p.remove('progress_child_${last}_uid');
    _childCount -= 1;
    await p.setInt('progress_child_count', _childCount);
    setState(() {
      if (_childSlot > _childCount) _childSlot = _childCount;
      _refreshPhotoExists();
    });
    _loadForSlot(_childSlot);
  }

  // ── Uzaktan bağlama işlemleri ───────────────────────────────────────────
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Çocuk: kendi bağlanma kodunu üretir (ebeveynine verir).
  Future<void> _generateMyCode() async {
    final code = await ParentLinkService.generateChildLinkCode();
    if (!mounted) return;
    if (code == null) {
      _snack('Kod üretilemedi. Giriş yaptığından emin ol.'.tr());
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Ebeveyn Bağlanma Kodu'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Bu kodu ebeveynine ver; kendi uygulamasında Gelişim Paneli '
                    'sekmesine girip "Çocuğu Bağla" ile yazsın.'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppPalette.textSecondary(ctx))),
            const SizedBox(height: 14),
            SelectableText(code.code,
                style: GoogleFonts.poppins(
                  fontSize: 26, fontWeight: FontWeight.w900,
                  letterSpacing: 2, color: const Color(0xFF10B981),
                )),
            const SizedBox(height: 8),
            Text('15 dakika geçerli.'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppPalette.textSecondary(ctx))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Kapat'.tr()),
          ),
        ],
      ),
    );
  }

  // Ebeveyn: bir slot'a kod ile çocuk bağlar.
  Future<void> _linkChildByCode(int slot) async {
    final codeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('$slot. ${"Çocuğu Bağla".tr()}',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Çocuğun uygulamasında Gelişim Paneli\'nden aldığı kodu gir.'
                    .tr(),
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppPalette.textSecondary(ctx))),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'EBEV-XXXXXX'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Bağla'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final code = codeCtrl.text.trim();
    final childUid = await ParentLinkService.resolveCodeChildUid(code);
    if (childUid == null) {
      _snack('Kod geçersiz ya da süresi dolmuş.'.tr());
      return;
    }
    final res = await ParentLinkService.requestLinkByCode(code);
    if (res == LinkRequestResult.success ||
        res == LinkRequestResult.pending ||
        res == LinkRequestResult.alreadyLinked) {
      final p = await SharedPreferences.getInstance();
      await p.setString('progress_child_${slot}_uid', childUid);
      if (mounted) setState(() => _childUids[slot] = childUid);
      _snack('İstek gönderildi. Çocuk profilinden onayladığında veriler görünür.'
          .tr());
      _selectSlot(slot);
    } else if (res == LinkRequestResult.selfLink) {
      _snack('Kendi hesabını bağlayamazsın.'.tr());
    } else {
      _snack('Bağlanamadı. Tekrar dene.'.tr());
    }
  }

  Future<void> _unlinkSlot(int slot) async {
    final uid = (_childUids[slot] ?? '').trim();
    if (uid.isNotEmpty) {
      await ParentLinkService.unlinkChild(uid);
    }
    final p = await SharedPreferences.getInstance();
    await p.remove('progress_child_${slot}_uid');
    if (mounted) setState(() => _childUids[slot] = '');
    _selectSlot(slot);
  }

  /// Firestore (doğru/yanlış/foto) + lokal (gerçek süre + ders) birleştir.
  List<Map<String, dynamic>> _mergeActivity(
    List<Map<String, dynamic>> cloud,
    List<Map<String, dynamic>> local,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final m in cloud) {
      final k = (m['dateKey'] ?? '').toString();
      if (k.isNotEmpty) byKey[k] = Map<String, dynamic>.from(m);
    }
    int totalOf(dynamic subs) => subs is Map
        ? subs.values.fold<int>(0, (s, v) => s + ((v as num?)?.toInt() ?? 0))
        : 0;
    for (final lm in local) {
      final k = (lm['dateKey'] ?? '').toString();
      if (k.isEmpty) continue;
      final merged = byKey[k] ?? {'dateKey': k};
      final cf = (merged['focusSeconds'] as num?)?.toInt() ?? 0;
      final lf = (lm['focusSeconds'] as num?)?.toInt() ?? 0;
      merged['focusSeconds'] = cf >= lf ? cf : lf;
      final cs = merged['subjectDurations'];
      final ls = lm['subjectDurations'];
      merged['subjectDurations'] = totalOf(ls) >= totalOf(cs) ? ls : cs;
      byKey[k] = merged;
    }
    final out = byKey.values.toList()
      ..sort((a, b) => (a['dateKey'] ?? '')
          .toString()
          .compareTo((b['dateKey'] ?? '').toString()));
    return out;
  }

  // ── İsim ──────────────────────────────────────────────────────────────
  // Seçili çocuğun ebeveyn tarafından girilen adı önceliklidir; yoksa
  // Firebase profil adı; o da yoksa varsayılan "N. Çocuk".
  String get _studentName {
    final custom = (_names[_childSlot] ?? '').trim();
    if (custom.isNotEmpty) return custom;
    final dn = (_baseStats['displayName'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;
    final un = (_baseStats['username'] ?? '').toString().trim();
    if (un.isNotEmpty) return un;
    return '$_childSlot. ${"Çocuk".tr()}';
  }

  String _slotName(int n) {
    final c = (_names[n] ?? '').trim();
    return c.isNotEmpty ? c : '$n. ${"Çocuk".tr()}';
  }

  // ── Foto seç (galeri) ───────────────────────────────────────────────────
  Future<void> _pickPhoto(int n) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.gallery, maxWidth: 512, imageQuality: 85);
      if (picked == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final saved = '${dir.path}/progress_child_${n}_avatar.jpg';
      await File(picked.path).copy(saved);
      final p = await SharedPreferences.getInstance();
      await p.setString('progress_child_${n}_photo', saved);
      if (mounted) {
        setState(() {
          _photos[n] = saved;
          _childSlot = n;
          _photoExists[n] = true;
        });
      }
    } catch (_) {}
  }

  // ── İsim + durum düzenle ────────────────────────────────────────────────
  Future<void> _editProfile(int n) async {
    final nameCtrl = TextEditingController(text: _names[n] ?? '');
    final statusCtrl = TextEditingController(text: _statuses[n] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('$n. ${"Çocuk".tr()}',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              maxLength: 24,
              decoration: InputDecoration(
                labelText: 'İsim'.tr(),
                hintText: 'Çocuğunun adı'.tr(),
              ),
            ),
            TextField(
              controller: statusCtrl,
              maxLength: 40,
              decoration: InputDecoration(
                labelText: 'Durum mesajı'.tr(),
                hintText: 'örn. 8. sınıf, LGS hazırlık'.tr(),
              ),
            ),
          ],
        ),
        actions: [
          if (_childCount > 1)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
                _removeChild(n);
              },
              child: Text('Kaldır'.tr(),
                  style: const TextStyle(color: Color(0xFFEF4444))),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Kaydet'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('progress_child_${n}_name', nameCtrl.text.trim());
    await p.setString('progress_child_${n}_status', statusCtrl.text.trim());
    if (mounted) {
      setState(() {
        _names[n] = nameCtrl.text.trim();
        _statuses[n] = statusCtrl.text.trim();
        _childSlot = n;
      });
    }
  }

  // ── Bu haftanın günleri (Pzt→Paz) ──────────────────────────────────────
  String _two(int n) => n.toString().padLeft(2, '0');
  // Hafta gün anahtarları gün boyunca sabit → bir kez hesapla, cache'le.
  List<String>? _weekDateKeysCache;
  List<String> get _weekDateKeys {
    final cached = _weekDateKeysCache;
    if (cached != null) return cached;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    return _weekDateKeysCache = List.generate(7, (i) {
      final d = monday.add(Duration(days: i));
      return '${d.year}-${_two(d.month)}-${_two(d.day)}';
    });
  }

  Map<String, StudentActivityModel> get _activityByDate {
    final cached = _activityByDateCache;
    if (cached != null) return cached;
    final m = <String, StudentActivityModel>{};
    for (final a in _activity) {
      m[a.dateKey] = a;
    }
    return _activityByDateCache = m;
  }

  _ProgressCat get _cat => _cats.firstWhere((c) => c.key == _selected);

  String get _todayKey {
    final n = DateTime.now();
    return '${n.year}-${_two(n.month)}-${_two(n.day)}';
  }

  // Süre tabanlı kategoriler (foto hariç — o adet bazlı).
  List<_ProgressCat> get _timeCats =>
      _cats.where((c) => !c.isCount).toList();

  // Bir kategorinin saniyesi (gün verilirse o gün, yoksa tüm hafta).
  int _catSec(_ProgressCat c, {String? dateKey}) {
    return _weekEntries
        .where((e) =>
            e['type'] == c.type &&
            (dateKey == null || e['dateKey'] == dateKey))
        .fold<int>(0, (s, e) => s + (e['sec'] as int? ?? 0));
  }

  // Bugün/hafta kategori→saniye dağılımı (sadece >0).
  Map<_ProgressCat, int> _catDistribution({required bool today}) {
    final out = <_ProgressCat, int>{};
    for (final c in _timeCats) {
      final s = _catSec(c, dateKey: today ? _todayKey : null);
      if (s > 0) out[c] = s;
    }
    return out;
  }

  // Veliye 1-2 cümlelik öneri (kural tabanlı — anlık, AI gerektirmez).
  String _insight({required bool today}) {
    final per = _catDistribution(today: today);
    final total = per.values.fold<int>(0, (s, v) => s + v);
    final scope = today ? 'Bugün'.tr() : 'Bu hafta'.tr();
    final name = _studentName;
    if (total == 0) {
      return today
          ? '$name ${"bugün henüz çalışma kaydı oluşturmadı.".tr()}'
          : '$name ${"bu hafta henüz çalışmaya başlamadı; küçük bir hedefle başlamak iyi olur.".tr()}';
    }
    final sorted = per.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    final topPct = (top.value * 100 / total).round();
    if (sorted.length == 1 || topPct >= 70) {
      return '$scope ${"toplam".tr()} ${_fmt(total)} ${"çalıştı; ağırlıklı olarak".tr()} '
          '${top.key.label.tr()} (%$topPct). '
          '${"Diğer alanlara da zaman ayırması dengeyi artırır.".tr()}';
    }
    return '$scope ${"toplam".tr()} ${_fmt(total)} ${"çalıştı; en çok".tr()} '
        '${top.key.label.tr()} (%$topPct), ${"ardından".tr()} ${sorted[1].key.label.tr()}. '
        '${"Dengeli bir çalışma temposu 👍".tr()}';
  }

  // Seçili kategorinin bir gündeki kayıtları.
  List<Map<String, dynamic>> _entriesOn(String dateKey) {
    return _weekEntries
        .where((e) => e['type'] == _cat.type && e['dateKey'] == dateKey)
        .toList();
  }

  // Bir günün değeri: süre kategorisinde saniye, foto'da adet.
  int _valueOn(String dateKey) {
    if (_cat.isCount) {
      return _activityByDate[dateKey]?.photoQuestionsSolved ?? 0;
    }
    return _entriesOn(dateKey).fold<int>(0, (s, e) => s + (e['sec'] as int? ?? 0));
  }

  // Belirli gün için ders → saniye haritası (süre kategorileri).
  Map<String, int> _daySubjectMap(String dateKey) {
    final out = <String, int>{};
    for (final e in _entriesOn(dateKey)) {
      final sec = e['sec'] as int? ?? 0;
      if (sec <= 0) continue;
      final subj = (e['subject'] ?? '').toString().trim();
      if (subj.isEmpty) continue;
      out[subj] = (out[subj] ?? 0) + sec;
    }
    return out;
  }

  // Haftalık ders dağılımı (süre kategorileri).
  Map<String, int> get _subjectTotals {
    final out = <String, int>{};
    for (final e in _weekEntries) {
      if (e['type'] != _cat.type) continue;
      final sec = e['sec'] as int? ?? 0;
      if (sec <= 0) continue;
      final subj = (e['subject'] ?? '').toString();
      if (subj.isEmpty) continue;
      out[subj] = (out[subj] ?? 0) + sec;
    }
    return out;
  }

  int get _weekCorrect {
    int c = 0;
    for (final k in _weekDateKeys) {
      c += _activityByDate[k]?.correctAnswers ?? 0;
    }
    return c;
  }

  int get _weekWrong {
    int c = 0;
    for (final k in _weekDateKeys) {
      c += _activityByDate[k]?.wrongAnswers ?? 0;
    }
    return c;
  }

  int get _weekBlank {
    int c = 0;
    for (final k in _weekDateKeys) {
      c += _activityByDate[k]?.blankAnswers ?? 0;
    }
    return c;
  }

  // Ders bazlı test sonucu: ders → [doğru, yanlış] (bu hafta toplamı).
  Map<String, List<int>> get _weekSubjectScores {
    final out = <String, List<int>>{};
    for (final k in _weekDateKeys) {
      final a = _activityByDate[k];
      if (a == null) continue;
      a.subjectCorrect.forEach((s, c) {
        out.putIfAbsent(s, () => [0, 0])[0] += c;
      });
      a.subjectWrong.forEach((s, w) {
        out.putIfAbsent(s, () => [0, 0])[1] += w;
      });
    }
    return out;
  }

  // ── Genel (hafta/ay) yardımcıları ───────────────────────────────────────
  // Verilen kayıtlardan kategori→saniye (süre kategorileri).
  Map<_ProgressCat, int> _catDistFrom(List<Map<String, dynamic>> entries) {
    final out = <_ProgressCat, int>{};
    for (final c in _timeCats) {
      int s = 0;
      for (final e in entries) {
        if (e['type'] == c.type) s += (e['sec'] as int? ?? 0);
      }
      if (s > 0) out[c] = s;
    }
    return out;
  }

  // Verilen günlük kayıtlardan ders→[doğru,yanlış].
  Map<String, List<int>> _subjScoresFrom(List<StudentActivityModel> acts) {
    final out = <String, List<int>>{};
    for (final a in acts) {
      a.subjectCorrect.forEach((s, c) {
        out.putIfAbsent(s, () => [0, 0])[0] += c;
      });
      a.subjectWrong.forEach((s, w) {
        out.putIfAbsent(s, () => [0, 0])[1] += w;
      });
    }
    return out;
  }

  String _fmt(int sec) {
    if (sec <= 0) return '0 dk';
    final m = sec ~/ 60;
    if (m < 1) return '<1 dk';
    if (m < 60) return '$m dk';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h sa' : '$h sa $r dk';
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final pageBg = _ovColor('bg') ?? AppPalette.bg(context);
    return RepaintBoundary(
      key: _shotKey,
      child: Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: ink,
        title: Text('Gelişim Paneli'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800,
              color: _titleColor(context),
            )),
        actions: [
          // 4 sekme tek oval çerçeve içinde — zeminden biraz farklı arka plan.
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.isDark(context)
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppPalette.border(context)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Yeni çocuk ekle — yeşil "+"
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.add_circle_rounded,
                        color: Color(0xFF10B981)),
                    tooltip: 'Çocuk ekle'.tr(),
                    onPressed: _addChild,
                  ),
                  // Paylaş — ekran görüntüsü alıp paylaşım sayfasını açar.
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                    icon: Transform.rotate(
                      angle: -pi / 4,
                      child: const Icon(Icons.send_rounded,
                          color: Color(0xFF25D366)),
                    ),
                    tooltip: 'Paylaş'.tr(),
                    onPressed: _shareScreenshot,
                  ),
                  // Renk paleti — RENKLİ simge (gradyan)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                    icon: _showPalette
                        ? Icon(Icons.close_rounded, color: ink)
                        : ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (r) => const LinearGradient(
                              colors: [
                                Color(0xFFFF6A00), Color(0xFFDB2777),
                                Color(0xFF7C3AED), Color(0xFF2563EB),
                              ],
                            ).createShader(r),
                            child: const Icon(Icons.palette_rounded,
                                color: Colors.white),
                          ),
                    tooltip: 'Renk'.tr(),
                    onPressed: () =>
                        setState(() => _showPalette = !_showPalette),
                  ),
                  // Yardım "?"
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.help_outline_rounded, color: ink),
                    tooltip: 'Nasıl çalışır?'.tr(),
                    onPressed: _showHelp,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Arka plan bırakma hedefi ('bg'): boş alana renk bırakılınca sayfa rengi.
                DragTarget<Color>(
                  onAcceptWithDetails: (d) => _setOv('bg', d.data),
                  builder: (ctx, cand, rej) => Column(
                    children: [
                      // Çocuk profilleri SABİT (sayfa kaysa da üstte kalır).
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                        child: _childTabs(context),
                      ),
                      // Geri kalan içerik kaydırılır.
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
                            children: _scrollChildren(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Renk paleti SABİT yüzer panel (dar + ortalı).
                if (_showPalette)
                  Positioned(
                    left: 0, right: 0,
                    top: _paletteTop,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _palettePanel(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    ),
    );
  }

  // Çocuğun sınıf ödevlerine geçiş kartı — öğretmenin verdiği ödevleri ve
  // çocuğun sonuçlarını (doğru/yanlış/başarı) gösteren ekranı açar.
  Widget _homeworkCard(BuildContext context, String childUid) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ParentChildHomeworksScreen(
            childUid: childUid,
            childName: _studentName,
          ),
        )),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.28),
                blurRadius: 14, offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: const Text('📚', style: TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Çocuğun Ödevleri'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w900,
                          color: Colors.white,
                        )),
                    const SizedBox(height: 3),
                    Text('Öğretmen ödevleri + sonuçları (doğru/yanlış/başarı)'
                        .tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.90),
                          height: 1.3,
                        )),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _scrollChildren(BuildContext context) {
    final out = <Widget>[];
    if (_loadError) {
      out.add(_noticeCard(
        context,
        icon: Icons.wifi_off_rounded,
        title: 'Veri yüklenemedi'.tr(),
        body: 'Çocuğun verisine ulaşılamadı (bağlantı veya izin sorunu). '
            'İnternet bağlantını kontrol edip tekrar dene.'.tr(),
        action: OutlinedButton.icon(
          onPressed: () => _loadForSlot(_childSlot),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text('Yenile'.tr()),
        ),
      ));
    } else if (_pending) {
      out.add(_noticeCard(
        context,
        icon: Icons.hourglass_top_rounded,
        title: 'Onay bekleniyor'.tr(),
        body: 'Çocuğun uygulamayı açıp profil sekmesinden bağlantı isteğini '
            'onaylaması gerekiyor. Onayladığında veriler burada görünür.'.tr(),
        action: OutlinedButton.icon(
          onPressed: () => _loadForSlot(_childSlot),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text('Yenile'.tr()),
        ),
      ));
    } else {
      if (_demo) {
        out.add(_demoBadge(context));
        out.add(const SizedBox(height: 10));
      }
      final childUid = (_childUids[_childSlot] ?? '').trim();
      out.addAll([
        _summaryHeader(context),
        const SizedBox(height: 16),
        // Çocuğun sınıf ödevleri (öğretmen verdiyse) — bağlı çocuk varsa.
        if (childUid.isNotEmpty) ...[
          _homeworkCard(context, childUid),
          const SizedBox(height: 16),
        ],
        _sectionTitle(context, 'Çalıştığı Alanlar'.tr()),
        const SizedBox(height: 10),
        _chipsGrid(context),
        const SizedBox(height: 16),
      ]);
      // Gelişime açık konular — yeterli test verisi varsa.
      final struggling = _strugglingSubjects();
      if (struggling.isNotEmpty) {
        out.add(_strugglingCard(context, struggling));
        out.add(const SizedBox(height: 16));
      }
      out.add(_zReport(context)); // Hafta (özet) → Ay (trend)
    }

    // Çocuk tarafı — kendi ebeveyn bağlanma kodunu üret.
    out.addAll([
      const SizedBox(height: 16),
      Center(
        child: TextButton.icon(
          onPressed: _generateMyCode,
          icon: const Icon(Icons.qr_code_rounded, size: 16),
          label: Text('Ebeveynine bağlanma kodu ver'.tr()),
        ),
      ),
    ]);
    return out;
  }

  // ── Renk paleti (3D modellerdeki / Kütüphanem ile aynı renk seti) ───────
  // Renk hedefleri — görsele uygun 2×3 düzen.
  static const _targets = <List<String>>[
    ['bg', 'Arka plan'],
    ['header', 'Başlık'],
    ['labels', 'Etiketler'],
    ['infopanel', 'Bilgi paneli'],
    ['titleText', 'Başlık yazısı'],
    ['bodyText', 'Yazılar'],
  ];

  Widget _palettePanel(BuildContext context) {
    const accent = Color(0xFFFBBF24); // sarı vurgu (görseldeki gibi)
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF22D3EE).withValues(alpha: 0.5), width: 1.4),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35), blurRadius: 22),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık + Sıfırla (hemen sağında) + ✕ + ✛
            Row(
              children: [
                const Text('🎨', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text('RENK PALETİ'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      letterSpacing: 0.5, color: const Color(0xFF22D3EE),
                    )),
                const SizedBox(width: 8),
                // ↻ Sıfırla — başlığın hemen sağında, küçük pill
                GestureDetector(
                  onTap: _clearOv,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppPalette.cardMuted(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded,
                            size: 12, color: AppPalette.textPrimary(context)),
                        const SizedBox(width: 3),
                        Text('Sıfırla'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: AppPalette.textPrimary(context),
                            )),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                _hdrBtn(Icons.close_rounded, const Color(0xFFEF4444),
                    () => setState(() => _showPalette = false)),
                const SizedBox(width: 6),
                GestureDetector(
                  onVerticalDragUpdate: (d) => setState(() {
                    _paletteTop = (_paletteTop + d.delta.dy).clamp(8.0, 420.0);
                  }),
                  child: _hdrBtnChild(
                      Icons.open_with_rounded, const Color(0xFFFBBF24)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Hedef seçiciler — 2×3, ince satırlar
            _targetRow(context, 0, accent),
            const SizedBox(height: 6),
            _targetRow(context, 3, accent),
            const SizedBox(height: 10),
            Text('Önce hedefi seç, sonra renge bas.'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 10, fontWeight: FontWeight.w500,
                  color: AppPalette.textSecondary(context),
                )),
            const SizedBox(height: 8),
            // Renkler — 2 satır, yatay kaydırılabilir (küçük kutular)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _swatchRow(_palette.sublist(0, 12)),
                  const SizedBox(height: 6),
                  _swatchRow(_palette.sublist(12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hdrBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: _hdrBtnChild(icon, color));

  Widget _hdrBtnChild(IconData icon, Color color) => Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1.3),
        ),
        child: Icon(icon, color: color, size: 16),
      );

  Widget _targetRow(BuildContext context, int start, Color accent) {
    Widget cell(int i) {
      final t = _targets[i];
      final sel = _colorTarget == t[0];
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = t[0]),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: sel ? accent : AppPalette.cardMuted(context),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(t[1].tr(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: sel
                      ? const Color(0xFF1A1A1A)
                      : AppPalette.textPrimary(context),
                )),
          ),
        ),
      );
    }

    Widget arrow() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(Icons.arrow_forward_rounded,
              size: 12, color: AppPalette.textSecondary(context)),
        );

    return Row(
      children: [
        cell(start),
        arrow(),
        cell(start + 1),
        arrow(),
        cell(start + 2),
      ],
    );
  }

  Widget _swatchRow(List<Color> colors) {
    return Row(
      children: colors.map((col) {
        final sel = _ov[_colorTarget]?.toARGB32() == col.toARGB32();
        final box = Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: col,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: sel ? const Color(0xFFFBBF24) : Colors.black26,
              width: sel ? 2.5 : 1,
            ),
          ),
          child: sel
              ? const Icon(Icons.check_rounded, size: 14, color: Color(0xFF1A1A1A))
              : null,
        );
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          // Tıkla → seçili hedefe uygula; SÜRÜKLE → bir öğeye bırak.
          child: Draggable<Color>(
            data: col,
            feedback: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: col,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
                ],
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.4, child: box),
            child: GestureDetector(
              onTap: () => _setOv(_colorTarget, col),
              child: box,
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showHelp() {
    final ctx = context;
    showDialog<void>(
      context: ctx,
      builder: (d) => Dialog(
        backgroundColor: AppPalette.card(d),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(d).size.height * 0.82, maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Renkli başlık şeridi
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFF6A00), Color(0xFFDB2777),
                      Color(0xFF7C3AED), Color(0xFF2563EB),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.insights_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Gelişim Paneli nasıl çalışır?'.tr(),
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w900,
                              color: Colors.white, height: 1.2)),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _helpLine(d, Icons.family_restroom_rounded,
                          const Color(0xFF10B981), 'Çocuk Sekmeleri',
                          'En üstteki iki sekme çocuklarındır. Fotoğrafa basıp galeriden resim koy, kalemle isim ve durum yaz.'),
                      _helpLine(d, Icons.link_rounded,
                          const Color(0xFF2563EB), 'Kod ile Bağla',
                          'Çocuk kendi uygulamasında "Ebeveynine bağlanma kodu ver" der; sen sekmeyi düzenleyip "Kod ile Bağla" ile girersin. Çocuk onaylayınca veriler akar.'),
                      _helpLine(d, Icons.widgets_rounded,
                          const Color(0xFFFF6A00), 'Çalıştığı Alanlar',
                          'Bir kategori kutusuna basınca detay açılır: hangi konuyu ne kadar, hangi gün çalışmış; test/yarışmada başarı durumu.'),
                      _helpLine(d, Icons.pie_chart_rounded,
                          const Color(0xFF7C3AED), 'Günlük & Haftalık Özet',
                          'Pasta grafikleri zamanını nasıl böldüğünü gösterir; sağda koç tarzı kısa bir yorum bulunur.'),
                      _helpLine(d, Icons.science_rounded,
                          const Color(0xFFFBBF24), 'Örnek Veri',
                          'Henüz bağlı çocuk yoksa panel demo veriyle dolu görünür; bağlayınca gerçek veriyle değişir.'),
                      _helpLine(d, Icons.palette_rounded,
                          const Color(0xFFDB2777), 'Renkleri Değiştir',
                          'Paleti aç, bir rengi tutup kutulara / arka plana / grafiklere sürükleyerek renklerini değiştir.'),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(d),
                    child: Text('Anladım'.tr(),
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpLine(BuildContext context, IconData icon, Color color,
      String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: color,
                    )),
                const SizedBox(height: 2),
                Text(text.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11.5, height: 1.45,
                      color: AppPalette.textSecondary(context),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Row(
      children: [
        Container(
          width: 4, height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w800,
              color: _titleColor(context),
            )),
      ],
    );
  }

  Widget _demoBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Text('🧪', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Örnek veri — çocuğunu kod ile bağladığında gerçek veriler görünür.'
                  .tr(),
              style: GoogleFonts.poppins(
                fontSize: 10.5, fontWeight: FontWeight.w600,
                color: const Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String body,
      Widget? action}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: const Color(0xFF10B981)),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
              )),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12, height: 1.5,
                color: AppPalette.textSecondary(context),
              )),
          if (action != null) ...[
            const SizedBox(height: 14),
            action,
          ],
        ],
      ),
    );
  }

  // ── Üst özet ──────────────────────────────────────────────────────────
  Widget _summaryHeader(BuildContext context) {
    final streak = (_baseStats['streakDays'] as num?)?.toInt() ?? 0;
    final totalMin = _activity.fold<int>(0, (s, a) => s + a.focusMinutes);
    final answered = _weekCorrect + _weekWrong;
    final pct = answered > 0 ? (_weekCorrect * 100 / answered).round() : 0;
    final headerOv = _ovColor('header');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: headerOv,
        gradient: headerOv != null
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_studentName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: Colors.white,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('${"Bu hafta".tr()} • ${"kategori seç".tr()} 👇',
              style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.85),
              )),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('$totalMin dk', 'Çalışma'.tr()),
              _stat('🔥 $streak', 'Seri gün'.tr()),
              _stat('%$pct', 'Başarı'.tr()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: GoogleFonts.poppins(
                fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.85),
              )),
        ],
      ),
    );
  }

  // ── İki çocuk sekmesi (sol 1. çocuk · sağ 2. çocuk) ─────────────────────
  // ── Çocuk profil şeridi ─────────────────────────────────────────────────
  Widget _childTabs(BuildContext context) {
    if (_childCount == 1) return _singleChildBar(context);
    if (_profileExpanded) return _expandedChildCard(context);
    return _compactChildRow(context);
  }

  // Tek çocuk: ortada sade kart.
  Widget _singleChildBar(BuildContext context) {
    const accent = Color(0xFF10B981);
    final status = (_statuses[1] ?? '').trim();
    return Center(
      child: _drop('child1', GestureDetector(
        onLongPress: () => _confirmRemoveChild(1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _resolve(['child1', 'infopanel'], AppPalette.card(context)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _pickPhoto(1),
                child: _avatarCircle(context, 1, 46),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Text(_slotName(1),
                        style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context),
                        )),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _editProfile(1),
                      child: Icon(Icons.edit_rounded, size: 13, color: accent),
                    ),
                    _linkBadge(1),
                  ]),
                  if (status.isNotEmpty)
                    Text(status,
                        style: GoogleFonts.poppins(
                          fontSize: 10, color: AppPalette.textSecondary(context),
                        )),
                ],
              ),
            ],
          ),
        ),
      )),
    );
  }

  // Birden fazla çocuk — kompakt yatay şerit (küçük chip'ler).
  Widget _compactChildRow(BuildContext context) {
    const accent = Color(0xFF10B981);
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _childCount,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final n = i + 1;
          final sel = _childSlot == n;
          return _drop('child$n', GestureDetector(
            onTap: () {
              if (_childSlot != n) {
                setState(() => _childSlot = n);
                _loadForSlot(n);
              }
              setState(() => _profileExpanded = true);
            },
            onLongPress: () => _confirmRemoveChild(n),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 130, // tüm çocuk sekmeleri aynı boyutta
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _resolve(['child$n', 'infopanel'],
                    sel ? accent.withValues(alpha: 0.10) : AppPalette.card(context)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sel ? accent : AppPalette.border(context),
                  width: sel ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  _avatarCircle(context, n, 34, showCamera: false),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(_slotName(n),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 11.5, fontWeight: FontWeight.w700,
                          color: AppPalette.textPrimary(context),
                        )),
                  ),
                ],
              ),
            ),
          ));
        },
      ),
    );
  }

  // Seçili çocuk genişletilmiş kart — büyük foto + isim/durum + küçültme butonu.
  Widget _expandedChildCard(BuildContext context) {
    final n = _childSlot;
    final status = (_statuses[n] ?? '').trim();
    const accent = Color(0xFF10B981);
    return _drop('child$n', Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: _resolve(['child$n', 'infopanel'], AppPalette.card(context)),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent, width: 1.4),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sol: büyük avatar
              GestureDetector(
                onTap: () => _pickPhoto(n),
                child: _avatarCircle(context, n, 76),
              ),
              const SizedBox(width: 14),
              // Sağ: isim + durum (bilgiler)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(_slotName(n),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 16, fontWeight: FontWeight.w800,
                                color: AppPalette.textPrimary(context),
                              )),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _editProfile(n),
                          child:
                              Icon(Icons.edit_rounded, size: 14, color: accent),
                        ),
                        _linkBadge(n),
                      ],
                    ),
                    if (status.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(status,
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: AppPalette.textSecondary(context),
                          )),
                    ],
                  ],
                ),
              ),
              // En sağ: diğer çocuklar — DİKEY sütun (yukarıdan aşağıya)
              if (_childCount > 1) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 30, top: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_childCount, (i) {
                      final m = i + 1;
                      if (m == n) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _childSlot = m);
                            _loadForSlot(m);
                          },
                          onLongPress: () => _confirmRemoveChild(m),
                          child:
                              _avatarCircle(context, m, 36, showCamera: false),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ],
          ),
          // Küçültme butonu — sağ üst
          Positioned(
            top: 0, right: 0,
            child: GestureDetector(
              onTap: () => setState(() => _profileExpanded = false),
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: AppPalette.cardMuted(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.keyboard_arrow_up_rounded,
                    size: 20, color: AppPalette.textSecondary(context)),
              ),
            ),
          ),
        ],
      ),
    ));
  }

  // Foto varlığını bir kez kontrol edip cache'le (build'de existsSync yok).
  void _refreshPhotoExists() {
    _photoExists.clear();
    _photos.forEach((n, path) {
      _photoExists[n] = path.isNotEmpty && File(path).existsSync();
    });
  }

  // İsim yanındaki bağlantı simgesi — kalemin sağında. Bağlı değilse kod gir
  // panelini açar, bağlıysa (onaylı) bağlantıyı kaldırır.
  Widget _linkBadge(int n) {
    final linked = (_childUids[n] ?? '').isNotEmpty;
    const accent = Color(0xFF10B981);
    return GestureDetector(
      onTap: () => linked ? _confirmUnlink(n) : _linkChildByCode(n),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(
          linked ? Icons.link_rounded : Icons.add_link_rounded,
          size: 14,
          color: linked ? accent : AppPalette.textSecondary(context),
        ),
      ),
    );
  }

  Future<void> _confirmUnlink(int n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Bağlantıyı kaldır'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(ctx))),
        content: Text(
            '${_slotName(n)} ${"ile uzaktan bağlantı kaldırılsın mı? Veriler artık görünmez.".tr()}',
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppPalette.textSecondary(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Kaldır'.tr(),
                style: const TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (ok == true) _unlinkSlot(n);
  }

  // Yuvarlak avatar (kamera rozeti isteğe bağlı).
  Widget _avatarCircle(BuildContext context, int n, double size,
      {bool showCamera = true}) {
    const accent = Color(0xFF10B981);
    final photo = _photos[n] ?? '';
    final hasPhoto = (_photoExists[n] ?? false) && photo.isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppPalette.cardMuted(context),
            border: Border.all(
                color: accent.withValues(alpha: 0.40), width: 1.4),
            image: hasPhoto
                ? DecorationImage(
                    image: FileImage(File(photo)), fit: BoxFit.cover)
                : null,
          ),
          alignment: Alignment.center,
          child: hasPhoto
              ? null
              : Icon(Icons.person_rounded,
                  color: AppPalette.textSecondary(context),
                  size: size * 0.48),
        ),
        if (showCamera)
          Positioned(
            right: -2, bottom: -2,
            child: Container(
              padding: EdgeInsets.all(size > 50 ? 4 : 3),
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: accent),
              child: Icon(Icons.camera_alt_rounded,
                  size: size > 50 ? 13 : 9, color: Colors.white),
            ),
          ),
      ],
    );
  }

  // ── 6 kategori sekmesi (2 sıra × 3) ─────────────────────────────────────
  Widget _chipsGrid(BuildContext context) {
    Widget row(List<_ProgressCat> cs) => Row(
          children: [
            for (int i = 0; i < cs.length; i++) ...[
              Expanded(child: _chip(context, cs[i])),
              if (i < cs.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
    return Column(
      children: [
        row(_cats.sublist(0, 3)),
        const SizedBox(height: 8),
        row(_cats.sublist(3, 6)),
      ],
    );
  }

  Widget _chip(BuildContext context, _ProgressCat c) {
    final sel = c.key == _selected;
    return _drop('chip_${c.key}', GestureDetector(
      onTap: () {
        setState(() => _selected = c.key);
        _openCategoryModal(context, c);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: _resolve(['chip_${c.key}', 'labels'],
              sel ? c.color.withValues(alpha: 0.12) : AppPalette.card(context)),
          borderRadius: BorderRadius.circular(14),
          // İnce çerçeve (seçiliyken kategori rengi).
          border: Border.all(
            color: sel ? c.color : _frame(context),
            width: sel ? 1.6 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(c.icon, color: c.color, size: 22),
            const SizedBox(height: 5),
            Text(c.label.tr(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: sel ? c.color : AppPalette.textSecondary(context),
                )),
          ],
        ),
      ),
    ));
  }

  // ── "Z raporu" — Günlük + Haftalık + (en altta) Aylık detaylı rapor ─────
  // Bu hafta test çözülen dersleri başarıya göre sıralar (en düşük önce).
  // Yeterli örnek (>=3 soru) olmayan dersler güvenilmez sayılıp atlanır.
  List<({String subject, int pct, int total})> _strugglingSubjects() {
    final out = <({String subject, int pct, int total})>[];
    _weekSubjectScores.forEach((s, cw) {
      final total = cw[0] + cw[1];
      if (total < 3) return;
      out.add((subject: s, pct: (cw[0] * 100 / total).round(), total: total));
    });
    out.sort((a, b) => a.pct.compareTo(b.pct));
    return out;
  }

  // Gelişime açık konular kartı — "ne kadar çalıştı" değil "nerede zorlanıyor".
  Widget _strugglingCard(
      BuildContext context, List<({String subject, int pct, int total})> all) {
    // Başarısı %70'in altındakiler "zorlandığı"; en fazla 3 göster.
    final weak = all.where((e) => e.pct < 70).take(3).toList();
    const warm = Color(0xFFEF4444);
    Color barColor(int pct) => pct < 50
        ? const Color(0xFFEF4444)
        : (pct < 70 ? const Color(0xFFF59E0B) : const Color(0xFF10B981));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: _resolve(['struggling', 'infopanel'], AppPalette.card(context)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _frame(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📌', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 7),
              Text('Gelişime Açık Konular'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13.5, fontWeight: FontWeight.w800,
                    color: _titleColor(context),
                  )),
            ],
          ),
          const SizedBox(height: 10),
          if (weak.isEmpty)
            Row(
              children: [
                const Text('👍', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '$_studentName ${"bu hafta test çözdüğü derslerde belirgin bir zorluk yaşamadı.".tr()}',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5, fontWeight: FontWeight.w500,
                        height: 1.4, color: _bodyColor(context),
                      )),
                ),
              ],
            )
          else ...[
            Text(
                '$_studentName ${"bu hafta en çok şu derslerde zorlandı — tekrar iyi gelir:".tr()}',
                style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w500,
                  color: _bodyColor(context),
                )),
            const SizedBox(height: 10),
            ...weak.map((e) {
              final col = barColor(e.pct);
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(e.subject,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 11.5, fontWeight: FontWeight.w700,
                            color: AppPalette.textPrimary(context),
                          )),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            height: 14,
                            decoration: BoxDecoration(
                              color: AppPalette.border(context),
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: (e.pct / 100).clamp(0.04, 1.0),
                            child: Container(
                              height: 14,
                              decoration: BoxDecoration(
                                color: col,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('%${e.pct}',
                        style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w800, color: col,
                        )),
                    Text('  · ${e.total} ${"soru".tr()}',
                        style: GoogleFonts.poppins(
                          fontSize: 9.5, fontWeight: FontWeight.w500,
                          color: AppPalette.textSecondary(context),
                        )),
                  ],
                ),
              );
            }),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 13, color: warm),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                      'İpucu: En düşük dersin konularını tekrar çözmek başarıyı en hızlı yükseltir.'
                          .tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 9.5, fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                        color: AppPalette.textSecondary(context),
                      )),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _zReport(BuildContext context) {
    // Ana ekran: Hafta (özet) → Ay (trend). Günlük detay, kategori kartına
    // basınca açılan modaldeki "Gün gün" dökümünde — burada tekrar edilmez.
    return Column(
      children: [
        _summaryBlock(context,
            today: false, title: 'Haftanın Özeti'.tr(), icon: '📅'),
        const SizedBox(height: 12),
        _monthlyReport(context), // en altta, daha detaylı (aylık trend)
      ],
    );
  }

  // Özet bloğu metrik şeridi — süre · çözülen soru · başarı · (hafta: aktif gün).
  Widget _metricsStrip(BuildContext context, bool today) {
    Widget metric(String emoji, String val) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: AppPalette.cardMuted(context),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text('$emoji $val',
              style: GoogleFonts.poppins(
                fontSize: 10.5, fontWeight: FontWeight.w700,
                color: _bodyColor(context),
              )),
        );
    final total =
        _catDistribution(today: today).values.fold<int>(0, (s, v) => s + v);
    final chips = <Widget>[metric('⏱', _fmt(total))];
    if (today) {
      final a = _activityByDate[_todayKey];
      final c = a?.correctAnswers ?? 0, w = a?.wrongAnswers ?? 0;
      final q = c + w + (a?.blankAnswers ?? 0);
      final pct = (c + w) > 0 ? (c * 100 / (c + w)).round() : 0;
      chips.add(metric('📝', '$q ${"soru".tr()}'));
      chips.add(metric('✅', '%$pct ${"başarı".tr()}'));
      chips.add(metric('📷', '${a?.photoQuestionsSolved ?? 0} ${"foto".tr()}'));
    } else {
      final q = _weekCorrect + _weekWrong + _weekBlank;
      final pct = (_weekCorrect + _weekWrong) > 0
          ? (_weekCorrect * 100 / (_weekCorrect + _weekWrong)).round()
          : 0;
      final active = _weekDateKeys
          .where((k) => (_activityByDate[k]?.focusSeconds ?? 0) > 0)
          .length;
      // En çok çalışılan ders (hafta).
      final subTotals = <String, int>{};
      for (final a in _activity) {
        a.subjectDurations.forEach((s, sec) {
          subTotals[s] = (subTotals[s] ?? 0) + sec;
        });
      }
      String topSubj = '';
      int topSec = 0;
      subTotals.forEach((s, sec) {
        if (sec > topSec) {
          topSec = sec;
          topSubj = s;
        }
      });
      chips.add(metric('📝', '$q ${"soru".tr()}'));
      chips.add(metric('✅', '%$pct ${"başarı".tr()}'));
      chips.add(metric('📅', '$active/7 ${"gün".tr()}'));
      if (topSubj.isNotEmpty) chips.add(metric('⭐', topSubj));
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  // Tek özet bloğu — SOL: pasta + değerler · SAĞ: AI koç tarzı paragraf.
  Widget _summaryBlock(BuildContext context,
      {required bool today, required String title, required String icon}) {
    final which = today ? 'today' : 'week';
    final per = _catDistribution(today: today);
    final total = per.values.fold<int>(0, (s, v) => s + v);
    final entries = per.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // Blok bg sürükle hedefi (graik/koç içeride ayrı hedefler).
    return _drop('block_$which', Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _resolve(['block_$which', 'infopanel'], AppPalette.card(context)),
        borderRadius: BorderRadius.circular(16),
        // Çerçeve çizgisi
        border: Border.all(color: _frame(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 7),
              Text(title,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5, fontWeight: FontWeight.w800,
                    color: _titleColor(context),
                  )),
              const Spacer(),
              Text(total > 0 ? _fmt(total) : '—',
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: const Color(0xFF10B981),
                  )),
            ],
          ),
          const SizedBox(height: 10),
          _metricsStrip(context, today),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SOL — pasta + değerler
                SizedBox(
                  width: 150,
                  child: Column(
                    children: [
                      _drop('pie_$which', Container(
                        height: 122,
                        decoration: BoxDecoration(
                          color: _ovColor('pie_$which'),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: total == 0
                            ? Center(
                                child: Container(
                                  width: 76, height: 76,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: AppPalette.border(context),
                                        width: 6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text('veri yok'.tr(),
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            AppPalette.textSecondary(context),
                                      )),
                                ),
                              )
                            : PieChart(PieChartData(
                                centerSpaceRadius: 24,
                                sectionsSpace: 2,
                                sections: [
                                  for (final e in entries)
                                    PieChartSectionData(
                                      value: e.value.toDouble(),
                                      color: e.key.color,
                                      radius: 34,
                                      title: (e.value * 100 / total) >= 12
                                          ? '%${(e.value * 100 / total).round()}'
                                          : '',
                                      titleStyle: GoogleFonts.poppins(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                ],
                              )),
                      ), radius: 10),
                      const SizedBox(height: 8),
                      // Değerler — kategori + yüzde
                      if (total > 0)
                        ...entries.map((e) {
                          final pct = (e.value * 100 / total).round();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    color: e.key.color,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(e.key.label.tr(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            AppPalette.textPrimary(context),
                                      )),
                                ),
                                Text('%$pct',
                                    style: GoogleFonts.poppins(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: e.key.color,
                                    )),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // SAĞ — AI koç tarzı açıklama paragrafı (ayrı sürükle hedefi)
                Expanded(
                  child: _drop('coach_$which', Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: _resolve(['coach_$which'],
                          const Color(0xFF10B981).withValues(alpha: 0.07)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF10B981)
                              .withValues(alpha: 0.20)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('🤖', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 5),
                            Text('Koç Yorumu'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 10, fontWeight: FontWeight.w800,
                                  color: const Color(0xFF059669),
                                )),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(_insight(today: today),
                            style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w500,
                              height: 1.45, color: _bodyColor(context),
                            )),
                      ],
                    ),
                  )),
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  // ── AYIN ÖZETİ — detaylı 30 günlük rapor ────────────────────────────────
  Widget _monthlyReport(BuildContext context) {
    final acts = _monthActivity;
    final entries = _monthEntries;
    final dist = _catDistFrom(entries);
    final distSorted = dist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalSec = dist.values.fold<int>(0, (s, v) => s + v);

    int corr = 0, wr = 0, photo = 0, summ = 0, activeDays = 0;
    final subjDur = <String, int>{};
    for (final a in acts) {
      corr += a.correctAnswers;
      wr += a.wrongAnswers;
      photo += a.photoQuestionsSolved;
      summ += a.summariesCreated;
      a.subjectDurations.forEach((s, sec) => subjDur[s] = (subjDur[s] ?? 0) + sec);
      if (a.focusSeconds > 0) activeDays++;
    }
    final pct = (corr + wr) > 0 ? (corr * 100 / (corr + wr)).round() : 0;
    final streak = (_baseStats['streakDays'] as num?)?.toInt() ?? 0;
    String topSubj = '';
    int topSec = 0;
    subjDur.forEach((s, sec) {
      if (sec > topSec) {
        topSec = sec;
        topSubj = s;
      }
    });
    final hasAny = totalSec > 0 || (corr + wr) > 0;

    // Haftalık kırılım — son ~30 günü 7'şerli grupla (eski→yeni).
    final weekSums = <int>[];
    for (int i = 0; i < acts.length; i += 7) {
      int s = 0;
      for (int j = i; j < i + 7 && j < acts.length; j++) {
        s += acts[j].focusSeconds;
      }
      weekSums.add(s);
    }
    final maxWeek = weekSums.fold<int>(0, (m, v) => v > m ? v : m);

    Widget metric(String emoji, String val) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: AppPalette.cardMuted(context),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text('$emoji $val',
              style: GoogleFonts.poppins(
                fontSize: 10.5, fontWeight: FontWeight.w700,
                color: _bodyColor(context),
              )),
        );

    return _drop('block_month', Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _resolve(['block_month', 'infopanel'], AppPalette.card(context)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _frame(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📆', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 7),
              Text('Ayın Özeti'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    color: _titleColor(context),
                  )),
              const SizedBox(width: 6),
              Text('· ${"Son 30 gün".tr()}',
                  style: GoogleFonts.poppins(
                    fontSize: 10, fontWeight: FontWeight.w500,
                    color: AppPalette.textSecondary(context),
                  )),
              const Spacer(),
              Text(totalSec > 0 ? _fmt(totalSec) : '—',
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: const Color(0xFF10B981),
                  )),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasAny)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('Son 30 günde kayıtlı aktivite yok.'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12, color: AppPalette.textSecondary(context),
                    )),
              ),
            )
          else ...[
            // Genişletilmiş metrik şeridi
            Wrap(
              spacing: 6, runSpacing: 6,
              children: [
                metric('⏱', _fmt(totalSec)),
                metric('📝', '${corr + wr} ${"soru".tr()}'),
                metric('✅', '%$pct ${"başarı".tr()}'),
                metric('📅', '$activeDays/$_monthDays ${"gün".tr()}'),
                metric('🔥', '$streak ${"gün seri".tr()}'),
                metric('📷', '$photo ${"foto".tr()}'),
                metric('📚', '$summ ${"özet".tr()}'),
                if (topSubj.isNotEmpty) metric('⭐', topSubj),
              ],
            ),
            const SizedBox(height: 14),
            // Kategori dağılımı (pasta + lejant)
            if (distSorted.isNotEmpty) ...[
              Text('Kategori dağılımı'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w800,
                    color: AppPalette.textSecondary(context),
                  )),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _drop('pie_month', Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      color: _ovColor('pie_month'),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: PieChart(PieChartData(
                      centerSpaceRadius: 18,
                      sectionsSpace: 2,
                      sections: [
                        for (final e in distSorted)
                          PieChartSectionData(
                            value: e.value.toDouble(),
                            color: e.key.color,
                            radius: 26,
                            title: (e.value * 100 / totalSec) >= 12
                                ? '%${(e.value * 100 / totalSec).round()}'
                                : '',
                            titleStyle: GoogleFonts.poppins(
                              fontSize: 8, fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    )),
                  ), radius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: distSorted.map((e) {
                        final p = (e.value * 100 / totalSec).round();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(children: [
                            Container(
                              width: 9, height: 9,
                              decoration: BoxDecoration(
                                color: e.key.color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(e.key.label.tr(),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 10, fontWeight: FontWeight.w600,
                                    color: AppPalette.textPrimary(context),
                                  )),
                            ),
                            Text('${_fmt(e.value)} · %$p',
                                style: GoogleFonts.poppins(
                                  fontSize: 9.5, fontWeight: FontWeight.w800,
                                  color: e.key.color,
                                )),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            // Haftalık kırılım (eski → yeni)
            if (weekSums.isNotEmpty && maxWeek > 0) ...[
              Text('Haftalık kırılım'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w800,
                    color: AppPalette.textSecondary(context),
                  )),
              const SizedBox(height: 8),
              SizedBox(
                height: 90,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(weekSums.length, (i) {
                    final v = weekSums[i];
                    final frac = maxWeek == 0 ? 0.0 : v / maxWeek;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(v > 0 ? '${v ~/ 60}' : '',
                                style: GoogleFonts.poppins(
                                  fontSize: 8, fontWeight: FontWeight.w700,
                                  color: const Color(0xFF10B981),
                                )),
                            const SizedBox(height: 2),
                            Container(
                              height: (frac.clamp(0.0, 1.0)) * 58 +
                                  (v > 0 ? 4 : 0),
                              decoration: BoxDecoration(
                                color: v > 0
                                    ? const Color(0xFF10B981)
                                    : AppPalette.border(context),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('${i + 1}. ${"hf".tr()}',
                                style: GoogleFonts.poppins(
                                  fontSize: 8, fontWeight: FontWeight.w600,
                                  color: AppPalette.textSecondary(context),
                                )),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),
            ],
            // Ders bazlı test tablosu (ay)
            if (_subjScoresFrom(acts).isNotEmpty) ...[
              _subjectScoreTableFrom(context, _subjScoresFrom(acts),
                  title: 'Ders bazlı sonuç (ay)'.tr()),
              const SizedBox(height: 14),
            ],
            // Koç yorumu (aylık)
            _drop('coach_month', Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: _resolve(['coach_month'],
                    const Color(0xFF10B981).withValues(alpha: 0.07)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.20)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🤖', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        _monthInsight(totalSec, pct, activeDays, topSubj),
                        style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w500,
                          height: 1.45, color: _bodyColor(context),
                        )),
                  ),
                ],
              ),
            ), radius: 12),
          ],
        ],
      ),
    ));
  }

  String _monthInsight(int totalSec, int pct, int activeDays, String topSubj) {
    final name = _studentName;
    if (totalSec == 0) {
      return '$name ${"son 30 günde kayıtlı çalışma oluşturmadı.".tr()}';
    }
    final tail = pct >= 70
        ? 'Başarı yüksek, tempoyu koru.'.tr()
        : (pct >= 50
            ? 'İstikrarlı; zayıf derslere biraz daha ağırlık verilebilir.'.tr()
            : 'Yanlışların üzerinden geçmek başarıyı yükseltir.'.tr());
    return '$name ${"son 30 günde toplam".tr()} ${_fmt(totalSec)} '
        '${"çalıştı, $activeDays/$_monthDays gün aktifti".tr()}'
        '${topSubj.isNotEmpty ? ", ${"en çok".tr()} $topSubj" : ""}. '
        '${"Test başarısı".tr()} %$pct. $tail';
  }

  // ── Kategori sekmesine basınca açılan modal (blur arka plan + çarpı) ────
  void _openCategoryModal(BuildContext context, _ProgressCat c) {
    int? selectedDay; // hangi gün çubuğuna basıldı
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat'.tr(),
      barrierColor: Colors.black.withValues(alpha: 0.25),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: 480,
                    maxHeight: MediaQuery.of(ctx).size.height * 0.82,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.card(ctx),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _frame(ctx), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Başlık + sağ üstte çarpı
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
                        child: Row(
                          children: [
                            Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(
                                color: c.color.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Icon(c.icon, color: c.color, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('${c.label.tr()} — ${"bu hafta".tr()}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15, fontWeight: FontWeight.w800,
                                    color: AppPalette.textPrimary(ctx),
                                  )),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: AppPalette.cardMuted(ctx),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.close_rounded,
                                    size: 18,
                                    color: AppPalette.textPrimary(ctx)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: AppPalette.border(ctx)),
                      Flexible(
                        child: StatefulBuilder(
                          builder: (ctx2, setLocal) => SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            child: _categoryContent(ctx2, c,
                              selectedDay: selectedDay,
                              onDayTap: (d) => setLocal(() {
                                selectedDay = selectedDay == d ? null : d;
                              }),
                            ),
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
    );
  }

  // Ebeveyne kısa bilgi cümlesi.
  String _categoryBlurb(_ProgressCat c, int total, bool hasAny) {
    final name = _studentName;
    if (!hasAny) return '$name ${"bu hafta bu alanda henüz çalışmadı.".tr()}';
    const tip = ' Grafiklerin üstüne basarak o günün detaylarını görebilirsiniz.';
    if (c.key == 'test') {
      final corr = _weekCorrect, wr = _weekWrong;
      final ans = corr + wr;
      final pct = ans > 0 ? (corr * 100 / ans).round() : 0;
      return '$name ${"bu hafta test sorularında".tr()} %$pct '
          '${"başarı gösterdi".tr()} ($corr ${"doğru".tr()}, $wr ${"yanlış".tr()}). '
          '${"Gün gün dağılımı aşağıda.".tr()}$tip';
    }
    if (c.key == 'photo') {
      final n = _activity.fold<int>(0, (s, a) => s + a.photoQuestionsSolved);
      return '$name ${"bu hafta".tr()} $n ${"foto soru çözdü. Hangi gün ne kadar çözdüğü aşağıda.".tr()}';
    }
    if (c.key == 'contest') {
      return '$name ${"bu hafta yarışmalara toplam".tr()} ${_fmt(total)} '
          '${"ayırdı. Katıldığı günler aşağıda.".tr()}$tip';
    }
    final subj = _subjectTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSubj = subj.isNotEmpty ? subj.first.key : '';
    return '$name ${"bu hafta".tr()} ${c.label.tr()} '
        '${"alanında toplam".tr()} ${_fmt(total)} ${"çalıştı".tr()}'
        '${topSubj.isNotEmpty ? ", ${"en çok".tr()} $topSubj" : ""}. '
        '${"Konu ve gün dağılımı aşağıda.".tr()}$tip';
  }

  // ── Kategori içeriği (modal gövdesi) ────────────────────────────────────
  Widget _categoryContent(BuildContext context, _ProgressCat c,
      {int? selectedDay, void Function(int)? onDayTap}) {
    final keys = _weekDateKeys;
    final values = keys.map(_valueOn).toList();
    final maxV = values.fold<int>(0, (m, v) => v > m ? v : m);
    final hasAny = maxV > 0;
    final total = values.fold<int>(0, (s, v) => s + v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kısa bilgi (ebeveyne)
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: c.color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.color.withValues(alpha: 0.22)),
          ),
          child: Text(_categoryBlurb(c, total, hasAny),
              style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w500, height: 1.45,
                color: AppPalette.textSecondary(context),
              )),
        ),
        const SizedBox(height: 14),

        if (!hasAny)
          _emptyState(context, c)
        else ...[
          // Haftalık çubuk grafik — derse göre renkli yığılmış
          _weekBars(context, c, keys, values, maxV,
              selectedDay: selectedDay, onDayTap: onDayTap),
          const SizedBox(height: 12),

          // Seçili gün ders dağılımı
          if (selectedDay != null && !c.isCount) ...[
            _daySubjectDetail(context, c, keys[selectedDay], selectedDay),
            const SizedBox(height: 14),
          ],

          // Test kategorisi → doğru/yanlış/boş özeti
          if (c.key == 'test') ...[
            _scoreRow(context),
            const SizedBox(height: 14),
            _subjectScoreTable(context),
            const SizedBox(height: 14),
          ],

          // Ders dağılımı (süre kategorileri)
          if (!c.isCount && _subjectTotals.isNotEmpty) ...[
            _subjectBreakdown(context, c),
            const SizedBox(height: 14),
          ],

          // Gün gün döküm (Pzt→Paz)
          Text('Gün gün'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w800,
                color: AppPalette.textSecondary(context),
              )),
          const SizedBox(height: 8),
          ...List.generate(7, (i) => _dayRow(context, c, keys[i], i)),
        ],
      ],
    );
  }

  Widget _emptyState(BuildContext context, _ProgressCat c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(c.icon, size: 36, color: c.color.withValues(alpha: 0.35)),
            const SizedBox(height: 10),
            Text('Bu hafta bu kategoride aktivite yok.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: AppPalette.textSecondary(context),
                )),
          ],
        ),
      ),
    );
  }

  Widget _weekBars(BuildContext context, _ProgressCat c, List<String> keys,
      List<int> values, int maxV,
      {int? selectedDay, void Function(int)? onDayTap}) {
    final unitMax = c.isCount ? maxV : (maxV / 60.0);
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final v = values[i];
          final disp = c.isCount ? v.toDouble() : v / 60.0;
          final frac = maxV == 0 ? 0.0 : (disp / (unitMax == 0 ? 1 : unitMax));
          final barH = (frac.clamp(0.0, 1.0)) * 82.0 + (v > 0 ? 4 : 0);
          final isSel = selectedDay == i;
          final label = c.isCount
              ? (v > 0 ? '$v' : '')
              : (v > 0 ? '${(v / 60).round()}dk' : '');

          // Gün içi ders dağılımı (sadece süre kategorilerinde)
          final daySubs = (v > 0 && !c.isCount) ? _daySubjectMap(keys[i]) : <String, int>{};
          final sorted = daySubs.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final hasMulti = sorted.length > 1;

          return Expanded(
            child: GestureDetector(
              onTap: (!c.isCount && v > 0) ? () => onDayTap?.call(i) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Kısaltmalar (çok dersli) veya toplam label
                    if (v > 0) ...[
                      if (hasMulti)
                        ...sorted.take(2).map((e) => Text(
                              _subjAbbr(e.key),
                              style: GoogleFonts.poppins(
                                fontSize: 7, fontWeight: FontWeight.w900,
                                color: _subjectColor(e.key),
                              ),
                            ))
                      else
                        Text(label,
                            style: GoogleFonts.poppins(
                              fontSize: 8, fontWeight: FontWeight.w700,
                              color: sorted.isNotEmpty
                                  ? _subjectColor(sorted.first.key)
                                  : c.color,
                            )),
                    ],
                    const SizedBox(height: 2),
                    // Çubuk
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        height: barH,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: v == 0 ? AppPalette.border(context) : null,
                        ),
                        child: hasMulti && v > 0
                            ? Column(
                                children: sorted
                                    .map((e) => Expanded(
                                          flex: e.value,
                                          child: Container(
                                              color: _subjectColor(e.key)),
                                        ))
                                    .toList(),
                              )
                            : Container(
                                color: v > 0
                                    ? (sorted.isNotEmpty
                                        ? _subjectColor(sorted.first.key)
                                        : c.color)
                                    : null,
                              ),
                      ),
                    ),
                    // Seçili gün göstergesi
                    Container(
                      width: 6, height: 6,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSel ? c.color : Colors.transparent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_weekdayLabels[i].tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                          color: isSel
                              ? c.color
                              : AppPalette.textSecondary(context),
                        )),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _scoreRow(BuildContext context) {
    Widget cell(String v, String l, Color col) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: col.withValues(alpha: 0.30)),
            ),
            child: Column(
              children: [
                Text(v,
                    style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w900, color: col,
                    )),
                Text(l,
                    style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: AppPalette.textSecondary(context),
                    )),
              ],
            ),
          ),
        );
    return Row(
      children: [
        cell('$_weekCorrect', 'Doğru'.tr(), const Color(0xFF10B981)),
        cell('$_weekWrong', 'Yanlış'.tr(), const Color(0xFFEF4444)),
        cell('$_weekBlank', 'Boş'.tr(), const Color(0xFF9CA3AF)),
      ],
    );
  }

  // Ders bazlı test tablosu: ders · çözülen · doğru · yanlış · %başarı
  Widget _subjectScoreTable(BuildContext context) =>
      _subjectScoreTableFrom(context, _weekSubjectScores);

  Widget _subjectScoreTableFrom(
      BuildContext context, Map<String, List<int>> raw,
      {String? title}) {
    final scores = raw.entries.toList()
      ..sort((a, b) =>
          (b.value[0] + b.value[1]).compareTo(a.value[0] + a.value[1]));
    if (scores.isEmpty) return const SizedBox.shrink();
    final ink = AppPalette.textPrimary(context);
    final mute = AppPalette.textSecondary(context);
    Widget headCell(String t, int flex, [TextAlign a = TextAlign.start]) =>
        Expanded(
          flex: flex,
          child: Text(t,
              textAlign: a,
              style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w800, color: mute,
              )),
        );
    Widget dataCell(String t, int flex, Color col,
            [TextAlign a = TextAlign.start, bool bold = false]) =>
        Expanded(
          flex: flex,
          child: Text(t,
              textAlign: a,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: col,
              )),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title ?? 'Ders bazlı sonuç'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w800, color: mute,
            )),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppPalette.cardMuted(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            headCell('Ders'.tr(), 5),
            headCell('Çözülen'.tr(), 3, TextAlign.center),
            headCell('D'.tr(), 2, TextAlign.center),
            headCell('Y'.tr(), 2, TextAlign.center),
            headCell('%', 3, TextAlign.end),
          ]),
        ),
        ...scores.map((e) {
          final corr = e.value[0], wr = e.value[1];
          final total = corr + wr;
          final pct = total > 0 ? (corr * 100 / total).round() : 0;
          final pctCol = pct >= 70
              ? const Color(0xFF10B981)
              : (pct >= 50 ? const Color(0xFFFBBF24) : const Color(0xFFEF4444));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              dataCell(e.key, 5, ink),
              dataCell('$total', 3, ink, TextAlign.center),
              dataCell('$corr', 2, const Color(0xFF10B981), TextAlign.center),
              dataCell('$wr', 2, const Color(0xFFEF4444), TextAlign.center),
              dataCell('%$pct', 3, pctCol, TextAlign.end, true),
            ]),
          );
        }),
      ],
    );
  }

  // Seçili gün ders dağılımı — grafik altında gösterilir.
  Widget _daySubjectDetail(
      BuildContext context, _ProgressCat c, String dateKey, int dayIdx) {
    final subs = _daySubjectMap(dateKey);
    final mute = AppPalette.textSecondary(context);
    final ink = AppPalette.textPrimary(context);
    final sorted = subs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_weekdayLabels[dayIdx].tr()} ${"ders dağılımı".tr()}',
            style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w800, color: mute,
            ),
          ),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Bu gün ders kaydı yok.'.tr(),
                  style: GoogleFonts.poppins(fontSize: 11, color: mute)),
            )
          else ...[
            const SizedBox(height: 8),
            ...sorted.map((e) {
              final col = _subjectColor(e.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 9, height: 9,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                          color: col, shape: BoxShape.circle),
                    ),
                    Expanded(
                      child: Text(e.key,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 11.5, fontWeight: FontWeight.w600,
                            color: ink,
                          )),
                    ),
                    Text(_fmt(e.value),
                        style: GoogleFonts.poppins(
                          fontSize: 11.5, fontWeight: FontWeight.w700,
                          color: col,
                        )),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _subjectBreakdown(BuildContext context, _ProgressCat c) {
    final totals = _subjectTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxSec = totals.first.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ders dağılımı'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w800,
              color: AppPalette.textSecondary(context),
            )),
        const SizedBox(height: 8),
        ...totals.take(6).map((e) {
          final frac = maxSec == 0 ? 0.0 : e.value / maxSec;
          final col = _subjectColor(e.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                ),
                SizedBox(
                  width: 80,
                  child: Text(e.key,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: AppPalette.textPrimary(context),
                      )),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppPalette.border(context),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: frac.clamp(0.05, 1.0),
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: col,
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(_fmt(e.value),
                    style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: col,
                    )),
              ],
            ),
          );
        }),
      ],
    );
  }

  // Tek gün satırı — takvim benzeri: gün adı + o gün ne yapıldı.
  Widget _dayRow(BuildContext context, _ProgressCat c, String dateKey, int i) {
    final isCount = c.isCount;
    final entries = isCount ? const <Map<String, dynamic>>[] : _entriesOn(dateKey);
    final value = _valueOn(dateKey);
    final empty = value <= 0 && entries.isEmpty;

    String summary;
    if (isCount) {
      summary = value > 0 ? '$value ${"foto soru".tr()}' : '—';
    } else {
      summary = value > 0 ? _fmt(value) : '—';
    }

    // Gün içeriği: ders/konu satırları (süre kategorileri).
    final detailLines = <String>[];
    if (!isCount) {
      // Aynı konuyu topla.
      final byTopic = <String, int>{};
      for (final e in entries) {
        final t = (e['topic'] ?? e['subject'] ?? '').toString();
        if (t.isEmpty) continue;
        byTopic[t] = (byTopic[t] ?? 0) + (e['sec'] as int? ?? 0);
      }
      byTopic.forEach((t, sec) {
        detailLines.add(sec > 0 ? '$t · ${_fmt(sec)}' : t);
      });
    } else if (c.key == 'test') {
      final a = _activityByDate[dateKey];
      if (a != null && (a.correctAnswers + a.wrongAnswers) > 0) {
        detailLines.add('${a.correctAnswers} ${"doğru".tr()} · '
            '${a.wrongAnswers} ${"yanlış".tr()}');
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: empty
            ? AppPalette.cardMuted(context)
            : c.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: empty
              ? AppPalette.border(context)
              : c.color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: empty
                  ? Colors.transparent
                  : c.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(_weekdayLabels[i].tr(),
                style: GoogleFonts.poppins(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: empty ? AppPalette.textSecondary(context) : c.color,
                )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary,
                    style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: empty
                          ? AppPalette.textSecondary(context)
                          : AppPalette.textPrimary(context),
                    )),
                if (detailLines.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  ...detailLines.take(4).map((l) => Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text('• $l',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 10.5, fontWeight: FontWeight.w500,
                              color: AppPalette.textSecondary(context),
                            )),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
