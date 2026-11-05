// Models mirror the server's JSON (docs/api.md). Parsing is defensive: a missing field never crashes the UI.

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
String _s(Object? v, [String d = '']) => v is String ? v : d;
bool _b(Object? v, [bool d = false]) => v is bool ? v : d;
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    v is List ? v.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList() : <T>[];
List<String> _strings(Object? v) => v is List ? v.whereType<String>().toList() : <String>[];

const categories = ['improvise', 'create', 'perform', 'solve', 'social_courage'];
const themes = ['singing', 'dancing', 'romance', 'food_props', 'accents', 'public_speaking', 'dark_humor', 'physical_comedy', 'role_play', 'trivia_pressure'];
/// The 12 built-in avatars (assets/avatars/a01.png ... a12.png).
const avatarKeys = ['a01', 'a02', 'a03', 'a04', 'a05', 'a06', 'a07', 'a08', 'a09', 'a10', 'a11', 'a12'];

String prettyKey(String k) => k.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

class Boundaries {
  final List<String> excludedCategories;
  final List<String> excludedThemes;
  final int maxDifficulty;

  /// True when the server has added the teen floor (the player is 16-17, or the session is a teen session).
  final bool teen;
  const Boundaries({this.excludedCategories = const [], this.excludedThemes = const [], this.maxDifficulty = 5, this.teen = false});

  factory Boundaries.fromJson(Object? j) {
    final m = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    return Boundaries(
      excludedCategories: _strings(m['excludedCategories']),
      excludedThemes: _strings(m['excludedThemes']),
      maxDifficulty: _i(m['maxDifficulty'], 5).clamp(1, 5),
      teen: _b(m['teen']),
    );
  }

  Map<String, dynamic> toJson() => {'excludedCategories': excludedCategories, 'excludedThemes': excludedThemes, 'maxDifficulty': maxDifficulty};

  Boundaries copyWith({List<String>? excludedCategories, List<String>? excludedThemes, int? maxDifficulty}) => Boundaries(
        excludedCategories: excludedCategories ?? this.excludedCategories,
        excludedThemes: excludedThemes ?? this.excludedThemes,
        maxDifficulty: maxDifficulty ?? this.maxDifficulty,
        teen: teen,
      );
}

class Profile {
  final String id;
  final String? handle;
  final String avatar;
  /// Passed the age gate (16 or over). The server decides; the app only mirrors it.
  final bool ageVerified;
  final String role;
  final Boundaries boundaries;
  final String bio, accent;

  /// 'teen' (16-17), 'adult' (18+) or '' before the age gate. Derived by the server from the birth date on every request.
  final String band;

  /// The content floor the server adds for teens (null for adults). Shown in Settings and Setup so nothing is a surprise.
  final Boundaries? teenFloor;

  /// The birth date this account gave at the age gate (YYYY-MM-DD), or null. The first answer is final (see the server).
  final String? birthDate;
  const Profile({required this.id, this.handle, this.avatar = 'a01', this.ageVerified = false, this.role = 'user', this.boundaries = const Boundaries(), this.bio = '', this.accent = 'neon', this.band = '', this.teenFloor, this.birthDate});

  bool get isModerator => role == 'moderator' || role == 'admin';
  bool get isTeen => band == 'teen';

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: _s(j['id']),
        handle: j['handle'] as String?,
        avatar: _s(j['avatar'], 'a01'),
        ageVerified: j['ageVerifiedAt'] != null,
        role: _s(j['role'], 'user'),
        boundaries: Boundaries.fromJson(j['boundaries']),
        bio: _s(j['bio']),
        accent: _s(j['accent'], 'neon'),
        band: _s(j['band']),
        teenFloor: j['teenFloor'] is Map ? Boundaries.fromJson(j['teenFloor']) : null,
        birthDate: j['birthDate'] is String ? j['birthDate'] as String : null,
      );
}

