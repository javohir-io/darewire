import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/config.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../gfx/glass.dart';

// The shared building blocks. The rules that keep every screen looking like one product:
//   * Content sits on flat [Surface]s: one hairline, no glow, no gradient. Glass is only for what floats over content.
//   * One accent per area. Colour means something: primary = the thing to tap, accent = points, accent2 = like and streak, danger = live and stop.
//   * Hierarchy comes from size and tone (text, dim, faint), not from borders and effects.
//   * Everything tappable gives feedback through [Pressable] (a small scale), never an ink splash.

void toast(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
}

String compact(int n) => n >= 1000000 ? '${(n / 1000000).toStringAsFixed(1)}M' : n >= 10000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';

// ---- surfaces -------------------------------------------------------------------------------------------------------

/// The standard card: a glass pane (light body, specular rim, soft shadow) over the live scene. No blur, so any number fit on a screen.
class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  /// Highlights the card with the theme colour (a chosen option, or something waiting on you).
  final bool selected;

  /// A colour wash for the pane.
  final Color? color;
  const Surface({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = R.lg, this.onTap, this.selected = false, this.color});

  @override
  Widget build(BuildContext context) {
    final card = GlassPane(radius: radius, padding: padding, tint: selected ? C.primary : color, outline: selected ? C.primaryHi : null, child: child);
    return onTap == null ? card : Pressable(onTap: onTap, child: card);
  }
}

/// A set of rows in one card, separated by inset hairlines (like an iOS grouped list).
class GroupedList extends StatelessWidget {
  final List<Widget> children;
  const GroupedList({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Surface(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) Padding(padding: const EdgeInsets.only(left: 60), child: Divider(height: 1, thickness: 1, color: C.hairline)),
          ],
        ]),
      );
}

/// A rounded-square badge holding an icon, tinted with a colour. Used in rows, empty states and tiles.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  const IconBadge(this.icon, {super.key, this.size = 36, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? C.primaryHi;
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(color: C.a(c, 0.16), shape: squircle(size * 0.3)),
      child: Icon(icon, size: size * 0.52, color: c),
    );
  }
}

/// A big screen title with room for actions on the right, like the large title in an iOS navigation bar.
class ScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const ScreenHeader(this.title, {super.key, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.large(36)),
              if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: T.body(14))),
            ]),
          ),
          for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a),
        ]),
      );
}

// ---- buttons --------------------------------------------------------------------------------------------------------

enum BtnKind { primary, glass, danger, quiet }

/// primary: the one thing to do. glass: a calm secondary (flat, despite the name, so it is cheap in lists).
/// danger: destructive or stopping, tinted not solid. quiet: text only.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final IconData? icon, trailingIcon;
  final bool busy, expand;
  final double height;
  const AppButton({super.key, required this.label, this.onPressed, this.kind = BtnKind.primary, this.icon, this.trailingIcon, this.busy = false, this.expand = true, this.height = 52});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final Color fg = switch (kind) {
      BtnKind.primary => C.onColor(C.primary),
      BtnKind.glass => C.text,
      BtnKind.danger => C.danger,
      BtnKind.quiet => C.dim,
    };
    final BoxDecoration deco = switch (kind) {
      BtnKind.primary => BoxDecoration(gradient: C.brand, borderRadius: BorderRadius.circular(R.pill), border: Border.all(color: C.a(Colors.white, 0.28)), boxShadow: [BoxShadow(color: C.a(C.primary, 0.45), blurRadius: 22, offset: const Offset(0, 8), spreadRadius: -8)]),
      BtnKind.glass => BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.a(Colors.white, 0.16), C.a(Colors.white, 0.07)]), borderRadius: BorderRadius.circular(R.pill), border: Border.all(color: C.a(Colors.white, 0.20))),
      BtnKind.danger => BoxDecoration(color: C.a(C.danger, 0.14), borderRadius: BorderRadius.circular(R.pill), border: Border.all(color: C.a(C.danger, 0.35))),
      BtnKind.quiet => BoxDecoration(borderRadius: BorderRadius.circular(R.pill)),
    };
    final content = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (busy)
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
      else ...[
        if (icon != null) ...[Icon(icon, size: 19, color: fg), const SizedBox(width: 8)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.strong(15.5).copyWith(color: fg, fontWeight: FontWeight.w700))),
        if (trailingIcon != null) ...[const SizedBox(width: 6), Icon(trailingIcon, size: 18, color: fg)],
      ],
    ]);
    final button = AnimatedOpacity(
      duration: Motion.quick,
      opacity: enabled || busy ? 1 : 0.45,
      child: Container(height: kind == BtnKind.quiet ? math.min(height, 44) : height, width: expand ? double.infinity : null, padding: const EdgeInsets.symmetric(horizontal: 22), decoration: deco, child: Center(widthFactor: 1, child: content)),
    );
    return Pressable(
      semanticLabel: label,
      haptic: kind == BtnKind.primary,
      onTap: enabled ? onPressed : null,
      scale: 0.97,
      child: button,
    );
  }
}

