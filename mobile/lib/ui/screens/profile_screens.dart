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
import 'auth_screens.dart';
import 'feed_screen.dart';
import 'report_sheet.dart';

IconData badgeIcon(String id) => switch (id) {
      'warden' => Icons.shield_rounded,
      'first_blood' => Icons.bolt_rounded,
      'on_fire' => Icons.local_fire_department_rounded,
      'unstoppable' => Icons.rocket_launch_rounded,
      'veteran' => Icons.military_tech_rounded,
      'high_roller' => Icons.diamond_rounded,
      'clipper' => Icons.movie_filter_rounded,
      'crowd_favorite' => Icons.favorite_rounded,
      'duelist' => Icons.sports_martial_arts_rounded,
      _ => Icons.star_rounded,
    };

/// Another player's profile (opened from the Feed, a duel, the leaderboard or a session).
class UserProfileScreen extends ConsumerWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(body: SafeArea(bottom: false, child: ProfileBody(userId: userId, self: false)));
}

/// The Profile tab: your own profile.
class SelfProfileTab extends ConsumerWidget {
  const SelfProfileTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value?.profile;
    if (me == null) return const SizedBox.shrink();
    return ProfileBody(userId: me.id, self: true);
  }
}

/// A clean, minimal profile in the style of short-video apps: avatar, three numbers, two buttons, a bio, then icon tabs over a grid of videos.
class ProfileBody extends ConsumerStatefulWidget {
  final String userId;
  final bool self;
  const ProfileBody({super.key, required this.userId, required this.self});
  @override
  ConsumerState<ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<ProfileBody> {
  int _tab = 0;

  Future<void> _toggleFollow(UserProfile p) async {
    try {
      final api = ref.read(apiProvider);
      p.relation.isFollowing ? await api.unfollow(p.id) : await api.follow(p.id);
      ref.invalidate(userProfileProvider(widget.userId));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _message(UserProfile p) async {
    try {
      final id = await ref.read(apiProvider).openChat(p.id);
      if (mounted) await context.push('/chat/$id');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _toggleBlock(UserProfile p) async {
    try {
      final api = ref.read(apiProvider);
      if (p.iBlocked) {
        await api.unblock(p.id);
      } else {
        await api.block(p.id);
      }
      ref.invalidate(userProfileProvider(widget.userId));
      if (mounted) toast(context, p.iBlocked ? 'Unblocked' : 'Blocked. You will not see each other in sessions or the Feed.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userProfileProvider(widget.userId));
    return async.when(
      loading: () => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => EmptyState(
        icon: Icons.person_off_rounded,
        title: e is ApiException ? e.message : 'Could not load this profile',
        action: AppButton(label: 'Try again', kind: BtnKind.glass, expand: false, onPressed: () => ref.invalidate(userProfileProvider(widget.userId))),
      ),
      data: _content,
    );
  }

  Widget _content(UserProfile p) {
    final ac = accentOf(p.accent);
    final wallet = widget.self ? ref.watch(walletProvider).valueOrNull : null;
    return RefreshIndicator(
      color: ac.hi,
      backgroundColor: C.bg2,
      onRefresh: () async {
        ref.invalidate(userProfileProvider(widget.userId));
        ref.invalidate(walletProvider);
      },
      child: ListView(padding: const EdgeInsets.only(bottom: 130), children: [
        _topBar(p),
        const SizedBox(height: 6),
        Center(
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.a(Colors.white, 0.18), width: 1.5)),
            child: Avatar(p.avatar, size: 96),
          ),
        ),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: Text('@${p.handle}', style: T.title(18), overflow: TextOverflow.ellipsis)),
          if (p.staff) ...[const SizedBox(width: 6), Icon(Icons.verified_rounded, color: ac.main, size: 18)],
        ]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _stat(compact(p.relation.following), 'Following', onTap: () => context.push('/u/${p.id}/following')),
          const SizedBox(width: 26),
          _stat(compact(p.relation.followers), 'Followers', onTap: () => context.push('/u/${p.id}/followers')),
          const SizedBox(width: 26),
          _stat(compact(p.stats.likes), 'Likes'),
          const SizedBox(width: 26),
          _stat(compact(widget.self ? (wallet?.balance ?? p.stats.points) : p.stats.points), 'Points'),
        ]),
        const SizedBox(height: 18),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: _buttons(p, ac)),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            p.bio.isNotEmpty ? p.bio : (p.isMe ? 'Tap Edit profile to add a bio.' : ''),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: T.body(14).copyWith(color: p.bio.isEmpty ? C.faint : C.a(Colors.white, 0.85)),
          ),
        ),
        if (p.badges.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [for (final b in p.badges.take(4)) _miniBadge(b)]),
          ),
        ],
        const SizedBox(height: 18),
        _tabs(ac),
        if (_tab == 0) _videos(p, ac) else if (_tab == 1) _rounds(p) else _badges(p, ac),
      ]),
    );
  }

  Widget _topBar(UserProfile p) {
    final canPop = Navigator.of(context).canPop();
    return SizedBox(
      height: 52,
      child: Row(children: [
        SizedBox(
          width: 52,
          child: canPop && !widget.self ? IconButton(tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20)) : null,
        ),
        Expanded(child: Center(child: Text(p.handle, style: T.title(17), overflow: TextOverflow.ellipsis))),
        SizedBox(
          width: 52,
          child: widget.self
              ? IconButton(tooltip: 'Settings', onPressed: () => context.push('/settings'), icon: const Icon(Icons.menu_rounded))
              : PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_horiz_rounded),
                  color: C.bg2,
                  onSelected: (v) {
                    if (v == 'block') _toggleBlock(p);
                    if (v == 'report') showReportSheet(context, target: Person(id: p.id, handle: p.handle, avatar: p.avatar, role: 'watcher'));
                  },
                  itemBuilder: (c) => [
                    PopupMenuItem(value: 'block', child: Text(p.iBlocked ? 'Unblock' : 'Block', style: T.strong(14))),
                    PopupMenuItem(value: 'report', child: Text('Report', style: T.strong(14).copyWith(color: C.danger))),
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _stat(String value, String label, {VoidCallback? onTap}) => Pressable(onTap: onTap, scale: 0.95, semanticLabel: '$value $label', child: Column(children: [Text(value, style: T.num(20)), const SizedBox(height: 2), Text(label, style: T.label(12.5))]));

  Widget _buttons(UserProfile p, ({Color main, Color hi}) ac) {
    if (p.isMe) {
      return Row(children: [
        Expanded(
          child: _FlatButton(label: 'Edit profile', onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupScreen(editing: true)));
            ref.invalidate(userProfileProvider(widget.userId));
          }),
        ),
        const SizedBox(width: 8),
        Expanded(child: _FlatButton(label: 'Rewards', icon: Icons.bolt_rounded, onTap: () => context.push('/rewards'))),
        const SizedBox(width: 8),
        _FlatButton(icon: Icons.ios_share_rounded, square: true, onTap: () {
          Clipboard.setData(ClipboardData(text: '@${p.handle} on DAREWIRE'));
          toast(context, 'Profile name copied');
        }),
      ]);
    }
    final r = p.relation;
    return Row(children: [
      Expanded(flex: 5, child: _FlatButton(label: r.isFollowing ? 'Following' : (r.followsYou ? 'Follow back' : 'Follow'), icon: r.isFollowing ? Icons.check_rounded : Icons.person_add_alt_1_rounded, color: r.isFollowing ? null : ac.main, onTap: p.iBlocked ? null : () => _toggleFollow(p))),
      const SizedBox(width: 8),
      if (r.canMessage) ...[Expanded(flex: 4, child: _FlatButton(label: 'Message', icon: Icons.chat_bubble_outline_rounded, onTap: p.iBlocked ? null : () => _message(p))), const SizedBox(width: 8)],
      _FlatButton(icon: Icons.bolt_rounded, square: true, label: 'Challenge to a duel', onTap: p.iBlocked ? null : () => context.push('/duel/new?target=${p.id}&handle=${p.handle}')),
      const SizedBox(width: 8),
      _FlatButton(icon: Icons.ios_share_rounded, square: true, onTap: () {
        Clipboard.setData(ClipboardData(text: '@${p.handle} on DAREWIRE'));
        toast(context, 'Profile name copied');
      }),
    ]);
  }

  Widget _miniBadge(BadgeItem b) => Tooltip(
        message: b.desc,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: C.a(Colors.white, 0.08), borderRadius: BorderRadius.circular(R.pill)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(badgeIcon(b.id), size: 14, color: C.dim), const SizedBox(width: 6), Text(b.label, style: T.label(12).copyWith(color: C.dim))]),
        ),
      );

  Widget _tabs(({Color main, Color hi}) ac) {
    const icons = [Icons.grid_view_rounded, Icons.history_rounded, Icons.military_tech_outlined];
    const names = ['Videos', 'Rounds', 'Badges'];
    return Column(children: [
      Container(height: 0.6, color: C.a(Colors.white, 0.10)),
      Row(children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: _tab == i,
              label: names[i],
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tab = i),
                child: SizedBox(height: 46, child: Icon(icons[i], size: 24, color: _tab == i ? Colors.white : C.faint)),
              ),
            ),
          ),
      ]),
      SizedBox(
        height: 2,
        child: Stack(children: [
          Container(color: C.a(Colors.white, 0.06)),
          AnimatedAlign(
            duration: Motion.standard,
            curve: Motion.premium,
            alignment: Alignment(_tab - 1.0, 0),
            child: FractionallySizedBox(widthFactor: 1 / 3, child: Center(child: Container(width: 34, height: 2, color: Colors.white))),
          ),
        ]),
      ),
    ]);
  }

  Widget _videos(UserProfile p, ({Color main, Color hi}) ac) {
    if (p.iBlocked) return _note(Icons.block_rounded, 'You blocked this player, so their videos are hidden.');
    if (p.clips.isEmpty) return _note(Icons.videocam_outlined, p.isMe ? 'Post a video after a round and it shows up here.' : 'No videos yet.');
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: 0.74),
      itemCount: p.clips.length,
      itemBuilder: (c, i) {
        final clip = p.clips[i];
        final tiles = C.pal.tiles[i % C.pal.tiles.length];
        final field = DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [C.a(tiles[0], 0.55), C.a(Colors.black, 0.75)])));
        return Pressable(
          scale: 0.98,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ClipViewerScreen(clips: p.clips, start: i))),
          child: Stack(fit: StackFit.expand, children: [
            // the clip's first frame when it has one, otherwise the colour field
            if (clip.poster != null) Image.network(clip.poster!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => field) else field,
            if (clip.poster != null) DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, C.a(Colors.black, 0.55)], stops: const [0.55, 1]))),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(children: [
                if (clip.poster == null) Align(alignment: Alignment.topLeft, child: Text(clip.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: T.strong(12.5))),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.play_arrow_outlined, size: 16, color: Colors.white), const SizedBox(width: 2), Text(compact(clip.views), style: T.label(12).copyWith(color: Colors.white))]),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _rounds(UserProfile p) {
    if (p.recent.isEmpty) return _note(Icons.history_rounded, 'No rounds yet.');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(children: [
        for (final r in p.recent)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.a(Colors.white, 0.08)))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.title ?? 'Round', style: T.strong(15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(prettyKey(r.outcome), style: T.label(12.5).copyWith(color: r.outcome == 'completed' ? C.ok : (r.outcome == 'failed' ? C.danger : C.warn))),
                ]),
              ),
              Text('+${r.points}', style: T.num(15)),
            ]),
          ),
      ]),
    );
  }

  Widget _badges(UserProfile p, ({Color main, Color hi}) ac) {
    if (p.badges.isEmpty) return _note(Icons.military_tech_outlined, p.isMe ? 'Complete a dare or post a video to earn your first badge.' : 'No badges yet.');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Wrap(spacing: 14, runSpacing: 18, children: [
        for (final b in p.badges)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 36 - 28) / 3,
            child: Column(children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: C.a(ac.main, 0.18)), child: Icon(badgeIcon(b.id), color: ac.hi, size: 26)),
              const SizedBox(height: 8),
              Text(b.label, style: T.strong(12.5), textAlign: TextAlign.center, maxLines: 2),
              const SizedBox(height: 2),
              Text(b.desc, style: T.label(11), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
      ]),
    );
  }

  Widget _note(IconData icon, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 16),
        child: Column(children: [Icon(icon, size: 40, color: C.faint), const SizedBox(height: 12), Text(text, textAlign: TextAlign.center, style: T.body(14))]),
      );
}

