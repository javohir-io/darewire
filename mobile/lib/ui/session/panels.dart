import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/kit.dart';
import '../widgets/dare_card.dart';

typedef Send = Future<String?> Function(String type, [Map<String, dynamic> data]);

/// Everything a phase panel needs: the authoritative view, the server clock offset and a way to send commands.
/// Panels never compute outcomes. They render what the server says and send what the server permits.
class PanelArgs {
  final BuildContext context;
  final SessionView v;
  final int offsetMs;
  final Send send;
  const PanelArgs(this.context, this.v, this.offsetMs, this.send);

  bool get isPlayer => v.isPlayer;
  bool get isHost => v.you?.isHost == true;
  bool get isWatcher => v.you?.role == 'watcher';
  String get myId => v.you?.id ?? '';
  RoundView? get round => v.round;

  Future<void> run(String type, [Map<String, dynamic> data = const {}]) async {
    final err = await send(type, data);
    if (err != null && context.mounted) toast(context, err);
  }
}

Widget _h(String text) => Text(text, style: T.title(20));

class _Waiting extends StatelessWidget {
  final String text;
  const _Waiting(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: C.a(C.primaryHi, 0.9))),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: T.body())),
        ]),
      );
}

class _Countdown extends StatelessWidget {
  final PanelArgs a;
  final String label;
  const _Countdown(this.a, this.label);
  @override
  Widget build(BuildContext context) => DeadlineBuilder(
        deadline: a.v.phaseDeadline,
        startedAt: a.v.phaseStartedAt,
        offsetMs: a.offsetMs,
        builder: (c, ms, f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: T.strong(13.5)),
            const Spacer(),
            Text(clock(ms), style: T.num(17).copyWith(color: f < 0.25 ? C.danger : C.text)),
          ]),
          const SizedBox(height: 6),
          ProgressBar(fraction: f, urgent: f < 0.25),
        ]),
      );
}

// ---------------------------------------------------------------------------------------------------------------

class LobbyPanel extends StatelessWidget {
  final PanelArgs a;
  const LobbyPanel(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    final v = a.v;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _h('The stage'),
      const SizedBox(height: 6),
      Text(v.player == null ? 'Nobody is on stage yet.' : '@${v.player!.handle} is on stage. When they start, five dares appear and the crowd picks one.', style: T.body()),
      const SizedBox(height: 6),
      Text('If the player allows it, finished rounds can be posted as videos. Only the player is recorded, never viewers or chat.', style: T.body(12.5)),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: v.code));
          toast(context, 'Code copied');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: C.glass, borderRadius: BorderRadius.circular(R.md), border: Border.all(color: C.border)),
          child: Row(children: [
            Text('Join code', style: T.strong(13.5)),
            const Spacer(),
            Text(v.code, style: T.num(22).copyWith(letterSpacing: 5, color: C.accent)),
            const SizedBox(width: 10),
            Icon(Icons.copy_rounded, size: 16, color: C.dim),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      if ((a.isPlayer || a.isHost) && v.player != null) AppButton(label: 'Start the session', icon: Icons.bolt, onPressed: () => a.run('session:start')),
      if (a.isHost && v.player == null) ...[
        AppButton(label: 'Take the stage', icon: Icons.videocam_rounded, onPressed: () async {
          await a.run('stage:request');
          await a.run('stage:handoff', {'userId': a.myId});
        }),
      ],
      if (a.isWatcher && !a.isHost) ...[
        v.you!.queued
            ? AppButton(label: 'Leave the queue', kind: BtnKind.glass, onPressed: () => a.run('stage:cancel'))
            : AppButton(label: 'Request the stage', kind: BtnKind.glass, icon: Icons.front_hand_rounded, onPressed: () => a.run('stage:request')),
      ],
      if (v.queue.isNotEmpty) ...[
        const SizedBox(height: 16),
        const SectionTitle('Waiting for a turn'),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final p in v.queue) Tag('@${p.handle}', icon: Icons.person_outline)]),
      ],
    ]);
  }
}

class ReadyPanel extends StatefulWidget {
  final PanelArgs a;
  const ReadyPanel(this.a, {super.key});
  @override
  State<ReadyPanel> createState() => _ReadyPanelState();
}

