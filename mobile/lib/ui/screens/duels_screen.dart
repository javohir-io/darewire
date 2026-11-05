import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/kit.dart';

String _left(DateTime? t) {
  if (t == null) return '';
  final d = t.difference(DateTime.now());
  if (d.isNegative) return 'expired';
  if (d.inHours >= 24) return '${d.inDays}d left';
  if (d.inHours >= 1) return '${d.inHours}h left';
  return '${d.inMinutes.clamp(1, 59)}m left';
}

/// The Duels tab: challenges waiting on you, in progress, and finished.
class DuelsTab extends ConsumerWidget {
  const DuelsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(duelsProvider);
    return RefreshIndicator(
      color: C.primaryHi,
      backgroundColor: C.bg2,
      onRefresh: () async => ref.invalidate(duelsProvider),
      child: ListView(padding: const EdgeInsets.only(bottom: 130), children: [
        ScreenHeader(
          'Duels',
          subtitle: 'Challenge someone to a dare. When it is completed, you both earn points.',
          actions: [AppButton(label: 'New duel', icon: Icons.add_rounded, expand: false, height: 42, onPressed: () => context.push('/duel/new'))],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: async.when(
            loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
            error: (e, _) => EmptyState(icon: Icons.wifi_off_rounded, title: e is ApiException ? e.message : 'Could not load your duels', action: AppButton(label: 'Try again', kind: BtnKind.glass, expand: false, onPressed: () => ref.invalidate(duelsProvider))),
            data: (list) => _body(context, list),
          ),
        ),
      ]),
    );
  }

  Widget _body(BuildContext context, List<Duel> list) {
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 30),
        child: EmptyState(
          icon: Icons.bolt_rounded,
          title: 'No duels yet',
          message: 'Pick a player, choose a dare, and send it. They have 48 hours to accept.',
          action: AppButton(label: 'Challenge someone', icon: Icons.bolt_rounded, expand: false, onPressed: () => context.push('/duel/new')),
        ),
      );
    }
    final mine = list.where((d) => d.isOpen && d.myMove).toList();
    final waiting = list.where((d) => d.isOpen && !d.myMove).toList();
    final done = list.where((d) => !d.isOpen).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (mine.isNotEmpty) ...[
        SectionTitle('Your move (${mine.length})'),
        for (final d in mine) DuelCard(d),
        const SizedBox(height: 14),
      ],
      if (waiting.isNotEmpty) ...[
        const SectionTitle('Waiting on them'),
        for (final d in waiting) DuelCard(d),
        const SizedBox(height: 14),
      ],
      if (done.isNotEmpty) ...[
        const SectionTitle('History'),
        for (final d in done.take(15)) DuelCard(d),
      ],
    ]);
  }
}

class DuelCard extends ConsumerStatefulWidget {
  final Duel d;
  const DuelCard(this.d, {super.key});
  @override
  ConsumerState<DuelCard> createState() => _DuelCardState();
}

