import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String code, message;
  ApiException(this.status, this.code, this.message);
  @override
  String toString() => message;
}

/// Thin REST client. The bearer token comes from the auth service on every call, so refreshed tokens are always used.
class ApiClient {
  final Future<String?> Function() token;
  final http.Client _http = http.Client();
  ApiClient(this.token);

  Future<dynamic> _call(String method, String path, [Object? body]) async {
    final t = await token();
    final uri = Uri.parse('${Env.apiUrl}$path');
    final headers = {'content-type': 'application/json', if (t != null) 'authorization': 'Bearer $t'};
    final enc = body == null ? null : jsonEncode(body);
    http.Response r;
    try {
      r = await (switch (method) {
        'GET' => _http.get(uri, headers: headers),
        'POST' => _http.post(uri, headers: headers, body: enc),
        'PUT' => _http.put(uri, headers: headers, body: enc),
        _ => _http.delete(uri, headers: headers),
      }).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ApiException(0, 'network', 'Cannot reach the DAREWIRE server. Check your connection.');
    }
    final dynamic json = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 400) {
      final e = (json is Map && json['error'] is Map) ? json['error'] as Map : const {};
      throw ApiException(r.statusCode, (e['code'] ?? 'error').toString(), (e['message'] ?? 'Request failed (${r.statusCode})').toString());
    }
    return json;
  }

  Future<({Profile profile, bool needsAge, bool needsHandle})> me() async {
    final j = await _call('GET', '/v1/me') as Map;
    final needs = (j['needs'] as Map?) ?? const {};
    return (profile: Profile.fromJson(Map<String, dynamic>.from(j['profile'] as Map)), needsAge: needs['age'] == true, needsHandle: needs['handle'] == true);
  }

  Future<Profile> updateMe({String? handle, String? avatar, Boundaries? boundaries, String? bio, String? accent}) async {
    final j = await _call('PUT', '/v1/me', {
      if (handle != null) 'handle': handle,
      if (avatar != null) 'avatar': avatar,
      if (bio != null) 'bio': bio,
      if (accent != null) 'accent': accent,
      if (boundaries != null) 'boundaries': boundaries.toJson(),
    }) as Map;
    return Profile.fromJson(Map<String, dynamic>.from(j['profile'] as Map));
  }

  Future<void> confirmAge(String birthDate) async => _call('POST', '/v1/me/age', {'birthDate': birthDate});
  Future<void> deleteAccount() async => _call('DELETE', '/v1/me');

  /// Uploads a photo from the gallery (already resized on the device). The server checks the real file type and size.
  Future<Profile> uploadAvatar(Uint8List bytes) async {
    final j = await _call('PUT', '/v1/me/avatar', {'data': base64Encode(bytes)}) as Map;
    return Profile.fromJson(Map<String, dynamic>.from(j['profile'] as Map));
  }

  Future<Profile> removeAvatar() async {
    final j = await _call('DELETE', '/v1/me/avatar') as Map;
    return Profile.fromJson(Map<String, dynamic>.from(j['profile'] as Map));
  }

  // wallet, quests, duels
  Future<WalletState> wallet() async => WalletState.fromJson(Map<String, dynamic>.from(await _call('GET', '/v1/me/wallet') as Map));
  Future<QuestsState> quests() async => QuestsState.fromJson(Map<String, dynamic>.from(await _call('GET', '/v1/me/quests') as Map));
  Future<int> claimQuest(String id) async => ((await _call('POST', '/v1/quests/$id/claim') as Map)['amount'] as num).toInt();

  Future<List<UserHit>> searchUsers(String q) async {
    final j = await _call('GET', '/v1/users/search?q=${Uri.encodeQueryComponent(q)}') as Map;
    return (j['users'] as List).map((e) => UserHit.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<Duel>> duels() async {
    final j = await _call('GET', '/v1/duels') as Map;
    return (j['duels'] as List).map((e) => Duel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<DuelIdea>> duelIdeas(String targetId) async {
    final j = await _call('GET', '/v1/duels/ideas?target=${Uri.encodeQueryComponent(targetId)}') as Map;
    return (j['ideas'] as List).map((e) => DuelIdea.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Duel> createDuel({required String targetId, int? libraryIndex, ({String title, String objective, int difficulty})? custom}) async {
    final j = await _call('POST', '/v1/duels', {
      'targetId': targetId,
      if (libraryIndex != null) 'libraryIndex': libraryIndex,
      if (custom != null) 'custom': {'title': custom.title, 'objective': custom.objective, 'difficulty': custom.difficulty},
    }) as Map;
    return Duel.fromJson(Map<String, dynamic>.from(j['duel'] as Map));
  }

  Future<void> duelAction(String id, String action) async => _call('POST', '/v1/duels/$id/$action');
  Future<void> duelSubmit(String id, {String? note, String? clipId}) async => _call('POST', '/v1/duels/$id/submit', {if (note != null) 'note': note, if (clipId != null) 'clipId': clipId});
  Future<({int paid, bool capped})> duelJudge(String id, bool approve) async {
    final j = await _call('POST', '/v1/duels/$id/judge', {'approve': approve}) as Map;
    return (paid: (j['paid'] as num?)?.toInt() ?? 0, capped: j['capped'] == true);
  }

  Future<List<FeedClip>> myClips() async {
    final j = await _call('GET', '/v1/me/clips') as Map;
    return (j['items'] as List).whereType<Map>().where((e) => e['status'] == 'published').map((e) => FeedClip.fromJson(Map<String, dynamic>.from(e))).where((c) => c.videoUrl != null).toList();
  }

  Future<List<SessionSummary>> sessions() async {
    final j = await _call('GET', '/v1/sessions') as Map;
    return (j['sessions'] as List).map((e) => SessionSummary.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<({String id, String code})> createSession({required String title, required bool twist, required bool isPrivate, required bool hostPlays, bool fast = false}) async {
    final j = await _call('POST', '/v1/sessions', {
      'title': title, 'twist': twist, 'visibility': isPrivate ? 'private' : 'public', 'hostPlays': hostPlays, if (fast) 'fast': true,
    }) as Map;
    return (id: j['id'] as String, code: j['code'] as String);
  }

  Future<String> joinByCode(String code) async {
    final j = await _call('POST', '/v1/sessions/join', {'code': code}) as Map;
    return j['sessionId'] as String;
  }

  Future<({String url, String token, bool canPublish})> mediaToken(String sessionId) async {
    final j = await _call('POST', '/v1/sessions/$sessionId/media-token') as Map;
    return (url: j['url'] as String, token: j['token'] as String, canPublish: j['canPublish'] == true);
  }

  Future<List<RoundResult>> history() async {
    final j = await _call('GET', '/v1/me/history') as Map;
    return (j['history'] as List).map((e) => RoundResult.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<LeaderRow>> leaderboard() async {
    final j = await _call('GET', '/v1/leaderboard') as Map;
    return (j['leaderboard'] as List).map((e) => LeaderRow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> report({required String kind, String? note, String? targetUserId, String? sessionId, String? clipId, String? conversationId}) async => _call('POST', '/v1/reports', {
        if (conversationId != null) 'conversationId': conversationId,
        'kind': kind,
        if (note != null) 'note': note,
        if (targetUserId != null) 'targetUserId': targetUserId,
        if (sessionId != null) 'sessionId': sessionId,
        if (clipId != null) 'clipId': clipId,
      });

  Future<UserProfile> userProfile(String id) async =>
      UserProfile.fromJson(Map<String, dynamic>.from(await _call('GET', '/v1/users/${Uri.encodeComponent(id)}') as Map));

  Future<CipherReply> cipherChat({required List<Map<String, String>> messages, required int loyalty, required String tone, int? hour}) async {
    final j = await _call('POST', '/v1/cipher/chat', {'messages': messages, 'loyalty': loyalty, 'tone': tone, if (hour != null) 'hour': hour}) as Map;
    return CipherReply.fromJson(Map<String, dynamic>.from(j));
  }

  // following
  String _u(String id) => Uri.encodeComponent(id);
  Future<List<PersonRow>> _people(String path) async => ((await _call('GET', path) as Map)['people'] as List).map((e) => PersonRow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  Future<void> follow(String userId) async => _call('POST', '/v1/users/${_u(userId)}/follow');
  Future<void> unfollow(String userId) async => _call('DELETE', '/v1/users/${_u(userId)}/follow');
  Future<List<PersonRow>> followers(String userId) => _people('/v1/users/${_u(userId)}/followers');
  Future<List<PersonRow>> following(String userId) => _people('/v1/users/${_u(userId)}/following');
  Future<List<PersonRow>> suggestedPeople() => _people('/v1/people/suggested');
  Future<List<PersonRow>> blockedPeople() => _people('/v1/blocks');

  // chat
  Future<List<ChatRow>> chats() async => ((await _call('GET', '/v1/chats') as Map)['chats'] as List).map((e) => ChatRow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  Future<String> openChat(String userId) async => (await _call('POST', '/v1/chats', {'userId': userId}) as Map)['id'] as String;
  Future<ChatThread> thread(String id) async => ChatThread.fromJson(Map<String, dynamic>.from(await _call('GET', '/v1/chats/${_u(id)}') as Map));
  Future<void> sendMessage(String id, String text) async => _call('POST', '/v1/chats/${_u(id)}/messages', {'text': text});
  Future<void> respondChat(String id, {required bool accept}) async => _call('POST', '/v1/chats/${_u(id)}/${accept ? 'accept' : 'decline'}');

  // activity
  Future<List<ActivityItem>> activity() async => ((await _call('GET', '/v1/activity') as Map)['items'] as List).map((e) => ActivityItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  Future<void> markActivityRead() async => _call('POST', '/v1/activity/read');
  Future<Badges> badges() async => Badges.fromJson(Map<String, dynamic>.from(await _call('GET', '/v1/badges') as Map));

  // feed
  Future<({List<FeedClip> items, int? nextPage})> feed({required String sort, required int page}) async {
    final j = await _call('GET', '/v1/feed?sort=$sort&page=$page') as Map;
    return (items: (j['items'] as List).map((e) => FeedClip.fromJson(Map<String, dynamic>.from(e as Map))).toList(), nextPage: j['nextPage'] as int?);
  }

  Future<void> setLike(String clipId, bool on) async => _call(on ? 'POST' : 'DELETE', '/v1/clips/$clipId/like');
  Future<void> viewClip(String clipId) async => _call('POST', '/v1/clips/$clipId/view');
  Future<void> publishClip(String clipId, String caption) async => _call('POST', '/v1/clips/$clipId/publish', {'caption': caption});
  Future<void> deleteClip(String clipId) async => _call('DELETE', '/v1/clips/$clipId');
  Future<List<HiddenClip>> modClips() async {
    final j = await _call('GET', '/v1/mod/clips') as Map;
    return (j['items'] as List).map((e) => HiddenClip.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> modClipAction(String id, String action) async => _call('POST', '/v1/mod/clips/$id/$action');

  Future<void> block(String userId) async => _call('POST', '/v1/blocks', {'userId': userId});
  Future<void> unblock(String userId) async => _call('DELETE', '/v1/blocks/${Uri.encodeComponent(userId)}');

  // moderation
  Future<List<ReportItem>> modReports() async {
    final j = await _call('GET', '/v1/mod/reports') as Map;
    return (j['reports'] as List).map((e) => ReportItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<ModSession>> modSessions() async {
    final j = await _call('GET', '/v1/mod/sessions') as Map;
    return (j['sessions'] as List).map((e) => ModSession.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> modResetAvatar(String userId) async => _call('POST', '/v1/mod/users/$userId/reset-avatar');
  Future<void> modResolve(String id, String action) async => _call('POST', '/v1/mod/reports/$id/resolve', {'action': action});
  Future<void> modEnd(String sessionId) async => _call('POST', '/v1/mod/sessions/$sessionId/end');
  Future<void> modCut(String sessionId) async => _call('POST', '/v1/mod/sessions/$sessionId/cut');
}
