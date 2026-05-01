// VoiceCommandScreen — Sesli komut ekranı.
// Kullanıcı mikrofona basıp soru sorar; transkript canlı gösterilir;
// final transcript Gemini'ye iletilir; cevap aşağıda görünür.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart' show localeService;
import '../services/analytics.dart';
import '../services/gemini_service.dart';
import '../services/runtime_translator.dart';
import '../services/usage_quota.dart';
import '../widgets/latex_text.dart';
import '../widgets/voice_input_button.dart';

class VoiceCommandScreen extends StatefulWidget {
  const VoiceCommandScreen({super.key});

  @override
  State<VoiceCommandScreen> createState() => _VoiceCommandScreenState();
}

class _VoiceCommandScreenState extends State<VoiceCommandScreen> {
  String _transcript = '';
  bool _transcriptFinal = false;
  bool _solving = false;
  String? _aiAnswer;
  GeminiException? _error;

  Future<void> _onComplete(String finalText) async {
    if (finalText.trim().isEmpty) return;
    // Quota check (Solution kategorisi).
    final quota = await UsageQuota.get(QuotaKind.solution);
    if (quota.isExhausted) {
      Analytics.logQuotaExhausted(QuotaKind.solution.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(quota.isDailyExhausted
            ? 'Günlük çözüm sınırına ulaştın (${quota.dailyLimit}).'
            : 'Aylık çözüm sınırına ulaştın (${quota.monthlyLimit}).'),
      ));
      return;
    }
    await UsageQuota.increment(QuotaKind.solution);
    Analytics.logEvent('voice_question_asked', params: {
      'lang': localeService.localeCode,
      'length': finalText.length,
    });
    setState(() {
      _solving = true;
      _aiAnswer = null;
      _error = null;
    });
    try {
      final answer = await GeminiService.solveHomework(
        question: finalText,
        solutionType: 'Adım Adım Çöz',
        subject: 'Genel',
      );
      if (!mounted) return;
      setState(() {
        _aiAnswer = answer;
        _solving = false;
      });
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _solving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = GeminiException.unknown(e.toString());
        _solving = false;
      });
    }
  }

  void _onText(String text, bool isFinal) {
    if (!mounted) return;
    setState(() {
      _transcript = text;
      _transcriptFinal = isFinal;
    });
  }

  void _onError(String reason) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(reason)),
    );
  }

  void _reset() {
    setState(() {
      _transcript = '';
      _transcriptFinal = false;
      _aiAnswer = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Text(
          localeService.tr('voice_command'),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_transcript.isNotEmpty || _aiAnswer != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Sıfırla'.tr(),
              onPressed: _reset,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ── Transkript bölümü ─────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: VoiceTranscriptView(
                  text: _transcript,
                  isFinal: _transcriptFinal,
                ),
              ),
              const SizedBox(height: 20),

              // ── Mikrofon butonu ──────────────────────────────────────
              VoiceInputButton(
                localeCode: localeService.localeCode,
                size: 88,
                onText: _onText,
                onComplete: _onComplete,
                onError: _onError,
              ),
              const SizedBox(height: 12),
              Text(
                'Mikrofona bas, sorunu sor.\nKonuşman bittiğinde otomatik çözülecek.'
                    .tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // ── AI cevabı / hata / loading ────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: _buildAnswerSection(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerSection() {
    if (_solving) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'AI çözüm üretiyor…'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEF4444)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF4444)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error!.userMessage,
                style: GoogleFonts.poppins(fontSize: 13, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }
    if (_aiAnswer != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
                    ),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'QuAlsar AI',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF22C55E), size: 16),
              ],
            ),
            const SizedBox(height: 12),
            LatexText(_aiAnswer!, fontSize: 14, lineHeight: 1.6),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
