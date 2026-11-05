import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../gfx/glass.dart';
import '../../state/providers.dart';
import '../widgets/kit.dart';
import 'report_sheet.dart';

/// "now", "5m", "3h", "2d", or a date.
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${t.day}/${t.month}';
}

// ---- shared pieces ----------------------------------------------------------------------------------------------------

/// Follow / Following. Updates at once and puts it back if the server says no.
class FollowButton extends ConsumerStatefulWidget {
  final String userId;
  final bool following;
  final String followLabel;
  final ValueChanged<bool>? onChanged;
  const FollowButton({super.key, required this.userId, required this.following, this.followLabel = 'Follow', this.onChanged});
  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  late bool _on = widget.following;
  bool _busy = false;

  @override
  void didUpdateWidget(FollowButton old) {
    super.didUpdateWidget(old);
    if (old.following != widget.following) _on = widget.following;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final next = !_on;
    setState(() {
      _on = next;
      _busy = true;
    });
    try {
      final api = ref.read(apiProvider);
      next ? await api.follow(widget.userId) : await api.unfollow(widget.userId);
      widget.onChanged?.call(next);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _on = !next);
        toast(context, e.message);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AppButton(label: _on ? 'Following' : widget.followLabel, kind: _on ? BtnKind.glass : BtnKind.primary, expand: false, height: 36, onPressed: _toggle);
}

/// A person in a list: picture, handle, a "follows you" note, and a follow button.
class PersonTile extends ConsumerWidget {
  final PersonRow p;
  final bool showFollow;
  final Widget? trailing;
  const PersonTile(this.p, {super.key, this.showFollow = true, this.trailing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meId = ref.watch(meProvider).valueOrNull?.profile.id;
    return Pressable(
      scale: 0.99,
      onTap: () => context.push('/u/${p.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Avatar(p.avatar, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('@${p.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.strong(15.5)),
              if (p.followsYou) Text('Follows you', style: T.label(12.5)),
            ]),
          ),
          if (trailing != null) trailing! else if (showFollow && p.id != meId) FollowButton(userId: p.id, following: p.iFollow, followLabel: p.followsYou ? 'Follow back' : 'Follow'),
        ]),
      ),
    );
  }
}

Widget _loading() => const Padding(padding: EdgeInsets.all(40), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))));

Widget _errorState(Object e, VoidCallback retry) => EmptyState(icon: Icons.wifi_off_rounded, title: e is ApiException ? e.message : 'Something went wrong', action: AppButton(label: 'Try again', kind: BtnKind.glass, expand: false, onPressed: retry));

