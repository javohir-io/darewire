import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import 'kit.dart';

String _key(String userId) => 'teen_intro_v1:$userId';

/// Has this person already seen the teen explainer on this device?
Future<bool> teenIntroSeen(String userId) async => (await SharedPreferences.getInstance()).getBool(_key(userId)) ?? false;

/// The plain-language "what protects you" sheet for 16-17 year olds. Shown once after sign-up, and available again from Settings.
/// Every line describes something the SERVER enforces (see docs/threat-model.md); nothing here is only a promise made by the app.
Future<void> showTeenIntro(BuildContext context, {required String userId}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_key(userId), true);
  if (!context.mounted) return;
  await showGlassSheet<void>(
    context,
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your teen account', style: T.large(26)),
        const SizedBox(height: 6),
        Text('You are 16 or 17, so a few extra protections are on. You do not have to switch anything on.', style: T.body(14.5)),
        const SizedBox(height: 18),
        const _Point(Icons.groups_rounded, 'Teen-only rooms', 'You play and watch with other people aged 16 to 17. Adults cannot find, follow, join or message you.'),
        const _Point(Icons.chat_bubble_outline_rounded, 'Chat with friends only', 'You can message people you both follow. Links, phone numbers and meet-up talk are blocked in chats.'),
        const _Point(Icons.tune_rounded, 'Dares kept comfortable', 'Dares stop at level 3 and skip romance, dark humor and anything that means approaching strangers.'),
        const _Point(Icons.shield_outlined, 'You are in control', 'Pass any dare, hit Safety stop, block or report anyone, at any time. No penalty, ever.'),
        const _Point(Icons.do_not_disturb_on_outlined, 'No meet-ups, no money', 'DAREWIRE never asks you to go anywhere, meet anyone or pay for anything. If someone does, report it and tell an adult you trust.'),
        const SizedBox(height: 14),
        AppButton(label: 'Got it', onPressed: () => Navigator.of(c).pop()),
      ]),
    ),
  );
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String title, text;
  const _Point(this.icon, this.title, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(icon, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.strong(15.5)),
              const SizedBox(height: 2),
              Text(text, style: T.body(13.5)),
            ]),
          ),
        ]),
      );
}
