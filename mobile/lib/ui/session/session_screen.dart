import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrackRenderer, VideoViewFit;
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/media.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../screens/clip_sheet.dart';
import '../screens/report_sheet.dart';
import '../widgets/kit.dart';
import 'panels.dart';

const _attemptPhases = {'READY_CHECK', 'CHALLENGE_GENERATION', 'CHALLENGE_VOTE', 'PLAYER_REVIEW', 'LIVE_ROUND', 'SUBMISSION'};

class SessionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String want; // watcher | player | observer
  const SessionScreen({super.key, required this.sessionId, this.want = 'watcher'});
  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  late final SessionArgs args = (id: widget.sessionId, want: widget.want);
  late final LiveMedia media;
  final _reactions = StreamController<String>.broadcast();
  final _chatCtl = TextEditingController();
  StreamSubscription<ServerEvent>? _ev;
  bool? _lastPlayer;
  String? _offerShown;

  @override
  void initState() {
    super.initState();
    media = LiveMedia(ref.read(apiProvider), widget.sessionId);
    media.addListener(() {
      if (mounted) setState(() {});
    });
    _ev = ref.read(sessionProvider(args).notifier).events.listen(_onEvent);
  }

  @override
  void dispose() {
    _ev?.cancel();
    _reactions.close();
    _chatCtl.dispose();
    media.dispose();
    super.dispose();
  }

  void _onEvent(ServerEvent e) {
    switch (e.type) {
      case 'reaction':
        _reactions.add('${e.data['kind']}');
      case 'vote:locked' || 'safety:stop':
        HapticFeedback.heavyImpact();
      case 'round:started':
        HapticFeedback.mediumImpact();
      case 'twist:open':
        HapticFeedback.vibrate();
      case 'verdict:finalized':
        HapticFeedback.lightImpact();
      case 'stream:cut':
        if (mounted) toast(context, 'A moderator cut the stream.');
      case 'clip:ready':
        final id = '${e.data['id']}';
        if (mounted && _offerShown != id) {
          _offerShown = id;
          showClipOfferSheet(context, clipId: id, title: '${e.data['title']}', durationMs: (e.data['durationMs'] as num?)?.toInt() ?? 0);
        }
    }
  }

  Future<void> _confirmLeave(SessionController ctrl, SessionView v) async {
    final onStage = v.isPlayer && _attemptPhases.contains(v.phase);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Leave this session?', style: T.title(18)),
        content: Text(onStage ? 'You are on stage. Leaving ends your turn. There is no penalty.' : 'You can rejoin with the code while it is live.', style: T.body()),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: Text('Leave', style: TextStyle(color: C.danger))),
        ],
      ),
    );
    if (ok == true) await _leave(ctrl);
  }

  Future<void> _leave(SessionController ctrl) async {
    await ctrl.leave();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(sessionProvider(args));
    final ctrl = ref.read(sessionProvider(args).notifier);

    ref.listen<SessionUi>(sessionProvider(args), (prev, next) {
      final nv = next.view;
      if (nv == null) return;
      final wantsPublish = nv.isPlayer && !nv.streamCut;
      if (_lastPlayer != wantsPublish && nv.phase != 'SESSION_END') {
        _lastPlayer = wantsPublish;
        media.connect(wantPublish: wantsPublish);
      }
    });

    if (ui.fatal != null) return _Fatal(message: ui.fatal!, onBack: () => context.go('/home'));
    final v = ui.view;
    if (v == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(height: 16),
        Text('Connecting to the session', style: T.body(14)),
      ]));
    }

    final me = ref.watch(meProvider).value?.profile;
    final isMod = me?.isModerator == true;
    final a = PanelArgs(context, v, ui.offsetMs, ctrl.send);
    final h = MediaQuery.sizeOf(context).height;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave(ctrl, v);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(children: [
            _TopBar(
              v: v,
              onBack: () => _confirmLeave(ctrl, v),
              onReportSession: () => showReportSheet(context, sessionId: v.id),
              onReportPlayer: v.player == null || v.player!.id == a.myId ? null : () => showReportSheet(context, sessionId: v.id, target: v.player),
              isMod: isMod,
              onModEnd: () => ctrl.send('mod:end'),
              onModCut: () => ctrl.send('mod:cut'),
            ),
            if (ui.conn != Conn.live)
              Container(
                width: double.infinity,
                color: C.a(C.warn, 0.16),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(ui.conn == Conn.connecting ? 'Connecting…' : 'Reconnecting. Your place is saved.', textAlign: TextAlign.center, style: T.label(12).copyWith(color: C.warn)),
              ),
            SizedBox(
              height: (h * 0.32).clamp(190.0, 330.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _Stage(
                  v: v,
                  media: media,
                  chat: ui.chat,
                  reactions: _reactions.stream,
                  onSafety: () async {
                    HapticFeedback.heavyImpact();
                    final err = await ctrl.send('safety:stop');
                    if (err != null && context.mounted) toast(context, err);
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Surface(
                  radius: R.xl,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: Motion.standard,
                      switchInCurve: Motion.enter,
                      switchOutCurve: Motion.exit,
                      child: KeyedSubtree(
                        key: ValueKey('${v.phase}:${v.round?.n}:${v.round?.passes}'),
                        child: _panel(a, v, () => showReportSheet(context, sessionId: v.id, target: v.player), () => _leave(ctrl)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!v.isObserver && v.phase != 'SESSION_END')
              _Composer(
                controller: _chatCtl,
                onSend: () async {
                  final t = _chatCtl.text.trim();
                  if (t.isEmpty) return;
                  _chatCtl.clear();
                  final err = await ctrl.send('chat:send', {'text': t});
                  if (err != null && context.mounted) toast(context, err);
                },
                onReact: (k) => ctrl.send('reaction:send', {'kind': k}),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _panel(PanelArgs a, SessionView v, VoidCallback report, VoidCallback leave) => switch (v.phase) {
        'LOBBY' => LobbyPanel(a),
        'READY_CHECK' => ReadyPanel(a),
        'CHALLENGE_GENERATION' => GenerationPanel(a),
        'CHALLENGE_VOTE' => VotePanel(a),
        'PLAYER_REVIEW' => ReviewPanel(a),
        'LIVE_ROUND' => LivePanel(a),
        'SUBMISSION' => SubmissionPanel(a),
        'AUDIENCE_VERDICT' => VerdictPanel(a),
        'ROUND_RESULT' => ResultPanel(a, onReport: report),
        _ => EndPanel(a, onLeave: leave),
      };
}

class _TopBar extends StatelessWidget {
  final SessionView v;
  final VoidCallback onBack, onReportSession;
  final VoidCallback? onReportPlayer;
  final bool isMod;
  final VoidCallback onModEnd, onModCut;
  const _TopBar({required this.v, required this.onBack, required this.onReportSession, this.onReportPlayer, required this.isMod, required this.onModEnd, required this.onModCut});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Row(children: [
        IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), tooltip: 'Leave'),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.title, style: T.title(16), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${v.isTeenSession ? 'Teen room  ·  ' : ''}${v.watcherCount} watching  ·  Round ${v.roundNumber == 0 ? "-" : v.roundNumber}  ·  Code ${v.code}', style: T.label(12)),
          ]),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (s) {
            switch (s) {
              case 'copy':
                Clipboard.setData(ClipboardData(text: v.code));
                toast(context, 'Code copied');
              case 'rs':
                onReportSession();
              case 'rp':
                onReportPlayer?.call();
              case 'end':
                onModEnd();
              case 'cut':
                onModCut();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'copy', child: Text('Copy join code')),
            const PopupMenuItem(value: 'rs', child: Text('Report session')),
            if (onReportPlayer != null) PopupMenuItem(value: 'rp', child: Text('Report @${v.player?.handle}')),
            if (isMod) PopupMenuItem(value: 'cut', child: Text('Moderator: cut stream', style: TextStyle(color: C.danger))),
            if (isMod) PopupMenuItem(value: 'end', child: Text('Moderator: end session', style: TextStyle(color: C.danger))),
          ],
        ),
      ]),
    );
  }
}

class _Stage extends StatelessWidget {
  final SessionView v;
  final LiveMedia media;
  final List<ChatMessage> chat;
  final Stream<String> reactions;
  final VoidCallback onSafety;
  const _Stage({required this.v, required this.media, required this.chat, required this.reactions, required this.onSafety});

  @override
  Widget build(BuildContext context) {
    final track = media.track;
    final showSafety = v.isPlayer && _attemptPhases.contains(v.phase);
    final live = v.phase == 'LIVE_ROUND';
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(R.xl),
      child: Container(
        foregroundDecoration: ShapeDecoration(shape: squircle(R.xl, side: BorderSide(color: C.a(Colors.white, 0.12)))),
        color: C.a(C.bg, 0.6),
        child: Stack(fit: StackFit.expand, children: [
          if (track != null && !v.streamCut)
            VideoTrackRenderer(track, fit: VideoViewFit.cover)
          else
            _StagePlaceholder(v: v, note: v.streamCut ? 'The stream was cut by a moderator.' : media.connecting ? 'Connecting video…' : media.error),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Colors.transparent, Color(0xB3000000)], stops: [0, .45, 1]))),
          Positioned(
            left: 12,
            top: 12,
            child: Row(children: [
              if (v.player != null) ...[
                Avatar(v.player!.avatar, size: 30, live: live),
                const SizedBox(width: 8),
                Text('@${v.player!.handle}', style: T.strong(14)),
                if (live) ...[const SizedBox(width: 8), const _StagePill('LIVE', dot: true)],
                if (v.player!.streak > 1) ...[const SizedBox(width: 8), _StagePill('${v.player!.streak} streak', icon: Icons.local_fire_department_rounded)],
              ] else
                Text('No one on stage', style: T.label(12)),
            ]),
          ),
          if (showSafety)
            Positioned(
              right: 10,
              top: 8,
              // The safety stop is always solid and always reachable: ends the turn at once, no penalty.
              child: Pressable(
                semanticLabel: 'Safety stop. Ends your turn immediately with no penalty.',
                onTap: onSafety,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: ShapeDecoration(color: C.danger, shape: const StadiumBorder(), shadows: [BoxShadow(color: C.a(Colors.black, 0.35), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.front_hand_rounded, size: 16, color: Colors.white), const SizedBox(width: 6), Text('Safety stop', style: T.strong(13).copyWith(color: Colors.white))]),
                ),
              ),
            ),
          Positioned(left: 12, bottom: 10, right: 80, child: _ChatOverlay(chat)),
          Positioned.fill(child: ReactionLayer(kinds: reactions)),
        ]),
      ),
    );
  }
}