class _ReadyPanelState extends State<ReadyPanel> {
  bool _allowClips = false; // opt-in, off by default, asked again every run

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final b = a.v.boundaries;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _h('Ready check'),
      const SizedBox(height: 8),
      if (a.isPlayer) ...[
        Text('Your boundaries are applied by the server to every dare. Nothing outside them can reach the vote.', style: T.body()),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Tag('Up to level ${b.maxDifficulty}', color: C.accent),
          for (final c in b.excludedCategories) Tag('No ${prettyKey(c)}', color: C.danger),
          for (final t in b.excludedThemes) Tag('No ${prettyKey(t)}', color: C.danger),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.a(C.primary, 0.16), borderRadius: BorderRadius.circular(R.md), border: Border.all(color: C.a(C.primaryHi, 0.5))),
          child: Row(children: [
            Icon(Icons.shield_outlined, color: C.primaryHi),
            const SizedBox(width: 12),
            Expanded(child: Text('You can pass any dare, and the safety stop ends your turn instantly with no penalty.', style: T.strong(13))),
          ]),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _allowClips,
          
          onChanged: (v) => setState(() => _allowClips = v),
          title: Text('Record my rounds as videos', style: T.strong(14.5)),
          subtitle: Text('Off by default. Records only your camera and mic after you accept a dare, never viewers or chat. A safety stop deletes it on the spot. You choose whether to post each video afterwards; unposted videos are deleted within 24 hours.', style: T.body(12.5)),
        ),
        const SizedBox(height: 10),
        AppButton(label: "I'm ready", icon: Icons.videocam_rounded, onPressed: () => a.run('player:ready', {'allowClips': _allowClips})),
      ] else
        const _Waiting('The player is checking their boundaries and camera.'),
      const SizedBox(height: 10),
      _Countdown(a, 'Ready check closes'),
    ]);
  }
}

class GenerationPanel extends StatelessWidget {
  final PanelArgs a;
  const GenerationPanel(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _h('Writing five dares'),
      const SizedBox(height: 16),
      for (var i = 0; i < 5; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            Text('${i + 1}', style: T.num(13).copyWith(color: C.primaryHi)),
            const SizedBox(width: 12),
            Expanded(
              child: Container(height: 2, color: C.a(Colors.white, 0.1))
                  .animate(onPlay: (c) => c.repeat(), delay: (i * 140).ms)
                  .shimmer(duration: 1400.ms, color: C.primaryHi),
            ),
          ]),
        ),
      Text('Every dare is checked against our safety rules and the player\'s boundaries before the crowd sees it.', style: T.body(13)),
    ]);
  }
}

class VotePanel extends StatefulWidget {
  final PanelArgs a;
  const VotePanel(this.a, {super.key});
  @override
  State<VotePanel> createState() => _VotePanelState();
}

class _VotePanelState extends State<VotePanel> {
  int? _pending; // shown instantly; the server's snapshot replaces it within a quarter of a second

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final r = a.round;
    if (r == null) return const SizedBox.shrink();
    final tally = r.tally ?? List.filled(r.options.length, 0);
    final total = tally.fold<int>(0, (s, x) => s + x);
    final mine = a.v.you?.vote ?? _pending;
    final canVote = a.isWatcher && a.v.you?.vote == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Countdown(a, a.isWatcher ? 'Choose the dare' : 'The crowd is choosing'),
      const SizedBox(height: 10),
      for (var i = 0; i < r.options.length; i++)
        DareCard(
          index: i,
          challenge: r.options[i],
          share: total == 0 ? 0 : tally[i] / total,
          votes: tally[i],
          selected: mine == i,
          dimmed: mine != null && mine != i,
          onTap: canVote && _pending == null
              ? () async {
                  HapticFeedback.mediumImpact();
                  setState(() => _pending = i);
                  final err = await a.send('vote:cast', {'option': i});
                  if (err != null) {
                    if (mounted) setState(() => _pending = null);
                    if (context.mounted) toast(context, err);
                  }
                }
              : null,
        ).animate(delay: (i * 60).ms).fadeIn(duration: 260.ms).slideY(begin: 0.08, end: 0),
      Text(
        a.isWatcher
            ? (mine == null ? 'One vote each. You cannot change it, so choose wisely.' : 'Vote locked in. $total ${total == 1 ? "vote" : "votes"} so far.')
            : '$total ${total == 1 ? "vote" : "votes"} so far. You will see the winner next.',
        style: T.body(12.5),
      ),
    ]);
  }
}

