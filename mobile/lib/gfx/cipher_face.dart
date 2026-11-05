import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';

const moodLabel = {
  'idle': 'Calm',
  'thinking': 'Thinking',
  'happy': 'Happy',
  'laugh': 'Excited',
  'sad': 'Low',
  'shy': 'Shy',
  'surprised': 'Surprised',
  'worried': 'Uneasy',
  'curious': 'Curious',
  'suspicious': 'Wary',
  'sleepy': 'Sleepy',
};

/// How each mood looks. There is no face: Cipher shows how he feels through colour, glow, motion and shape.
class _Feel {
  final double pulse; // breathing speed
  final double wobble; // how much the surface ripples
  final double bounce; // vertical bounce
  final double glow; // core brightness 0..1
  final double ring; // ring orbit speed
  final double squash; // resting squash (below 1 = sunk, above 1 = stretched)
  final double tint; // 0 = theme colour, 1 = full mood colour
  final Color? color;
  const _Feel(this.pulse, this.wobble, this.bounce, this.glow, this.ring, this.squash, this.tint, this.color);
}

_Feel _feelOf(String mood) => switch (mood) {
      'happy' => _Feel(1.6, 0.05, 0.05, 0.9, 1.4, 1.02, 0.45, C.accent2),
      'laugh' => _Feel(3.4, 0.07, 0.09, 1.0, 2.4, 1.0, 0.6, C.accent),
      'sad' => _Feel(0.6, 0.02, 0.0, 0.25, 0.4, 0.93, 0.5, const Color(0xFF5E7BFF)),
      'shy' => _Feel(1.2, 0.03, 0.01, 0.6, 0.8, 0.96, 0.6, const Color(0xFFFF7DB8)),
      'surprised' => _Feel(4.2, 0.06, 0.03, 1.0, 3.0, 1.06, 0.4, C.accent),
      'worried' => _Feel(2.8, 0.09, 0.0, 0.45, 1.2, 0.97, 0.45, const Color(0xFFFFB347)),
      'curious' => _Feel(1.4, 0.04, 0.02, 0.8, 2.0, 1.03, 0.35, C.accent),
      'suspicious' => _Feel(0.9, 0.02, 0.0, 0.5, 0.7, 0.98, 0.6, const Color(0xFFFF4D4D)),
      'sleepy' => _Feel(0.35, 0.015, 0.0, 0.15, 0.2, 0.95, 0.3, const Color(0xFF7A8CFF)),
      'thinking' => _Feel(1.8, 0.04, 0.0, 0.7, 3.6, 1.0, 0.3, C.edgeA),
      _ => _Feel(1.0, 0.035, 0.015, 0.7, 1.0, 1.0, 0.0, null),
    };

/// Cipher: a small living 3D orb. No eyes, no mouth. He breathes, his surface ripples, a ring orbits him, and a core glows inside.
/// He tilts toward your finger, squishes when you tap him, throws sparks, and his colour and motion change with his mood.
class CipherFace extends StatefulWidget {
  final String mood;
  final double size;
  final bool talking;
  final bool interactive;

  /// Called on every touch, so the owner can show a line of dialogue or wake him up.
  final VoidCallback? onTap;
  const CipherFace({super.key, this.mood = 'idle', this.size = 180, this.talking = false, this.interactive = true, this.onTap});

  @override
  State<CipherFace> createState() => _CipherFaceState();
}

class _Spark {
  final int id;
  final double dx;
  _Spark(this.id, this.dx);
}

