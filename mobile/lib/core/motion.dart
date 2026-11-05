import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// DAREWIRE's motion identity, following the "Premium with Playful accents" archetype from the motion-design skill:
///
/// * ONE signature curve ([premium]) for 80% of motion, with no overshoot. Entrances decelerate, exits accelerate.
/// * THREE durations: [quick] for press and toggle feedback, [standard] for cards and chips, [slow] for page-level change.
/// * Overshoot ([pop]) is reserved for tiny, joyful moments: a like, a streak, Cipher. It is never used for layout.
/// * Stagger budgets stay under 400 ms in total, and nothing travels more than a third of the screen.
class Motion {
  static const quick = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 340);
  static const slow = Duration(milliseconds: 520);

  /// The signature curve: smooth at both ends, no overshoot.
  static const Curve premium = Cubic(0.4, 0.0, 0.2, 1.0);

  /// Entrances: quick start, long gentle landing.
  static const Curve enter = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Exits: gentle start, fast departure.
  static const Curve exit = Cubic(0.3, 0.0, 1.0, 1.0);

  /// Playful overshoot. Likes, streaks and the mascot only.
  static const Curve pop = Curves.easeOutBack;

  /// Delay for the [i]th item of a cascade: 50 ms apart, never more than 300 ms in total.
  static Duration stagger(int i, {int step = 50, int max = 300}) => Duration(milliseconds: (i * step).clamp(0, max));

  /// True when the phone asks for less motion (or tests disable animations).
  static bool reduced(BuildContext c) => MediaQuery.maybeDisableAnimationsOf(c) ?? false;
}

/// Fades a child in while it rises a short way (16 px, well under a third of the screen). Plays once.
class Reveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double dy;
  const Reveal({super.key, required this.child, this.delay = Duration.zero, this.dy = 16});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    final total = Motion.slow + widget.delay;
    _c = AnimationController(vsync: this, duration: total);
    _t = CurvedAnimation(parent: _c, curve: Interval(widget.delay.inMilliseconds / total.inMilliseconds, 1.0, curve: Motion.enter));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _t.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - _t.value) * widget.dy), child: child),
        ),
      );
}

/// Press feedback for anything tappable: a small scale-down and a light haptic. Replaces ink splashes.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final String? semanticLabel;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.97, this.haptic = false, this.semanticLabel});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final body = AnimatedScale(
      scale: _down && enabled ? widget.scale : 1,
      duration: _down ? const Duration(milliseconds: 90) : Motion.quick,
      curve: _down ? Curves.easeOut : Motion.premium,
      child: widget.child,
    );
    if (!enabled) return body;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: () {
          if (widget.haptic) HapticFeedback.selectionClick();
          widget.onTap?.call();
        },
        onLongPress: widget.onLongPress,
        child: body,
      ),
    );
  }
}
