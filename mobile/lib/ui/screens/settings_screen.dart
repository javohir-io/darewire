import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/config.dart';
import '../../core/motion.dart';
import '../../core/perf.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../gfx/backdrop.dart';
import '../../state/providers.dart';
import '../widgets/kit.dart';
import '../widgets/teen_intro.dart';
import 'auth_screens.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).value?.profile;
    final current = ref.watch(themeProvider);
    final teen = me?.isTeen ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 40), children: [
          if (teen) ...[
            Surface(
              onTap: () => me == null ? null : showTeenIntro(context, userId: me.id),
              color: C.a(C.primary, 0.12),
              child: Row(children: [
                const IconBadge(Icons.verified_user_rounded, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Teen account', style: T.strong(16)),
                    const SizedBox(height: 2),
                    Text('Teen-only rooms and safer dares are on. Tap to see how you are protected.', style: T.body(13)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: C.faint),
              ]),
            ),
            const SizedBox(height: 22),
          ],
          const SectionTitle('Appearance'),
          Surface(
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (final p in palettes) _Swatch(p, selected: p.id == current, onTap: () => ref.read(themeProvider.notifier).choose(p.id))]),
              const SizedBox(height: 14),
              Divider(height: 1, color: C.hairline),
              ValueListenableBuilder<bool>(
                valueListenable: GlassClock.enabled,
                builder: (context, on, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: on,
                  onChanged: (v) => GlassClock.setEnabled(v),
                  title: Text('Animated background', style: T.strong(15)),
                  subtitle: Text('Turn this off to save battery, or if the app feels slow on your phone.', style: T.body(12.5)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const SectionTitle('Performance'),
          Surface(
            child: ValueListenableBuilder<String>(
              valueListenable: Perf.mode,
              builder: (context, m, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Smooth mode', style: T.strong(15.5)),
                const SizedBox(height: 4),
                Text('Turns off blur and the animated background so the app runs smoothly on slower phones. Auto switches it on by itself if the app is struggling.', style: T.body(13)),
                const SizedBox(height: 14),
                Segmented(labels: const ['Auto', 'On', 'Off'], index: const ['auto', 'on', 'off'].indexOf(m), onChanged: (i) => Perf.setMode(const ['auto', 'on', 'off'][i])),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.only(left: 4), child: Text('Your theme and performance choice are saved on this device.', style: T.body(12.5))),
          const SizedBox(height: 22),
          const SectionTitle('Account'),
          GroupedList(children: [
            ListRow(icon: Icons.person_rounded, title: 'Edit profile', subtitle: 'Photo, handle, bio and boundaries', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupScreen(editing: true)))),
            ListRow(icon: Icons.bolt_rounded, title: 'Rewards', subtitle: 'Points, quests and leaderboard', onTap: () => context.push('/rewards')),
            ListRow(icon: Icons.person_add_alt_1_rounded, title: 'Find people', subtitle: 'Search and follow', onTap: () => context.push('/discover')),
            ListRow(icon: Icons.block_rounded, title: 'Blocked accounts', subtitle: 'People you have blocked', onTap: () => context.push('/blocked')),
            ListRow(icon: Icons.health_and_safety_rounded, title: 'Safety centre', subtitle: 'Blocking, reporting and staying safe', onTap: () => context.push('/safety')),
            if (me?.isModerator == true) ListRow(icon: Icons.shield_rounded, title: 'Moderation console', onTap: () => context.push('/mod')),
          ]),
          const SizedBox(height: 18),
          GroupedList(children: [
            ListRow(icon: Icons.logout_rounded, title: 'Sign out', onTap: () => ref.read(authServiceProvider).signOut()),
            ListRow(icon: Icons.delete_forever_rounded, title: 'Delete my account', danger: true, onTap: () => _delete(context, ref)),
          ]),
          const SizedBox(height: 24),
          Text(teen ? 'DAREWIRE is for ages 16 and over. You are on a teen account.' : 'DAREWIRE is for ages 16 and over.', textAlign: TextAlign.center, style: T.body(12.5)),
          const SizedBox(height: 6),
          Text('Build $buildTag', textAlign: TextAlign.center, style: T.label(11.5)),
        ]),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete your account?', style: T.title(18)),
        content: Text('This permanently removes your profile, history, points, duels and videos. It cannot be undone.', style: T.body()),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: Text('Delete', style: TextStyle(color: C.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).deleteAccount();
      await ref.read(authServiceProvider).signOut();
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }
}

/// One theme as a round swatch with its name. The chosen one gets a white ring.
class _Swatch extends StatelessWidget {
  final Pal p;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch(this.p, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
        semanticLabel: '${p.name} theme',
        onTap: onTap,
        scale: 0.94,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: Motion.standard,
            curve: Motion.premium,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2)),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.primary, p.accent2]),
                border: Border.all(color: C.a(Colors.white, 0.18)),
              ),
              child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 26) : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(p.name, style: T.label(12).copyWith(color: selected ? C.text : C.faint)),
        ]),
      );
}
