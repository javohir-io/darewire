import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../state/providers.dart';
import '../ui/screens/auth_screens.dart';
import '../ui/screens/cipher_screen.dart';
import '../ui/screens/duels_screen.dart';
import '../ui/screens/home_screens.dart';
import '../ui/screens/mod_screen.dart';
import '../ui/screens/profile_screens.dart';
import '../ui/screens/rewards_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/social_screens.dart';
import '../ui/session/session_screen.dart';

/// Bridges Riverpod state to go_router: the router re-evaluates redirects whenever sign-in or profile state changes.
class _RouterNotifier extends ChangeNotifier {
  final Ref ref;
  _RouterNotifier(this.ref) {
    ref.listen(signedInProvider, (_, __) => notifyListeners());
    ref.listen(meProvider, (_, __) => notifyListeners());
  }

  static const _onboarding = {'/', '/welcome', '/age', '/setup', '/connect-error'};

  String? redirect(BuildContext context, GoRouterState state) {
    final loc = state.matchedLocation;
    final signedIn = ref.read(signedInProvider);
    if (!signedIn) return loc == '/welcome' ? null : '/welcome';
    final me = ref.read(meProvider);
    if (me.isLoading && !me.hasValue) return loc == '/' ? null : '/';
    if (me.hasError && !me.hasValue) return loc == '/connect-error' ? null : '/connect-error';
    final m = me.value;
    if (m == null) return loc == '/' ? null : '/';
    if (m.needsAge) return loc == '/age' ? null : '/age';
    if (m.needsHandle) return loc == '/setup' ? null : '/setup';
    if (_onboarding.contains(loc)) return '/home';
    return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final n = _RouterNotifier(ref);
  ref.onDispose(n.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: n,
    redirect: n.redirect,
    routes: [
      GoRoute(path: '/', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (c, s) => const WelcomeScreen()),
      GoRoute(path: '/connect-error', builder: (c, s) => ConnectErrorScreen(ref.read(meProvider).error ?? 'Could not reach DAREWIRE.')),
      GoRoute(path: '/age', builder: (c, s) => const AgeGateScreen()),
      GoRoute(path: '/setup', builder: (c, s) => const SetupScreen()),
      GoRoute(path: '/home', builder: (c, s) => const HomeShell()),
      GoRoute(path: '/create', builder: (c, s) => const CreateSessionScreen()),
      GoRoute(path: '/mod', builder: (c, s) => const ModScreen()),
      GoRoute(path: '/rewards', builder: (c, s) => const RewardsScreen()),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
      GoRoute(path: '/cipher', builder: (c, s) => const CipherScreen()),
      GoRoute(path: '/duel/new', builder: (c, s) => NewDuelScreen(targetId: s.uri.queryParameters['target'], targetHandle: s.uri.queryParameters['handle'])),
      GoRoute(path: '/u/:id', builder: (c, s) => UserProfileScreen(userId: s.pathParameters['id']!)),
      GoRoute(path: '/u/:id/followers', builder: (c, s) => PeopleListScreen(userId: s.pathParameters['id']!, followers: true)),
      GoRoute(path: '/u/:id/following', builder: (c, s) => PeopleListScreen(userId: s.pathParameters['id']!, followers: false)),
      GoRoute(path: '/inbox', builder: (c, s) => const InboxScreen()),
      GoRoute(path: '/chat/:id', builder: (c, s) => ChatScreen(chatId: s.pathParameters['id']!)),
      GoRoute(path: '/activity', builder: (c, s) => const ActivityScreen()),
      GoRoute(path: '/discover', builder: (c, s) => const DiscoverScreen()),
      GoRoute(path: '/blocked', builder: (c, s) => const BlockedScreen()),
      GoRoute(path: '/safety', builder: (c, s) => const SafetyCentreScreen()),
      GoRoute(
        path: '/session/:id',
        builder: (c, s) => SessionScreen(sessionId: s.pathParameters['id']!, want: s.uri.queryParameters['want'] ?? 'watcher'),
      ),
    ],
  );
});
