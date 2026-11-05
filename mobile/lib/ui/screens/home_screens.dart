import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../gfx/brand.dart';
import '../../gfx/cipher_face.dart';
import '../../gfx/backdrop.dart';
import '../../gfx/glass.dart';
import '../../state/cipher_controller.dart';
import '../../state/providers.dart';
import '../../gfx/y2k.dart';
import '../widgets/clip_thumb.dart';
import '../widgets/hero_reel.dart';
import '../widgets/kit.dart';
import '../widgets/live_card.dart';
import '../widgets/teen_intro.dart';
import 'duels_screen.dart';
import 'feed_screen.dart';
import 'profile_screens.dart';

/// The app frame: four tabs and a floating glass tab bar with a "create" button in the middle.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _feedSeen = false; // the Feed (and its video players) is only built once you first open it
  bool _introChecked = false;
  Timer? _badgeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTeenIntro(ref.read(meProvider).valueOrNull?.profile));
    // The red dots on Messages and Activity are refreshed every 30 seconds while the app is open.
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(badgesProvider);
    });
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
  }

  /// Shows the "Your teen account" explainer once per account per device.
  Future<void> _maybeTeenIntro(Profile? p) async {
    if (_introChecked || p == null || !p.isTeen) return;
    _introChecked = true;
    if (await teenIntroSeen(p.id) || !mounted) return;
    await showTeenIntro(context, userId: p.id);
  }

  void _select(int i) {
    if (ref.read(shellTabProvider) != i) HapticFeedback.selectionClick();
    ref.read(shellTabProvider.notifier).state = i;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(meProvider, (_, next) => _maybeTeenIntro(next.valueOrNull?.profile));
    final tab = ref.watch(shellTabProvider);
    final avatar = ref.watch(meProvider).value?.profile.avatar ?? 'a01';
    final badge = ref.watch(duelBadgeProvider);
    if (tab == 1) _feedSeen = true;
    // The Feed is full-screen video: the scene behind it cannot be seen, so stop painting it.
    WidgetsBinding.instance.addPostFrameCallback((_) => GlassClock.paused.value = tab == 1);
    return Stack(children: [
      // The Feed runs full-bleed behind the status bar and the tab bar; the other tabs respect the safe area.
      IndexedStack(index: tab, children: [
        const SafeArea(bottom: false, child: HomeTab()),
        _feedSeen ? FeedTab(active: tab == 1) : const SizedBox.shrink(),
        const SafeArea(bottom: false, child: DuelsTab()),
        const SafeArea(bottom: false, child: SelfProfileTab()),
      ]),
      Positioned(
        left: 16,
        right: 16,
        bottom: 6,
        child: SafeArea(top: false, child: _TabBar(tab: tab, avatar: avatar, badge: badge, onSelect: _select, onCreate: () {
          HapticFeedback.mediumImpact();
          showCreateSheet(context);
        })),
      ),
    ]);
  }
}

/// The floating tab bar. A glass "lens" slides behind the selected tab (the liquid-glass signature), and Create sits in the middle.
class _TabBar extends StatelessWidget {
  final int tab, badge;
  final String avatar;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;
  const _TabBar({required this.tab, required this.avatar, required this.badge, required this.onSelect, required this.onCreate});

