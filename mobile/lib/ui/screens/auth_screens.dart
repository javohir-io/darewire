import 'dart:typed_data';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker, CupertinoDatePickerMode, CupertinoTheme, CupertinoThemeData;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../core/config.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../gfx/brand.dart';
import '../../gfx/cipher_face.dart';
import '../../gfx/glass.dart';
import '../../gfx/y2k.dart';
import '../../state/providers.dart';
import '../widgets/kit.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Reveal(dy: 8, child: Wordmark(size: 36)));
}

class ConnectErrorScreen extends ConsumerWidget {
  final Object error;
  const ConnectErrorScreen(this.error, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CipherFace(size: 110, mood: 'worried'),
            const SizedBox(height: 10),
            Text(error is ApiException ? (error as ApiException).message : 'We could not reach DAREWIRE.', textAlign: TextAlign.center, style: T.title(18)),
            const SizedBox(height: 8),
            Text('Server: ${Env.apiUrl}', style: T.label(11)),
            const SizedBox(height: 20),
            AppButton(label: 'Try again', expand: false, onPressed: () => ref.read(meProvider.notifier).refresh()),
            const SizedBox(height: 8),
            AppButton(label: 'Sign out', kind: BtnKind.quiet, expand: false, onPressed: () => ref.read(authServiceProvider).signOut()),
          ]),
        ),
      );
}