/// A flat, quiet button for the profile (no glow): grey by default, filled with the profile colour for the main action.
class _FlatButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;
  final bool square;
  const _FlatButton({this.label, this.icon, this.onTap, this.color, this.square = false});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: label ?? 'Share',
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          height: 44,
          width: square ? 44 : null,
          padding: square ? null : const EdgeInsets.symmetric(horizontal: 12),
          decoration: ShapeDecoration(color: color ?? C.a(Colors.white, 0.10), shape: squircle(14)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) Icon(icon, size: 19, color: Colors.white),
            if (icon != null && label != null && !square) const SizedBox(width: 6),
            if (label != null && !square) Flexible(child: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.strong(14.5).copyWith(color: Colors.white))),
          ]),
        ),
      ),
    );
  }
}

/// Full-screen swipeable viewer for one player's videos.
class ClipViewerScreen extends StatefulWidget {
  final List<FeedClip> clips;
  final int start;
  const ClipViewerScreen({super.key, required this.clips, required this.start});
  @override
  State<ClipViewerScreen> createState() => _ClipViewerScreenState();
}

class _ClipViewerScreenState extends State<ClipViewerScreen> {
  late final PageController _pc = PageController(initialPage: widget.start);
  late int _i = widget.start;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        PageView.builder(
          controller: _pc,
          scrollDirection: Axis.vertical,
          itemCount: widget.clips.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (c, i) => ClipPage(key: ValueKey(widget.clips[i].id), clip: widget.clips[i], active: i == _i),
        ),
        Positioned(left: 12, top: MediaQuery.paddingOf(context).top + 8, child: GlassOrb(icon: Icons.close_rounded, semantics: 'Close', size: 44, onTap: () => Navigator.of(context).maybePop())),
      ]),
    );
  }
}