class ReviewPanel extends StatelessWidget {
  final PanelArgs a;
  const ReviewPanel(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = a.round;
    final c = r?.chosen;
    if (r == null || c == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.bolt_rounded, color: C.accent),
        const SizedBox(width: 6),
        Text(r.chosenBy == 'no_votes' ? 'No votes, so a dare was picked for you' : 'The crowd chose', style: T.strong(13.5).copyWith(color: C.accent)),
      ]),
      const SizedBox(height: 10),
      Text(c.title, style: T.display(20)).animate().fadeIn(duration: 400.ms).slideY(begin: .2, end: 0),
      const SizedBox(height: 10),
      Text(c.objective, style: T.body(16)),
      const SizedBox(height: 12),
      Row(children: [Tag(prettyKey(c.category)), const SizedBox(width: 8), Text('${c.durationSeconds}s', style: T.num(13)), const SizedBox(width: 10), Pips(c.difficulty)]),
      const SizedBox(height: 14),
      for (final line in c.completionCriteria)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 3), child: Icon(Icons.check_circle_outline, size: 15, color: C.accent)),
            const SizedBox(width: 8),
            Expanded(child: Text(line, style: T.body(13.5))),
          ]),
        ),
      const SizedBox(height: 10),
      if (a.isPlayer) ...[
        AppButton(label: 'Accept the dare', icon: Icons.play_arrow_rounded, onPressed: () => a.run('challenge:accept')),
        const SizedBox(height: 10),
        AppButton(label: 'Pass and get new dares', kind: BtnKind.glass, icon: Icons.skip_next_rounded, onPressed: () => a.run('challenge:pass')),
        const SizedBox(height: 10),
        _Countdown(a, 'No answer = automatic pass'),
      ] else ...[
        const _Waiting('Waiting for the player to accept. They are free to pass.'),
      ],
    ]);
  }
}

class LivePanel extends StatelessWidget {
  final PanelArgs a;
  const LivePanel(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = a.round;
    final c = r?.chosen;
    if (r == null || c == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DeadlineBuilder(
        deadline: r.deadline,
        startedAt: r.startedAt,
        offsetMs: a.offsetMs,
        builder: (ctx, ms, f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Live', style: T.strong(13.5).copyWith(color: C.danger)),
            const SizedBox(width: 8),
            Container(width: 7, height: 7, decoration: BoxDecoration(color: C.danger, shape: BoxShape.circle))
                .animate(onPlay: (x) => x.repeat(reverse: true))
                .fade(begin: 0.3, end: 1, duration: 700.ms),
            const Spacer(),
            Text(clock(ms), style: T.display(28).copyWith(color: f < 0.2 ? C.danger : C.text)),
          ]),
          const SizedBox(height: 4),
          ProgressBar(fraction: f, height: 14, urgent: f < 0.2),
        ]),
      ),
      const SizedBox(height: 10),
      Text(c.title, style: T.title(20)),
      const SizedBox(height: 6),
      Text(c.objective, style: T.body(15)),
      const SizedBox(height: 10),
      _TwistBlock(a, r),
      const SizedBox(height: 8),
      if (a.isPlayer)
        AppButton(label: 'Finish attempt', icon: Icons.flag_rounded, kind: BtnKind.glass, onPressed: () => a.run('attempt:finish'))
      else
        Text('Send reactions below. The twist vote can open mid-round.', style: T.body(12.5)),
    ]);
  }
}

class _TwistBlock extends StatelessWidget {
  final PanelArgs a;
  final RoundView r;
  const _TwistBlock(this.a, this.r);