// ---- Messages ---------------------------------------------------------------------------------------------------------

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});
  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  Timer? _poll;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.invalidate(chatsProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(chatsProvider);
    final teen = ref.watch(isTeenProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Messages'), actions: [IconButton(tooltip: 'Find people', onPressed: () => context.push('/discover'), icon: const Icon(Icons.person_add_alt_1_rounded))]),
      body: SafeArea(
        child: RefreshIndicator(
          color: C.primaryHi,
          backgroundColor: C.bg2,
          onRefresh: () async => ref.invalidate(chatsProvider),
          child: async.when(
            loading: () => ListView(children: [_loading()]),
            error: (e, _) => ListView(children: [_errorState(e, () => ref.invalidate(chatsProvider))]),
            data: (all) {
              final requests = all.where((c) => c.incomingRequest).toList();
              final chats = all.where((c) => !c.incomingRequest).toList();
              final shown = _tab == 1 ? requests : chats;
              return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
                if (requests.isNotEmpty) ...[Segmented(labels: ['Chats', 'Requests (${requests.length})'], index: _tab, onChanged: (i) => setState(() => _tab = i)), const SizedBox(height: 14)],
                if (shown.isEmpty)
                  EmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: _tab == 1 ? 'No requests' : 'No messages yet',
                    message: teen ? 'You can chat with people you both follow. Follow someone, and when they follow you back, say hi.' : 'Follow people and start a conversation from their profile.',
                    action: AppButton(label: 'Find people', expand: false, icon: Icons.search_rounded, onPressed: () => context.push('/discover')),
                  )
                else
                  for (final c in shown) _row(c),
                if (teen) Padding(padding: const EdgeInsets.only(top: 22), child: Text('Chats are only with people you both follow. Never share personal details, and report anything that feels wrong.', textAlign: TextAlign.center, style: T.body(12.5))),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _row(ChatRow c) {
    final unread = c.unread > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Surface(
        padding: const EdgeInsets.all(12),
        radius: R.lg,
        onTap: () async {
          await context.push('/chat/${c.id}');
          ref.invalidate(chatsProvider);
          ref.invalidate(badgesProvider);
        },
        child: Row(children: [
          Avatar(c.person.avatar, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text('@${c.person.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.strong(15.5))),
                if (c.incomingRequest) ...[const SizedBox(width: 8), const Tag('Request')] else if (c.outgoingRequest) ...[const SizedBox(width: 8), const Tag('Pending')],
              ]),
              const SizedBox(height: 3),
              Text('${c.lastMine ? 'You: ' : ''}${c.lastText}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.body(13.5).copyWith(color: unread ? C.text : C.dim, fontWeight: unread ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(c.lastAt.isEmpty ? '' : timeAgo(DateTime.tryParse(c.lastAt)?.toLocal() ?? DateTime.now()), style: T.label(12)),
            const SizedBox(height: 6),
            if (unread) Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, gradient: C.brand)) else const SizedBox(height: 10),
          ]),
        ]),
      ),
    );
  }
}

