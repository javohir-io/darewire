import 'package:flutter_test/flutter_test.dart';
import 'package:darewire/data/models.dart';

void main() {
  teenModelTests();
  socialModelTests();
  test('SessionView parses a server snapshot and never trusts missing fields', () {
    final v = SessionView.fromJson({
      'id': 's1', 'code': 'ABC123', 'title': 'T', 'phase': 'CHALLENGE_VOTE', 'rev': 7, 'serverTime': 1000, 'phaseStartedAt': 900,
      'phaseDeadline': 1900, 'roundNumber': 1, 'hostId': 'h', 'watcherCount': 3,
      'you': {'id': 'u', 'role': 'watcher', 'vote': 2},
      'round': {
        'n': 1, 'tally': [0, 1, 2, 0, 0], 'totalVotes': 3,
        'options': List.generate(5, (i) => {'id': 'c$i', 'category': 'create', 'title': 'Dare $i', 'objective': 'Do something', 'durationSeconds': 40, 'difficulty': 2}),
      },
    });
    expect(v.phase, 'CHALLENGE_VOTE');
    expect(v.you!.vote, 2);
    expect(v.isPlayer, false);
    expect(v.round!.options.length, 5);
    expect(v.round!.tally, [0, 1, 2, 0, 0]);
    expect(SessionView.fromJson(const {}).phase, 'LOBBY');
  });

  test('Boundaries round-trip and clamp difficulty', () {
    final b = Boundaries.fromJson({'excludedCategories': ['perform'], 'excludedThemes': ['singing'], 'maxDifficulty': 99});
    expect(b.maxDifficulty, 5);
    expect(b.toJson()['excludedCategories'], ['perform']);
  });

  test('prettyKey', () => expect(prettyKey('social_courage'), 'Social Courage'));

  test('FeedClip parses a feed item and copies like state', () {
    final c = FeedClip.fromJson({
      'id': 'c1', 'title': 'Sock Court', 'caption': 'x', 'category': 'perform', 'videoUrl': 'https://x/y.mp4', 'difficulty': 3, 'likes': 4,
      'liked': false, 'mine': false, 'demo': true, 'author': {'id': 'u', 'handle': 'vera', 'avatar': 'raven'},
    });
    expect(c.authorHandle, 'vera');
    final l = c.withLike(true, 5);
    expect(l.liked, true);
    expect(l.likes, 5);
    expect(FeedClip.fromJson(const {}).authorHandle, '?');
  });

  test('UserProfile parses a public profile and CipherReply parses a reply', () {
    final u = UserProfile.fromJson({
      'profile': {'id': 'u1', 'handle': 'vera', 'avatar': 'raven', 'bio': 'sock lawyer', 'accent': 'gold', 'joinedAt': '2026-01-02T00:00:00.000Z', 'staff': false},
      'isMe': false, 'iBlocked': false,
      'stats': {'rounds': 4, 'completed': 3, 'points': 750, 'bestStreak': 3, 'clips': 1, 'likes': 30},
      'badges': [{'id': 'on_fire', 'label': 'On Fire', 'desc': 'x'}],
      'clips': [], 'recent': [{'round': 1, 'outcome': 'completed', 'title': 'T', 'points': 200}],
    });
    expect(u.handle, 'vera');
    expect(u.stats.rate, 0.75);
    expect(u.badges.single.id, 'on_fire');
    expect(UserProfile.fromJson(const {}).handle, '?');
    final r = CipherReply.fromJson({'messages': ['hi', 'yo'], 'mood': 'happy', 'loyaltyDelta': 2, 'offline': true});
    expect(r.messages.length, 2);
    expect(r.offline, true);
  });
}

