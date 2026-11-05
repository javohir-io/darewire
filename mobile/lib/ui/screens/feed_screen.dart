import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../gfx/glass.dart';
import '../../state/providers.dart';
import '../widgets/kit.dart';
import '../widgets/live_card.dart';
import 'report_sheet.dart';

/// The Feed has two pages you can swipe between: Live (people doing dares right now) and Dares (recorded dare videos).
class FeedTab extends ConsumerStatefulWidget {
  final bool active; // false while another tab is showing, so audio and video stop
  const FeedTab({super.key, required this.active});
  @override
  ConsumerState<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends ConsumerState<FeedTab> {
  late final PageController _pages = PageController(initialPage: ref.read(feedPageProvider));

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(feedPageProvider);
    ref.listen<int>(feedPageProvider, (_, p) {
      if (_pages.hasClients && (_pages.page?.round() ?? p) != p) _pages.animateToPage(p, duration: Motion.standard, curve: Motion.premium);
    });
    final top = MediaQuery.paddingOf(context).top;
    return Stack(fit: StackFit.expand, children: [
      PageView(
        controller: _pages,
        onPageChanged: (i) => ref.read(feedPageProvider.notifier).state = i,
        children: [
          LivePage(active: widget.active && page == 0),
          DaresPage(active: widget.active && page == 1),
        ],
      ),
      Positioned(
        top: top + 10,
        left: 0,
        right: 0,
        child: Center(
          child: SizedBox(
            width: 210,
            child: Segmented(clear: true, labels: const ['Live', 'Dares'], index: page, onChanged: (i) => ref.read(feedPageProvider.notifier).state = i),
          ),
        ),
      ),
    ]);
  }
}

// ---- Live page -----------------------------------------------------------------------------------------------------

class LivePage extends ConsumerWidget {
  final bool active;
  const LivePage({super.key, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = MediaQuery.paddingOf(context).top;
    final sessions = ref.watch(sessionsProvider);
    return RefreshIndicator(
      color: C.primaryHi,
      backgroundColor: C.bg2,
      edgeOffset: top + 60,
      onRefresh: () async => ref.invalidate(sessionsProvider),
      child: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          SizedBox(height: top + 120),
          EmptyState(icon: Icons.wifi_off_rounded, title: e is ApiException ? e.message : 'Could not load live sessions', action: AppButton(label: 'Try again', kind: BtnKind.glass, expand: false, onPressed: () => ref.invalidate(sessionsProvider))),
        ]),
        data: (list) {
          final onStage = list.where((s) => s.onStage).toList();
          final waiting = list.where((s) => !s.onStage).toList();
          if (list.isEmpty) {
            return ListView(children: [
              SizedBox(height: top + 100),
              EmptyState(
                icon: Icons.sensors_rounded,
                title: 'Nobody is live right now',
                message: 'Start a session and your dares will show up here for everyone to watch.',
                action: AppButton(label: 'Go live', icon: Icons.videocam_rounded, expand: false, onPressed: () => context.push('/create')),
              ),
            ]);
          }
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: SizedBox(height: top + 66)),
            if (onStage.isNotEmpty) ...[
              SliverPadding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), sliver: SliverToBoxAdapter(child: SectionTitle('Doing dares now (${onStage.length})'))),
              _grid(onStage),
            ],
            if (waiting.isNotEmpty) ...[
              SliverPadding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0), sliver: const SliverToBoxAdapter(child: SectionTitle('Waiting for a player'))),
              _grid(waiting),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 130)),
          ]);
        },
      ),
    );
  }

  Widget _grid(List<SessionSummary> items) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.78),
          delegate: SliverChildBuilderDelegate((c, i) => Reveal(delay: Motion.stagger(i), child: LiveCard(items[i])), childCount: items.length),
        ),
      );
}

// ---- Dares page (recorded videos) -----------------------------------------------------------------------------------

