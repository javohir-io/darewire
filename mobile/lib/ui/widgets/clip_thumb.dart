import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../gfx/glass.dart';

/// A dare as a poster card: the clip's first frame, a soft scrim, and the title. Used on Home and on profiles.
/// Clips without a poster (real dares until thumbnails exist) get a quiet colour field instead of a blank box.
class ClipThumb extends StatelessWidget {
  final FeedClip clip;
  final double? width, height;
  final double radius;
  final bool showAuthor;
  final bool showPlay;
  final VoidCallback? onTap;
  const ClipThumb(this.clip, {super.key, this.width, this.height, this.radius = R.lg - 2, this.showAuthor = true, this.showPlay = true, this.onTap});

  List<Color> get _field {
    final tiles = C.pal.tiles;
    final h = clip.id.codeUnits.fold<int>(0, (a, b) => (a + b) & 0xFFFF);
    final t = tiles[h % tiles.length];
    return [Color.lerp(t[0], C.bg, 0.15)!, Color.lerp(t[1], C.bg, 0.6)!];
  }

  @override
  Widget build(BuildContext context) {
    final field = DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _field)));
    final body = SizedBox(
      width: width,
      height: height,
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(fit: StackFit.expand, children: [
          if (clip.poster != null)
            Image.network(clip.poster!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => field, frameBuilder: (c, child, frame, sync) => sync || frame != null ? child : field)
          else
            field,
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, C.a(Colors.black, 0.72)], stops: const [0.45, 1]))),
          if (showPlay)
            Positioned(top: 8, right: 8, child: SizedBox(width: 30, height: 30, child: Glass(radius: 99, clear: true, blur: 14, padding: EdgeInsets.zero, child: const Icon(Icons.play_arrow_rounded, size: 19, color: Colors.white)))),
          Positioned(
            left: 12,
            right: 12,
            bottom: 11,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(clip.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.title(15).copyWith(height: 1.15)),
              if (showAuthor) ...[const SizedBox(height: 3), Text('@${clip.authorHandle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label(12).copyWith(color: C.a(Colors.white, 0.78)))],
            ]),
          ),
          Positioned.fill(child: DecoratedBox(decoration: ShapeDecoration(shape: squircle(radius, side: BorderSide(color: C.a(Colors.white, 0.10)))))),
        ]),
      ),
    );
    return onTap == null ? body : Pressable(semanticLabel: clip.title, onTap: onTap, child: body);
  }
}