void teenModelTests() {
  group('age bands and teen protections', () {
    test('Profile reads the server-derived band and teen floor', () {
      final p = Profile.fromJson({
        'id': 'u1', 'handle': 'tess', 'ageVerifiedAt': '2026-10-01T00:00:00Z', 'band': 'teen', 'birthDate': '2010-05-01',
        'teenFloor': {'excludedCategories': ['social_courage'], 'excludedThemes': ['romance', 'dark_humor'], 'maxDifficulty': 3},
      });
      expect(p.ageVerified, isTrue);
      expect(p.isTeen, isTrue);
      expect(p.teenFloor!.maxDifficulty, 3);
      expect(p.teenFloor!.excludedThemes, contains('romance'));
      expect(p.birthDate, '2010-05-01');
    });

    test('an adult has no teen floor, and an unanswered age gate is not verified', () {
      final a = Profile.fromJson({'id': 'u2', 'ageVerifiedAt': '2026-10-01T00:00:00Z', 'band': 'adult'});
      expect(a.isTeen, isFalse);
      expect(a.teenFloor, isNull);
      final fresh = Profile.fromJson({'id': 'u3'});
      expect(fresh.ageVerified, isFalse);
      expect(fresh.band, '');
    });

    test('Boundaries remembers when the teen floor is applied', () {
      expect(Boundaries.fromJson({'maxDifficulty': 3, 'teen': true}).teen, isTrue);
      expect(Boundaries.fromJson({'maxDifficulty': 3}).teen, isFalse);
      expect(Boundaries.fromJson({'teen': true}).copyWith(maxDifficulty: 2).teen, isTrue);
    });

    test('FeedClip keeps its poster through a like', () {
      final c = FeedClip.fromJson({'id': 'c1', 'title': 'Dino', 'videoUrl': 'http://x/v.mp4', 'poster': 'http://x/v.jpg', 'author': {'id': 'a', 'handle': 'rex'}});
      expect(c.poster, 'http://x/v.jpg');
      expect(c.withLike(true, 5).poster, 'http://x/v.jpg');
      expect(FeedClip.fromJson({'id': 'c2', 'title': 'x'}).poster, isNull);
    });
  });
}

void socialModelTests() {
  group('following, chat and activity models', () {
    test('UserProfile carries the relation; a missing relation means no relationship', () {
      final p = UserProfile.fromJson({
        'profile': {'id': 'u', 'handle': 'ben'},
        'relation': {'followers': 3, 'following': 2, 'isFollowing': true, 'followsYou': false, 'canMessage': true, 'messageMode': 'request'},
      });
      expect(p.relation.followers, 3);
      expect(p.relation.isFollowing, isTrue);
      expect(p.relation.messageMode, 'request');
      final none = UserProfile.fromJson({'profile': {'id': 'u', 'handle': 'x'}});
      expect(none.relation.canMessage, isFalse);
      expect(none.relation.messageMode, 'none');
    });

    test('ChatRow, thread and message parsing never trust missing fields', () {
      final row = ChatRow.fromJson({'id': 'c1', 'person': {'id': 'p', 'handle': 'tess', 'avatar': 'a02'}, 'lastText': 'hi', 'unread': 2, 'incomingRequest': true});
      expect(row.unread, 2);
      expect(row.incomingRequest, isTrue);
      expect(row.person.handle, 'tess');
      final t = ChatThread.fromJson({
        'id': 'c1', 'person': {'id': 'p', 'handle': 'tess'}, 'canSend': false, 'sendBlockedReason': 'Accept this request to reply', 'teen': true,
        'messages': [{'id': 'm1', 'mine': true, 'text': 'yo', 'at': '2026-11-03T10:00:00Z'}],
      });
      expect(t.canSend, isFalse);
      expect(t.teen, isTrue);
      expect(t.messages.length, 1);
      expect(t.messages.first.mine, isTrue);
      expect(ChatThread.fromJson({'id': 'c', 'person': {'id': 'p'}}).canSend, isTrue);   // default: allowed, the server still decides
    });

    test('ActivityItem and Badges', () {
      final a = ActivityItem.fromJson({'id': 'n1', 'kind': 'follow', 'actor': {'id': 'p', 'handle': 'ava'}, 'at': '2026-11-03T10:00:00Z', 'read': false, 'iFollowActor': false});
      expect(a.kind, 'follow');
      expect(a.read, isFalse);
      expect(Badges.fromJson({'activity': 2, 'chats': 1}).chats, 1);
      expect(Badges.fromJson(const {}).activity, 0);
    });
  });
}
