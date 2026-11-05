import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/kit.dart';

/// Moderator console. Visible only to moderator/admin profiles, and every action is re-checked and audit-logged on the server.
class ModScreen extends ConsumerStatefulWidget {
  const ModScreen({super.key});
  @override
  ConsumerState<ModScreen> createState() => _ModScreenState();
}

class _ModScreenState extends ConsumerState<ModScreen> {
  List<ReportItem> _reports = [];
  List<ModSession> _sessions = [];
  List<HiddenClip> _clips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    try {
      final r = await api.modReports();
      final s = await api.modSessions();
      final cl = await api.modClips();
      if (mounted) {
        setState(() {
          _reports = r;
          _sessions = s;
          _clips = cl;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, e.message);
      }
    }
  }

  Future<void> _do(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (mounted) toast(context, ok);
      await _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(apiProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Moderation'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(18), children: [
              const SectionTitle('Open reports'),
              if (_reports.isEmpty) Text('Nothing waiting.', style: T.body()),
              for (final r in _reports)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Surface(
                    radius: R.md,
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Tag(prettyKey(r.kind), color: C.danger), const Spacer(), Text(r.sessionId?.substring(0, 6) ?? '', style: T.label(11))]),
                      if (r.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.note, style: T.body(13.5))),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _chip('Dismiss', () => _do(() => api.modResolve(r.id, 'dismiss'), 'Dismissed')),
                        _chip('Warn', () => _do(() => api.modResolve(r.id, 'warn'), 'Warned')),
                        _chip('Remove', () => _do(() => api.modResolve(r.id, 'kick'), 'Removed')),
                        if (r.kind == 'inappropriate_avatar' && r.targetUserId != null) _chip('Reset photo', () => _do(() => api.modResetAvatar(r.targetUserId!), 'Photo reset')),
                        _chip('Suspend 24h', () => _do(() => api.modResolve(r.id, 'suspend_24h'), 'Suspended'), danger: true),
                      ]),
                    ]),
                  ),
                ),
              const SizedBox(height: 18),
              const SectionTitle('Hidden videos (3 or more reports)'),
              if (_clips.isEmpty) Text('Nothing hidden.', style: T.body()),
              for (final c in _clips)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${c.title}  ·  @${c.author}', style: T.strong(14)),
                  trailing: Wrap(spacing: 4, children: [
                    IconButton(tooltip: 'Restore', icon: const Icon(Icons.restore_rounded), onPressed: () => _do(() => api.modClipAction(c.id, 'restore'), 'Restored')),
                    IconButton(tooltip: 'Remove', icon: Icon(Icons.delete_outline_rounded, color: C.danger), onPressed: () => _do(() => api.modClipAction(c.id, 'remove'), 'Removed')),
                  ]),
                ),
              const SizedBox(height: 18),
              const SectionTitle('Active sessions'),
              for (final s in _sessions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${s.title}  ·  ${s.code}', style: T.strong(14)),
                  subtitle: Text('${prettyKey(s.phase.toLowerCase())} · ${s.clients} connected', style: T.label(11.5)),
                  trailing: Wrap(spacing: 4, children: [
                    IconButton(tooltip: 'Observe', icon: const Icon(Icons.visibility_outlined), onPressed: () => context.push('/session/${s.id}?want=observer')),
                    IconButton(tooltip: 'Cut stream', icon: Icon(Icons.videocam_off_outlined, color: C.danger), onPressed: () => _do(() => api.modCut(s.id), 'Stream cut')),
                    IconButton(tooltip: 'End session', icon: Icon(Icons.stop_circle_outlined, color: C.danger), onPressed: () => _do(() => api.modEnd(s.id), 'Session ended')),
                  ]),
                ),
            ]),
    );
  }

  Widget _chip(String t, VoidCallback f, {bool danger = false}) => ActionChip(
        label: Text(t, style: T.strong(12.5).copyWith(color: danger ? C.danger : C.text)),
        onPressed: f,
        backgroundColor: C.glass,
        side: BorderSide(color: danger ? C.danger : C.border),
      );
}