  static const _labels = ['Home', 'Feed', 'Duels', 'Profile'];
  static const _off = [Icons.home_outlined, Icons.play_circle_outline_rounded, Icons.bolt_outlined];
  static const _on = [Icons.home_rounded, Icons.play_circle_rounded, Icons.bolt_rounded];
  static const _createW = 66.0;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: R.pill,
      blur: 32,
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        height: 60,
        child: LayoutBuilder(builder: (context, c) {
          final slot = (c.maxWidth - _createW) / 4;
          final left = tab < 2 ? tab * slot : 2 * slot + _createW + (tab - 2) * slot;
          return Stack(children: [
            AnimatedPositioned(
              duration: Motion.standard,
              curve: Motion.premium,
              left: left,
              width: slot,
              top: 0,
              bottom: 0,
              child: Container(decoration: ShapeDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.a(Colors.white, 0.26), C.a(Colors.white, 0.10)]), shape: StadiumBorder(side: BorderSide(color: C.a(Colors.white, 0.30))), shadows: [BoxShadow(color: C.a(C.primary, 0.35), blurRadius: 16, spreadRadius: -4)])),
            ),
            Row(children: [
              Expanded(child: _item(0)),
              Expanded(child: _item(1)),
              SizedBox(width: _createW, child: Center(child: _create())),
              Expanded(child: _item(2)),
              Expanded(child: _item(3)),
            ]),
          ]);
        }),
      ),
    );
  }

  Widget _create() => Pressable(
        semanticLabel: 'Create',
        scale: 0.9,
        onTap: onCreate,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: C.brand, border: Border.all(color: C.a(Colors.white, 0.45), width: 1.4), boxShadow: [BoxShadow(color: C.a(C.primary, 0.55), blurRadius: 20, spreadRadius: -4)]),
          child: Icon(Icons.add_rounded, color: C.onColor(C.primary), size: 30),
        ),
      );

  Widget _item(int index) {
    final on = tab == index;
    final col = on ? Colors.white : C.a(Colors.white, 0.62);
    final Widget icon = index == 3 ? Avatar(avatar, size: 24, ring: on) : Icon(on ? _on[index] : _off[index], size: 25, color: col);
    return Semantics(
      button: true,
      selected: on,
      label: _labels[index],
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(index),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Stack(clipBehavior: Clip.none, children: [
            icon,
            if (index == 2 && badge > 0)
              Positioned(
                right: -10,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: ShapeDecoration(color: C.accent2, shape: const StadiumBorder()),
                  child: Text('$badge', style: T.num(10.5).copyWith(color: C.onColor(C.accent2))),
                ),
              ),
          ]),
          const SizedBox(height: 2),
          Text(_labels[index], style: T.label(10.5).copyWith(color: col, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

/// The "+" menu.
Future<void> showCreateSheet(BuildContext context) {
  return showGlassSheet<void>(
    context,
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 10), child: Text('Create', style: T.large(26))),
        ListRow(icon: Icons.videocam_rounded, title: 'Go live', subtitle: 'Host a session. AI writes five dares and the crowd picks one.', onTap: () {
          Navigator.of(c).pop();
          context.push('/create');
        }),
        ListRow(icon: Icons.bolt_rounded, title: 'Challenge someone', subtitle: 'Send a duel and earn points when it is completed.', onTap: () {
          Navigator.of(c).pop();
          context.push('/duel/new');
        }),
        ListRow(icon: Icons.chat_bubble_rounded, title: 'Talk to Cipher', subtitle: 'Get dare ideas or a pep talk.', onTap: () {
          Navigator.of(c).pop();
          context.push('/cipher');
        }),
      ]),
    ),
  );
}