class _DuelCardState extends ConsumerState<DuelCard> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() f) async {
    setState(() => _busy = true);
    try {
      final msg = await f();
      if (msg != null && mounted) toast(context, msg);
      ref.invalidate(duelsProvider);
      ref.invalidate(walletProvider);
      ref.invalidate(questsProvider);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submit() async {
    final res = await showGlassSheet<({String note, String? clipId})>(context, builder: (c) => _SubmitSheet(widget.d));
    if (res == null) return;
    await _run(() async {
      await ref.read(apiProvider).duelSubmit(widget.d.id, note: res.note, clipId: res.clipId);
      return 'Sent. Waiting for ${widget.d.otherHandle} to confirm.';
    });
  }

  Future<void> _judge(bool approve) => _run(() async {
        final r = await ref.read(apiProvider).duelJudge(widget.d.id, approve);
        if (!approve) return 'Marked as not completed.';
        if (r.paid > 0) return 'Approved. ${widget.d.otherHandle} earned ${r.paid} points.';
        return r.capped ? 'Approved. No points this time because the daily limit was reached.' : 'Approved.';
      });

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final (label, color) = switch (d.status) {
      'pending' => (d.iChallenged ? 'Waiting for answer' : 'New challenge', C.accent),
      'accepted' => (d.iChallenged ? 'In progress' : 'Your turn to do it', C.primaryHi),
      'submitted' => (d.iChallenged ? 'Needs your review' : 'Waiting for review', C.accent2),
      'completed' => ('Completed', C.ok),
      'rejected' => ('Not completed', C.danger),
      'declined' => ('Declined', C.faint),
      'cancelled' => ('Cancelled', C.faint),
      _ => ('Expired', C.faint),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Surface(
        selected: d.myMove,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pressable(onTap: () => context.push('/u/${d.otherId}'), child: Avatar(d.otherAvatar, size: 44)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.iChallenged ? 'You challenged @${d.otherHandle}' : '@${d.otherHandle} challenged you', style: T.strong(14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [Tag(label, color: color), if (d.isOpen) ...[const SizedBox(width: 8), Text(_left(d.expiresAt), style: T.label(11.5))]]),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Text(d.title, style: T.title(18)),
          const SizedBox(height: 4),
          Text(d.objective, style: T.body(14)),
          const SizedBox(height: 10),
          Row(children: [
            Tag(prettyKey(d.category)),
            const SizedBox(width: 8),
            Pips(d.difficulty),
            const Spacer(),
            Icon(Icons.bolt_rounded, size: 16, color: C.accent),
            const SizedBox(width: 2),
            Text(d.status == 'completed' && !d.iChallenged ? '+${d.rewarded}' : '${d.reward}', style: T.num(15).copyWith(color: C.accent)),
            const SizedBox(width: 4),
            Text('points', style: T.label(12)),
          ]),
          if (d.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: ShapeDecoration(color: C.a(Colors.white, 0.05), shape: squircle(R.sm)),
              child: Text('Note: ${d.note}', style: T.body(13)),
            ),
          ],
          if (d.proofClipId != null) ...[const SizedBox(height: 8), const Tag('Video attached', icon: Icons.videocam_rounded)],
          ..._actions(d),
        ]),
      ),
    );
  }

  List<Widget> _actions(Duel d) {
    final Widget? w = switch ((d.status, d.iChallenged)) {
      ('pending', false) => Row(children: [
          Expanded(child: AppButton(label: 'Accept', icon: Icons.check_rounded, busy: _busy, onPressed: () => _run(() async {
                await ref.read(apiProvider).duelAction(d.id, 'accept');
                return 'Accepted. Go do it, then submit.';
              }))),
          const SizedBox(width: 10),
          Expanded(child: AppButton(label: 'Decline', kind: BtnKind.glass, onPressed: _busy ? null : () => _run(() async {
                await ref.read(apiProvider).duelAction(d.id, 'decline');
                return null;
              }))),
        ]),
      ('accepted', false) => AppButton(label: 'I did it. Submit', icon: Icons.flag_rounded, busy: _busy, onPressed: _submit),
      ('submitted', true) => Row(children: [
          Expanded(child: AppButton(label: 'Approve', icon: Icons.check_rounded, busy: _busy, onPressed: () => _judge(true))),
          const SizedBox(width: 10),
          Expanded(child: AppButton(label: 'Not done', kind: BtnKind.danger, onPressed: _busy ? null : () => _judge(false))),
        ]),
      ('pending', true) || ('accepted', true) => AppButton(label: 'Cancel duel', kind: BtnKind.quiet, height: 44, onPressed: _busy ? null : () => _run(() async {
            await ref.read(apiProvider).duelAction(d.id, 'cancel');
            return null;
          })),
      _ => null,
    };
    return w == null ? const [] : [const SizedBox(height: 14), w];
  }
}

class _SubmitSheet extends ConsumerStatefulWidget {
  final Duel d;
  const _SubmitSheet(this.d);
  @override
  ConsumerState<_SubmitSheet> createState() => _SubmitSheetState();
}