class Challenge {
  final String id, category, title, objective, scoringType, origin;
  final int durationSeconds, difficulty;
  final List<String> completionCriteria, allowedModifiers, tags;
  const Challenge({
    required this.id, required this.category, required this.title, required this.objective, required this.durationSeconds,
    required this.difficulty, this.completionCriteria = const [], this.allowedModifiers = const [], this.tags = const [],
    this.scoringType = 'audience_judgment', this.origin = 'fallback',
  });

  factory Challenge.fromJson(Map<String, dynamic> j) => Challenge(
        id: _s(j['id']), category: _s(j['category']), title: _s(j['title']), objective: _s(j['objective']),
        durationSeconds: _i(j['durationSeconds'], 45), difficulty: _i(j['difficulty'], 1),
        completionCriteria: _strings(j['completionCriteria']), allowedModifiers: _strings(j['allowedModifiers']), tags: _strings(j['tags']),
        scoringType: _s(j['scoringType'], 'audience_judgment'), origin: _s(j['origin'], 'fallback'),
      );
}

class Person {
  final String id, handle, avatar, role;
  final int score, streak;
  final bool online;
  const Person({required this.id, required this.handle, required this.avatar, required this.role, this.score = 0, this.streak = 0, this.online = true});

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: _s(j['id']), handle: _s(j['handle'], '?'), avatar: _s(j['avatar'], 'a01'), role: _s(j['role'], 'watcher'),
        score: _i(j['score']), streak: _i(j['streak']), online: _b(j['online'], true),
      );
}

class Modifier {
  final String id, text;
  const Modifier(this.id, this.text);
  factory Modifier.fromJson(Map<String, dynamic> j) => Modifier(_s(j['id']), _s(j['text']));
}

class TwistView {
  final String status;
  final List<Modifier> options;
  final List<int> tally;
  final int opensAt, closesAt;
  final Modifier? applied;
  const TwistView({required this.status, required this.options, required this.tally, required this.opensAt, required this.closesAt, this.applied});

  factory TwistView.fromJson(Map<String, dynamic> j) => TwistView(
        status: _s(j['status']),
        options: _list(j['options'], Modifier.fromJson),
        tally: (j['tally'] is List) ? (j['tally'] as List).map((e) => _i(e)).toList() : <int>[],
        opensAt: _i(j['opensAt']), closesAt: _i(j['closesAt']),
        applied: j['applied'] is Map ? Modifier.fromJson(Map<String, dynamic>.from(j['applied'] as Map)) : null,
      );
}

class RoundResult {
  final int round, playerPoints, streak, yes, no, passes;
  final String playerHandle, outcome;
  final String? challengeTitle, twist;
  final bool judged;
  final Map<String, int> awards;
  const RoundResult({
    required this.round, required this.playerHandle, required this.outcome, this.challengeTitle, this.twist, this.playerPoints = 0,
    this.streak = 0, this.yes = 0, this.no = 0, this.passes = 0, this.judged = false, this.awards = const {},
  });

  factory RoundResult.fromJson(Map<String, dynamic> j) => RoundResult(
        round: _i(j['round']), playerHandle: _s(j['playerHandle']), outcome: _s(j['outcome']), challengeTitle: j['challengeTitle'] as String?,
        twist: j['twist'] as String?, playerPoints: _i(j['playerPoints']), streak: _i(j['streak']), yes: _i(j['yes']), no: _i(j['no']),
        passes: _i(j['passes']), judged: _b(j['judged']),
        awards: j['awards'] is Map ? (j['awards'] as Map).map((k, v) => MapEntry(k.toString(), _i(v))) : <String, int>{},
      );

  bool get isSafety => outcome == 'safety_stop';
}