const _tips = [
  'Tap me! I like it.',
  'Want a dare idea? Open chat and ask.',
  'Complete a dare to earn points and keep your streak going.',
  'Challenge a friend to a duel. You both earn points when it is done.',
  'You can pass any dare, any time. No penalty.',
];

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});
  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  final _code = TextEditingController();
  bool _joining = false;
  int _tip = 0;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.length < 4) return;
    setState(() => _joining = true);
    try {
      final id = await ref.read(apiProvider).joinByCode(code);
      if (mounted) context.push('/session/$id?want=watcher');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _joining = false);
  }

  void _openFeed(int page) {
    ref.read(feedPageProvider.notifier).state = page;
    ref.read(shellTabProvider.notifier).state = 1;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);
    final trending = ref.watch(trendingProvider);
    final me = ref.watch(meProvider).value?.profile;
    final wallet = ref.watch(walletProvider).valueOrNull;
    final quests = ref.watch(questsProvider).valueOrNull;
    final cipher = ref.watch(cipherProvider);
    final badges = ref.watch(badgesProvider).valueOrNull;
    return RefreshIndicator(
      color: C.primaryHi,
      backgroundColor: C.bg2,
      onRefresh: () async {
        ref.invalidate(sessionsProvider);
        ref.invalidate(trendingProvider);
        ref.invalidate(walletProvider);
        ref.invalidate(questsProvider);
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 130), children: [
        Reveal(
          child: Row(children: [
            const Wordmark(size: 19),
            const Spacer(),
            _HeaderIcon(icon: Icons.search_rounded, label: 'Find people', onTap: () => context.push('/discover')),
            const SizedBox(width: 8),
            _HeaderIcon(icon: Icons.notifications_none_rounded, label: 'Activity', badge: badges?.activity ?? 0, onTap: () async {
              await context.push('/activity');
              ref.invalidate(badgesProvider);
            }),
            const SizedBox(width: 8),
            _HeaderIcon(icon: Icons.send_rounded, label: 'Messages', badge: badges?.chats ?? 0, onTap: () async {
              await context.push('/inbox');
              ref.invalidate(badgesProvider);
            }),
          ]),
        ),
        const SizedBox(height: 24),
        Reveal(
          delay: Motion.stagger(1),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('HEY,', style: T.tech(12).copyWith(color: C.dim)),
                  const SizedBox(height: 4),
                  GradientText(me?.handle != null ? me!.handle! : 'there', style: T.wide(34)),
                ]),
              ),
              PointsPill(wallet?.balance ?? 0, onTap: () => context.push('/rewards')),
            ]),
            const SizedBox(height: 6),
            Text('What are we daring today?', style: T.body(16)),
          ]),
        ),
        const SizedBox(height: 18),
        Reveal(
          delay: Motion.stagger(2),
          child: trending.maybeWhen(
            data: (clips) => clips.isEmpty ? const SizedBox.shrink() : HeroReel(clips: clips, active: ref.watch(shellTabProvider) == 0, onOpen: () => _openFeed(1)),
            orElse: () => const _HeroSkeleton(),
          ),
        ),
        const SizedBox(height: 14),
        Reveal(
          delay: Motion.stagger(3),
          child: Surface(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(children: [
              CipherFace(
                size: 104,
                mood: cipher.mood,
                onTap: () {
                  ref.read(cipherProvider.notifier).touch();
                  setState(() => _tip = (_tip + 1) % _tips.length);
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cipher', style: T.title(17)),
                  const SizedBox(height: 3),
                  AnimatedSwitcher(duration: Motion.standard, switchInCurve: Motion.enter, child: Text(_tips[_tip], key: ValueKey(_tip), style: T.body(13.5))),
                  const SizedBox(height: 10),
                  AppButton(label: 'Chat with Cipher', height: 40, kind: BtnKind.glass, trailingIcon: Icons.chevron_right_rounded, onPressed: () => context.push('/cipher')),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Reveal(
          delay: Motion.stagger(4),
          child: Row(children: [
            Expanded(child: _ActionTile(primary: true, icon: Icons.videocam_rounded, title: 'Go live', subtitle: 'Host a session. The crowd picks your dare.', onTap: () => context.push('/create'))),
            const SizedBox(width: 12),
            Expanded(child: _ActionTile(icon: Icons.bolt_rounded, title: 'Duel', subtitle: 'Challenge a friend. Earn points together.', onTap: () => context.push('/duel/new'))),
          ]),
        ),
        const SizedBox(height: 28),
        SectionTitle('Live now', action: 'See all', onAction: () => _openFeed(0)),
        sessions.when(
          loading: () => const SizedBox(height: 210, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
          error: (e, _) => Text(e is ApiException ? e.message : 'Could not load live sessions', style: T.body()),
          data: (list) {
            final live = [...list]..sort((a, b) => (b.onStage ? 1 : 0).compareTo(a.onStage ? 1 : 0));
            if (live.isEmpty) {
              return Surface(
                child: Row(children: [
                  IconBadge(Icons.sensors_rounded, size: 40, color: C.dim),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Nobody is live right now', style: T.strong(15.5)), const SizedBox(height: 2), Text('Be the first to go live.', style: T.body(13.5))])),
                  AppButton(label: 'Go live', expand: false, height: 40, onPressed: () => context.push('/create')),
                ]),
              );
            }
            return SizedBox(
              height: 244,
              child: ListView.separated(
                clipBehavior: Clip.none,
                scrollDirection: Axis.horizontal,
                itemCount: live.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (c, i) => LiveCard(live[i], width: 176),
              ),
            );
          },
        ),
        trending.maybeWhen(
          data: (clips) => clips.isEmpty
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 26),
                  SectionTitle('More dares', action: 'Watch', onAction: () => _openFeed(1)),
                  SizedBox(
                    height: 236,
                    child: ListView.separated(
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      itemCount: clips.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (c, i) => ClipThumb(clips[(i + 1) % clips.length], width: 156, height: 236, radius: R.xl, onTap: () => _openFeed(1)),
                    ),
                  ),
                ]),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Daily streak'),
        _StreakCard(quests: quests),
        const SizedBox(height: 24),
        const SectionTitle('Join with a code'),
        Row(children: [
          Expanded(child: TextField(controller: _code, textCapitalization: TextCapitalization.characters, maxLength: 6, onSubmitted: (_) => _join(), decoration: const InputDecoration(hintText: 'Enter the 6 character code', counterText: ''))),
          const SizedBox(width: 10),
          SizedBox(width: 100, child: AppButton(label: 'Join', kind: BtnKind.glass, busy: _joining, onPressed: _join)),
        ]),
      ]),
    );
  }
}

