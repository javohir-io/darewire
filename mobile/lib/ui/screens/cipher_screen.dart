import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../gfx/cipher_face.dart';
import '../../gfx/glass.dart';
import '../../state/cipher_controller.dart';
import '../widgets/kit.dart';

const _quick = ['Give me a dare idea', 'Hype me up', 'I am nervous', 'How does the twist work?', 'Tell me a joke'];

/// Full-screen chat with Cipher. His face reacts to what you say, and he responds when you touch him.
class CipherScreen extends ConsumerStatefulWidget {
  const CipherScreen({super.key});
  @override
  ConsumerState<CipherScreen> createState() => _CipherScreenState();
}

class _CipherScreenState extends ConsumerState<CipherScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.standard, curve: Motion.premium);
      });

  void _send([String? text]) {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty) return;
    _input.clear();
    HapticFeedback.selectionClick();
    ref.read(cipherProvider.notifier).send(t);
    _toBottom();
  }

  void _settings() {
    final c = ref.read(cipherProvider.notifier);
    showGlassSheet<void>(
      context,
      builder: (_) => Consumer(builder: (context, ref, _) {
        final s = ref.watch(cipherProvider);
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Cipher settings', style: T.large(24)),
            const SizedBox(height: 14),
            Text('How Cipher talks', style: T.strong(14)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final t in const ['Blunt', 'Gentle', 'Playful'])
                ChoiceChip(
                  label: Text(t),
                  selected: s.tone == t,
                  onSelected: (_) => c.setTone(t),
                  selectedColor: C.a(C.primary, 0.40),
                  backgroundColor: C.surface,
                  showCheckmark: false,
                  shape: const StadiumBorder(),
                  labelStyle: T.strong(13),
                  side: BorderSide(color: s.tone == t ? C.primaryHi : C.hairline),
                ),
            ]),
            const SizedBox(height: 16),
            Text('Cipher remembers your chat on this phone only. Each message goes through DAREWIRE\'s server to Google Gemini with a short slice of the recent conversation; the server does not store it. Cipher is an AI and can be wrong. For anything serious, talk to a person.', style: T.body(12.5)),
            const SizedBox(height: 16),
            AppButton(
              label: 'Clear Cipher\'s memory',
              kind: BtnKind.danger,
              onPressed: () async {
                await c.wipe();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(cipherProvider);
    ref.listen<CipherState>(cipherProvider, (a, b) {
      if (a?.msgs.length != b.msgs.length || a?.typing != b.typing) _toBottom();
    });
    final kb = MediaQuery.viewInsetsOf(context).bottom > 0;
    final faceSize = kb ? 104.0 : 188.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cipher'),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 4), child: Tag('Trust ${s.loyalty}', color: s.loyalty >= 70 ? C.ok : (s.loyalty >= 40 ? C.warn : C.danger), icon: Icons.favorite_rounded)),
          IconButton(onPressed: _settings, icon: const Icon(Icons.tune_rounded), tooltip: 'Cipher settings'),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          AnimatedContainer(
            duration: Motion.standard,
            curve: Motion.premium,
            height: faceSize + 26,
            child: Stack(alignment: Alignment.center, children: [
              CipherFace(size: faceSize, mood: s.mood, talking: s.typing, onTap: ref.read(cipherProvider.notifier).touch),
              Positioned(bottom: 0, child: _status(s)),
            ]),
          ),
          if (s.offline)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
              child: Text('Offline mode: the server has no Gemini key, so Cipher is using simple saved replies.', textAlign: TextAlign.center, style: T.label(11.5).copyWith(color: C.warn)),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: s.msgs.length + (s.typing ? 1 : 0),
              itemBuilder: (c, i) {
                if (i == s.msgs.length) return const _TypingBubble();
                final m = s.msgs[i];
                final first = i == 0 || s.msgs[i - 1].mine != m.mine;
                return _Bubble(m, first: first).animate().fadeIn(duration: 220.ms).slideY(begin: 0.10, end: 0, duration: 280.ms, curve: Motion.enter);
              },
            ),
          ),
          if (!kb && s.msgs.length < 8 && !s.busy)
            SizedBox(
              height: 42,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                for (final q in _quick)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Pressable(
                      onTap: () => _send(q),
                      child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: ShapeDecoration(color: C.surfaceHi, shape: StadiumBorder(side: BorderSide(color: C.hairline))), child: Text(q, style: T.strong(13))),
                    ),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Glass(
              radius: R.pill,
              blur: 24,
              padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: 400,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    onChanged: (_) => ref.read(cipherProvider.notifier).touch(),
                    style: T.strong(15),
                    decoration: const InputDecoration(hintText: 'Message Cipher', counterText: '', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
                  ),
                ),
                Pressable(
                  semanticLabel: 'Send',
                  scale: 0.9,
                  onTap: s.busy ? null : _send,
                  child: AnimatedOpacity(
                    duration: Motion.quick,
                    opacity: s.busy ? 0.4 : 1,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(shape: BoxShape.circle, gradient: C.brand, border: Border.all(color: C.a(Colors.white, 0.2))),
                      child: Icon(Icons.arrow_upward_rounded, color: C.onColor(C.primary), size: 22),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _status(CipherState s) {
    final label = s.typing ? 'Typing' : (s.busy ? 'Thinking' : (moodLabel[s.mood] ?? 'Listening'));
    return Glass(
      radius: R.pill,
      clear: true,
      blur: 14,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: s.busy || s.typing ? C.warn : C.ok)),
        const SizedBox(width: 7),
        Text(label, style: T.label(11.5).copyWith(color: Colors.white)),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final CMsg m;
  final bool first;
  const _Bubble(this.m, {required this.first});

  @override
  Widget build(BuildContext context) {
    final max = MediaQuery.sizeOf(context).width * 0.76;
    final mine = m.mine;
    return Padding(
      padding: EdgeInsets.only(top: first ? 10 : 3),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max),
          child: mine
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  decoration: BoxDecoration(gradient: C.brand, borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6))),
                  child: Text(m.text, style: T.strong(15).copyWith(color: C.onColor(C.primary))),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  decoration: BoxDecoration(color: C.surfaceHi, borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(6), bottomRight: Radius.circular(20))),
                  child: Text(m.text, style: T.strong(15).copyWith(fontWeight: FontWeight.w500)),
                ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: C.surfaceHi, borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(6), bottomRight: Radius.circular(20))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Container(width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 2.5), decoration: BoxDecoration(shape: BoxShape.circle, color: C.dim))
                    .animate(onPlay: (c) => c.repeat(reverse: true), delay: (i * 160).ms)
                    .moveY(begin: 0, end: -5, duration: 380.ms)
                    .fade(begin: 0.4, end: 1, duration: 380.ms),
            ]),
          ),
        ),
      );
}