class RoundView {
  final int n, totalVotes, passes;
  final List<Challenge> options;
  final List<int>? tally;
  final int? chosenIdx, startedAt, deadline;
  final String? chosenBy, note;
  final TwistView? twist;
  final int verdictCast;
  final int? verdictYes, verdictNo;
  final RoundResult? result;
  const RoundView({
    required this.n, this.options = const [], this.tally, this.totalVotes = 0, this.chosenIdx, this.chosenBy, this.passes = 0,
    this.startedAt, this.deadline, this.note, this.twist, this.verdictCast = 0, this.verdictYes, this.verdictNo, this.result,
  });

  Challenge? get chosen => (chosenIdx != null && chosenIdx! >= 0 && chosenIdx! < options.length) ? options[chosenIdx!] : null;

  factory RoundView.fromJson(Map<String, dynamic> j) {
    final v = j['verdict'] is Map ? Map<String, dynamic>.from(j['verdict'] as Map) : <String, dynamic>{};
    return RoundView(
      n: _i(j['n']), options: _list(j['options'], Challenge.fromJson),
      tally: j['tally'] is List ? (j['tally'] as List).map((e) => _i(e)).toList() : null,
      totalVotes: _i(j['totalVotes']), chosenIdx: j['chosenIdx'] as int?, chosenBy: j['chosenBy'] as String?, passes: _i(j['passes']),
      startedAt: j['startedAt'] as int?, deadline: j['deadline'] as int?, note: j['note'] as String?,
      twist: j['twist'] is Map ? TwistView.fromJson(Map<String, dynamic>.from(j['twist'] as Map)) : null,
      verdictCast: _i(v['cast']), verdictYes: v['yes'] as int?, verdictNo: v['no'] as int?,
      result: j['result'] is Map ? RoundResult.fromJson(Map<String, dynamic>.from(j['result'] as Map)) : null,
    );
  }
}

class YouView {
  final String id, role;
  final bool isHost, queued;
  final int? vote, twistVote;
  final bool? verdict;
  const YouView({required this.id, required this.role, this.isHost = false, this.queued = false, this.vote, this.twistVote, this.verdict});

  factory YouView.fromJson(Map<String, dynamic> j) => YouView(
        id: _s(j['id']), role: _s(j['role'], 'watcher'), isHost: _b(j['isHost']), queued: _b(j['queued']),
        vote: j['vote'] as int?, twistVote: j['twistVote'] as int?, verdict: j['verdict'] as bool?,
      );
}

/// The authoritative state of a session as seen by one user. The client never computes tallies, winners or scores.
class SessionView {
  final String id, code, title, phase, hostId;
  final String? endedReason;
  final int rev, serverTime, phaseStartedAt, roundNumber, watcherCount;
  final int? phaseDeadline;
  final bool twistEnabled, streamCut;
  final YouView? you;
  final Person? player;
  final List<Person> roster, queue;
  final Boundaries boundaries;
  final RoundView? round;
  final List<RoundResult> history;

  /// Who the session is for: 'teen' (16-17 only) or 'adult'.
  final String band;

  const SessionView({
    required this.id, required this.code, required this.title, required this.phase, required this.hostId, required this.rev,
    required this.serverTime, required this.phaseStartedAt, required this.roundNumber, required this.watcherCount, this.phaseDeadline,
    this.twistEnabled = true, this.streamCut = false, this.endedReason, this.you, this.player, this.roster = const [], this.queue = const [],
    this.boundaries = const Boundaries(), this.round, this.history = const [], this.band = 'adult',
  });

  bool get isPlayer => you?.role == 'player';
  bool get isObserver => you == null;

