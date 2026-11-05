import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../state/providers.dart';
import '../widgets/kit.dart';

/// Shown to the player after a finished round that was recorded with their consent. Nothing is public unless they tap "Post".
Future<void> showClipOfferSheet(BuildContext context, {required String clipId, required String title, required int durationMs}) {
  return showGlassSheet<void>(context, dismissible: false, builder: (_) => _ClipOffer(clipId: clipId, title: title, durationMs: durationMs));
}

class _ClipOffer extends ConsumerStatefulWidget {
  final String clipId, title;
  final int durationMs;
  const _ClipOffer({required this.clipId, required this.title, required this.durationMs});
  @override
  ConsumerState<_ClipOffer> createState() => _ClipOfferState();
}

class _ClipOfferState extends ConsumerState<_ClipOffer> {
  final _caption = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).publishClip(widget.clipId, _caption.text.trim());
      ref.read(feedProvider.notifier).load(reset: true);
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'Posted to Dares');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, e.message);
      }
    }
  }

  Future<void> _discard() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).deleteClip(widget.clipId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Post your dare video?', style: T.large(24)),
        const SizedBox(height: 8),
        Text('${widget.title}  ·  ${(widget.durationMs / 1000).round()}s', style: T.strong(15)),
        const SizedBox(height: 8),
        Text('Only you can see this right now. If you post it, other ${ref.watch(isTeenProvider) ? 'teens' : 'adults'} on DAREWIRE can watch it in the Dares feed. You can delete it at any time. If you discard it, the video is deleted.', style: T.body(13.5)),
        const SizedBox(height: 14),
        TextField(controller: _caption, maxLength: 140, decoration: const InputDecoration(hintText: 'Add a caption (optional)')),
        const SizedBox(height: 6),
        AppButton(label: 'Post to Dares', icon: Icons.movie_filter_rounded, busy: _busy, onPressed: _post),
        const SizedBox(height: 8),
        AppButton(label: 'Discard', kind: BtnKind.quiet, onPressed: _busy ? null : _discard),
      ]),
    );
  }
}
