import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api.dart';
import '../data/auth.dart';
import '../data/models.dart';

/// Overridden in main() with the real service (Supabase or the development login).
final authServiceProvider = Provider<AuthService>((ref) => throw UnimplementedError('authServiceProvider must be overridden'));

final apiProvider = Provider<ApiClient>((ref) => ApiClient(() => ref.read(authServiceProvider).accessToken()));

/// Whether someone is signed in. Follows the auth service.
class SignedInNotifier extends Notifier<bool> {
  @override
  bool build() {
    final svc = ref.watch(authServiceProvider);
    final sub = svc.changes.listen((v) => state = v);
    ref.onDispose(sub.cancel);
    return svc.signedIn;
  }
}

final signedInProvider = NotifierProvider<SignedInNotifier, bool>(SignedInNotifier.new);

class MeState {
  final Profile profile;
  final bool needsAge, needsHandle;
  const MeState(this.profile, this.needsAge, this.needsHandle);
}

/// The signed-in user's profile and onboarding status (age gate, handle).
class MeNotifier extends AsyncNotifier<MeState?> {
  @override
  Future<MeState?> build() async {
    final signedIn = ref.watch(signedInProvider);
    if (!signedIn) return null;
    return _load();
  }

  Future<MeState> _load() async {
    final r = await ref.read(apiProvider).me();
    return MeState(r.profile, r.needsAge, r.needsHandle);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  /// Silent refresh that keeps the current screen (no loading flash).
  Future<void> reload() async {
    state = await AsyncValue.guard(_load);
  }

  Future<void> confirmAge(String birthDate) async {
    await ref.read(apiProvider).confirmAge(birthDate);
    await reload();
  }

  Future<void> save({String? handle, String? avatar, Boundaries? boundaries, String? bio, String? accent}) async {
    await ref.read(apiProvider).updateMe(handle: handle, avatar: avatar, boundaries: boundaries, bio: bio, accent: accent);
    await reload();
  }
}

final meProvider = AsyncNotifierProvider<MeNotifier, MeState?>(MeNotifier.new);

final sessionsProvider = FutureProvider.autoDispose<List<SessionSummary>>((ref) async {
  // Poll while a screen shows live sessions; autoDispose stops it when nobody is watching.
  final timer = Timer(const Duration(seconds: 8), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.read(apiProvider).sessions();
});

final userProfileProvider = FutureProvider.autoDispose.family<UserProfile, String>((ref, id) => ref.read(apiProvider).userProfile(id));
final leaderboardProvider = FutureProvider.autoDispose<List<LeaderRow>>((ref) => ref.read(apiProvider).leaderboard());
final historyProvider = FutureProvider.autoDispose<List<RoundResult>>((ref) => ref.read(apiProvider).history());

class FeedState {
  final List<FeedClip> items;
  final int? nextPage;
  final bool loading;
  final String sort; // hot = "For You", new = "Newest", following = people you follow
  final String? error;
  const FeedState({this.items = const [], this.nextPage = 0, this.loading = false, this.sort = 'hot', this.error});

  FeedState copyWith({List<FeedClip>? items, Object? nextPage = _keep, bool? loading, String? sort, String? error}) => FeedState(
        items: items ?? this.items,
        nextPage: identical(nextPage, _keep) ? this.nextPage : nextPage as int?,
        loading: loading ?? this.loading,
        sort: sort ?? this.sort,
        error: error,
      );
}

const Object _keep = Object();

/// The video feed. "For You" ranks by engagement and freshness and puts clips you have not seen first; "New" is chronological.
class FeedController extends Notifier<FeedState> {
  @override
  FeedState build() {
    Future.microtask(() => load(reset: true));
    return const FeedState(loading: true);
  }

  Future<void> load({bool reset = false, String? sort}) async {
    final s = sort ?? state.sort;
    if (state.loading && !reset) return;
    if (reset) state = FeedState(loading: true, sort: s);
    final page = reset ? 0 : state.nextPage;
    if (page == null) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final r = await ref.read(apiProvider).feed(sort: s, page: page);
      final seen = state.items.map((e) => e.id).toSet();
      state = state.copyWith(items: [...state.items, ...r.items.where((e) => !seen.contains(e.id))], nextPage: r.nextPage, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e is ApiException ? e.message : 'Could not load the feed');
    }
  }

  Future<void> loadMore() => load();

  Future<void> setSort(String sort) => state.sort == sort ? Future.value() : load(reset: true, sort: sort);

  /// Mirrors a like made on a clip page into the list (the page talks to the API itself, so it also works for clips opened from a profile).
  void applyLike(String id, bool on, int likes) {
    final i = state.items.indexWhere((c) => c.id == id);
    if (i >= 0) _replace(i, state.items[i].withLike(on, likes));
  }

  void _replace(int i, FeedClip c) {
    final next = [...state.items];
    next[i] = c;
    state = state.copyWith(items: next);
  }

  void remove(String id) => state = state.copyWith(items: state.items.where((c) => c.id != id).toList());
}

final feedProvider = NotifierProvider<FeedController, FeedState>(FeedController.new);

/// Which bottom tab is showing (0 Home, 1 Feed, 2 Duels, 3 Profile) and which Feed page (0 Live, 1 Dares). Lets any screen jump to them.
final shellTabProvider = StateProvider<int>((ref) => 0);
final feedPageProvider = StateProvider<int>((ref) => 1);

/// My duels. Refreshes every 20 seconds while the app is open, so a challenge appears without pulling to refresh.
final duelsProvider = FutureProvider<List<Duel>>((ref) async {
  final timer = Timer(const Duration(seconds: 20), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final me = ref.watch(meProvider).valueOrNull;
  if (!ref.watch(signedInProvider) || me == null || me.needsAge || me.needsHandle) return <Duel>[]; // nothing to load until sign-up is finished
  return ref.read(apiProvider).duels();
});

/// Duels waiting on me (to answer, to do, or to judge): the badge on the Duels tab.
final duelBadgeProvider = Provider<int>((ref) => ref.watch(duelsProvider).maybeWhen(data: (l) => l.where((d) => d.myMove).length, orElse: () => 0));

final walletProvider = FutureProvider.autoDispose<WalletState>((ref) => ref.read(apiProvider).wallet());
final questsProvider = FutureProvider.autoDispose<QuestsState>((ref) => ref.read(apiProvider).quests());
final feedMutedProvider = StateProvider<bool>((ref) => kIsWeb); // browsers block autoplay with sound until the user taps

/// Same client as [apiProvider]; a short alias used by feed widgets.
final apiProviderForViews = Provider<ApiClient>((ref) => ref.watch(apiProvider));

/// True for a 16-17 year old account. The server decides this from the birth date; the app only mirrors it (for copy and for hiding
/// things the server would refuse anyway).
final isTeenProvider = Provider<bool>((ref) => ref.watch(meProvider).valueOrNull?.profile.isTeen ?? false);

/// A handful of hot dares for the Home screen. Cheap: one request, no paging.
final trendingProvider = FutureProvider.autoDispose<List<FeedClip>>((ref) async {
  final r = await ref.read(apiProvider).feed(sort: 'hot', page: 0);
  return r.items.take(6).toList();
});

// ---- following, chat, activity ----

/// Numbers for the badges on Home (unread activity, chats with something new). Refreshed every 30 seconds while the app is open.
final badgesProvider = FutureProvider.autoDispose<Badges>((ref) => ref.read(apiProvider).badges());
final chatsProvider = FutureProvider.autoDispose<List<ChatRow>>((ref) => ref.read(apiProvider).chats());
final activityProvider = FutureProvider.autoDispose<List<ActivityItem>>((ref) => ref.read(apiProvider).activity());
final suggestedPeopleProvider = FutureProvider.autoDispose<List<PersonRow>>((ref) => ref.read(apiProvider).suggestedPeople());
final blockedPeopleProvider = FutureProvider.autoDispose<List<PersonRow>>((ref) => ref.read(apiProvider).blockedPeople());
final followersProvider = FutureProvider.autoDispose.family<List<PersonRow>, String>((ref, id) => ref.read(apiProvider).followers(id));
final followingProvider = FutureProvider.autoDispose.family<List<PersonRow>, String>((ref, id) => ref.read(apiProvider).following(id));