  factory SessionView.fromJson(Map<String, dynamic> j) => SessionView(
        id: _s(j['id']), code: _s(j['code']), title: _s(j['title']), phase: _s(j['phase'], 'LOBBY'), hostId: _s(j['hostId']),
        rev: _i(j['rev']), serverTime: _i(j['serverTime']), phaseStartedAt: _i(j['phaseStartedAt']), phaseDeadline: j['phaseDeadline'] as int?,
        roundNumber: _i(j['roundNumber']), watcherCount: _i(j['watcherCount']), twistEnabled: _b(j['twistEnabled'], true),
        streamCut: _b(j['streamCut']), endedReason: j['endedReason'] as String?,
        you: j['you'] is Map ? YouView.fromJson(Map<String, dynamic>.from(j['you'] as Map)) : null,
        player: j['player'] is Map ? Person.fromJson(Map<String, dynamic>.from(j['player'] as Map)) : null,
        roster: _list(j['roster'], Person.fromJson), queue: _list(j['queue'], Person.fromJson),
        boundaries: Boundaries.fromJson(j['boundaries']),
        round: j['round'] is Map ? RoundView.fromJson(Map<String, dynamic>.from(j['round'] as Map)) : null,
        history: _list(j['history'], RoundResult.fromJson),
        band: _s(j['band'], 'adult'),
      );

  bool get isTeenSession => band == 'teen';
}

class SessionSummary {
  final String id, code, title, phase;
  final int watchers, round, playerStreak;
  final String? playerId, playerHandle, playerAvatar, dareTitle;
  final int dareDifficulty;
  final bool twist;
  const SessionSummary({
    required this.id, required this.code, required this.title, required this.phase, required this.watchers, required this.round,
    this.playerId, this.playerHandle, this.playerAvatar, this.playerStreak = 0, this.dareTitle, this.dareDifficulty = 0, this.twist = true,
  });

  /// A player is on stage right now.
  bool get onStage => playerHandle != null;
  bool get inRound => phase == 'LIVE_ROUND';

  factory SessionSummary.fromJson(Map<String, dynamic> j) {
    final p = j['player'] is Map ? Map<String, dynamic>.from(j['player'] as Map) : null;
    final d = j['dare'] is Map ? Map<String, dynamic>.from(j['dare'] as Map) : null;
    return SessionSummary(
      id: _s(j['id']), code: _s(j['code']), title: _s(j['title']), phase: _s(j['phase']), watchers: _i(j['watchers']), round: _i(j['round']),
      playerId: p?['id'] as String?, playerHandle: p?['handle'] as String?, playerAvatar: p?['avatar'] as String?, playerStreak: _i(p?['streak']),
      dareTitle: d?['title'] as String?, dareDifficulty: _i(d?['difficulty']), twist: _b(j['twist'], true),
    );
  }
}

class LeaderRow {
  final String userId, handle, avatar;
  final int points, completed;
  const LeaderRow({required this.userId, required this.handle, required this.avatar, required this.points, required this.completed});
  factory LeaderRow.fromJson(Map<String, dynamic> j) =>
      LeaderRow(userId: _s(j['userId']), handle: _s(j['handle']), avatar: _s(j['avatar'], 'a01'), points: _i(j['points']), completed: _i(j['completed']));
}

class ChatMessage {
  final String id, userId, handle, text;
  const ChatMessage({required this.id, required this.userId, required this.handle, required this.text});
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(id: _s(j['id']), userId: _s(j['userId']), handle: _s(j['handle']), text: _s(j['text']));
}

class ReportItem {
  final String id, kind, note;
  final String? targetUserId, sessionId;
  const ReportItem({required this.id, required this.kind, required this.note, this.targetUserId, this.sessionId});
  factory ReportItem.fromJson(Map<String, dynamic> j) =>
      ReportItem(id: _s(j['id']), kind: _s(j['kind']), note: _s(j['note']), targetUserId: j['targetUserId'] as String?, sessionId: j['sessionId'] as String?);
}

class ModSession {
  final String id, code, title, phase;
  final int clients;
  const ModSession({required this.id, required this.code, required this.title, required this.phase, required this.clients});
  factory ModSession.fromJson(Map<String, dynamic> j) => ModSession(id: _s(j['id']), code: _s(j['code']), title: _s(j['title']), phase: _s(j['phase']), clients: _i(j['clients']));
}

