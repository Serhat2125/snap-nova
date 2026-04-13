import 'package:flutter/material.dart';

class SolutionOptionCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isSelected;
  final bool isCentered;
  final VoidCallback onTap;

  const SolutionOptionCard({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.isSelected,
    this.isCentered = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = accentColor;
    final sel = isSelected;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isCentered ? 1.08 : (sel ? 1.05 : 1.0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: 98,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: sel
                  ? [
                      c.withValues(alpha: 0.22),
                      const Color(0xFF0B0B18),
                    ]
                  : [
                      const Color(0xFF0E0E1C),
                      const Color(0xFF07070F),
                    ],
            ),
            border: Border.all(
              color: c.withValues(alpha: sel ? 0.80 : (isCentered ? 0.55 : 0.28)),
              width: sel ? 1.6 : (isCentered ? 1.4 : 1.1),
            ),
            boxShadow: isCentered
                ? [
                    BoxShadow(
                      color: c.withValues(alpha: 0.50),
                      blurRadius: 20,
                      spreadRadius: 1,
                    ),
                  ]
                : sel
                    ? [
                        BoxShadow(
                          color: c.withValues(alpha: 0.30),
                          blurRadius: 16,
                          spreadRadius: 0,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Icon badge ────────────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: c.withValues(alpha: (sel || isCentered) ? 0.20 : 0.12),
                    border: Border.all(
                      color: c.withValues(alpha: (sel || isCentered) ? 0.60 : 0.25),
                      width: 1.0,
                    ),
                    // İkon badge glow yok
                  ),
                  child: Icon(icon, color: c, size: 16),
                ),
                const SizedBox(height: 7),
                // ── Title ─────────────────────────────────────────────
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: (sel || isCentered)
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.85),
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                // ── Subtitle ──────────────────────────────────────────
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: sel
                        ? c.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.38),
                    height: 1.2,
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
