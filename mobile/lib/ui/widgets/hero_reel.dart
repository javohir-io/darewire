import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../gfx/glass.dart';
import '../../gfx/y2k.dart';
import 'kit.dart';

/// The hero on Home: trending dares playing live (muted), one after another, behind frosted-glass chips and a huge title.
/// One video player at a time. It pauses when Home is not the visible tab and when the OS asks for reduced motion.
class HeroReel extends StatefulWidget {
  final List<FeedClip> clips;
  final bool active;
  final VoidCallback onOpen;
  const HeroReel({super.key, required this.clips, required this.active, required this.onOpen});

  @override
  State<HeroReel> createState() => _HeroReelState();
}

class _HeroReelState extends State<HeroReel> {
  VideoPlayerController? _c;
  int _i = 0;
  int _gen = 0; // ignores answers from a player that has already been replaced
  bool _ready = false;

  FeedClip get _clip => widget.clips[_i % widget.clips.length];

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  @override
  void didUpdateWidget(HeroReel old) {
    super.didUpdateWidget(old);
    if (old.clips.length != widget.clips.length || (widget.clips.isNotEmpty && old.clips.isNotEmpty && old.clips.first.id != widget.clips.first.id)) {
      _load(0);
    } else if (old.active != widget.active) {
      _sync();
    }
  }

  bool get _mayPlay => widget.active && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync() {
    final c = _c;
    if (c == null || !_ready) return;
    _mayPlay ? c.play() : c.pause();
  }

  Future<void> _load(int i) async {
    final gen = ++_gen;
    final old = _c;
    old?.removeListener(_tick);
    _c = null;
    setState(() {
      _i = i % widget.clips.length;
      _ready = false;
    });
    final url = _clip.videoUrl;
    if (url == null) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await c.initialize();
      if (!mounted || gen != _gen) {
        await c.dispose();
        await old?.dispose();
        return;
      }
      await c.setVolume(0);
      await c.setLooping(false);
      c.addListener(_tick);
      _c = c;
      setState(() => _ready = true);
      if (_mayPlay) await c.play();
      await old?.dispose();
    } catch (_) {
      await c.dispose();
      await old?.dispose();
      // a clip that will not play: show its poster for a moment, then move on
      if (mounted && gen == _gen) Future<void>.delayed(const Duration(seconds: 3), () => mounted && gen == _gen && widget.clips.length > 1 ? _load(_i + 1) : null);
    }
  }

  void _tick() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    final end = c.value.duration - const Duration(milliseconds: 120);
    if (c.value.duration > Duration.zero && c.value.position >= end && widget.clips.length > 1) _load(_i + 1);
  }

  @override
  void dispose() {
    _gen++;
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    final w = MediaQuery.sizeOf(context).width - 40;
    final h = (w * 1.22).clamp(340.0, 520.0);
    final c = _c;
    return Pressable(
      semanticLabel: 'Trending dare: ${clip.title}. Open the feed',
      scale: 0.985,
      onTap: widget.onOpen,
      child: SizedBox(
        height: h,
        child: HoloRing(
          radius: 34,
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(34),
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(color: C.bg2),
              AnimatedSwitcher(
                duration: Motion.slow,
                child: clip.poster != null ? Image.network(clip.poster!, key: ValueKey(clip.id), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()) : const SizedBox.shrink(),
              ),
              if (c != null && _ready)
                AnimatedOpacity(
                  opacity: 1,
                  duration: Motion.standard,
                  child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c))),
                ),
              DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.a(Colors.black, 0.35), Colors.transparent, Colors.transparent, C.a(Colors.black, 0.88)], stops: const [0, 0.22, 0.45, 1]))),
              Positioned(
                top: 14,
                left: 14,
                right: 14,
                child: Row(children: [
                  Glass(
                    radius: R.pill,
                    clear: true,
                    blur: 22,
                    padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [Avatar(clip.authorAvatar, size: 30), const SizedBox(width: 8), Text('@${clip.authorHandle}', style: T.strong(13.5))]),
                  ),
                  const Spacer(),
                  Glass(
                    radius: R.pill,
                    clear: true,
                    blur: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [const Sparkle(size: 13), const SizedBox(width: 7), Text('TRENDING', style: T.tech(10.5).copyWith(color: Colors.white))]),
                  ),
                ]),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(clip.title.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: T.wide(27).copyWith(height: 1.02, shadows: const [Shadow(blurRadius: 18, color: Color(0x99000000))])),
                  if (clip.caption.isNotEmpty) ...[const SizedBox(height: 6), Text(clip.caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.body(14).copyWith(color: C.a(Colors.white, 0.88)))],
                  const SizedBox(height: 16),
                  Row(children: [
                    AppButton(label: 'Watch dares', expand: false, height: 48, trailingIcon: Icons.north_east_rounded, onPressed: widget.onOpen),
                    const Spacer(),
                    for (var k = 0; k < widget.clips.length; k++)
                      AnimatedContainer(duration: Motion.standard, curve: Motion.premium, margin: const EdgeInsets.only(left: 5), width: k == _i % widget.clips.length ? 20 : 6, height: 6, decoration: BoxDecoration(color: k == _i % widget.clips.length ? Colors.white : C.a(Colors.white, 0.35), borderRadius: BorderRadius.circular(6))),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