  @override
  Widget build(BuildContext context) {
    final t = r.twist;
    if (t == null) return const SizedBox.shrink();
    if (t.status == 'closed') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.a(C.accent2, 0.16), borderRadius: BorderRadius.circular(R.md), border: Border.all(color: C.accent2)),
        child: Row(children: [
          Icon(Icons.electric_bolt_rounded, color: C.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(t.applied != null ? 'Twist: ${t.applied!.text}' : 'No twist this time. The crowd stayed quiet.', style: T.strong(14))),
        ]),
      ).animate().shake(duration: 400.ms, hz: 6).fadeIn();
    }
    final total = t.tally.fold<int>(0, (s, x) => s + x);
    final mine = a.v.you?.twistVote;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.glass, borderRadius: BorderRadius.circular(R.md), border: Border.all(color: C.a(C.accent, 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.electric_bolt_rounded, color: C.accent, size: 18),
          const SizedBox(width: 8),
          Text('Twist vote: choose now', style: T.strong(13.5).copyWith(color: C.accent)),
          const Spacer(),
          DeadlineBuilder(deadline: t.closesAt, offsetMs: a.offsetMs, builder: (c, ms, f) => Text(clock(ms), style: T.num(13))),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < t.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.sm),
              onTap: a.isWatcher && mine == null ? () => a.run('twist:vote', {'option': i}) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.sm),
                  color: mine == i ? C.a(C.primary, 0.4) : C.a(Colors.white, 0.04),
                  border: Border.all(color: mine == i ? C.primaryHi : C.border),
                ),
                child: Row(children: [
                  Expanded(child: Text(t.options[i].text, style: T.strong(13))),
                  Text(total == 0 ? '' : '${t.tally[i]}', style: T.num(13)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class SubmissionPanel extends StatefulWidget {
  final PanelArgs a;
  const SubmissionPanel(this.a, {super.key});
  @override
  State<SubmissionPanel> createState() => _SubmissionPanelState();
}

class _SubmissionPanelState extends State<SubmissionPanel> {
  final _note = TextEditingController();
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _h('Attempt over'),
      const SizedBox(height: 8),
      if (a.isPlayer) ...[
        Text('Add an optional note for the judges, then submit.', style: T.body()),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLength: 280, maxLines: 3, minLines: 2, decoration: const InputDecoration(hintText: 'What did you do? (optional)')),
        const SizedBox(height: 8),
        AppButton(label: 'Submit to the crowd', icon: Icons.send_rounded, onPressed: () => a.run('attempt:submit', {'note': _note.text})),
      ] else
        const _Waiting('The player is submitting their attempt.'),
      const SizedBox(height: 10),
      _Countdown(a, 'Submission closes'),
    ]);
  }
}

class VerdictPanel extends StatelessWidget {
  final PanelArgs a;
  const VerdictPanel(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = a.round;
    final mine = a.v.you?.verdict;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _h('Verdict'),
      const SizedBox(height: 6),
      Text(r?.chosen?.title ?? '', style: T.title(18)),
      if (r?.note != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.glass, borderRadius: BorderRadius.circular(R.md), border: Border.all(color: C.border)),
          child: Text('Player note: ${r!.note}', style: T.body(13.5)),
        ),
      ],
      const SizedBox(height: 14),
      if (a.isWatcher) ...[
        Row(children: [
          Expanded(child: AppButton(label: 'Nailed it', icon: Icons.check_rounded, kind: mine == true ? BtnKind.primary : BtnKind.glass, onPressed: mine == null ? () => a.run('verdict:cast', {'completed': true}) : null)),
          const SizedBox(width: 10),
          Expanded(child: AppButton(label: 'Missed it', icon: Icons.close_rounded, kind: mine == false ? BtnKind.danger : BtnKind.glass, onPressed: mine == null ? () => a.run('verdict:cast', {'completed': false}) : null)),
        ]),
        const SizedBox(height: 8),
        Text(mine == null ? 'Judge against the completion criteria. One verdict each.' : 'Verdict recorded. Results after the timer.', style: T.body(12.5)),
      ] else
        const _Waiting('The crowd is judging.'),
      const SizedBox(height: 10),
      _Countdown(a, 'Judging closes'),
    ]);
  }
}

class ResultPanel extends StatelessWidget {
  final PanelArgs a;
  final VoidCallback onReport;
  const ResultPanel(this.a, {super.key, required this.onReport});

  static const _titles = {
    'completed': 'Dare complete',
    'failed': 'Not this time',
    'safety_stop': 'Stage paused. No penalty.',
    'abandoned': 'The player disconnected',
    'moderated': 'Stream ended by moderation',
  };

