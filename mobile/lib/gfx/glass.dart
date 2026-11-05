import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/motion.dart';
import '../core/perf.dart';
import '../core/theme.dart';
import '../ui/widgets/kit.dart' show Avatar;

/// Liquid glass, for things that FLOAT over content: the tab bar, sheets, and controls over video.
/// (Cards that hold content are flat [Surface]s instead. Glass everywhere is what makes an interface look busy.)
///
/// What makes it read as glass rather than a grey box, bottom to top:
///  1. the scene behind it, blurred;
///  2. a faint body tint, lighter at the top, with a little dark underneath so text stays readable on bright video;
///  3. a soft specular sheen near the light-facing top-left corner;
///  4. a 1px rim that is bright where light hits (top-left) and bottom-right, and almost gone in between;
///  5. a soft shadow drawn only OUTSIDE the shape (a normal box shadow would show through the glass and muddy it).
/// Corners are continuous (squircle) like iOS. Nothing here animates, so lists and scrolling stay smooth.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;

  /// Washes the glass with a colour (a selected or highlighted state). Use sparingly.
  final Color? tint;

  /// Lighter glass for small controls over video: thinner body, softer shadow.
  /// Small controls over video are NOT blurred: at that size the blur is barely visible, but re-blurring every video frame
  /// for a dozen chips is what makes a phone stutter. They get a slightly darker tinted body instead.
  final bool clear;
  const Glass({super.key, required this.child, this.radius = R.lg, this.padding = const EdgeInsets.all(16), this.blur = 28, this.tint, this.clear = false});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));
    return ValueListenableBuilder<bool>(
      valueListenable: Perf.lite,
      builder: (context, lite, _) {
        // Real blur only for the few large panels (tab bar, sheets, composer, sign-in card), and never in smooth mode.
        final blurred = !clear && !lite && blur > 0;
        final body = CustomPaint(
          foregroundPainter: _Rim(shape, clear),
          // Two layers on purpose: a solid base, then the light gradient on top. (A BoxDecoration with both a colour and a gradient
          // paints ONLY the gradient, so the base would silently disappear and the panel would be see-through.)
          child: DecoratedBox(
            decoration: BoxDecoration(color: blurred ? C.a(C.bg2, 0.80) : (clear ? C.a(Colors.black, 0.30) : C.a(C.bg2, 0.97))),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: tint != null ? [C.a(tint!, 0.34), C.a(tint!, 0.14)] : [C.a(Colors.white, clear ? 0.15 : 0.11), C.a(Colors.white, clear ? 0.05 : 0.045)],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        );
        return CustomPaint(
          painter: _OuterShadow(shape, clear),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(radius),
            child: blurred ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: blur * 0.6, sigmaY: blur * 0.6), child: body) : body,
          ),
        );
      },
    );
  }
}

class _OuterShadow extends CustomPainter {
  final ShapeBorder shape;
  final bool clear;
  const _OuterShadow(this.shape, this.clear);

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape.getOuterPath(Offset.zero & size);
    final big = Path()..addRect(Rect.fromLTWH(-120, -120, size.width + 240, size.height + 280));
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, big, path)); // paint outside the glass only
    canvas.drawPath(
      path.shift(Offset(0, clear ? 5 : 12)),
      Paint()
        ..color = C.a(Colors.black, clear ? 0.22 : 0.34)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, clear ? 8 : 16),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OuterShadow old) => old.clear != clear;
}

class _Rim extends CustomPainter {
  final ShapeBorder shape;
  final bool clear;
  const _Rim(this.shape, this.clear);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final path = shape.getInnerPath(rect.deflate(0.5));
    // a soft specular pool near the top-left corner
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(center: const Alignment(-0.85, -1.15), radius: 1.05, colors: [C.a(Colors.white, clear ? 0.16 : 0.12), Colors.transparent]).createShader(rect),
    );
    canvas.restore();
    // the rim: bright where light enters (top-left) and leaves (bottom-right)
    final k = clear ? 0.8 : 1.0;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [C.a(Colors.white, 0.46 * k), C.a(Colors.white, 0.07), C.a(Colors.white, 0.05), C.a(Colors.white, 0.26 * k)],
          stops: const [0, 0.38, 0.66, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _Rim old) => old.clear != clear;
}

/// The glass look WITHOUT the blur: light gradient body, specular rim and a soft outer shadow. Cheap enough for every card on a screen.
/// Over the live backdrop it reads as glass; [Glass] adds the real blur for the few things that sit over video or imagery.
class GlassPane extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Washes the pane with a colour (a highlighted state).
  final Color? tint;

  /// Draws a solid outline in this colour instead of the soft rim (a chosen option).
  final Color? outline;

  /// A soft drop shadow. Off by default: a blurred shadow under every card in a scrolling list is costly.
  final bool elevated;
  const GlassPane({super.key, required this.child, this.radius = R.lg, this.padding = const EdgeInsets.all(16), this.tint, this.outline, this.elevated = false});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));
    return CustomPaint(
      painter: elevated ? _OuterShadow(shape, true) : null,
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          foregroundPainter: outline == null ? _Rim(shape, false) : _Outline(shape, outline!),
          child: DecoratedBox(
            decoration: BoxDecoration(color: C.a(C.bg2, 0.72)),   // the base (see the note in Glass: colour + gradient in one decoration loses the colour)
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 340),
              curve: Motion.premium,
              padding: padding,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: tint != null ? [C.a(tint!, 0.36), C.a(tint!, 0.16)] : [C.a(Colors.white, 0.13), C.a(Colors.white, 0.055)],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _Outline extends CustomPainter {
  final ShapeBorder shape;
  final Color color;
  const _Outline(this.shape, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawPath(shape.getInnerPath((Offset.zero & size).deflate(0.8)), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = color);
  }

  @override
  bool shouldRepaint(covariant _Outline old) => old.color != color;
}

/// A circular glass control (icon, with an optional small label underneath), used for the action rail over video.
class GlassOrb extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool active;
  final Color? activeColor;
  final double size;
  final String semantics;
  const GlassOrb({super.key, required this.icon, required this.onTap, required this.semantics, this.label, this.active = false, this.activeColor, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final c = active ? (activeColor ?? C.accent2) : Colors.white;
    return Pressable(
      semanticLabel: semantics,
      onTap: onTap,
      scale: 0.9,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: size,
          height: size,
          child: Glass(radius: 999, clear: true, blur: 22, padding: EdgeInsets.zero, child: Center(child: Icon(icon, color: c, size: size * 0.46))),
        ),
        if (label != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text(label!, style: T.label(11.5).copyWith(color: Colors.white, shadows: const [Shadow(blurRadius: 6, color: Color(0x99000000))]))),
      ]),
    );
  }
}

/// A small floating chip with an avatar and a handle.
class PersonChip extends StatelessWidget {
  final String avatar, handle;
  final VoidCallback? onTap;
  const PersonChip({super.key, required this.avatar, required this.handle, this.onTap});
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Glass(
          radius: R.pill,
          clear: true,
          blur: 18,
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Avatar(avatar, size: 28), const SizedBox(width: 8), Text('@$handle', style: T.strong(13))]),
        ),
      );
}