/// A round glass icon in the Home header, with a small red count when something is new.
class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final int badge;
  final VoidCallback onTap;
  const _HeaderIcon({required this.icon, required this.label, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) => Pressable(
        semanticLabel: badge > 0 ? '$label, $badge new' : label,
        onTap: onTap,
        scale: 0.92,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.a(Colors.white, 0.16), C.a(Colors.white, 0.07)]), border: Border.all(color: C.a(Colors.white, 0.20))),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          if (badge > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: ShapeDecoration(color: C.accent2, shape: StadiumBorder(side: BorderSide(color: C.bg, width: 1.5))),
                child: Text(badge > 9 ? '9+' : '$badge', textAlign: TextAlign.center, style: T.num(10.5).copyWith(color: C.onColor(C.accent2))),
              ),
            ),
        ]),
      );
}

/// A placeholder with the same shape as the hero while trending dares load: a drifting gradient and a sparkle.
class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width - 40;
    return SizedBox(
      height: (w * 1.22).clamp(340.0, 520.0),
      child: HoloRing(
        radius: 34,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(34),
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [C.a(C.primary, 0.55), C.a(C.accent2, 0.35), C.a(C.bg, 0.9)])),
            child: const Center(child: Sparkle(size: 44)),
          ),
        ),
      ),
    );
  }
}

/// A large action card. The primary one is the theme colour; the other is a flat surface. Only one primary action per screen.
class _ActionTile extends StatelessWidget {
  final bool primary;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _ActionTile({this.primary = false, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = primary ? C.onColor(C.primary) : C.text;
    return Pressable(
      semanticLabel: title,
      onTap: onTap,
      scale: 0.98,
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(16),
        decoration: ShapeDecoration(
          gradient: primary ? C.brand : null,
          color: primary ? null : C.surface,
          shape: squircle(R.lg, side: BorderSide(color: primary ? C.a(Colors.white, 0.18) : C.hairline)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 38, height: 38, decoration: ShapeDecoration(color: primary ? C.a(Colors.white, 0.20) : C.a(C.primaryHi, 0.16), shape: squircle(12)), child: Icon(icon, size: 21, color: primary ? fg : C.primaryHi)),
          const Spacer(),
          Text(title.toUpperCase(), style: T.wide(15).copyWith(color: fg)),
          const SizedBox(height: 3),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.body(12.5).copyWith(color: primary ? C.a(fg, 0.8) : C.dim, height: 1.25)),
        ]),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final QuestsState? quests;
  const _StreakCard({required this.quests});

  @override
  Widget build(BuildContext context) {
    final q = quests;
    final week = q?.week ?? const [];
    return Surface(
      onTap: () => context.push('/rewards'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.local_fire_department_rounded, color: C.accent2, size: 22),
          const SizedBox(width: 8),
          Text('${q?.streak ?? 0} day streak', style: T.title(17)),
          const Spacer(),
          if ((q?.claimable ?? 0) > 0)
            Tag('${q!.claimable} ready to claim', color: C.accent)
          else
            Row(mainAxisSize: MainAxisSize.min, children: [Text('Rewards', style: T.strong(13.5).copyWith(color: C.primaryHi)), Icon(Icons.chevron_right_rounded, size: 20, color: C.primaryHi)]),
        ]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final d in week.isEmpty ? List.generate(7, (i) => WeekDay(const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i], false, false, false)) : week) _DayDot(d),
        ]),
        const SizedBox(height: 12),
        Text('Complete a dare each day to keep your streak going.', style: T.body(12.5)),
      ]),
    );
  }
}

