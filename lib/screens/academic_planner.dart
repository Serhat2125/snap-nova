import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/gemini_service.dart';
import '../widgets/latex_text.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Kütüphane — Konu özeti kartları + AI ile oluşturma
//  • En üstte "Kütüphanemize hoşgeldin" bannerı (3 sn)
//  • 3 tane mavi çerçeveli "+" kartı (yeni özet oluşturmak için)
//  • + basınca: ders başlığı → konu adı → Özet Oluştur akışı
//  • Geçmiş özetler alt listede
// ═══════════════════════════════════════════════════════════════════════════════

const _monthlyLimit = 15;
const _blue = Color(0xFF2563EB);
const _orange = Color(0xFFFF6A00);

class _Summary {
  final String id;
  final String topic;
  final String subject;
  final String grade;
  final String content;
  final DateTime createdAt;

  const _Summary({
    required this.id,
    required this.topic,
    required this.subject,
    required this.grade,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic,
        'subject': subject,
        'grade': grade,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory _Summary.fromJson(Map<String, dynamic> j) => _Summary(
        id: j['id'] as String,
        topic: j['topic'] as String,
        subject: j['subject'] as String,
        grade: (j['grade'] as String?) ?? '',
        content: j['content'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class AcademicPlanner extends StatefulWidget {
  const AcademicPlanner({super.key});
  @override
  State<AcademicPlanner> createState() => _AcademicPlannerState();
}

class _AcademicPlannerState extends State<AcademicPlanner>
    with SingleTickerProviderStateMixin {
  static const _summariesKey = 'topic_summaries_v1';
  static const _usageKey = 'topic_summary_usage';

  String _grade = '';
  int _monthUsed = 0;
  String _monthKey = '';
  List<_Summary> _summaries = [];

  // Hoşgeldin bannerı
  bool _showWelcome = true;
  Timer? _welcomeTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _welcomeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showWelcome = false);
    });
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    super.dispose();
  }

  // ── Depolama ───────────────────────────────────────────────────────────────
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final grade = prefs.getString('user_grade_level') ?? '';

    final now = DateTime.now();
    final mkey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final usageRaw = prefs.getString(_usageKey);
    var used = 0;
    if (usageRaw != null) {
      try {
        final j = jsonDecode(usageRaw) as Map<String, dynamic>;
        if (j['month'] == mkey) used = (j['count'] as num).toInt();
      } catch (_) {}
    }

    final listRaw = prefs.getStringList(_summariesKey) ?? [];
    final list = listRaw
        .map((s) {
          try {
            return _Summary.fromJson(
                jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<_Summary>()
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (!mounted) return;
    setState(() {
      _grade = grade;
      _monthKey = mkey;
      _monthUsed = used;
      _summaries = list;
    });
  }

  Future<void> _persistUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _usageKey,
      jsonEncode({'month': _monthKey, 'count': _monthUsed}),
    );
  }

  Future<void> _persistSummaries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _summariesKey,
      _summaries.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  // ── Yeni özet üret: önce bottom sheet, sonra AI çağrısı ───────────────────
  Future<void> _startNewSummary() async {
    if (_monthUsed >= _monthlyLimit) {
      _showSnack('Bu ay kullanılabilir özet hakkınız doldu.');
      return;
    }
    final result = await showModalBottomSheet<_NewRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewSummarySheet(),
    );
    if (result == null || !mounted) return;
    await _generate(result.subject, result.topic);
  }

  Future<void> _generate(String subject, String topic) async {
    final loading = ValueNotifier(true);
    // Yükleniyor dialog'u
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child:
                  CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Özet hazırlanıyor…',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final prompt =
          'Konu: "$topic"\nDers: $subject\nSınıf: ${_grade.isEmpty ? "lise" : _grade}\n\n'
          'Bu öğrencinin sınıf düzeyine uygun, net ve anlaşılır kısa bir konu özeti hazırla. '
          'Şu bölümleri içer:\n'
          '📚 KONU: [konunun adı]\n'
          '🔑 TEMEL KAVRAMLAR: [3-5 madde, her biri 1 cümle]\n'
          '📐 ANAHTAR FORMÜLLER: [varsa LaTeX ile — sayısal derslerde]\n'
          '💡 PÜF NOKTA: [1-2 cümle]\n'
          '🎯 ÖRNEK: [küçük çözümlü 1 örnek — sayısal ders ise]';

      final content = await GeminiService.solveHomework(
        question: prompt,
        solutionType: 'KonuÖzeti',
        subject: subject,
      );

      final summary = _Summary(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        topic: topic,
        subject: subject,
        grade: _grade,
        content: content,
        createdAt: DateTime.now(),
      );
      _summaries.insert(0, summary);
      _monthUsed += 1;
      await _persistSummaries();
      await _persistUsage();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // loading
      setState(() {});
      _openSummary(summary);
    } on GeminiException catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showSnack(e.userMessage);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showSnack('Hata: $e');
      }
    } finally {
      loading.dispose();
    }
  }

  Future<void> _delete(_Summary s) async {
    setState(() => _summaries.removeWhere((x) => x.id == s.id));
    await _persistSummaries();
  }

  void _openSummary(_Summary s) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _SummaryDetailPage(summary: s)),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final remaining = _monthlyLimit - _monthUsed;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          'Kütüphane',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
                vertical: 10, horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _orange),
              ),
              alignment: Alignment.center,
              child: Text(
                '$remaining / $_monthlyLimit',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _orange,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              child: _showWelcome
                  ? _welcomeBanner()
                  : const SizedBox(width: double.infinity, height: 0),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'İstediğin konunun özetini oluştur',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: _addCard(onTap: _startNewSummary)),
                  const SizedBox(width: 10),
                  Expanded(child: _addCard(onTap: _startNewSummary)),
                  const SizedBox(width: 10),
                  Expanded(child: _addCard(onTap: _startNewSummary)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (_summaries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Özetlerin',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            ..._summaries.map((s) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _SummaryCard(
                    summary: s,
                    onTap: () => _openSummary(s),
                    onDelete: () => _delete(s),
                  ),
                )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _welcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDBEAFE), Color(0xFFBFDBFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Kütüphanemize hoşgeldin!',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addCard({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 0.85, // tam kare değil, dikey uyumlu
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _blue, width: 1),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.add_rounded,
                color: _blue, size: 26),
          ),
        ),
      ),
    );
  }
}