// ---- a conversation ---------------------------------------------------------------------------------------------------

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  const ChatScreen({super.key, required this.chatId});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  ChatThread? _t;
  Object? _error;
  Timer? _poll;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Messages arrive by asking every few seconds while the chat is open (no push notifications yet).
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final t = await ref.read(apiProvider).thread(widget.chatId);
      if (mounted) {
        setState(() {
          _t = t;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = e);
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiProvider).sendMessage(widget.chatId, text);
      _text.clear();
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);   // the text stays, so it can be changed
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _respond(bool accept) async {
    try {
      await ref.read(apiProvider).respondChat(widget.chatId, accept: accept);
      ref.invalidate(chatsProvider);
      ref.invalidate(badgesProvider);
      if (!accept && mounted) {
        context.pop();
        return;
      }
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _menu(String v, ChatThread t) async {
    if (v == 'report') {
      await showReportSheet(context, conversationId: t.id, target: Person(id: t.person.id, handle: t.person.handle, avatar: t.person.avatar, role: 'user'));
    } else if (v == 'block') {
      try {
        await ref.read(apiProvider).block(t.person.id);
        ref.invalidate(chatsProvider);
        if (mounted) {
          toast(context, 'Blocked @${t.person.handle}');
          context.pop();
        }
      } on ApiException catch (e) {
        if (mounted) toast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) {
      final err = _error;
      return Scaffold(
        appBar: AppBar(),
        body: err == null ? _loading() : (err is ApiException && err.status == 404 ? const EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'This chat is not available') : _errorState(err, _load)),
      );
    }
    final msgs = t.messages.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Pressable(onTap: () => context.push('/u/${t.person.id}'), child: Row(mainAxisSize: MainAxisSize.min, children: [Avatar(t.person.avatar, size: 34), const SizedBox(width: 10), Text('@${t.person.handle}', style: T.strong(16))])),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (v) => _menu(v, t),
            itemBuilder: (_) => [PopupMenuItem(value: 'report', child: Text('Report', style: T.strong(14).copyWith(color: C.danger))), PopupMenuItem(value: 'block', child: Text('Block', style: T.strong(14)))],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (t.teen) Padding(padding: const EdgeInsets.fromLTRB(20, 2, 20, 8), child: Text('Only people you both follow can chat here. Never share personal details. Tap ⋯ to report or block.', textAlign: TextAlign.center, style: T.body(12))),
          Expanded(
            child: msgs.isEmpty
                ? Center(child: Text(t.canSend ? 'Say hi to @${t.person.handle}' : '', style: T.body(14)))
                : ListView.builder(reverse: true, padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), itemCount: msgs.length, itemBuilder: (c, i) => _Bubble(msgs[i], showTime: i == 0 || msgs[i - 1].mine != msgs[i].mine)),
          ),
          if (t.incomingRequest)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Surface(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('@${t.person.handle} wants to message you', style: T.strong(15)),
                  const SizedBox(height: 4),
                  Text('They will not know you have seen it until you accept.', textAlign: TextAlign.center, style: T.body(12.5)),
                  const SizedBox(height: 12),
                  Row(children: [Expanded(child: AppButton(label: 'Decline', kind: BtnKind.glass, height: 44, onPressed: () => _respond(false))), const SizedBox(width: 10), Expanded(child: AppButton(label: 'Accept', height: 44, onPressed: () => _respond(true)))]),
                ]),
              ),
            )
          else if (t.canSend)
            _composer()
          else
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 14), child: Surface(radius: R.lg, padding: const EdgeInsets.all(14), child: Row(children: [Icon(Icons.lock_outline_rounded, size: 18, color: C.dim), const SizedBox(width: 10), Expanded(child: Text(t.sendBlockedReason ?? 'You cannot reply right now', style: T.body(13.5)))]))),
        ]),
      ),
    );
  }

  Widget _composer() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Glass(
          radius: R.pill,
          blur: 24,
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Message', counterText: '', filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              ),
            ),
            Pressable(
              semanticLabel: 'Send',
              scale: 0.9,
              onTap: _sending ? null : _send,
              child: AnimatedOpacity(
                duration: Motion.quick,
                opacity: _sending ? 0.4 : 1,
                child: Container(width: 42, height: 42, decoration: BoxDecoration(shape: BoxShape.circle, gradient: C.brand, border: Border.all(color: C.a(Colors.white, 0.3))), child: Icon(Icons.arrow_upward_rounded, color: C.onColor(C.primary), size: 22)),
              ),
            ),
          ]),
        ),
      );
}

class _Bubble extends StatelessWidget {
  final DirectMessage m;
  final bool showTime;
  const _Bubble(this.m, {required this.showTime});

  @override
  Widget build(BuildContext context) {
    final r = m.mine ? const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6)) : const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(6), bottomRight: Radius.circular(20));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: m.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: m.text));
            toast(context, 'Copied');
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(gradient: m.mine ? C.brand : null, color: m.mine ? null : C.surfaceHi, borderRadius: r, border: m.mine ? null : Border.all(color: C.hairline)),
              child: Text(m.text, style: T.strong(15).copyWith(fontWeight: FontWeight.w500, color: m.mine ? C.onColor(C.primary) : C.text)),
            ),
          ),
        ),
        if (showTime) Padding(padding: const EdgeInsets.only(top: 3, left: 4, right: 4), child: Text(timeAgo(m.at), style: T.label(11))),
      ]),
    );
  }
}