class _DayDot extends StatelessWidget {
  final WeekDay d;
  const _DayDot(this.d);
  @override
  Widget build(BuildContext context) {
    final done = d.active;
    return Column(children: [
      AnimatedContainer(
        duration: Motion.standard,
        curve: Motion.premium,
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? C.accent2 : C.a(Colors.white, d.future ? 0.03 : 0.08),
          border: Border.all(color: d.today ? C.a(Colors.white, 0.85) : (done ? Colors.transparent : C.hairline), width: d.today ? 1.6 : 1),
        ),
        child: done ? Icon(Icons.check_rounded, size: 19, color: C.onColor(C.accent2)) : null,
      ),
      const SizedBox(height: 6),
      Text(d.label, style: T.label(11.5).copyWith(color: d.today ? C.text : C.faint)),
    ]);
  }
}

class CreateSessionScreen extends ConsumerStatefulWidget {
  const CreateSessionScreen({super.key});
  @override
  ConsumerState<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends ConsumerState<CreateSessionScreen> {
  final _title = TextEditingController();
  bool _twist = true;
  bool _private = false;
  bool _hostPlays = true;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).createSession(title: _title.text.trim(), twist: _twist, isPrivate: _private, hostPlays: _hostPlays);
      if (mounted) context.pushReplacement('/session/${r.id}?want=${_hostPlays ? "player" : "watcher"}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teen = ref.watch(isTeenProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Go live')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), children: [
          Text('Name your session', style: T.title(18)),
          const SizedBox(height: 10),
          TextField(controller: _title, maxLength: 40, decoration: const InputDecoration(hintText: 'For example: Friday dare night', counterText: '')),
          const SizedBox(height: 18),
          Surface(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(children: [
              _switch('I take the stage', 'Turn off to host while someone else performs.', _hostPlays, (v) => setState(() => _hostPlays = v)),
              Divider(height: 1, color: C.hairline),
              _switch('Twist round', 'During a dare, the crowd votes on a surprise change.', _twist, (v) => setState(() => _twist = v)),
              Divider(height: 1, color: C.hairline),
              _switch('Private session', 'Hidden from Live now. Share the code with friends.', _private, (v) => setState(() => _private = v)),
            ]),
          ),
          const SizedBox(height: 16),
          Surface(
            color: C.a(C.primary, 0.10),
            padding: const EdgeInsets.all(14),
            radius: R.md,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(teen ? Icons.groups_rounded : Icons.verified_user_outlined, size: 20, color: C.primaryHi),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  teen
                      ? 'This is a teen session: only people aged 16 to 17 can see or join it. Dares follow the teen safety rules and stop at level 3.'
                      : 'Only adults (18 and over) can see or join this session. Dares are checked by our safety rules and always respect the player\'s boundaries.',
                  style: T.body(13),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          AppButton(label: 'Open the stage', icon: Icons.videocam_rounded, busy: _busy, onPressed: _create),
        ]),
      ),
    );
  }

  Widget _switch(String t, String sub, bool v, ValueChanged<bool> on) => SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        value: v,
        onChanged: on,
        title: Text(t, style: T.strong(15)),
        subtitle: Text(sub, style: T.body(12.5)),
      );
}
