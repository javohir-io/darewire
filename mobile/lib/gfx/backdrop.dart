import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/perf.dart';
import '../core/theme.dart';
import 'y2k.dart';

/// One shared clock (seconds) for the background. It runs at 15 frames a second (the motion is slow, so this looks smooth and costs little),
/// stops when the OS asks for reduced motion, and can be switched off in Settings for older phones.
class GlassClock {
  static final ValueNotifier<double> t = ValueNotifier<double>(8.0);

  /// The user's choice in Settings (remembered on the device).
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  /// Set while something full-screen covers the scene (the Feed's video): nothing to see, so nothing to paint.
  static final ValueNotifier<bool> paused = ValueNotifier<bool>(false);
  static const _key = 'motion_enabled';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled.value = p.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, v);
  }
}

/// The live scene behind every screen. Four big colour fields from the theme drift and swell on a near-black base (the idea behind
/// shadergradient), an iridescent sheen turns slowly across it, glossy bubbles float up and a few sparkles twinkle (the Y2K
/// reference). Glass blurs all of this, which is what makes the glass visibly glassy. Text always sits on the dark base or on a panel.
class AppBackdrop extends StatefulWidget {
  const AppBackdrop({super.key});
  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    GlassClock.enabled.addListener(_apply);
    GlassClock.paused.addListener(_apply);
    Perf.lite.addListener(_apply);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apply();
  }

  void _apply() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context) || !GlassClock.enabled.value || GlassClock.paused.value || Perf.lite.value) {
      _ticker?.stop();
      GlassClock.t.value = 8.0;
    } else {
      _ticker ??= createTicker((d) {
        final s = d.inMicroseconds / 1000000.0;
        if (s - _last >= 1 / 15) {
          _last = s;
          GlassClock.t.value = s;
        }
      });
      if (!_ticker!.isActive) _ticker!.start();
    }
  }

  @override
  void dispose() {
    GlassClock.enabled.removeListener(_apply);
    GlassClock.paused.removeListener(_apply);
    Perf.lite.removeListener(_apply);
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: ValueListenableBuilder<bool>(valueListenable: Perf.lite, builder: (_, lite, __) => CustomPaint(size: Size.infinite, painter: _ScenePainter(GlassClock.t, C.pal, lite))));
}

class _Field {
  final double x, y, ax, ay, phase, size, strength;
  final int kx, ky, color;
  const _Field(this.x, this.y, this.ax, this.ay, this.kx, this.ky, this.phase, this.size, this.strength, this.color);
}

const _fields = [
  _Field(0.05, 0.06, 0.26, 0.12, 1, 2, 0.00, 1.25, 0.70, 0),
  _Field(1.00, 0.40, 0.20, 0.18, 2, 1, 0.34, 1.15, 0.58, 1),
  _Field(0.10, 0.88, 0.28, 0.12, 1, 1, 0.66, 1.20, 0.60, 2),
  _Field(0.78, 0.98, 0.18, 0.10, 2, 2, 0.15, 0.95, 0.40, 0),
];

class _Bubble {
  final double x, size, speed, phase, sway;
  const _Bubble(this.x, this.size, this.speed, this.phase, this.sway);
}

const _bubbles = [
  _Bubble(0.82, 64, 1.0, 0.10, 0.04),
  _Bubble(0.16, 38, 1.0, 0.55, 0.05),
  _Bubble(0.58, 22, 2.0, 0.80, 0.03),
  _Bubble(0.92, 18, 2.0, 0.30, 0.03),
  _Bubble(0.34, 88, 1.0, 0.95, 0.04),
];

const List<List<double>> _sparks = [
  [0.14, 0.20, 9.0, 0.0], [0.86, 0.12, 12.0, 0.3], [0.70, 0.46, 7.0, 0.6], [0.08, 0.62, 10.0, 0.15], [0.92, 0.78, 8.0, 0.8], [0.50, 0.90, 6.0, 0.45],
];

class _ScenePainter extends CustomPainter {
  final ValueNotifier<double> t;
  final Pal pal;
  final bool lite;
  _ScenePainter(this.t, this.pal, this.lite) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final v = (t.value / 36.0) % 1.0; // one seamless loop every 36 seconds
    const tau = math.pi * 2;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [pal.bg2, pal.bg]).createShader(rect));

    // 1. colour fields, drifting and swelling
    for (final f in lite ? _fields.take(2) : _fields) {
      final cx = size.width * (f.x + f.ax * math.sin(tau * (f.kx * v + f.phase)));
      final cy = size.height * (f.y + f.ay * math.cos(tau * (f.ky * v + f.phase)));
      final r = size.shortestSide * f.size * (1 + 0.12 * math.sin(tau * (2 * v + f.phase)));
      final col = pal.blobs[f.color % pal.blobs.length];
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..shader = RadialGradient(colors: [col.withAlpha((f.strength * 255).round()), col.withAlpha((f.strength * 110).round()), col.withAlpha(0)], stops: const [0, 0.5, 1]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }

    // (smooth mode paints only two fields: no sheen, bubbles or sparkles)
    if (lite) {
      canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, pal.bg.withAlpha(150)], stops: const [0.55, 1]).createShader(rect));
      return;
    }

    // 2. an iridescent sheen turning slowly (very low strength: it tints, it does not paint)
    final c = Offset(size.width * 0.85, size.height * 0.22);
    canvas.drawCircle(
      c,
      size.longestSide * 0.75,
      Paint()..shader = ui.Gradient.sweep(c, [for (final h in C.holoColors) h.withAlpha(34)], null, TileMode.clamp, tau * v, tau * v + tau),
    );

    // 3. glossy bubbles rising
    for (final b in _bubbles) {
      final rise = (v * b.speed + b.phase) % 1.0;
      final cy = size.height * (1.12 - rise * 1.3);
      final cx = size.width * (b.x + b.sway * math.sin(tau * (v * 2 + b.phase)));
      _bubble(canvas, Offset(cx, cy), b.size / 2, pal.blobs[(b.size.toInt()) % pal.blobs.length]);
    }

    // 4. sparkles
    for (final s in _sparks) {
      final tw = 0.5 + 0.5 * math.sin(tau * (v * 3 + s[3]));
      final a = (60 + 150 * tw).round();
      final r = s[2] * (0.6 + 0.5 * tw);
      canvas.drawPath(SparklePainter.star(Offset(size.width * s[0], size.height * s[1]), r, 0.12), Paint()..color = Colors.white.withAlpha(a));
    }

    // a floor so the bottom stays calm under the tab bar
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, pal.bg.withAlpha(150)], stops: const [0.55, 1]).createShader(rect));
  }

  /// A soap-bubble: a faint tinted body, a bright specular highlight at the top-left and a thin rim.
  void _bubble(Canvas canvas, Offset c, double r, Color tint) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()..shader = RadialGradient(center: const Alignment(-0.4, -0.5), radius: 1.1, colors: [Colors.white.withAlpha(70), tint.withAlpha(26), tint.withAlpha(70)], stops: const [0, 0.6, 1]).createShader(rect));
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withAlpha(60));
    canvas.drawOval(Rect.fromCenter(center: c + Offset(-r * 0.38, -r * 0.42), width: r * 0.5, height: r * 0.28), Paint()..color = Colors.white.withAlpha(120));
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => old.pal.id != pal.id || old.lite != lite;
}