// ---- small pieces ---------------------------------------------------------------------------------------------------

/// A quiet label chip. With a colour it becomes a status chip (tinted background, coloured text); without, it is neutral.
class Tag extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  const Tag(this.text, {super.key, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? C.dim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: ShapeDecoration(color: color != null ? C.a(color!, 0.14) : C.surfaceHi, shape: const StadiumBorder()),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label(12).copyWith(color: fg))),
      ]),
    );
  }
}

/// Difficulty as five small dots.
class Pips extends StatelessWidget {
  final int level;
  final int max;
  const Pips(this.level, {super.key, this.max = 5});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Difficulty $level of $max',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < max; i++)
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: i < level ? C.a(Colors.white, 0.85) : C.a(Colors.white, 0.18)),
            ),
        ]),
      );
}

/// A small coloured dot, for status ("live", "waiting").
class StatusDot extends StatelessWidget {
  final Color color;
  final double size;
  const StatusDot(this.color, {super.key, this.size = 7});
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

/// A person's picture. [ring] adds a thin white ring; [live] turns the ring into a colour ring (like a story that is live now).
class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool ring;
  final bool live;
  const Avatar(this.name, {super.key, this.size = 44, this.ring = false, this.live = false});

  static String _asset(String name) {
    if (RegExp(r'^a(0[1-9]|1[0-2])$').hasMatch(name)) return 'assets/avatars/$name.png';
    final h = name.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xFFFF);
    return 'assets/avatars/a${((h % 12) + 1).toString().padLeft(2, '0')}.png';
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(_asset(name), width: size, height: size, fit: BoxFit.cover, alignment: Alignment.topCenter);
    final isCustom = name.startsWith('/v1/avatars/');
    final photo = isCustom ? Image.network('${Env.apiUrl}$name', width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback) : fallback;
    // Built-in avatars are transparent busts, so they sit on a quiet disc; photos fill the circle.
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [C.a(C.primaryHi, 0.40), C.a(C.accent2, 0.30)])),
      child: ClipOval(child: photo),
    );
    if (!ring && !live) return disc;
    final gap = size >= 80 ? 4.0 : 2.0;
    final w = size >= 80 ? 2.5 : 2.0;
    return Container(
      padding: EdgeInsets.all(w),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: live ? LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [C.accent2, C.primaryHi]) : null,
        color: live ? null : C.a(Colors.white, 0.22),
      ),
      child: Container(padding: EdgeInsets.all(gap), decoration: BoxDecoration(shape: BoxShape.circle, color: C.bg), child: disc),
    );
  }
}

/// A section heading with an optional "see all" action.
class SectionTitle extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.text, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Text(text, style: T.wide(15).copyWith(fontWeight: FontWeight.w700))),
          if (action != null)
            Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Text(action!, style: T.strong(13.5).copyWith(color: C.primaryHi)), Icon(Icons.chevron_right_rounded, size: 18, color: C.primaryHi)]),
              ),
            ),
        ]),
      );
}

