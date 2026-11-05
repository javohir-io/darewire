import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import 'kit.dart';

/// One of the five dares. The soft fill behind the text is the live vote share; a chosen dare gets the theme colour outline.
/// No glow: the share bar and the outline already say everything.
class DareCard extends StatelessWidget {
  final int index;
  final Challenge challenge;
  final double share; // 0..1
  final int votes;
  final bool selected;
  final bool winner;
  final bool dimmed;
  final VoidCallback? onTap;
  const DareCard({super.key, required this.index, required this.challenge, required this.share, required this.votes, this.selected = false, this.winner = false, this.dimmed = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hot = selected || winner;
    final edge = winner ? C.accent : C.primaryHi;
    final fill = winner ? C.accent : C.primary;
    final card = AnimatedOpacity(
      duration: Motion.standard,
      opacity: dimmed ? 0.4 : 1,
      child: AnimatedContainer(
        duration: Motion.standard,
        curve: Motion.premium,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: ShapeDecoration(color: C.surface, shape: squircle(R.lg, side: BorderSide(color: hot ? edge : C.hairline, width: hot ? 1.6 : 1))),
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(R.lg),
          child: Stack(children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: LayoutBuilder(
                  builder: (context, c) => TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: share.clamp(0.0, 1.0)),
                    duration: Motion.slow,
                    curve: Motion.premium,
                    builder: (context, v, _) => Container(width: c.maxWidth * v, color: C.a(fill, hot ? 0.30 : 0.20)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedContainer(
                  duration: Motion.quick,
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: hot ? edge : C.a(Colors.white, 0.12)),
                  child: Center(child: Text('${index + 1}', style: T.num(13).copyWith(color: hot ? C.onColor(edge) : Colors.white))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(challenge.title, style: T.title(16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(challenge.objective, style: T.body(13), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 10),
                    Row(children: [Tag(prettyKey(challenge.category)), const SizedBox(width: 10), Text('${challenge.durationSeconds}s', style: T.label(12)), const SizedBox(width: 10), Pips(challenge.difficulty)]),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${(share * 100).round()}%', style: T.num(16).copyWith(color: hot ? Colors.white : C.dim)),
                  Text('$votes', style: T.label(12)),
                  if (winner) Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.bolt_rounded, color: C.accent, size: 20)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      label: 'Dare ${index + 1}: ${challenge.title}. ${(share * 100).round()} percent of votes.',
      child: onTap == null ? card : Pressable(onTap: onTap, scale: 0.985, child: card),
    );
  }
}