// ---- Activity ---------------------------------------------------------------------------------------------------------

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  bool _marked = false;

  static const _text = {'follow': 'started following you', 'like': 'liked your dare video', 'message_request': 'wants to message you', 'request_accepted': 'accepted your message request'};
  static const _icon = {'follow': Icons.person_add_alt_1_rounded, 'like': Icons.favorite_rounded, 'message_request': Icons.chat_bubble_rounded, 'request_accepted': Icons.check_circle_rounded};

  @override
  Widget build(BuildContext context) {
    // Mark everything read once it has loaded, but keep the unread highlight on screen for this visit.
    ref.listen(activityProvider, (_, next) {
      if (next.hasValue && !_marked) {
        _marked = true;
        ref.read(apiProvider).markActivityRead().then((_) => ref.invalidate(badgesProvider)).catchError((_) {});
      }
    });
    final async = ref.watch(activityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: SafeArea(
        child: RefreshIndicator(
          color: C.primaryHi,
          backgroundColor: C.bg2,
          onRefresh: () async => ref.invalidate(activityProvider),
          child: async.when(
            loading: () => ListView(children: [_loading()]),
            error: (e, _) => ListView(children: [_errorState(e, () => ref.invalidate(activityProvider))]),
            data: (items) => items.isEmpty
                ? ListView(children: const [EmptyState(icon: Icons.notifications_none_rounded, title: 'Nothing yet', message: 'New followers, likes and message requests show up here.')])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                    itemCount: items.length,
                    itemBuilder: (c, i) => _row(items[i]),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _row(ActivityItem a) {
    final isChat = a.kind == 'message_request' || a.kind == 'request_accepted';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Surface(
        selected: false,
        color: a.read ? null : C.primary,
        padding: const EdgeInsets.all(12),
        radius: R.lg,
        onTap: () => context.push(isChat ? '/inbox' : '/u/${a.actor.id}'),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Avatar(a.actor.avatar, size: 48),
            Positioned(right: -4, bottom: -4, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(shape: BoxShape.circle, gradient: C.brand, border: Border.all(color: C.bg, width: 2)), child: Icon(_icon[a.kind] ?? Icons.notifications_rounded, size: 11, color: C.onColor(C.primary)))),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Text.rich(TextSpan(children: [TextSpan(text: '@${a.actor.handle} ', style: T.strong(14.5)), TextSpan(text: '${_text[a.kind] ?? 'did something'}  ', style: T.body(14.5).copyWith(color: C.text)), TextSpan(text: timeAgo(a.at), style: T.label(12.5))])),
          ),
          if (a.kind == 'follow') ...[const SizedBox(width: 8), FollowButton(userId: a.actor.id, following: a.iFollowActor, followLabel: 'Follow back')],
        ]),
      ),
    );
  }
}

// ---- Discover ---------------------------------------------------------------------------------------------------------

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<UserHit> _hits = [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() => _hits = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final r = await ref.read(apiProvider).searchUsers(v.trim());
        if (mounted && _q.text.trim() == v.trim()) setState(() => _hits = r);
      } on ApiException {
        // ignore: a failed search just shows nothing
      }
      if (mounted) setState(() => _searching = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggested = ref.watch(suggestedPeopleProvider);
    final searching = _q.text.trim().length >= 2;
    return Scaffold(
      appBar: AppBar(title: const Text('Find people')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
          TextField(controller: _q, onChanged: _onChanged, textInputAction: TextInputAction.search, decoration: InputDecoration(hintText: 'Search by handle', prefixIcon: Icon(Icons.search_rounded, color: C.faint), suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null)),
          const SizedBox(height: 18),
          if (searching) ...[
            if (_hits.isEmpty && !_searching) const EmptyState(icon: Icons.person_search_rounded, title: 'No one found', message: 'Check the spelling of the handle.'),
            for (final h in _hits) PersonTile(PersonRow(id: h.id, handle: h.handle, avatar: h.avatar), showFollow: false, trailing: Icon(Icons.chevron_right_rounded, color: C.faint)),
          ] else ...[
            const SectionTitle('Suggested for you'),
            suggested.when(
              loading: _loading,
              error: (e, _) => _errorState(e, () => ref.invalidate(suggestedPeopleProvider)),
              data: (list) => list.isEmpty ? const EmptyState(icon: Icons.groups_rounded, title: 'No suggestions yet', message: 'Search for a friend by their handle.') : Column(children: [for (final p in list) PersonTile(p)]),
            ),
          ],
        ]),
      ),
    );
  }
}

// ---- followers / following / blocked --------------------------------------------------------------------------------------