class _CipherFaceState extends State<CipherFace> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  late final AnimationController _squish = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  final _rng = math.Random();
  final _sparks = <_Spark>[];
  Timer? _revert, _tapReset;
  Offset _look = Offset.zero;
  String? _override;
  int _taps = 0, _sparkId = 0;

  @override
  void dispose() {
    _revert?.cancel();
    _tapReset?.cancel();
    _loop.dispose();
    _squish.dispose();
    super.dispose();
  }

  void _poke() {
    HapticFeedback.lightImpact();
    widget.onTap?.call();
    _squish.forward(from: 0);
    _taps++;
    _tapReset?.cancel();
    _tapReset = Timer(const Duration(milliseconds: 1400), () => _taps = 0);
    setState(() {
      _override = _taps >= 6 ? 'surprised' : (_taps >= 3 ? 'laugh' : 'happy');
      for (var i = 0; i < 3; i++) {
        _sparks.add(_Spark(_sparkId++, (_rng.nextDouble() - 0.5) * widget.size * 0.7));
      }
    });
    _revert?.cancel();
    _revert = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _override = null);
    });
  }

  void _track(Offset local) {
    final d = (local - Offset(widget.size / 2, widget.size / 2)) / (widget.size / 2);
    setState(() => _look = Offset(d.dx.clamp(-1.0, 1.0), d.dy.clamp(-1.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final mood = _override ?? widget.mood;
    final s = widget.size;
    final orb = AnimatedBuilder(
      animation: Listenable.merge([_loop, _squish]),
      builder: (context, _) => CustomPaint(
        size: Size(s, s),
        painter: _OrbPainter(feel: _feelOf(mood), t: still ? 0 : _loop.value * 60, look: _look, squish: math.sin(_squish.value * math.pi) * (1 - _squish.value * 0.3), talk: widget.talking, pal: C.pal),
      ),
    );
    return Semantics(
      button: widget.interactive,
      label: 'Cipher, feeling ${moodLabel[mood]?.toLowerCase() ?? 'calm'}. Tap to say hi.',
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.interactive ? (d) => _track(d.localPosition) : null,
            onTap: widget.interactive ? _poke : null,
            onPanUpdate: widget.interactive ? (d) => _track(d.localPosition) : null,
            onPanEnd: widget.interactive ? (_) => setState(() => _look = Offset.zero) : null,
            child: orb,
          ),
          for (final sp in _sparks)
            Positioned(
              key: ValueKey(sp.id),
              left: s / 2 + sp.dx - 8,
              top: s * 0.12,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1100),
                  onEnd: () {
                    if (mounted) setState(() => _sparks.removeWhere((x) => x.id == sp.id));
                  },
                  builder: (context, v, _) => Opacity(
                    opacity: (1 - v).clamp(0.0, 1.0),
                    child: Transform.translate(offset: Offset(math.sin(v * 6 + sp.id) * 8, -v * s * 0.4), child: Icon(Icons.auto_awesome_rounded, size: 10 + 12 * (1 - v), color: C.accent)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final _Feel feel;
  final double t, squish;
  final Offset look;
  final bool talk;
  final Pal pal;
  _OrbPainter({required this.feel, required this.t, required this.look, required this.squish, required this.talk, required this.pal});

  Color _mood(Color base) => feel.color == null ? base : Color.lerp(base, feel.color, feel.tint)!;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final breath = math.sin(t * feel.pulse * 1.2) * 0.5 + 0.5; // 0..1
    final bob = math.sin(t * (1.0 + feel.pulse * 0.5)) * s * 0.012 - (feel.bounce > 0 ? (math.sin(t * feel.pulse * 3).abs()) * s * feel.bounce : 0);
    final sx = (1 + 0.03 * breath + 0.16 * squish) * (2 - feel.squash).clamp(0.95, 1.08);
    final sy = (1 - 0.03 * breath - 0.16 * squish) * feel.squash;
    final r0 = s * 0.31;
    final c0 = Offset(s / 2 + look.dx * s * 0.025, s * 0.52 + look.dy * s * 0.015);

    final hi = _mood(pal.primaryHi);
    final mid = _mood(pal.primary);
    final deep = Color.lerp(mid, Colors.black, 0.62)!;
    final glowCol = _mood(pal.accent);

    // ground shadow, and a coloured pool of light on the "floor"
    canvas.drawOval(Rect.fromCenter(center: Offset(s / 2, s * 0.9), width: s * 0.55 * (1 + squish * 0.15), height: s * 0.07), Paint()..color = Colors.black.withAlpha(120)..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03));
    canvas.drawOval(Rect.fromCenter(center: Offset(s / 2, s * 0.9), width: s * 0.7, height: s * 0.09), Paint()..color = mid.withAlpha((60 + 80 * feel.glow).round())..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.05));

    canvas.save();
    canvas.translate(c0.dx, s * 0.9);
    canvas.scale(sx, sy);
    canvas.translate(-c0.dx, -s * 0.9 + bob);

    // orbit ring, back half (behind the body)
    final ringRect = Rect.fromCenter(center: c0, width: r0 * 2.75, height: r0 * 0.85);
    final ringPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.012..color = _mood(pal.edgeB).withAlpha(150);
    canvas.save();
    canvas.translate(c0.dx, c0.dy);
    canvas.rotate(-0.32 + look.dx * 0.12);
    canvas.translate(-c0.dx, -c0.dy);
    canvas.drawArc(ringRect, math.pi, math.pi, false, ringPaint);
    final beadA = t * feel.ring * 1.1;
    final bx = c0.dx + math.cos(beadA) * ringRect.width / 2, by = c0.dy + math.sin(beadA) * ringRect.height / 2;
    final beadFront = math.sin(beadA) > 0;
    void bead() {
      canvas.drawCircle(Offset(bx, by), s * 0.03, Paint()..color = glowCol.withAlpha(200)..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.02));
      canvas.drawCircle(Offset(bx, by), s * 0.016, Paint()..color = Colors.white);
    }

    if (!beadFront) bead();
    canvas.restore();

    // outer aura
    canvas.drawCircle(c0, r0 * 1.25, Paint()..shader = RadialGradient(colors: [glowCol.withAlpha((50 + 70 * feel.glow).round()), Colors.transparent]).createShader(Rect.fromCircle(center: c0, radius: r0 * 1.25)));

    // the body: a sphere whose surface ripples slowly
    final path = Path();
    const n = 72;
    for (var i = 0; i <= n; i++) {
      final a = i / n * math.pi * 2;
      final w = feel.wobble * (math.sin(a * 3 + t * 1.3 * feel.pulse) * 0.6 + math.sin(a * 5 - t * 0.9 * feel.pulse) * 0.4 + (talk ? math.sin(a * 4 + t * 14) * 0.5 : 0));
      final r = r0 * (1 + w);
      final p = Offset(c0.dx + math.cos(a) * r, c0.dy + math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    final light = Offset(c0.dx - r0 * (0.38 - look.dx * 0.15), c0.dy - r0 * (0.46 - look.dy * 0.15));
    canvas.drawShadow(path, mid.withAlpha(200), s * 0.03, true);
    canvas.drawPath(path, Paint()..shader = RadialGradient(center: Alignment.center, radius: 1.0, colors: [hi, mid, deep], stops: const [0, 0.55, 1]).createShader(Rect.fromCircle(center: light, radius: r0 * 1.6)));

    canvas.save();
    canvas.clipPath(path);
    // inner glowing core that pulses
    final coreR = r0 * (0.42 + 0.08 * breath + (talk ? 0.06 * math.sin(t * 14) : 0));
    canvas.drawCircle(c0.translate(look.dx * r0 * 0.1, r0 * 0.12), coreR * 1.8, Paint()..shader = RadialGradient(colors: [glowCol.withAlpha((90 + 150 * feel.glow).round()), Colors.transparent]).createShader(Rect.fromCircle(center: c0, radius: coreR * 1.8)));
    canvas.drawCircle(c0.translate(look.dx * r0 * 0.1, r0 * 0.12), coreR * 0.42, Paint()..color = Colors.white.withAlpha((120 + 110 * feel.glow).round())..maskFilter = MaskFilter.blur(BlurStyle.normal, r0 * 0.18));
    // fresnel rim light along the lower right
    canvas.drawCircle(c0, r0, Paint()..style = PaintingStyle.stroke..strokeWidth = r0 * 0.35..shader = SweepGradient(startAngle: 0, endAngle: math.pi * 2, colors: [_mood(pal.edgeB).withAlpha(170), Colors.transparent, Colors.transparent, _mood(pal.edgeB).withAlpha(170)], stops: const [0, 0.25, 0.6, 1], transform: GradientRotation(math.pi * 0.15)).createShader(Rect.fromCircle(center: c0, radius: r0))..maskFilter = MaskFilter.blur(BlurStyle.normal, r0 * 0.18));
    // soft top-left sheen and a crisp specular dot
    canvas.drawOval(Rect.fromCenter(center: light.translate(r0 * 0.1, 0), width: r0 * 0.85, height: r0 * 0.5), Paint()..color = Colors.white.withAlpha(90)..maskFilter = MaskFilter.blur(BlurStyle.normal, r0 * 0.1));
    canvas.drawCircle(light.translate(-r0 * 0.08, -r0 * 0.04), r0 * 0.07, Paint()..color = Colors.white.withAlpha(230));
    canvas.restore();
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = Colors.white.withAlpha(70));

    // orbit ring, front half (in front of the body)
    canvas.save();
    canvas.translate(c0.dx, c0.dy);
    canvas.rotate(-0.32 + look.dx * 0.12);
    canvas.translate(-c0.dx, -c0.dy);
    canvas.drawArc(ringRect, 0, math.pi, false, ringPaint..color = _mood(pal.edgeB).withAlpha(235));
    if (beadFront) bead();
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}