/// Vertical, full-screen, swipe-to-next feed of recorded dares. Only the visible clip plays; neighbours are built just in time.
class DaresPage extends ConsumerStatefulWidget {
  final bool active;
  const DaresPage({super.key, required this.active});
  @override
  ConsumerState<DaresPage> createState() => _DaresPageState();
}

class _DaresPageState extends ConsumerState<DaresPage> {
  final _page = PageController();
  int _index = 0;
  String? _viewed;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _onPage(int i, FeedState f) {
    setState(() => _index = i);
    if (i >= f.items.length - 3) ref.read(feedProvider.notifier).loadMore();
    _markViewed(f, i);
  }

  void _markViewed(FeedState f, int i) {
    if (i < 0 || i >= f.items.length) return;
    final id = f.items[i].id;
    if (_viewed == id) return;
    _viewed = id;
    ref.read(apiProvider).viewClip(id).catchError((_) {});
  }

  void _sort(String s) {
    if (_page.hasClients) _page.jumpToPage(0);
    _index = 0;
    ref.read(feedProvider.notifier).setSort(s);
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(feedProvider);
    if (widget.active && f.items.isNotEmpty && _viewed == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _markViewed(f, _index));
    }
    final top = MediaQuery.paddingOf(context).top;
    return Stack(fit: StackFit.expand, children: [
      if (f.items.isEmpty)
        _Empty(loading: f.loading, error: f.error, following: f.sort == 'following', onRetry: () => ref.read(feedProvider.notifier).load(reset: true))
      else
        PageView.builder(
          controller: _page,
          scrollDirection: Axis.vertical,
          itemCount: f.items.length,
          onPageChanged: (i) => _onPage(i, f),
          itemBuilder: (c, i) => ClipPage(key: ValueKey(f.items[i].id), clip: f.items[i], active: widget.active && i == _index),
        ),
      Positioned(
        top: top + 64,
        right: 16,
        child: Pressable(
          semanticLabel: 'Showing ${_sortLabel(f.sort)}. Tap to change',
          onTap: () => _sort(f.sort == 'hot' ? 'following' : (f.sort == 'following' ? 'new' : 'hot')),
          child: Glass(
            radius: R.pill,
            clear: true,
            blur: 20,
            padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(f.sort == 'hot' ? Icons.auto_awesome_rounded : (f.sort == 'following' ? Icons.group_rounded : Icons.schedule_rounded), size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text(_sortLabel(f.sort), style: T.strong(12.5).copyWith(color: Colors.white)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

String _sortLabel(String s) => s == 'hot' ? 'For you' : (s == 'following' ? 'Following' : 'Newest');

class _Empty extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final bool following;
  const _Empty({required this.loading, this.error, required this.onRetry, this.following = false});
  @override
  Widget build(BuildContext context) => loading
      ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
      : EmptyState(
          icon: following ? Icons.group_add_rounded : Icons.movie_filter_rounded,
          title: error ?? (following ? 'Nothing from people you follow yet' : 'No dare videos yet'),
          message: following ? 'Follow people to see their dare videos here.' : 'Finish a dare and post the recording after the round. It will show up here for everyone.',
          action: following && error == null ? AppButton(label: 'Find people', icon: Icons.search_rounded, expand: false, onPressed: () => context.push('/discover')) : AppButton(label: 'Refresh', kind: BtnKind.glass, expand: false, onPressed: onRetry),
        );
}

class ClipPage extends ConsumerStatefulWidget {
  final FeedClip clip;
  final bool active;
  const ClipPage({super.key, required this.clip, required this.active});
  @override
  ConsumerState<ClipPage> createState() => _ClipPageState();
}

class _ClipPageState extends ConsumerState<ClipPage> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _paused = false;
  bool _heart = false;
  int _heartKey = 0;
  late bool _liked = widget.clip.liked;
  late int _likes = widget.clip.likes;

  @override
  void initState() {
    super.initState();
    final url = widget.clip.videoUrl;
    if (url == null) {
      _failed = true;
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _c = c;
    c.setLooping(true);
    c.initialize().then((_) {
      if (!mounted) return;
      c.setVolume(ref.read(feedMutedProvider) ? 0 : 1);
      setState(() {});
      _sync();
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didUpdateWidget(covariant ClipPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (!widget.active) _paused = false;
      _sync();
    }
  }

  void _sync() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (widget.active && !_paused) {
      c.play();
    } else {
      c.pause();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _setLike(bool on) async {
    final before = (_liked, _likes);
    setState(() {
      _liked = on;
      _likes = (_likes + (on ? 1 : -1)).clamp(0, 1 << 30);
    });
    ref.read(feedProvider.notifier).applyLike(widget.clip.id, on, _likes);
    try {
      await ref.read(apiProvider).setLike(widget.clip.id, on);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = before.$1;
        _likes = before.$2;
      });
      ref.read(feedProvider.notifier).applyLike(widget.clip.id, before.$1, before.$2);
    }
  }

  void _like() {
    HapticFeedback.mediumImpact();
    if (!_liked) _setLike(true);
    setState(() {
      _heart = true;
      _heartKey++;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _heart = false);
    });
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete this video?', style: T.title(18)),
        content: Text('It is removed from the Feed and from our storage.', style: T.body()),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: Text('Delete', style: TextStyle(color: C.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).deleteClip(widget.clip.id);
      ref.read(feedProvider.notifier).remove(widget.clip.id);
    } catch (_) {
      if (mounted) toast(context, 'Could not delete');
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final muted = ref.watch(feedMutedProvider);
    ref.listen<bool>(feedMutedProvider, (_, m) => _c?.setVolume(m ? 0 : 1));
    final bottomInset = 104.0 + MediaQuery.paddingOf(context).bottom * 0.3;
    final c = _c;
    final ready = c != null && c.value.isInitialized;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!ready) return;
        setState(() => _paused = !_paused);
        _sync();
      },
      onDoubleTap: _like,
      child: Stack(fit: StackFit.expand, children: [
        Container(color: C.bg),
        // The poster frame is there from the first frame, so there is never a black flash; the video fades in over it.
        if (clip.poster != null) Image.network(clip.poster!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        if (c != null)
          AnimatedOpacity(
            opacity: ready ? 1 : 0,
            duration: Motion.standard,
            curve: Motion.premium,
            child: ready ? FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c))) : const SizedBox.expand(),
          ),
        if (!ready)
          Center(
            child: _failed
                ? Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.videocam_off_rounded, color: C.dim, size: 40), const SizedBox(height: 8), Text('Video unavailable', style: T.body())])
                : (clip.poster != null ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)) : Column(mainAxisSize: MainAxisSize.min, children: [Avatar(clip.authorAvatar, size: 76, live: true), const SizedBox(height: 14), const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))])),
          ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x73000000), Colors.transparent, Colors.transparent, Color(0xD9000000)], stops: [0, .20, .52, 1])),
          ),
        ),
        if (_paused && ready) Center(child: SizedBox(width: 76, height: 76, child: Glass(radius: 999, clear: true, padding: EdgeInsets.zero, child: const Icon(Icons.play_arrow_rounded, size: 40, color: Colors.white)))),
        if (_heart)
          Center(
            key: ValueKey(_heartKey),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 750),
              builder: (context, v, _) {
                // playful moment: a quick overshoot in, then a fade out
                final grow = Motion.pop.transform((v / 0.4).clamp(0.0, 1.0));
                final fade = 1 - Curves.easeIn.transform(((v - 0.6) / 0.4).clamp(0.0, 1.0));
                return Opacity(opacity: fade, child: Transform.scale(scale: 0.4 + 0.7 * grow, child: Icon(Icons.favorite_rounded, size: 112, color: C.accent2, shadows: const [Shadow(blurRadius: 24, color: Color(0x66000000))])));
              },
            ),
          ),
        Positioned(
          right: 12,
          bottom: bottomInset + 6,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GlassOrb(icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, label: compact(_likes), active: _liked, semantics: 'Like', onTap: () {
              HapticFeedback.selectionClick();
              _setLike(!_liked);
            }),
            const SizedBox(height: 14),
            if (!clip.mine && !clip.demo) ...[
              GlassOrb(icon: Icons.bolt_rounded, label: 'Duel', semantics: 'Challenge ${clip.authorHandle} to a duel', onTap: () => context.push('/duel/new?target=${clip.authorId}&handle=${clip.authorHandle}')),
              const SizedBox(height: 14),
            ],
            GlassOrb(icon: Icons.ios_share_rounded, label: 'Share', semantics: 'Share', onTap: () {
              Clipboard.setData(ClipboardData(text: '@${clip.authorHandle} took on "${clip.title}" on DAREWIRE'));
              toast(context, 'Copied');
            }),
            const SizedBox(height: 14),
            GlassOrb(icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, semantics: muted ? 'Unmute' : 'Mute', onTap: () => ref.read(feedMutedProvider.notifier).state = !muted),
            const SizedBox(height: 14),
            if (clip.mine)
              GlassOrb(icon: Icons.delete_outline_rounded, semantics: 'Delete video', onTap: _delete)
            else
              GlassOrb(icon: Icons.flag_outlined, semantics: 'Report video', onTap: clip.demo ? () => toast(context, 'Demo video') : () => showReportSheet(context, clipId: clip.id)),
          ]),
        ),
        Positioned(
          left: 18,
          right: 84,
          bottom: bottomInset,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Pressable(
              onTap: () => clip.demo ? toast(context, 'Demo creator') : context.push('/u/${clip.authorId}'),
              child: Glass(
                radius: R.pill,
                clear: true,
                blur: 22,
                padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Avatar(clip.authorAvatar, size: 32),
                  const SizedBox(width: 9),
                  Flexible(child: Text('@${clip.authorHandle}', style: T.strong(14.5), overflow: TextOverflow.ellipsis)),
                  if (clip.demo) ...[const SizedBox(width: 8), Text('DEMO', style: T.tech(9.5).copyWith(color: C.a(Colors.white, 0.8)))],
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Text(clip.title.toUpperCase(), maxLines: 3, overflow: TextOverflow.ellipsis, style: T.wide(27).copyWith(height: 1.02, shadows: const [Shadow(blurRadius: 18, color: Color(0xA0000000))])),
            if (clip.caption.isNotEmpty) ...[const SizedBox(height: 4), Text(clip.caption, style: T.body(14).copyWith(color: C.a(Colors.white, 0.88), shadows: const [Shadow(blurRadius: 8, color: Color(0x80000000))]), maxLines: 2, overflow: TextOverflow.ellipsis)],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _OnVideoChip(prettyKey(clip.category)),
              _OnVideoChip(null, child: Pips(clip.difficulty)),
              if (clip.twist != null) _OnVideoChip('Twist: ${prettyKey(clip.twist!)}', icon: Icons.electric_bolt_rounded),
              Text('${compact(clip.views)} views', style: T.label(12).copyWith(color: C.a(Colors.white, 0.75))),
            ]),
          ]),
        ),
        if (ready)
          Positioned(
            left: 18,
            right: 18,
            bottom: bottomInset - 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: VideoProgressIndicator(c, allowScrubbing: false, padding: EdgeInsets.zero, colors: VideoProgressColors(playedColor: C.a(Colors.white, 0.9), bufferedColor: C.a(Colors.white, 0.2), backgroundColor: C.a(Colors.white, 0.12))),
            ),
          ),
      ]),
    );
  }
}

/// A small frosted-glass chip that stays readable on any video frame.
class _OnVideoChip extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final Widget? child;
  const _OnVideoChip(this.text, {this.icon, this.child});

  @override
  Widget build(BuildContext context) => Glass(
        radius: R.pill,
        clear: true,
        blur: 16,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: Colors.white), const SizedBox(width: 4)],
          if (text != null) Text(text!, style: T.label(12).copyWith(color: Colors.white)),
          if (child != null) child!,
        ]),
      );
}