class _StagePlaceholder extends StatelessWidget {
  final SessionView v;
  final String? note;
  const _StagePlaceholder({required this.v, this.note});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (v.player != null) Avatar(v.player!.avatar, size: 72, ring: true),
            const SizedBox(height: 12),
            Text(note ?? (v.player == null ? 'The stage is empty' : 'Waiting for video'), textAlign: TextAlign.center, style: T.body(13)),
          ]),
        ),
      );
}

const _shadow = [Shadow(blurRadius: 6, color: Color(0xB3000000))];

class _ChatOverlay extends StatelessWidget {
  final List<ChatMessage> chat;
  const _ChatOverlay(this.chat);
  @override
  Widget build(BuildContext context) {
    final last = chat.length > 4 ? chat.sublist(chat.length - 4) : chat;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < last.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text.rich(
            TextSpan(children: [TextSpan(text: '${last[i].handle}  ', style: T.strong(12.5).copyWith(color: Colors.white, shadows: _shadow)), TextSpan(text: last[i].text, style: T.body(12).copyWith(color: C.a(Colors.white, 0.92), shadows: _shadow))]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ]);
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final void Function(String kind) onReact;
  const _Composer({required this.controller, required this.onSend, required this.onReact});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLength: 140,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: T.strong(14),
              decoration: InputDecoration(hintText: 'Say something', counterText: '', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.pill))),
            ),
          ),
          for (final e in reactionEmoji.entries)
            Pressable(
              semanticLabel: 'React ${e.key}',
              scale: 0.8,
              onTap: () {
                HapticFeedback.selectionClick();
                onReact(e.key);
              },
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6), child: Text(e.value, style: const TextStyle(fontSize: 22))),
            ),
        ]),
      );
}

class _Fatal extends StatelessWidget {
  final String message;
  final VoidCallback onBack;
  const _Fatal({required this.message, required this.onBack});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.power_off_rounded, color: C.danger, size: 44),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center, style: T.title(18)),
            const SizedBox(height: 20),
            AppButton(label: 'Back to home', expand: false, onPressed: onBack),
          ]),
        ),
      );
}

/// A small dark pill that stays readable on live video: the LIVE marker and the streak.
class _StagePill extends StatelessWidget {
  final String text;
  final bool dot;
  final IconData? icon;
  const _StagePill(this.text, {this.dot = false, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: ShapeDecoration(color: dot ? C.a(C.danger, 0.92) : C.a(Colors.black, 0.4), shape: const StadiumBorder()),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)), const SizedBox(width: 5)],
          if (icon != null) ...[Icon(icon, size: 12, color: C.accent2), const SizedBox(width: 4)],
          Text(text, style: T.label(11).copyWith(color: Colors.white, fontWeight: dot ? FontWeight.w800 : FontWeight.w600, letterSpacing: dot ? 0.6 : 0)),
        ]),
      );
}