class PeopleListScreen extends ConsumerWidget {
  final String userId;
  final bool followers;
  const PeopleListScreen({super.key, required this.userId, required this.followers});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = followers ? followersProvider(userId) : followingProvider(userId);
    final async = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(followers ? 'Followers' : 'Following')),
      body: SafeArea(
        child: async.when(
          loading: () => ListView(children: [_loading()]),
          error: (e, _) => ListView(children: [_errorState(e, () => ref.invalidate(provider))]),
          data: (list) => list.isEmpty
              ? EmptyState(icon: Icons.groups_rounded, title: followers ? 'No followers yet' : 'Not following anyone yet')
              : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [for (final p in list) PersonTile(p)]),
        ),
      ),
    );
  }
}

class BlockedScreen extends ConsumerWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(blockedPeopleProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked accounts')),
      body: SafeArea(
        child: async.when(
          loading: () => ListView(children: [_loading()]),
          error: (e, _) => ListView(children: [_errorState(e, () => ref.invalidate(blockedPeopleProvider))]),
          data: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.block_rounded, title: 'No one is blocked', message: 'People you block cannot see your profile, follow you or message you, and you will not see them.')
              : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
                  for (final p in list)
                    PersonTile(
                      p,
                      trailing: AppButton(
                        label: 'Unblock',
                        kind: BtnKind.glass,
                        expand: false,
                        height: 36,
                        onPressed: () async {
                          try {
                            await ref.read(apiProvider).unblock(p.id);
                            ref.invalidate(blockedPeopleProvider);
                          } on ApiException catch (e) {
                            if (context.mounted) toast(context, e.message);
                          }
                        },
                      ),
                    ),
                ]),
        ),
      ),
    );
  }
}

// ---- Safety centre ----------------------------------------------------------------------------------------------------

/// Plain-language safety help: what protects you, what to do if something feels wrong, and what DAREWIRE will never ask.
class SafetyCentreScreen extends ConsumerWidget {
  const SafetyCentreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teen = ref.watch(isTeenProvider);
    Widget block(IconData icon, String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Surface(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconBadge(icon, size: 38),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: T.strong(15.5)), const SizedBox(height: 3), Text(text, style: T.body(13.5))])),
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Safety centre')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
          Text(teen ? 'Your teen account has extra protections. Here is how to stay in control.' : 'How to stay in control on DAREWIRE.', style: T.body(15)),
          const SizedBox(height: 18),
          block(Icons.front_hand_rounded, 'You can always stop', 'Pass any dare for free, or hit Safety stop during a round. There is never a penalty.'),
          block(Icons.block_rounded, 'Block someone', 'Open their profile or chat, tap the three dots, then Block. They cannot see you, follow you or message you, and any following ends.'),
          block(Icons.flag_outlined, 'Report anything', 'Report a video, a player, a session or a chat. Reporting from a chat sends the last few messages to our moderators. Three reports hide a video straight away until a person reviews it.'),
          block(Icons.chat_bubble_outline_rounded, 'About chats', teen ? 'You can only chat with people you both follow, and only with other teens. Links, phone numbers and meet-up talk are blocked.' : 'Chats are with people you follow back, or one message request that the other person can accept or decline. Links and contact details are blocked.'),
          block(Icons.do_not_disturb_on_outlined, 'What DAREWIRE will never do', 'We will never ask you for your password, to pay for anything, to meet anyone, or to move a chat to another app. If someone says they are from DAREWIRE and asks, report them.'),
          if (teen) block(Icons.people_outline_rounded, 'Talk to someone you trust', 'If something online upsets you or someone pressures you, tell a parent, carer, teacher or another adult you trust. You are never in trouble for telling.'),
          const SizedBox(height: 8),
          Text('If you or someone else is in danger right now, contact your local emergency number.', textAlign: TextAlign.center, style: T.body(12.5)),
        ]),
      ),
    );
  }
}