/// A server push other than the state snapshot ("vote:locked", "safety:stop", ...), used to trigger animations and haptics.
class ServerEvent {
  final String type;
  final Map<String, dynamic> data;
  const ServerEvent(this.type, this.data);
}

/// A published clip in the Feed.
class FeedClip {
  final String id, title, caption, category;
  final String? videoUrl, twist, poster;
  final int difficulty, durationMs, likes, views;
  final bool liked, mine, demo;
  final String authorId, authorHandle, authorAvatar;
  const FeedClip({
    required this.id, required this.title, required this.caption, required this.category, this.videoUrl, this.twist, this.poster,
    this.difficulty = 1, this.durationMs = 0, this.likes = 0, this.views = 0, this.liked = false, this.mine = false, this.demo = false,
    required this.authorId, required this.authorHandle, required this.authorAvatar,
  });

  factory FeedClip.fromJson(Map<String, dynamic> j) {
    final a = j['author'] is Map ? Map<String, dynamic>.from(j['author'] as Map) : <String, dynamic>{};
    return FeedClip(
      id: _s(j['id']), title: _s(j['title']), caption: _s(j['caption']), category: _s(j['category']), videoUrl: j['videoUrl'] as String?, poster: j['poster'] as String?,
      twist: j['twist'] as String?, difficulty: _i(j['difficulty'], 1), durationMs: _i(j['durationMs']), likes: _i(j['likes']), views: _i(j['views']),
      liked: _b(j['liked']), mine: _b(j['mine']), demo: _b(j['demo']),
      authorId: _s(a['id']), authorHandle: _s(a['handle'], '?'), authorAvatar: _s(a['avatar'], 'a01'),
    );
  }

  FeedClip withLike(bool liked, int likes) => FeedClip(
        id: id, title: title, caption: caption, category: category, videoUrl: videoUrl, poster: poster, twist: twist, difficulty: difficulty, durationMs: durationMs,
        likes: likes, views: views, liked: liked, mine: mine, demo: demo, authorId: authorId, authorHandle: authorHandle, authorAvatar: authorAvatar,
      );
}

class HiddenClip {
  final String id, title, author;
  const HiddenClip(this.id, this.title, this.author);
  factory HiddenClip.fromJson(Map<String, dynamic> j) => HiddenClip(_s(j['id']), _s(j['title']), _s(j['author']));
}

class UserStats {
  final int rounds, completed, points, bestStreak, clips, likes, duels;
  const UserStats({this.rounds = 0, this.completed = 0, this.points = 0, this.bestStreak = 0, this.clips = 0, this.likes = 0, this.duels = 0});
  factory UserStats.fromJson(Object? j) {
    final m = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    return UserStats(rounds: _i(m['rounds']), completed: _i(m['completed']), points: _i(m['points']), bestStreak: _i(m['bestStreak']), clips: _i(m['clips']), likes: _i(m['likes']), duels: _i(m['duels']));
  }
  double get rate => rounds == 0 ? 0 : completed / rounds;
}

class BadgeItem {
  final String id, label, desc;
  const BadgeItem(this.id, this.label, this.desc);
  factory BadgeItem.fromJson(Map<String, dynamic> j) => BadgeItem(_s(j['id']), _s(j['label']), _s(j['desc']));
}

class RecentRound {
  final int round, points;
  final String? title;
  final String outcome;
  const RecentRound({required this.round, required this.outcome, this.title, this.points = 0});
  factory RecentRound.fromJson(Map<String, dynamic> j) => RecentRound(round: _i(j['round']), outcome: _s(j['outcome']), title: j['title'] as String?, points: _i(j['points']));
}

