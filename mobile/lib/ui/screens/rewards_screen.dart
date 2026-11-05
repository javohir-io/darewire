import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/kit.dart';

/// Points, daily quests, streak, leaderboard and recent activity.
class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});
  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  int _tab = 0;
  String? _claiming;

  Future<void> _claim(QuestItem q) async {
    setState(() => _claiming = q.id);
    try {
      final n = await ref.read(apiProvider).claimQuest(q.id);
      ref.invalidate(questsProvider);
      ref.invalidate(walletProvider);
      if (mounted) toast(context, '+$n points');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _claiming = null);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final quests = ref.watch(questsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Rewards')),
      body: SafeArea(
        child: RefreshIndicator(
          color: C.primaryHi,
          backgroundColor: C.bg2,
          onRefresh: () async {
            ref.invalidate(walletProvider);
            ref.invalidate(questsProvider);
            ref.invalidate(leaderboardProvider);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 40), children: [
            Reveal(child: _hero(wallet.valueOrNull)),
            const SizedBox(height: 16),
            Segmented(labels: const ['Quests', 'Leaderboard', 'Activity'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: Motion.standard,
              switchInCurve: Motion.enter,
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: switch (_tab) {
                  0 => _questsTab(quests),
                  1 => _leaderboard(),
                  _ => _activity(wallet),
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// The balance, big and calm. A quiet colour field instead of a glowing gradient card.
  Widget _hero(WalletState? w) {
    final t = C.pal.tiles[0];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: ShapeDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(t[0], C.bg, 0.10)!, Color.lerp(t[1], C.bg, 0.55)!]),
        shape: squircle(R.xl, side: BorderSide(color: C.a(Colors.white, 0.14))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your points', style: T.strong(14).copyWith(color: C.a(Colors.white, 0.75))),
        const SizedBox(height: 2),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('${w?.balance ?? 0}', style: T.large(54).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          Icon(Icons.bolt_rounded, color: C.accent, size: 32),
        ]),
        Text('${w?.completed ?? 0} dares completed', style: T.body(14).copyWith(color: C.a(Colors.white, 0.75))),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: ShapeDecoration(color: C.a(Colors.black, 0.26), shape: squircle(R.md)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 18, color: C.a(Colors.white, 0.85)),
            const SizedBox(width: 10),
            Expanded(child: Text(w?.cashOutAvailable == true ? 'Cash-out is available.' : 'Cash-out is not available yet. For now, points are for status and rewards inside DAREWIRE.', style: T.body(12.5).copyWith(color: C.a(Colors.white, 0.85)))),
          ]),
        ),
      ]),
    );
  }

  Widget _loading() => const Padding(padding: EdgeInsets.all(30), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));

  Widget _questsTab(AsyncValue<QuestsState> async) {
    return async.when(
      loading: _loading,
      error: (e, _) => Text(e is ApiException ? e.message : 'Could not load quests', style: T.body()),
      data: (q) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.local_fire_department_rounded, color: C.accent2, size: 22),
              const SizedBox(width: 8),
              Text('${q.streak} day streak', style: T.title(17)),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (final d in q.week) _dot(d)]),
          ]),
        ),
        const SizedBox(height: 20),
        const SectionTitle('Daily quests'),
        for (final item in q.quests) _quest(item),
        const SizedBox(height: 4),
        Text('Quests reset every day at midnight UTC.', style: T.body(12.5)),
      ]),
    );
  }

  Widget _dot(WeekDay d) => Column(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: d.active ? C.accent2 : C.a(Colors.white, d.future ? 0.03 : 0.08),
            border: Border.all(color: d.today ? C.a(Colors.white, 0.85) : (d.active ? Colors.transparent : C.hairline), width: d.today ? 1.6 : 1),
          ),
          child: d.active ? Icon(Icons.check_rounded, size: 19, color: C.onColor(C.accent2)) : null,
        ),
        const SizedBox(height: 6),
        Text(d.label, style: T.label(11.5).copyWith(color: d.today ? C.text : C.faint)),
      ]);

  Widget _quest(QuestItem q) {
    final canClaim = q.done && !q.claimed;
    final f = q.goal == 0 ? 0.0 : (q.progress / q.goal).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Surface(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          _Ring(fraction: q.claimed ? 1 : f, done: q.done),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.title, style: T.strong(15.5)),
              const SizedBox(height: 2),
              Text(q.desc, style: T.body(13)),
              const SizedBox(height: 2),
              Text('${q.progress.clamp(0, q.goal)} of ${q.goal}', style: T.label(12)),
            ]),
          ),
          const SizedBox(width: 10),
          if (q.claimed)
            const Tag('Claimed', icon: Icons.check_rounded)
          else
            SizedBox(
              width: 96,
              child: AppButton(
                label: canClaim ? 'Claim +${q.reward}' : '+${q.reward}',
                height: 40,
                kind: canClaim ? BtnKind.primary : BtnKind.glass,
                busy: _claiming == q.id,
                onPressed: canClaim ? () => _claim(q) : null,
              ),
            ),
        ]),
      ),
    );
  }

  Widget _leaderboard() {
    final async = ref.watch(leaderboardProvider);
    return async.when(
      loading: _loading,
      error: (e, _) => Text(e is ApiException ? e.message : 'Could not load the leaderboard', style: T.body()),
      data: (rows) {
        if (rows.isEmpty) return const EmptyState(icon: Icons.emoji_events_rounded, title: 'No scores yet', message: 'Complete a dare to get on the board. Scores cover the last 30 days.');
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GroupedList(children: [
            for (var i = 0; i < rows.length; i++)
              Pressable(
                scale: 0.99,
                onTap: () => context.push('/u/${rows[i].userId}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    SizedBox(width: 26, child: Text('${i + 1}', style: T.num(16).copyWith(color: i == 0 ? C.accent : (i < 3 ? C.text : C.faint)))),
                    Avatar(rows[i].avatar, size: 40, ring: i == 0),
                    const SizedBox(width: 12),
                    Expanded(child: Text('@${rows[i].handle}', style: T.strong(15), overflow: TextOverflow.ellipsis)),
                    Text('${rows[i].points}', style: T.num(16)),
                    const SizedBox(width: 3),
                    Icon(Icons.bolt_rounded, size: 16, color: C.accent),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Text('Last 30 days', style: T.body(12.5)),
        ]);
      },
    );
  }

  Widget _activity(AsyncValue<WalletState> async) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return async.when(
      loading: _loading,
      error: (e, _) => Text(e is ApiException ? e.message : 'Could not load your activity', style: T.body()),
      data: (w) {
        if (w.activity.isEmpty) return const EmptyState(icon: Icons.receipt_long_rounded, title: 'Nothing yet', message: 'Points you earn from rounds, duels and quests show up here.');
        return GroupedList(children: [
          for (final e in w.activity)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                IconBadge(switch (e.kind) { 'round' => Icons.videocam_rounded, 'quest' => Icons.flag_rounded, _ => Icons.bolt_rounded }, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.note, style: T.strong(14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${e.at.day} ${months[e.at.month - 1]}', style: T.label(11.5)),
                  ]),
                ),
                Text('${e.amount >= 0 ? '+' : ''}${e.amount}', style: T.num(15).copyWith(color: e.amount >= 0 ? C.accent : C.danger)),
              ]),
            ),
        ]);
      },
    );
  }
}

/// A small progress ring for a quest. Turns into a check when the quest is done.
class _Ring extends StatelessWidget {
  final double fraction;
  final bool done;
  const _Ring({required this.fraction, required this.done});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: Stack(alignment: Alignment.center, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: Motion.slow,
            curve: Motion.premium,
            builder: (context, v, _) => CustomPaint(size: const Size(44, 44), painter: _RingPainter(v, done)),
          ),
          if (done) Icon(Icons.check_rounded, size: 20, color: C.primaryHi),
        ]),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final bool done;
  const _RingPainter(this.v, this.done);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 3);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = C.a(Colors.white, 0.10));
    if (v > 0) canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round..color = done ? C.primaryHi : C.a(C.primaryHi, 0.9));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.v != v || old.done != done;
}
