// ═══════════════════════════════════════════════════════════════════════════
//  StudentHomeworksScreen — Öğrencinin katıldığı sınıflardan gelen ödevler.
//
//  Liste: tüm sınıfların aktif ödevleri (tarih bazlı sıralı).
//  Karta tıkla → HomeworkSolveScreen açılır → ödev çözülür → submission Firestore.
//
//  Profile veya Library'den giriş alır. Aynı zamanda push notification'dan
//  açılabilir (homework_assigned tap).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'homework_solve_screen.dart';

class StudentHomeworksScreen extends StatefulWidget {
  const StudentHomeworksScreen({super.key});

  @override
  State<StudentHomeworksScreen> createState() => _StudentHomeworksScreenState();
}

class _StudentHomeworksScreenState extends State<StudentHomeworksScreen> {
  List<JoinedClass> _classes = [];
  // Öğretmen onayı bekleyen sınıflar — ödevleri gizli, üstte bilgi şeridi.
  List<JoinedClass> _pendingClasses = [];
  Map<String, List<HomeworkModel>> _byClass = {};
  Map<String, HomeworkSubmissionModel?> _mySubmissions = {};
  bool _loading = true;
  // Yükleme hatası (ağ/izin) — sessizce "ödev yok" göstermek yanıltıcıydı;
  // kullanıcıya hata + tekrar dene sunulur.
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      // Tüm sınıfları al
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid == null) {
        setState(() => _loading = false);
        return;
      }
      // joined classes
      final joinedSnap = await FirebaseFirestore.instance
          .collection('users').doc(myUid)
          .collection('joined_classes').get();
      final rawClasses = joinedSnap.docs
          .map((d) => JoinedClass.fromMap(d.id, d.data())).toList();
      // Üyelik durumunu CANLI üyelik dökümanından doğrula: öğretmen onayı
      // bekleyen (pending) sınıfların ödevleri gizlenir; üyeliği silinmiş
      // (reddedilmiş/çıkarılmış) sınıflar hiç listelenmez.
      final classes = <JoinedClass>[];
      final pending = <JoinedClass>[];
      await Future.wait(rawClasses.map((c) async {
        try {
          final member = await FirebaseFirestore.instance
              .collection('classes').doc(c.classId)
              .collection('students').doc(myUid).get();
          if (!member.exists) return;
          final st = (member.data()?['status'] ?? 'active').toString();
          if (st == 'pending') {
            pending.add(c.withStatus('pending'));
          } else {
            classes.add(c.withStatus(st));
          }
        } catch (_) {
          classes.add(c); // okuma hatasında sınıfı KORU
        }
      }));
      _classes = classes;
      _pendingClasses = pending;
      // Her sınıfın aktif ödevleri + benim teslimlerim — sınıflar arası ve
      // teslim okumaları PARALEL (eski seri N+1 akış 3 sınıf × 20 ödevde
      // 60+ ardışık istek yapıp sayfayı saniyelerce bekletiyordu).
      final byClass = <String, List<HomeworkModel>>{};
      final subs = <String, HomeworkSubmissionModel?>{};
      await Future.wait(classes.map((c) async {
        final hwSnap = await FirebaseFirestore.instance
            .collection('classes').doc(c.classId)
            .collection('homeworks')
            .orderBy('dueAt', descending: false)
            .limit(50).get();
        // Yayın zamanı gelmemiş (zamanlanmış) ödevler öğrencide gizli kalır.
        final hws = hwSnap.docs
            .map(HomeworkModel.fromDoc)
            .where((hw) => hw.isPublished)
            .toList();
        byClass[c.classId] = hws;
        await Future.wait(hws.map((hw) async {
          final subSnap = await FirebaseFirestore.instance
              .collection('classes').doc(c.classId)
              .collection('homeworks').doc(hw.id)
              .collection('submissions').doc(myUid).get();
          if (subSnap.exists) {
            subs[hw.id] = HomeworkSubmissionModel.fromMap(subSnap.data()!);
          }
        }));
      }));
      _byClass = byClass;
      _mySubmissions = subs;
    } catch (_) {
      _error = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final allHws = <(JoinedClass, HomeworkModel)>[];
    for (final c in _classes) {
      for (final hw in (_byClass[c.classId] ?? const <HomeworkModel>[])) {
        allHws.add((c, hw));
      }
    }
    // Bitiş tarihine göre sırala — en yakın bitenler önce
    allHws.sort((a, b) => a.$2.dueAt.compareTo(b.$2.dueAt));

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Sınıf Ödevlerim'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: ink),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Onay bekleyen sınıflar — ödevler öğretmen onayına kadar gizli.
                  for (final c in _pendingClasses)
                    _buildPendingBanner(context, c),
                  Expanded(child: RefreshIndicator(
                onRefresh: _load,
                child: allHws.isEmpty
                    // Boş/hata durumunda da aşağı çekilebilsin diye
                    // kaydırılabilir sarmalayıcı.
                    ? LayoutBuilder(
                        builder: (ctx, cons) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: cons.maxHeight,
                            child: _error
                                ? _buildError(context)
                                : _buildEmpty(context),
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: allHws.length,
                        itemBuilder: (ctx, i) {
                          final (cls, hw) = allHws[i];
                          final sub = _mySubmissions[hw.id];
                          return _buildHwCard(
                              context, cls, hw, sub, ink, muted);
                        },
                      ),
              )),
                ],
              ),
      ),
    );
  }

  /// Öğretmen onayı bekleyen sınıf için bilgi şeridi.
  Widget _buildPendingBanner(BuildContext context, JoinedClass c) {
    const amber = Color(0xFFF59E0B);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '"${c.className}" ${'sınıfı için öğretmen onayı bekleniyor. '
                  'Onaylanınca ödevleri burada göreceksin.'.tr()}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppPalette.textPrimary(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHwCard(BuildContext context, JoinedClass cls, HomeworkModel hw,
      HomeworkSubmissionModel? sub, Color ink, Color muted) {
    // Status badge
    Color statusColor; String statusLabel;
    if (sub?.isSubmitted ?? false) {
      statusColor = const Color(0xFF10B981); statusLabel = 'Teslim edildi'.tr();
    } else if (sub?.status == 'in_progress') {
      statusColor = const Color(0xFF06B6D4); statusLabel = 'Devam ediyor'.tr();
    } else if (hw.isOverdue) {
      statusColor = const Color(0xFFEF4444); statusLabel = 'Süresi geçti'.tr();
    } else {
      statusColor = const Color(0xFFFBBF24); statusLabel = 'Bekliyor'.tr();
    }
    final remaining = hw.timeRemaining;
    final remainingStr = remaining.isNegative
        ? 'Süre doldu'.tr()
        : remaining.inDays > 0
            ? '${remaining.inDays} gün kaldı'.tr()
            : remaining.inHours > 0
                ? '${remaining.inHours} saat kaldı'.tr()
                : '${remaining.inMinutes} dakika kaldı'.tr();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HomeworkSolveScreen(
              classId: cls.classId, homework: hw, submission: sub,
            ),
          ));
          _load(); // dönünce yenile
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (sub?.isSubmitted ?? false)
                  ? const Color(0xFF10B981).withValues(alpha: 0.30)
                  : AppPalette.border(context),
              width: (sub?.isSubmitted ?? false) ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(statusLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w800,
                          color: statusColor,
                        )),
                  ),
                  const Spacer(),
                  Text(remainingStr,
                      style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: hw.isOverdue
                            ? const Color(0xFFEF4444)
                            : muted,
                      )),
                ],
              ),
              const SizedBox(height: 8),
              Text(hw.title,
                  style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w800, color: ink,
                  ),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${cls.className} · ${hw.subject} · ${hw.topic}',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5, color: muted,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.help_outline_rounded, size: 14, color: muted),
                  const SizedBox(width: 4),
                  Text('${hw.questionCount} soru'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 11, color: muted,
                      )),
                  const SizedBox(width: 12),
                  if (sub?.scorePercent != null) ...[
                    Icon(Icons.star_rounded, size: 14,
                        color: const Color(0xFFFBBF24)),
                    const SizedBox(width: 4),
                    Text('%${sub!.scorePercent!.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w800,
                          color: const Color(0xFFB45309),
                        )),
                  ],
                  // Öğretmen cevap anahtarını paylaştıysa — sınıf geneli
                  // ya da yalnız bu öğrenciye — (ve teslim edilmişse)
                  // karta rozet; dokununca çözümler görülür.
                  if ((hw.answersShared || (sub?.answersShared ?? false)) &&
                      (sub?.isSubmitted ?? false)) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.key_rounded,
                        size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 3),
                    Text('Cevaplar paylaşıldı'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 10.5, fontWeight: FontWeight.w800,
                          color: const Color(0xFFB45309),
                        )),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Yükleme hatası — "ödev yok" ile karışmasın; tekrar dene butonlu.
  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📡', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Ödevler yüklenemedi'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 6),
            Text(
              'İnternet bağlantını kontrol edip tekrar dene.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED)),
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Tekrar Dene'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Henüz ödev yok'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 6),
            Text(
              'Sınıfa katıldığın öğretmenler ödev gönderince burada görünür.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