/// Another user's public profile: what the server chooses to show. Boundaries, birth date and anything private never appear here.
class UserProfile {
  final String id, handle, avatar, bio, accent, joinedAt;
  final bool staff, isMe, iBlocked;
  final UserStats stats;
  final List<BadgeItem> badges;
  final List<FeedClip> clips;
  final List<RecentRound> recent;
  final Relation relation;
  const UserProfile({
    required this.id, required this.handle, required this.avatar, required this.bio, required this.accent, required this.joinedAt, this.staff = false,
    this.isMe = false, this.iBlocked = false, this.stats = const UserStats(), this.badges = const [], this.clips = const [], this.recent = const [], this.relation = const Relation(),
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    final p = j['profile'] is Map ? Map<String, dynamic>.from(j['profile'] as Map) : <String, dynamic>{};
    return UserProfile(
      id: _s(p['id']), handle: _s(p['handle'], '?'), avatar: _s(p['avatar'], 'a01'), bio: _s(p['bio']), accent: _s(p['accent'], 'neon'),
      joinedAt: _s(p['joinedAt']), staff: _b(p['staff']), isMe: _b(j['isMe']), iBlocked: _b(j['iBlocked']), stats: UserStats.fromJson(j['stats']),
      badges: _list(j['badges'], BadgeItem.fromJson), clips: _list(j['clips'], FeedClip.fromJson), recent: _list(j['recent'], RecentRound.fromJson),
      relation: Relation.fromJson(j['relation']),
    );
  }
}

class CipherReply {
  final List<String> messages;
  final String? mood;
  final int loyaltyDelta;
  final bool crisis, offline;
  const CipherReply({required this.messages, this.mood, this.loyaltyDelta = 0, this.crisis = false, this.offline = false});
  factory CipherReply.fromJson(Map<String, dynamic> j) => CipherReply(
        messages: _strings(j['messages']), mood: j['mood'] as String?, loyaltyDelta: _i(j['loyaltyDelta']), crisis: _b(j['crisis']), offline: _b(j['offline']),
      );
}

// ---- duels, wallet, quests ------------------------------------------------------------------------------------------

class Duel {
  final String id, role, status, title, objective, category, note;
  final String otherId, otherHandle, otherAvatar;
  final int difficulty, durationSeconds, reward, rewarded;
  final List<String> criteria;
  final String? proofClipId;
  final DateTime? expiresAt;
  const Duel({
    required this.id, required this.role, required this.status, required this.title, required this.objective, required this.category,
    required this.otherId, required this.otherHandle, required this.otherAvatar, this.note = '', this.difficulty = 1, this.durationSeconds = 45,
    this.reward = 0, this.rewarded = 0, this.criteria = const [], this.proofClipId, this.expiresAt,
  });

  bool get iChallenged => role == 'challenger';
  bool get isOpen => status == 'pending' || status == 'accepted' || status == 'submitted';

  /// True when the next move belongs to me.
  bool get myMove => (status == 'pending' && !iChallenged) || (status == 'accepted' && !iChallenged) || (status == 'submitted' && iChallenged);