/// A small quiet label above a block of content.
class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const Eyebrow(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Text(text, style: T.label(12.5).copyWith(color: color ?? C.faint));
}

/// A number with a caption, on a flat tile.
class StatTile extends StatelessWidget {
  final IconData icon;
  final String value, label;
  const StatTile({super.key, required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Surface(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        radius: R.md,
        child: Column(children: [
          Icon(icon, size: 18, color: C.faint),
          const SizedBox(height: 8),
          Text(value, style: T.num(20)),
          const SizedBox(height: 2),
          Text(label, style: T.label(12), textAlign: TextAlign.center),
        ]),
      );
}

/// An iOS-style segmented control. Over video use [clear] (real glass); on a normal screen it is a flat track.
class Segmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool clear;
  const Segmented({super.key, required this.labels, required this.index, required this.onChanged, this.clear = false});

  @override
  Widget build(BuildContext context) {
    final track = LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / labels.length;
      return SizedBox(
        height: 38,
        child: Stack(children: [
          AnimatedPositioned(
            duration: Motion.standard,
            curve: Motion.premium,
            left: index * w,
            width: w,
            top: 0,
            bottom: 0,
            child: Container(
              decoration: ShapeDecoration(
                color: C.a(Colors.white, clear ? 0.22 : 0.16),
                shape: const StadiumBorder(),
                shadows: [BoxShadow(color: C.a(Colors.black, 0.25), blurRadius: 8, offset: const Offset(0, 2))],
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: labels[i],
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (i != index) HapticFeedback.selectionClick();
                      onChanged(i);
                    },
                    child: Center(child: AnimatedDefaultTextStyle(duration: Motion.quick, style: T.strong(13.5).copyWith(color: i == index ? Colors.white : C.a(Colors.white, 0.62)), child: Text(labels[i]))),
                  ),
                ),
              ),
          ]),
        ]),
      );
    });
    if (clear) return Glass(radius: R.pill, clear: true, blur: 24, padding: const EdgeInsets.all(4), child: track);
    return Container(padding: const EdgeInsets.all(4), decoration: ShapeDecoration(color: C.surface, shape: StadiumBorder(side: BorderSide(color: C.hairline))), child: track);
  }
}

/// Points balance as a small pill.
class PointsPill extends StatelessWidget {
  final int points;
  final VoidCallback? onTap;
  const PointsPill(this.points, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
        semanticLabel: '$points points',
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          decoration: ShapeDecoration(color: C.surfaceHi, shape: StadiumBorder(side: BorderSide(color: C.hairline))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bolt_rounded, size: 17, color: C.accent),
            const SizedBox(width: 4),
            Text(compact(points), style: T.num(14.5)),
          ]),
        ),
      );
}

/// Shown when a list is empty or something went wrong. Calm, with one clear next step.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            IconBadge(icon, size: 56, color: C.dim),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: T.title(18)),
            if (message != null) ...[const SizedBox(height: 6), Text(message!, textAlign: TextAlign.center, style: T.body(14))],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ]),
        ),
      );
}

/// One row of a [GroupedList]: icon badge, title, optional subtitle, and a chevron (or your own trailing widget).
class ListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
  final Widget? trailing;
  const ListRow({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.danger = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = danger ? C.danger : C.primaryHi;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          IconBadge(icon, size: 32, color: c),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.strong(15.5).copyWith(color: danger ? C.danger : C.text)),
              if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: T.body(13))),
            ]),
          ),
          trailing ?? (onTap != null ? Icon(Icons.chevron_right_rounded, color: C.faint, size: 22) : const SizedBox.shrink()),
        ]),
      ),
    );
  }
}

/// Rebuilds ~10x/second with the time left until a SERVER deadline. Uses the server clock offset, so it cannot be gamed
/// by changing the phone's clock and stays accurate after a reconnect.
class DeadlineBuilder extends StatefulWidget {
  final int? deadline;
  final int? startedAt;
  final int offsetMs;
  final Widget Function(BuildContext context, int remainingMs, double fraction) builder;
  const DeadlineBuilder({super.key, required this.deadline, this.startedAt, required this.offsetMs, required this.builder});

