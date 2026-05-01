// VoiceInputButton — bas-konuş mikrofon butonu, dalga animasyonu ile.
// Anlık transkript callback'le parent'a aktarılır; final transcript onComplete.
//
// Kullanım:
//   VoiceInputButton(
//     localeCode: localeService.localeCode,   // 'tr', 'en' vb.
//     onText: (text, isFinal) { ... },
//     onComplete: (final) { ... },
//   )

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/voice_input_service.dart';

class VoiceInputButton extends StatefulWidget {
  /// `LocaleService.localeCode` ('tr', 'en', 'jp'...) — cihaz tanıma diline çevrilir.
  final String localeCode;
  final void Function(String text, bool isFinal) onText;
  final void Function(String finalText)? onComplete;
  final void Function(String reason)? onError;
  /// Buton boyutu — küçük: 44, varsayılan: 56, büyük: 72.
  final double size;
  /// Renk gradyan — kırmızı (default), turkuaz, mor vb.
  final List<Color> colors;
  /// Compact mode: sadece ikon (label yok)
  final bool iconOnly;

  const VoiceInputButton({
    super.key,
    required this.localeCode,
    required this.onText,
    this.onComplete,
    this.onError,
    this.size = 56,
    this.colors = const [Color(0xFFFF6A00), Color(0xFFEF4444)],
    this.iconOnly = false,
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  bool _listening = false;
  bool _initialized = false;
  bool _available = false;
  double _level = 0;
  String _lastFinal = '';
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _initOnce();
  }

  Future<void> _initOnce() async {
    final ok = await VoiceInputService.init();
    if (!mounted) return;
    setState(() {
      _initialized = true;
      _available = ok;
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    if (_listening) VoiceInputService.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_available) {
      widget.onError?.call('Cihaz konuşma tanımayı desteklemiyor.');
      return;
    }
    final hasPermission = await VoiceInputService.requestMic();
    if (!hasPermission) {
      widget.onError?.call('Mikrofon izni reddedildi.');
      return;
    }
    final localeId =
        await VoiceInputService.resolveLocaleId(widget.localeCode);
    final started = await VoiceInputService.start(
      onResult: (text, isFinal) {
        if (!mounted) return;
        widget.onText(text, isFinal);
        if (isFinal) {
          _lastFinal = text;
          _stop(); // final geldikçe otomatik durdur
        }
      },
      onLevel: (lvl) {
        if (!mounted) return;
        setState(() => _level = lvl);
      },
      localeId: localeId,
    );
    if (!started) {
      widget.onError?.call('Dinleme başlatılamadı.');
      return;
    }
    if (mounted) setState(() => _listening = true);
  }

  Future<void> _stop() async {
    await VoiceInputService.stop();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _level = 0;
    });
    if (_lastFinal.isNotEmpty) {
      widget.onComplete?.call(_lastFinal);
    }
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _stop();
    } else {
      await _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return GestureDetector(
      onTap: _initialized ? _toggle : null,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          // Listening sırasında pulse + level'a göre büyüme
          final pulseScale = _listening
              ? 1.0 + 0.08 * _pulse.value + 0.18 * _level
              : 1.0;
          return Transform.scale(
            scale: pulseScale,
            child: Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _listening
                      ? widget.colors
                      : [
                          Colors.white,
                          Colors.white,
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: _listening
                      ? Colors.transparent
                      : widget.colors.last.withValues(alpha: 0.45),
                  width: 1.4,
                ),
                boxShadow: _listening
                    ? [
                        BoxShadow(
                          color: widget.colors.last.withValues(alpha: 0.40),
                          blurRadius: 24 + 16 * _level,
                          spreadRadius: 2 + 4 * _level,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              alignment: Alignment.center,
              child: Icon(
                _listening ? Icons.stop_rounded : Icons.mic_rounded,
                color: _listening ? Colors.white : widget.colors.last,
                size: s * 0.42,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Basit transkript display — gelen text'i gerçek zamanlı gösterir.
class VoiceTranscriptView extends StatelessWidget {
  final String text;
  final bool isListening;
  final bool isFinal;
  final TextStyle? style;
  const VoiceTranscriptView({
    super.key,
    required this.text,
    this.isListening = false,
    this.isFinal = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final s = style ??
        GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
          height: 1.4,
        );
    if (text.isEmpty) {
      return Text(
        isListening ? 'Dinleniyor…' : 'Konuşmaya başlamak için mikrofona bas.',
        style: s.copyWith(
            color: Colors.black45, fontStyle: FontStyle.italic),
      );
    }
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 180),
      style: s.copyWith(
        color: isFinal ? Colors.black : Colors.black87,
        fontWeight: isFinal ? FontWeight.w700 : FontWeight.w500,
      ),
      child: Text(text),
    );
  }
}