/// The first screen: a looping dare video fills the screen, with a huge headline and a glass sign-in card over it.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _handle = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  VideoPlayerController? _video;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    _startVideo();
  }

  /// The video is bundled with the app, so this screen is alive before the server answers. If it cannot play, the poster stays.
  Future<void> _startVideo() async {
    final c = VideoPlayerController.asset('assets/demo/welcome.mp4');
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setVolume(0);
      await c.setLooping(true);
      await c.play();
      setState(() {
        _video = c;
        _videoReady = true;
      });
    } catch (_) {
      await c.dispose();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    _email.dispose();
    _pass.dispose();
    _handle.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    final auth = ref.read(authServiceProvider);
    try {
      if (Env.useSupabase) {
        if (_signUp) {
          final msg = await auth.signUp(_email.text, _pass.text);
          if (msg != null && mounted) {
            toast(context, msg);
            setState(() => _signUp = false);
          }
        } else {
          await auth.signIn(_email.text, _pass.text);
        }
      } else {
        await auth.devLogin(_handle.text);
      }
    } catch (e) {
      if (mounted) toast(context, e is ArgumentError ? '${e.message}' : 'Sign-in failed. Check your details and try again.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    final title = T.wide(42).copyWith(height: 1.0, shadows: const [Shadow(blurRadius: 24, color: Color(0x80000000))]);
    return Stack(fit: StackFit.expand, children: [
      Image.asset('assets/demo/dare-karaoke.jpg', fit: BoxFit.cover),
      if (v != null && _videoReady) FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v))),
      DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.a(Colors.black, 0.55), C.a(Colors.black, 0.10), C.a(Colors.black, 0.55), C.a(C.bg, 0.96)], stops: const [0, 0.28, 0.58, 1]))),
      SafeArea(
        child: CustomScrollView(slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Reveal(child: Wordmark(size: 20)),
                const Spacer(),
                Reveal(delay: Motion.stagger(1), child: Row(children: [const Sparkle(size: 14), const SizedBox(width: 8), Text('LIVE DARES  ·  AGES 16+', style: T.tech(11).copyWith(color: Colors.white))])),
                const SizedBox(height: 12),
                Reveal(
                  delay: Motion.stagger(2),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TAKE ON', style: title), Text('DARES', style: title), GradientText('LIVE.', style: title)]),
                ),
                const SizedBox(height: 14),
                Reveal(delay: Motion.stagger(3), child: Text('The crowd votes. You decide.\nDo it live, earn the streak.', style: T.body(16).copyWith(color: C.a(Colors.white, 0.86), height: 1.35))),
                const SizedBox(height: 22),
                Reveal(
                  delay: Motion.stagger(4),
                  child: Glass(
                    radius: R.xl,
                    blur: 30,
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      if (Env.useSupabase) ...[
                        TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(hintText: 'Email')),
                        const SizedBox(height: 10),
                        TextField(controller: _pass, obscureText: true, autofillHints: const [AutofillHints.password], decoration: const InputDecoration(hintText: 'Password')),
                      ] else if (Env.devAuth) ...[
                        Row(children: [
                          Icon(Icons.build_rounded, size: 14, color: C.warn),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Development login. Supabase is not configured.', style: T.label(11.5).copyWith(color: C.warn))),
                        ]),
                        const SizedBox(height: 12),
                        TextField(controller: _handle, decoration: const InputDecoration(hintText: 'Pick a handle (a-z, 0-9, _)')),
                      ] else
                        Text('This build has no sign-in configured. Set SUPABASE_URL and SUPABASE_ANON_KEY (see the README).', style: T.body(13)),
                      const SizedBox(height: 14),
                      if (Env.useSupabase || Env.devAuth) AppButton(label: Env.useSupabase ? (_signUp ? 'Create account' : 'Sign in') : 'Continue', trailingIcon: Icons.north_east_rounded, busy: _busy, onPressed: _go),
                      if (Env.useSupabase) AppButton(label: _signUp ? 'I already have an account' : 'New here? Create an account', kind: BtnKind.quiet, onPressed: () => setState(() => _signUp = !_signUp)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Center(child: Text('For ages 16 and over.', style: T.body(12.5).copyWith(color: C.a(Colors.white, 0.7)))),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// "When is your birthday?" A neutral question: the screen does not say which ages are allowed, so nobody learns what to type.
/// The server decides (16 and over) and remembers the first answer, so entering a different date later does not change it.
class AgeGateScreen extends ConsumerStatefulWidget {
  const AgeGateScreen({super.key});
  @override
  ConsumerState<AgeGateScreen> createState() => _AgeGateScreenState();
}

class _AgeGateScreenState extends ConsumerState<AgeGateScreen> {
  late DateTime _dob = DateTime(DateTime.now().year - 17, 6, 15);
  bool _busy = false;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    // Someone who already gave a date that was too young is told so straight away, instead of being asked again.
    final p = ref.read(meProvider).valueOrNull?.profile;
    final given = p?.birthDate == null ? null : DateTime.tryParse(p!.birthDate!);
    if (given != null && p?.ageVerified == false) {
      if (ageOn(given, DateTime.now()) >= minAge) {
        // They have had their birthday since: ask the server again. It re-checks the date it already holds.
        _dob = given;
        WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
      } else {
        _blocked = true;
      }
    }
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(meProvider.notifier).confirmAge(_fmt(_dob));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          if (e.code == 'underage') _blocked = true;
        });
        if (e.code != 'underage') toast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Reveal(
            child: _blocked ? _blockedView() : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Wordmark(size: 20),
              const SizedBox(height: 28),
              Text('When is your birthday?', style: T.large(32)),
              const SizedBox(height: 8),
              Text('We use it to set up your account the right way. It stays private.', style: T.body(15.5)),
              const SizedBox(height: 22),
              Surface(
                padding: const EdgeInsets.symmetric(vertical: 4),
                radius: R.xl,
                child: SizedBox(
                  height: 190,
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(brightness: Brightness.dark),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      initialDateTime: _dob,
                      minimumYear: 1920,
                      maximumDate: now,
                      onDateTimeChanged: (d) => _dob = d,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AppButton(label: 'Continue', busy: _busy, onPressed: _submit),
              const SizedBox(height: 12),
              Text('By continuing you confirm this is your real birthday.', style: T.body(12.5), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }

  /// Shown when the date given is under the minimum age. Kind, clear, and with no way to keep guessing.
  Widget _blockedView() => Column(mainAxisSize: MainAxisSize.min, children: [
        const CipherFace(size: 120, mood: 'idle'),
        const SizedBox(height: 14),
        Text('You are not quite old enough yet', textAlign: TextAlign.center, style: T.large(26)),
        const SizedBox(height: 10),
        Text('DAREWIRE is for people aged 16 and over. Come back on your 16th birthday, we will be here.', textAlign: TextAlign.center, style: T.body(15.5)),
        const SizedBox(height: 24),
        AppButton(label: 'Sign out', kind: BtnKind.glass, onPressed: () => ref.read(authServiceProvider).signOut()),
      ]);
}

/// Handle, avatar, bio, profile colour and boundaries. Used for first-time setup and for editing later.
/// Boundaries are enforced by the server on every dare; they can be changed at any time.
class SetupScreen extends ConsumerStatefulWidget {
  final bool editing;
  const SetupScreen({super.key, this.editing = false});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  String _avatar = 'a01';
  String _accent = 'neon';
  Boundaries _b = const Boundaries();
  bool _busy = false;
  bool _uploading = false;
  bool _init = false;

  @override
  void dispose() {
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _seed(Profile p) {
    if (_init) return;
    _init = true;
    _handle.text = p.handle ?? '';
    _avatar = p.avatar;
    _bio.text = p.bio;
    _accent = p.accent;
    _b = p.boundaries;
  }

  /// Picks a photo from the gallery, shrinks it on the device and uploads it. The server re-checks type and size.
  Future<void> _pickPhoto() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 82);
      if (x == null) return;
      final Uint8List bytes = await x.readAsBytes();
      if (bytes.length > 500 * 1024) {
        if (mounted) toast(context, 'That photo is too large. Try a smaller one.');
        return;
      }
      setState(() => _uploading = true);
      final p = await ref.read(apiProvider).uploadAvatar(bytes);
      await ref.read(meProvider.notifier).reload();
      if (mounted) setState(() => _avatar = p.avatar);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (_) {
      if (mounted) toast(context, kIsWeb ? 'Could not open the photo picker in this browser.' : 'Could not open your photos. Check the photo permission in Settings.');
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      // A gallery photo was already saved by the upload; only send the avatar field for built-in avatars.
      final builtIn = !_avatar.startsWith('/v1/avatars/');
      await ref.read(meProvider.notifier).save(handle: _handle.text.trim().toLowerCase(), avatar: builtIn ? _avatar : null, boundaries: _b, bio: _bio.text.trim(), accent: _accent);
      if (mounted && widget.editing) {
        toast(context, 'Saved');
        Navigator.of(context).maybePop();
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).value;
    if (me == null) return const SizedBox.shrink();
    _seed(me.profile);
    final isPhoto = _avatar.startsWith('/v1/avatars/');
    // For 16-17 year olds the server adds a floor of its own. It is shown as locked options so nothing is hidden or a surprise.
    final floor = me.profile.teenFloor;
    final maxLevel = floor?.maxDifficulty ?? 5;
    final level = _b.maxDifficulty.clamp(1, maxLevel);
    return Scaffold(
      appBar: widget.editing ? AppBar(title: const Text('Edit profile')) : null,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          if (!widget.editing) ...[Text('Set up your profile', style: T.large(32)), const SizedBox(height: 6), Text('Pick a handle and a look. You can change both later.', style: T.body(15.5)), const SizedBox(height: 22)],
          Center(child: Avatar(_avatar, size: 104, ring: true)),
          const SizedBox(height: 22),
          const SectionTitle('Handle'),
          TextField(controller: _handle, maxLength: 20, decoration: const InputDecoration(hintText: 'Letters, numbers and _', prefixText: '@ ', counterText: '')),
          const SizedBox(height: 18),
          const SectionTitle('Avatar'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _photoTile(isPhoto),
            for (final a in avatarKeys)
              Pressable(
                onTap: () => setState(() => _avatar = a),
                scale: 0.94,
                child: AnimatedContainer(
                  duration: Motion.standard,
                  curve: Motion.premium,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _avatar == a ? Colors.white : Colors.transparent, width: 2)),
                  child: Avatar(a, size: 58),
                ),
              ),
          ]),
          const SizedBox(height: 22),
          const SectionTitle('Bio'),
          TextField(controller: _bio, maxLength: 120, maxLines: 2, minLines: 1, decoration: const InputDecoration(hintText: 'A line about you (no links or @handles)')),
          const SizedBox(height: 14),
          const SectionTitle('Profile colour'),
          Wrap(spacing: 12, children: [
            for (final k in accentKeys)
              Pressable(
                semanticLabel: '$k colour',
                onTap: () => setState(() => _accent = k),
                scale: 0.9,
                child: AnimatedContainer(
                  duration: Motion.standard,
                  curve: Motion.premium,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _accent == k ? Colors.white : Colors.transparent, width: 2)),
                  child: Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accentOf(k).hi, accentOf(k).main]))),
                ),
              ),
          ]),
          const SizedBox(height: 26),
          const SectionTitle('Boundaries'),
          Text('You will never be offered a dare that crosses these. You can also pass any dare, and the safety stop is always there.', style: T.body(13.5)),
          if (floor != null) ...[
            const SizedBox(height: 12),
            Surface(
              color: C.a(C.primary, 0.10),
              radius: R.md,
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: C.primaryHi),
                const SizedBox(width: 10),
                Expanded(child: Text('Teen account: some options are always on to keep dares comfortable. You can add more, but not remove these.', style: T.body(13))),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Text('Categories I do not want', style: T.strong(13.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in categories)
              _toggle(prettyKey(c), _b.excludedCategories.contains(c) || (floor?.excludedCategories.contains(c) ?? false), () => setState(() => _b = _b.copyWith(excludedCategories: _flip(_b.excludedCategories, c))), locked: floor?.excludedCategories.contains(c) ?? false),
          ]),
          const SizedBox(height: 16),
          Text('Themes I do not want', style: T.strong(13.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in themes)
              _toggle(prettyKey(t), _b.excludedThemes.contains(t) || (floor?.excludedThemes.contains(t) ?? false), () => setState(() => _b = _b.copyWith(excludedThemes: _flip(_b.excludedThemes, t))), locked: floor?.excludedThemes.contains(t) ?? false),
          ]),
          const SizedBox(height: 16),
          Text(maxLevel < 5 ? 'Highest difficulty: $level of 5 (teen accounts stop at $maxLevel)' : 'Highest difficulty: $level of 5', style: T.strong(13.5)),
          Slider(value: level.toDouble(), min: 1, max: maxLevel.toDouble(), divisions: maxLevel > 1 ? maxLevel - 1 : null, onChanged: (v) => setState(() => _b = _b.copyWith(maxDifficulty: v.round()))),
          const SizedBox(height: 14),
          AppButton(label: widget.editing ? 'Save' : 'Enter DAREWIRE', busy: _busy, onPressed: _save),
        ]),
      ),
    );
  }

  Widget _photoTile(bool isPhoto) => Pressable(
        onTap: _uploading ? null : _pickPhoto,
        scale: 0.94,
        semanticLabel: 'Choose a photo from your gallery',
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(shape: BoxShape.circle, color: C.surfaceHi, border: Border.all(color: isPhoto ? Colors.white : C.hairline, width: isPhoto ? 2 : 1)),
          child: _uploading
              ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2))
              : (isPhoto ? ClipOval(child: Avatar(_avatar, size: 58)) : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.photo_library_rounded, size: 22, color: C.primaryHi), Text('Gallery', style: T.label(10))])),
        ),
      );

  List<String> _flip(List<String> l, String v) => l.contains(v) ? (List.of(l)..remove(v)) : [...l, v];

  /// An option chip. "On" means "I do not want this". A [locked] chip is always on (the teen floor) and cannot be tapped.
  Widget _toggle(String label, bool on, VoidCallback tap, {bool locked = false}) => Pressable(
        onTap: locked ? null : tap,
        scale: 0.95,
        child: AnimatedContainer(
          duration: Motion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: ShapeDecoration(color: on ? C.a(C.danger, 0.16) : C.surface, shape: StadiumBorder(side: BorderSide(color: on ? C.a(C.danger, 0.55) : C.hairline))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (on) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(locked ? Icons.lock_outline_rounded : Icons.block, size: 13, color: C.danger)),
            Text(label, style: T.strong(13).copyWith(color: on ? C.a(C.text, 0.92) : C.text)),
          ]),
        ),
      );
}