  @override
  State<DeadlineBuilder> createState() => _DeadlineBuilderState();
}

class _DeadlineBuilderState extends State<DeadlineBuilder> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.deadline;
    if (d == null) return widget.builder(context, 0, 0);
    final now = DateTime.now().millisecondsSinceEpoch + widget.offsetMs;
    final remaining = math.max(0, d - now);
    final total = widget.startedAt != null ? math.max(1, d - widget.startedAt!) : math.max(1, remaining);
    return widget.builder(context, remaining, (remaining / total).clamp(0.0, 1.0));
  }
}

String clock(int ms) {
  final s = (ms / 1000).ceil();
  final m = s ~/ 60;
  return m > 0 ? '$m:${(s % 60).toString().padLeft(2, '0')}' : '${s}s';
}

/// A countdown / progress bar. Solid theme colour, turning to the warning colour as time runs low. No glow.
class ProgressBar extends StatelessWidget {
  final double fraction;
  final double height;
  final bool urgent;
  const ProgressBar({super.key, required this.fraction, this.height = 6, this.urgent = false});

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return Container(
      height: height,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(height), color: C.a(Colors.white, 0.10)),
      child: LayoutBuilder(
        builder: (context, c) => Align(
          alignment: Alignment.centerLeft,
          child: Container(width: math.max(height, c.maxWidth * f), decoration: BoxDecoration(borderRadius: BorderRadius.circular(height), color: urgent ? C.danger : C.primaryHi)),
        ),
      ),
    );
  }
}

/// Floating reactions rising from the bottom-right, fed by the server's "reaction" events.
class ReactionLayer extends StatefulWidget {
  final Stream<String> kinds;
  const ReactionLayer({super.key, required this.kinds});

  @override
  State<ReactionLayer> createState() => _ReactionLayerState();
}

const reactionEmoji = {'fire': '🔥', 'clap': '👏', 'laugh': '😂', 'wow': '😮', 'heart': '❤️'};

class _Particle {
  final int id;
  final String emoji;
  final double sway;
  _Particle(this.id, this.emoji, this.sway);
}

class _ReactionLayerState extends State<ReactionLayer> {
  final _items = <_Particle>[];
  StreamSubscription<String>? _sub;
  int _n = 0;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _sub = widget.kinds.listen((k) {
      if (!mounted || _items.length > 24) return; // never flood the screen
      setState(() => _items.add(_Particle(_n++, reactionEmoji[k] ?? '🔥', (_rng.nextDouble() - .5) * 60)));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (final p in _items)
            Positioned(
              key: ValueKey(p.id),
              right: 14,
              bottom: 0,
              top: 0,
              width: 70,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 2200),
                onEnd: () {
                  if (mounted) setState(() => _items.removeWhere((x) => x.id == p.id));
                },
                builder: (context, v, _) => Align(
                  alignment: Alignment(math.sin(v * 5) * p.sway / 60, 1 - v * 1.6),
                  child: Opacity(opacity: (1 - v).clamp(0.0, 1.0), child: Transform.scale(scale: 0.8 + v * 0.5, child: Text(p.emoji, style: const TextStyle(fontSize: 28)))),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens a floating glass bottom sheet, with a grabber, like an iOS sheet.
Future<V?> showGlassSheet<V>(BuildContext context, {required WidgetBuilder builder, bool dismissible = true}) {
  return showModalBottomSheet<V>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withAlpha(150),
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + MediaQuery.viewInsetsOf(c).bottom),
      // A sheet covers the page and holds text, so it is a solid glass panel (no blur needed to keep it readable).
      child: Glass(
        radius: R.xl,
        blur: 0,
        padding: EdgeInsets.zero,
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.only(top: 8, bottom: 2), child: Container(width: 36, height: 4, decoration: BoxDecoration(color: C.a(Colors.white, 0.28), borderRadius: BorderRadius.circular(4)))),
            Flexible(child: builder(c)),
          ]),
        ),
      ),
    ),
  );
}
