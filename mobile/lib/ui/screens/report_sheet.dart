import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/kit.dart';

const _kinds = {
  'unsafe_challenge': 'Unsafe dare',
  'harassment': 'Harassment or pressure',
  'sexual_content': 'Sexual content',
  'inappropriate_avatar': 'Inappropriate photo',
  'underage': 'Might be under 16',
  'spam': 'Spam',
  'other': 'Something else',
};

/// Report a session, video or player, and optionally block them. Reports reach moderators; blocking is instant and private.
Future<void> showReportSheet(BuildContext context, {String? sessionId, String? clipId, Person? target, String? conversationId}) {
  return showGlassSheet<void>(context, builder: (_) => _ReportBody(sessionId: sessionId, clipId: clipId, target: target, conversationId: conversationId));
}

class _ReportBody extends ConsumerStatefulWidget {
  final String? sessionId;
  final String? clipId;
  final Person? target;

  /// Set when reporting from a chat: the server attaches the last few messages for the moderator.
  final String? conversationId;
  const _ReportBody({this.sessionId, this.clipId, this.target, this.conversationId});
  @override
  ConsumerState<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends ConsumerState<_ReportBody> {
  late String _kind = widget.conversationId != null ? 'harassment' : 'unsafe_challenge';
  final _note = TextEditingController();
  bool _busy = false;
  bool _block = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    try {
      await api.report(kind: _kind, note: _note.text.trim(), targetUserId: widget.target?.id, sessionId: widget.sessionId, clipId: widget.clipId, conversationId: widget.conversationId);
      if (_block && widget.target != null) await api.block(widget.target!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'Thank you. A moderator will review this.');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.clipId != null ? 'Report this video' : (t == null ? 'Report this session' : 'Report @${t.handle}'), style: T.title(19)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in _kinds.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _kind == e.key,
              onSelected: (_) => setState(() => _kind = e.key),
              selectedColor: C.a(C.primary, 0.5),
              backgroundColor: C.glass,
              labelStyle: T.strong(13),
              side: BorderSide(color: _kind == e.key ? C.primaryHi : C.border),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(controller: _note, maxLength: 500, maxLines: 3, decoration: const InputDecoration(hintText: 'Tell us what happened (optional)')),
        if (t != null) SwitchListTile(contentPadding: EdgeInsets.zero, value: _block, onChanged: (v) => setState(() => _block = v), title: Text('Also block @${t.handle}', style: T.strong(14))),
        const SizedBox(height: 6),
        AppButton(label: 'Send report', busy: _busy, onPressed: _send),
      ]),
    );
  }
}
