import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The chrome four-point star from the Y2K reference: a concave star with a silver-to-lilac gradient and a bright edge.
/// Used as the brand mark and as a small "sparkle" accent. [color] tints it for use inside a theme-coloured area.
class Sparkle extends StatelessWidget {
  final double size;
  final Color? color;
  const Sparkle({super.key, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: SparklePainter(color: color));
}

class SparklePainter extends CustomPainter {
  final Color? color;
  final double glow;
  const SparklePainter({this.color, this.glow = 0});

  static Path star(Offset c, double r, [double pinch = 0.16]) {
    final p = Path()..moveTo(c.dx, c.dy - r);
    final k = r * pinch;
    p.quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy);
    p.quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r);
    p.quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy);
    p.quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r);
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = star(c, r);
    if (glow > 0) canvas.drawPath(path, Paint()..color = (color ?? const Color(0xFFB79CFF)).withAlpha((glow * 255).round())..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5));
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: color != null ? [Colors.white, color!, Color.lerp(color!, Colors.black, 0.25)!, Colors.white] : const [Colors.white, Color(0xFFD9D4F2), Color(0xFF9E92D6), Color(0xFFF4F1FF)],
          stops: const [0, 0.35, 0.7, 1],
        ).createShader(rect),
    );
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = math.max(0.6, size.shortestSide * 0.03)..color = Colors.white.withAlpha(190));
  }

  @override
  bool shouldRepaint(covariant SparklePainter old) => old.color != color || old.glow != glow;
}

/// Gradient-filled text (for one word of a headline).
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Gradient gradient;
  const GradientText(this.text, {super.key, required this.style, this.gradient = C.holoLinear});

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => gradient.createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
        child: Text(text, style: style.copyWith(color: Colors.white)),
      );
}

/// A thin iridescent outline around a child (used on the hero card and the create button).
class HoloRing extends StatelessWidget {
  final Widget child;
  final double radius;
  final double width;
  const HoloRing({super.key, required this.child, this.radius = 30, this.width = 1.4});

  @override
  Widget build(BuildContext context) => CustomPaint(foregroundPainter: _HoloRingPainter(radius, width), child: child);
}

class _HoloRingPainter extends CustomPainter {
  final double radius, width;
  const _HoloRingPainter(this.radius, this.width);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));
    canvas.drawPath(
      shape.getInnerPath(rect.deflate(width / 2)),
      Paint()..style = PaintingStyle.stroke..strokeWidth = width..shader = const SweepGradient(colors: C.holoColors, transform: GradientRotation(0.6)).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _HoloRingPainter old) => false;
}
