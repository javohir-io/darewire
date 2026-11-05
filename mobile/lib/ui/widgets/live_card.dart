import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../gfx/glass.dart';
import 'kit.dart';

/// A live session as a tappable card: who is on stage, what they are doing, and how many people watch.
/// A flat card over a soft colour field; the only bright things are the LIVE chip and the person's coloured ring.
class LiveCard extends StatelessWidget {
  final SessionSummary s;
  final double? width;
  const LiveCard(this.s, {super.key, this.width});

  /// A vivid two-colour field from the active theme (no longer washed out towards the background).
  List<Color> get _field {
    final tiles = C.pal.tiles;
    final h = s.id.codeUnits.fold<int>(0, (a, b) => (a + b) & 0xFFFF);
    final t = tiles[h % tiles.length];
    return [Color.lerp(t[0], C.bg, 0.12)!, Color.lerp(t[1], C.bg, 0.55)!];
  }

  String get _status {
    if (!s.onStage) return 'Waiting for a player';
    return switch (s.phase) {
      'LIVE_ROUND' => 'Doing a dare',
      'CHALLENGE_VOTE' => 'Crowd is voting',
      'PLAYER_REVIEW' => 'Deciding',
      'SUBMISSION' || 'AUDIENCE_VERDICT' => 'Judging now',
      'ROUND_RESULT' => 'Round finished',
      'CHALLENGE_GENERATION' => 'Getting dares',
      'READY_CHECK' => 'Getting ready',
      _ => 'On stage',
    };
  }

  @override
  Widget build(BuildContext context) {
    final g = _field;
    return Pressable(
      semanticLabel: 'Open ${s.title}',
      onTap: () => context.push('/session/${s.id}?want=watcher'),
      child: Container(
        width: width,
        decoration: ShapeDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
          shape: squircle(R.xl, side: BorderSide(color: C.a(Colors.white, 0.22))),
          shadows: [BoxShadow(color: C.a(g[0], 0.4), blurRadius: 26, offset: const Offset(0, 12), spreadRadius: -10)],
        ),
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(R.xl),
          child: Stack(fit: StackFit.expand, children: [
            // a soft light behind the avatar, and a diagonal sheen across the card
            Positioned(top: 34, left: 0, right: 0, child: Center(child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [C.a(Colors.white, 0.34), C.a(Colors.white, 0)]))))),
            DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [C.a(Colors.white, 0.18), Colors.transparent, C.a(Colors.white, 0.06)], stops: const [0, 0.45, 1]))),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                  decoration: ShapeDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF5A36), Color(0xFFFF2E63)]), shape: const StadiumBorder()),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('LIVE', style: T.label(11).copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  ]),
                ),
                const Spacer(),
                Glass(
                  radius: R.pill,
                  clear: true,
                  blur: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.visibility_outlined, size: 13, color: Colors.white), const SizedBox(width: 4), Text(compact(s.watchers), style: T.num(12))]),
                ),
              ]),
            ),
            Positioned(top: 58, left: 0, right: 0, child: Center(child: s.playerAvatar != null ? Avatar(s.playerAvatar!, size: 86, live: s.onStage) : IconBadge(Icons.person_add_alt_1_rounded, size: 72, color: Colors.white))),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Glass(
                radius: R.lg,
                clear: true,
                blur: 22,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(s.playerHandle != null ? '@${s.playerHandle}' : s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.strong(15)),
                  const SizedBox(height: 2),
                  Text(s.dareTitle != null && s.onStage ? s.dareTitle! : _status, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.body(12.5).copyWith(color: C.a(Colors.white, 0.85))),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