  factory Duel.fromJson(Map<String, dynamic> j) {
    final o = j['other'] is Map ? Map<String, dynamic>.from(j['other'] as Map) : <String, dynamic>{};
    return Duel(
      id: _s(j['id']), role: _s(j['role']), status: _s(j['status']), title: _s(j['title']), objective: _s(j['objective']), category: _s(j['category']),
      note: _s(j['note']), otherId: _s(o['id']), otherHandle: _s(o['handle'], '?'), otherAvatar: _s(o['avatar'], 'a01'),
      difficulty: _i(j['difficulty'], 1), durationSeconds: _i(j['durationSeconds'], 45), reward: _i(j['reward']), rewarded: _i(j['rewarded']),
      criteria: _strings(j['criteria']), proofClipId: j['proofClipId'] as String?, expiresAt: DateTime.tryParse(_s(j['expiresAt'])),
    );
  }
}

class DuelIdea {
  final int index, difficulty, durationSeconds;
  final String title, objective, category;
  const DuelIdea({required this.index, required this.title, required this.objective, required this.category, required this.difficulty, required this.durationSeconds});
  factory DuelIdea.fromJson(Map<String, dynamic> j) =>
      DuelIdea(index: _i(j['index']), title: _s(j['title']), objective: _s(j['objective']), category: _s(j['category']), difficulty: _i(j['difficulty'], 1), durationSeconds: _i(j['durationSeconds'], 45));
}

class UserHit {
  final String id, handle, avatar;
  const UserHit(this.id, this.handle, this.avatar);
  factory UserHit.fromJson(Map<String, dynamic> j) => UserHit(_s(j['id']), _s(j['handle']), _s(j['avatar'], 'a01'));
}

class QuestItem {
  final String id, title, desc;
  final int goal, reward, progress;
  final bool claimed;
  const QuestItem({required this.id, required this.title, required this.desc, required this.goal, required this.reward, required this.progress, required this.claimed});
  bool get done => progress >= goal;
  factory QuestItem.fromJson(Map<String, dynamic> j) => QuestItem(
        id: _s(j['id']), title: _s(j['title']), desc: _s(j['desc']), goal: _i(j['goal'], 1), reward: _i(j['reward']), progress: _i(j['progress']), claimed: _b(j['claimed']),
      );
}

class WeekDay {
  final String label;
  final bool active, today, future;
  const WeekDay(this.label, this.active, this.today, this.future);
}

class QuestsState {
  final int streak;
  final List<WeekDay> week;
  final List<QuestItem> quests;
  const QuestsState({this.streak = 0, this.week = const [], this.quests = const []});
  int get claimable => quests.where((q) => q.done && !q.claimed).length;
  factory QuestsState.fromJson(Map<String, dynamic> j) => QuestsState(
        streak: _i(j['streak']),
        week: j['week'] is List
            ? (j['week'] as List).whereType<Map>().map((e) => WeekDay(_s(e['label']), _b(e['active']), _b(e['today']), _b(e['future']))).toList()
            : const [],
        quests: _list(j['quests'], QuestItem.fromJson),
      );
}

class WalletEntry {
  final String id, kind, note;
  final int amount;
  final DateTime at;
  const WalletEntry(this.id, this.kind, this.note, this.amount, this.at);
}

class WalletState {
  final int balance, completed;
  final List<WalletEntry> activity;
  final bool cashOutAvailable;
  final String cashOutNote;
  const WalletState({this.balance = 0, this.completed = 0, this.activity = const [], this.cashOutAvailable = false, this.cashOutNote = ''});
  factory WalletState.fromJson(Map<String, dynamic> j) {
    final co = j['cashOut'] is Map ? Map<String, dynamic>.from(j['cashOut'] as Map) : <String, dynamic>{};
    return WalletState(
      balance: _i(j['balance']), completed: _i(j['completed']),
      activity: j['activity'] is List
          ? (j['activity'] as List).whereType<Map>().map((e) => WalletEntry(_s(e['id']), _s(e['kind']), _s(e['note']), _i(e['amount']), DateTime.fromMillisecondsSinceEpoch(_i(e['at'])))).toList()
          : const [],
      cashOutAvailable: _b(co['available']), cashOutNote: _s(co['note']),
    );
  }
}


// ---- following, chat, activity ----

/// How the viewer and another person relate: counts, who follows whom, and whether (and how) they may message.
class Relation {
  final int followers, following;
  final bool isFollowing, followsYou, canMessage;