// ── Yeni Özet Bottom Sheet ──────────────────────────────────────────────────
class _NewRequest {
  final String subject;
  final String topic;
  const _NewRequest({required this.subject, required this.topic});
}

class _NewSummarySheet extends StatefulWidget {
  const _NewSummarySheet();
  @override
  State<_NewSummarySheet> createState() => _NewSummarySheetState();
}

class _NewSummarySheetState extends State<_NewSummarySheet> {
  final _subjectCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();
  final _topicFocus = FocusNode();

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _topicCtrl.dispose();
    _topicFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Ders Başlığı Girin',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _subjectCtrl,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _topicFocus.requestFocus(),
              style: GoogleFonts.poppins(fontSize: 15),
              decoration: _dec('Örn. Matematik'),
            ),
            const SizedBox(height: 16),
            Text(
              'Konu Adı',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _topicCtrl,
              focusNode: _topicFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: GoogleFonts.poppins(fontSize: 15),
              decoration: _dec('Örn. Türev kuralları'),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(
                  'Özet Oluştur',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          fontSize: 14,
          color: Colors.grey.shade400,
        ),
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  void _submit() {
    final subject = _subjectCtrl.text.trim();
    final topic = _topicCtrl.text.trim();
    if (subject.isEmpty || topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ders başlığı ve konu adı gerekli.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pop(context, _NewRequest(subject: subject, topic: topic));
  }
}

// ── Özet Kartı (liste) ──────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final _Summary summary;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _SummaryCard({
    required this.summary,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final d = summary.createdAt;
    final dateText =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.bookmark_rounded,
                    color: _blue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.subject} · $dateText',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: Colors.grey.shade500),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Detay ─────────────────────────────────────────────────────────────────
class _SummaryDetailPage extends StatelessWidget {
  final _Summary summary;
  const _SummaryDetailPage({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          summary.topic,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _blue),
              ),
              child: Text(
                '${summary.subject}${summary.grade.isNotEmpty ? " · ${summary.grade}" : ""}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _blue,
                ),
              ),
            ),
            const SizedBox(height: 18),
            LatexText(
              summary.content,
              fontSize: 15,
              lineHeight: 1.6,
            ),
          ],
        ),
      ),
    );
  }
}