class _SubmitSheetState extends ConsumerState<_SubmitSheet> {
  final _note = TextEditingController();
  List<FeedClip> _clips = [];
  String? _clipId;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).myClips().then((c) {
      if (mounted) setState(() => _clips = c);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Submit your dare', style: T.large(24)),
        const SizedBox(height: 4),
        Text(widget.d.title, style: T.body(14)),
        const SizedBox(height: 14),
        TextField(controller: _note, maxLength: 200, maxLines: 3, minLines: 2, decoration: const InputDecoration(hintText: 'Tell them what you did (optional)')),
        if (_clips.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Attach one of your dare videos (optional)', style: T.strong(13.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _clips.take(8))
              ChoiceChip(
                label: Text(c.title, overflow: TextOverflow.ellipsis),
                selected: _clipId == c.id,
                onSelected: (v) => setState(() => _clipId = v ? c.id : null),
                selectedColor: C.a(C.primary, 0.40),
                backgroundColor: C.surface,
                showCheckmark: false,
                shape: const StadiumBorder(),
                labelStyle: T.strong(12.5),
                side: BorderSide(color: _clipId == c.id ? C.primaryHi : C.hairline),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        AppButton(label: 'Send to @${widget.d.otherHandle}', icon: Icons.send_rounded, onPressed: () => Navigator.of(context).pop((note: _note.text.trim(), clipId: _clipId))),
        const SizedBox(height: 8),
        Text('They decide whether it counts. Be honest, it keeps duels fun.', style: T.body(12.5)),
      ]),
    );
  }
}

// ---- Creating a duel --------------------------------------------------------------------------------------------------

class NewDuelScreen extends ConsumerStatefulWidget {
  final String? targetId, targetHandle;
  const NewDuelScreen({super.key, this.targetId, this.targetHandle});
  @override
  ConsumerState<NewDuelScreen> createState() => _NewDuelScreenState();
}