  /// 'chat' (mutual followers), 'request' (adults only: one message the other person must accept) or 'none'.
  final String messageMode;
  const Relation({this.followers = 0, this.following = 0, this.isFollowing = false, this.followsYou = false, this.canMessage = false, this.messageMode = 'none'});
  factory Relation.fromJson(Object? v) {
    final j = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    return Relation(followers: _i(j['followers']), following: _i(j['following']), isFollowing: _b(j['isFollowing']), followsYou: _b(j['followsYou']), canMessage: _b(j['canMessage']), messageMode: _s(j['messageMode'], 'none'));
  }
}

/// A person in a list (followers, suggestions, blocked).
class PersonRow {
  final String id, handle, avatar;
  final bool iFollow, followsYou;
  const PersonRow({required this.id, required this.handle, required this.avatar, this.iFollow = false, this.followsYou = false});
  factory PersonRow.fromJson(Map<String, dynamic> j) => PersonRow(id: _s(j['id']), handle: _s(j['handle'], '?'), avatar: _s(j['avatar'], 'a01'), iFollow: _b(j['iFollow']), followsYou: _b(j['followsYou']));
}

class ChatRow {
  final String id, lastText, status, lastAt;
  final PersonRow person;
  final bool lastMine, incomingRequest, outgoingRequest;
  final int unread;
  const ChatRow({required this.id, required this.person, this.lastText = '', this.status = 'active', this.lastAt = '', this.lastMine = false, this.incomingRequest = false, this.outgoingRequest = false, this.unread = 0});
  factory ChatRow.fromJson(Map<String, dynamic> j) => ChatRow(
        id: _s(j['id']), person: PersonRow.fromJson(Map<String, dynamic>.from(j['person'] as Map)), lastText: _s(j['lastText']), status: _s(j['status'], 'active'), lastAt: _s(j['lastAt']),
        lastMine: _b(j['lastMine']), incomingRequest: _b(j['incomingRequest']), outgoingRequest: _b(j['outgoingRequest']), unread: _i(j['unread']),
      );
}

class DirectMessage {
  final String id, text;
  final bool mine;
  final DateTime at;
  const DirectMessage({required this.id, required this.text, required this.mine, required this.at});
  factory DirectMessage.fromJson(Map<String, dynamic> j) => DirectMessage(id: _s(j['id']), text: _s(j['text']), mine: _b(j['mine']), at: DateTime.tryParse(_s(j['at']))?.toLocal() ?? DateTime.now());
}

class ChatThread {
  final String id, status;
  final PersonRow person;
  final bool incomingRequest, canSend, teen;
  final String? sendBlockedReason;
  final List<DirectMessage> messages;
  const ChatThread({required this.id, required this.person, this.status = 'active', this.incomingRequest = false, this.canSend = true, this.sendBlockedReason, this.teen = false, this.messages = const []});
  factory ChatThread.fromJson(Map<String, dynamic> j) => ChatThread(
        id: _s(j['id']), person: PersonRow.fromJson(Map<String, dynamic>.from(j['person'] as Map)), status: _s(j['status'], 'active'), incomingRequest: _b(j['incomingRequest']),
        canSend: _b(j['canSend'], true), sendBlockedReason: j['sendBlockedReason'] as String?, teen: _b(j['teen']), messages: _list(j['messages'], DirectMessage.fromJson),
      );
}

class ActivityItem {
  final String id, kind;
  final PersonRow actor;
  final String? ref;
  final DateTime at;
  final bool read, iFollowActor;
  const ActivityItem({required this.id, required this.kind, required this.actor, this.ref, required this.at, this.read = true, this.iFollowActor = false});
  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
        id: _s(j['id']), kind: _s(j['kind']), actor: PersonRow.fromJson(Map<String, dynamic>.from(j['actor'] as Map)), ref: j['ref'] as String?, at: DateTime.tryParse(_s(j['at']))?.toLocal() ?? DateTime.now(),
        read: _b(j['read'], true), iFollowActor: _b(j['iFollowActor']),
      );
}

class Badges {
  final int activity, chats;
  const Badges({this.activity = 0, this.chats = 0});
  factory Badges.fromJson(Map<String, dynamic> j) => Badges(activity: _i(j['activity']), chats: _i(j['chats']));
}