  @override
  Widget build(BuildContext context) {
    final res = a.round?.result;
    if (res == null) return const SizedBox.shrink();
    final good = res.outcome == 'completed';
    final mine = res.awards[a.myId] ?? 0;
    final v = a.v;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_titles[res.outcome] ?? res.outcome, style: T.display(26).copyWith(color: good ? C.accent : (res.isSafety ? C.text : C.danger)))
          .animate().fadeIn(duration: 350.ms).slideY(begin: .2, end: 0),
      const SizedBox(height: 6),
      Text(res.challengeTitle ?? 'No dare was played', style: T.body(15)),
      const SizedBox(height: 14),
      Row(children: [
        _Stat('Player', '+${res.playerPoints}'),
        const SizedBox(width: 10),
        _Stat('Judges', res.judged ? '${res.yes}-${res.no}' : 'none'),
        const SizedBox(width: 10),
        _Stat('Streak', '${res.streak}'),
        if (a.isWatcher) ...[const SizedBox(width: 10), _Stat('You', '+$mine')],
      ]),
      if (res.twist != null) ...[const SizedBox(height: 8), Tag('Twist applied: ${prettyKey(res.twist!)}', icon: Icons.electric_bolt_rounded, color: C.accent)],
      const SizedBox(height: 16),
      const SectionTitle('Scoreboard'),
      for (final p in v.roster.take(5)) _Row(p, isMe: p.id == a.myId),
      const SizedBox(height: 14),
      if (a.isPlayer || a.isHost) ...[
        if (!v.streamCut) AppButton(label: 'Next dare', icon: Icons.bolt, onPressed: () => a.run('round:next')),
        if (v.queue.isNotEmpty) ...[const SizedBox(height: 10), AppButton(label: 'Hand the stage to @${v.queue.first.handle}', kind: BtnKind.glass, icon: Icons.swap_horiz_rounded, onPressed: () => a.run('stage:handoff'))],
        const SizedBox(height: 10),
        AppButton(label: 'End session', kind: BtnKind.quiet, onPressed: () => a.run('session:end')),
      ] else ...[
        v.you?.queued == true
            ? AppButton(label: 'Leave the queue', kind: BtnKind.glass, onPressed: () => a.run('stage:cancel'))
            : AppButton(label: 'Request the stage', kind: BtnKind.glass, icon: Icons.front_hand_rounded, onPressed: () => a.run('stage:request')),
        const SizedBox(height: 6),
        AppButton(label: 'Something wrong? Report', kind: BtnKind.quiet, onPressed: onReport),
      ],
    ]);
  }
}

class EndPanel extends StatelessWidget {
  final PanelArgs a;
  final VoidCallback onLeave;
  const EndPanel(this.a, {super.key, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    final why = switch (a.v.endedReason) {
      'moderator_ended' => 'A moderator ended this session.',
      'host_ended' => 'The host ended the session.',
      _ => 'This session has ended.',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _h('Session ended'),
      const SizedBox(height: 6),
      Text(why, style: T.body()),
      const SizedBox(height: 16),
      const SectionTitle('Final scoreboard'),
      for (final p in a.v.roster.take(8)) _Row(p, isMe: p.id == a.myId),
      const SizedBox(height: 16),
      AppButton(label: 'Leave', onPressed: onLeave),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: C.glass, borderRadius: BorderRadius.circular(R.md), border: Border.all(color: C.border)),
          child: Column(children: [Text(value, style: T.num(18)), const SizedBox(height: 2), Text(label, style: T.label(12))]),
        ),
      );
}

class _Row extends StatelessWidget {
  final Person p;
  final bool isMe;
  const _Row(this.p, {required this.isMe});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: p.id.startsWith('sim:') ? null : () => context.push('/u/${p.id}'),
          child: Row(children: [
          Avatar(p.avatar, size: 32, ring: p.role == 'player'),
          const SizedBox(width: 10),
          Expanded(child: Text('@${p.handle}${isMe ? "  (you)" : ""}', style: T.strong(14).copyWith(color: isMe ? C.accent : C.text), overflow: TextOverflow.ellipsis)),
          Text('${p.score}', style: T.num(15)),
        ]),
        ),
      );
}