class _NewDuelScreenState extends ConsumerState<NewDuelScreen> {
  final _search = TextEditingController();
  final _title = TextEditingController();
  final _objective = TextEditingController();
  Timer? _debounce;
  UserHit? _target;
  List<UserHit> _hits = [];
  List<DuelIdea> _ideas = [];
  int? _picked; // library index
  bool _custom = false;
  int _difficulty = 2;
  bool _busy = false, _searching = false, _loadingIdeas = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.targetId != null) {
      _target = UserHit(widget.targetId!, widget.targetHandle ?? 'player', 'a01');
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadIdeas());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _title.dispose();
    _objective.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    final t = q.trim();
    if (t.length < 2) {
      setState(() => _hits = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final r = await ref.read(apiProvider).searchUsers(t);
        if (mounted) setState(() => _hits = r);
      } on ApiException catch (e) {
        if (mounted) toast(context, e.message);
      }
      if (mounted) setState(() => _searching = false);
    });
  }

  Future<void> _loadIdeas() async {
    final t = _target;
    if (t == null) return;
    setState(() {
      _loadingIdeas = true;
      _picked = null;
    });
    try {
      final r = await ref.read(apiProvider).duelIdeas(t.id);
      if (mounted) setState(() => _ideas = r);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _loadingIdeas = false);
  }

  Future<void> _send() async {
    final t = _target;
    if (t == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      if (_custom) {
        await api.createDuel(targetId: t.id, custom: (title: _title.text.trim(), objective: _objective.text.trim(), difficulty: _difficulty));
      } else {
        await api.createDuel(targetId: t.id, libraryIndex: _picked);
      }
      ref.invalidate(duelsProvider);
      ref.invalidate(questsProvider);
      if (!mounted) return;
      toast(context, 'Duel sent to @${t.handle}');
      ref.read(shellTabProvider.notifier).state = 2;
      context.go('/home');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  bool get _ready => _target != null && (_custom ? (_title.text.trim().length >= 3 && _objective.text.trim().length >= 10) : _picked != null);

  @override
  Widget build(BuildContext context) {
    // Teens pick from the dare ideas: free text between two teens is where pressure starts, so the server does not allow it.
    final teen = ref.watch(isTeenProvider);
    if (teen && _custom) _custom = false;
    return Scaffold(
      appBar: AppBar(title: const Text('New duel')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 30), children: [
          Text('1. Who do you want to challenge?', style: T.title(17)),
          const SizedBox(height: 10),
          if (_target != null)
            Surface(
              radius: R.md,
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Avatar(_target!.avatar, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text('@${_target!.handle}', style: T.strong(16))),
                TextButton(onPressed: () => setState(() {
                      _target = null;
                      _ideas = [];
                      _picked = null;
                    }), child: const Text('Change')),
              ]),
            )
          else ...[
            TextField(controller: _search, onChanged: _onSearch, autocorrect: false, decoration: InputDecoration(hintText: 'Search by handle', prefixIcon: const Icon(Icons.search_rounded), suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null)),
            const SizedBox(height: 8),
            for (final h in _hits)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Surface(
                  radius: R.md,
                  padding: const EdgeInsets.all(10),
                  onTap: () {
                    setState(() {
                      _target = h;
                      _hits = [];
                      _search.clear();
                    });
                    _loadIdeas();
                  },
                  child: Row(children: [Avatar(h.avatar, size: 38), const SizedBox(width: 12), Expanded(child: Text('@${h.handle}', style: T.strong(15)))]),
                ),
              ),
            if (_hits.isEmpty && _search.text.trim().length >= 2 && !_searching) Padding(padding: const EdgeInsets.all(8), child: Text('No players found with that handle.', style: T.body(13.5))),
          ],
          if (_target != null) ...[
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: Text('2. Choose a dare', style: T.title(17))),
              if (!_custom) TextButton.icon(onPressed: _loadingIdeas ? null : _loadIdeas, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('More ideas')),
            ]),
            const SizedBox(height: 8),
            if (!teen) ...[Segmented(labels: const ['Ideas', 'Write my own'], index: _custom ? 1 : 0, onChanged: (i) => setState(() => _custom = i == 1)), const SizedBox(height: 14)],
            if (!_custom) ...[
              if (_loadingIdeas) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              for (final i in _ideas) _idea(i),
              Text(teen ? 'These ideas follow the teen safety rules and @${_target!.handle}\'s boundaries.' : 'These ideas already respect @${_target!.handle}\'s boundaries.', style: T.body(12.5)),
            ] else ...[
              TextField(controller: _title, maxLength: 40, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Dare title', counterText: '')),
              const SizedBox(height: 10),
              TextField(controller: _objective, maxLength: 200, maxLines: 3, minLines: 2, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'What do they have to do?')),
              const SizedBox(height: 12),
              Text('Difficulty: $_difficulty of 5', style: T.strong(14)),
              Slider(value: _difficulty.toDouble(), min: 1, max: 5, divisions: 4, onChanged: (v) => setState(() => _difficulty = v.round())),
              Text('Your dare is checked by the same safety rules as live sessions, and by their boundaries.', style: T.body(12.5)),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: T.strong(14).copyWith(color: C.danger))),
            const SizedBox(height: 22),
            AppButton(label: 'Send duel', icon: Icons.bolt_rounded, busy: _busy, onPressed: _ready ? _send : null),
            const SizedBox(height: 10),
            Text('They have 48 hours to answer. You earn a small bonus when they complete it.', style: T.body(12.5)),
          ],
        ]),
      ),
    );
  }

  Widget _idea(DuelIdea i) {
    final on = _picked == i.index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Surface(
        selected: on,
        onTap: () => setState(() => _picked = i.index),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title, style: T.title(16)),
              const SizedBox(height: 3),
              Text(i.objective, style: T.body(13.5)),
              const SizedBox(height: 10),
              Row(children: [Tag(prettyKey(i.category)), const SizedBox(width: 10), Pips(i.difficulty), const SizedBox(width: 10), Text('${i.durationSeconds}s', style: T.label(12))]),
            ]),
          ),
          const SizedBox(width: 8),
          Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined, color: on ? C.primaryHi : C.faint),
        ]),
      ),
    );
  }
}
