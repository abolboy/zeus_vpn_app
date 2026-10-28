import 'package:flutter/material.dart';
import 'dart:math';

const Color neonCyan = Color(0xFF00F0FF);
const Color neonMagenta = Color(0xFFFF007F);
const Color neonGreen = Color(0xFF00FF88);
const Color neonAmber = Color(0xFFFFB800);
const Color glass = Color(0xFF0A0A14);

class CyberPainter extends CustomPainter {
  final double t;
  CyberPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = neonCyan.withValues(alpha: 0.06)..strokeWidth = 1;
    final horizon = size.height * 0.42;
    final shift = (t * 6) % 1;
    for (double i = 0; i <= 14; i++) {
      final f = (i + shift) / 14;
      final y = horizon + (size.height - horizon) * f * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (double i = -14; i <= 14; i++) {
      canvas.drawLine(Offset(size.width / 2, horizon), Offset(size.width / 2 + i * (size.width / 12), size.height), grid);
    }
    final rnd = Random(7);
    for (int i = 0; i < 40; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * horizon * 0.9;
      final tw = 0.5 + 0.5 * sin(t * 2 * pi + i);
      final star = Paint()..color = neonMagenta.withValues(alpha: 0.15 + 0.3 * tw);
      canvas.drawCircle(Offset(x, y), 1.2 * tw, star);
    }
  }
  @override
  bool shouldRepaint(CyberPainter old) => old.t != t;
}

class ScanlinePainter extends CustomPainter {
  final double t;
  ScanlinePainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final y = t * size.height;
    canvas.drawRect(Rect.fromLTWH(0, y - 30, size.width, 30), Paint()..color = neonCyan.withValues(alpha: 0.05));
    canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), Paint()..color = neonCyan.withValues(alpha: 0.25));
  }
  @override
  bool shouldRepaint(ScanlinePainter old) => old.t != t;
}
