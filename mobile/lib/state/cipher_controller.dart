import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models.dart';
import 'providers.dart';

@immutable
class CMsg {
  final String id, text;
  final bool mine;
  const CMsg(this.id, this.text, {required this.mine});
}

@immutable
class CipherState {
  final List<CMsg> msgs;
  final int loyalty;
  final String tone, mood;
  final bool typing, busy, loaded, offline;
  const CipherState({this.msgs = const [], this.loyalty = 70, this.tone = 'Blunt', this.mood = 'idle', this.typing = false, this.busy = false, this.loaded = false, this.offline = false});

  CipherState copyWith({List<CMsg>? msgs, int? loyalty, String? tone, String? mood, bool? typing, bool? busy, bool? loaded, bool? offline}) => CipherState(
        msgs: msgs ?? this.msgs, loyalty: loyalty ?? this.loyalty, tone: tone ?? this.tone, mood: mood ?? this.mood, typing: typing ?? this.typing,
        busy: busy ?? this.busy, loaded: loaded ?? this.loaded, offline: offline ?? this.offline,
      );
}

String moodFromUser(String t) {
  final s = t.toLowerCase();
  if (RegExp(r'love you|thank|appreciate|you.?re the best|proud of you').hasMatch(s)) return 'shy';
  if (RegExp(r'haha|lol|lmao|funny|dead\b').hasMatch(s)) return 'laugh';
  if (RegExp(r'hate you|stupid|shut up|useless|you suck|idiot|dumb').hasMatch(s)) return 'sad';
  if (RegExp(r'wow|omg|no way|what the|wtf').hasMatch(s)) return 'surprised';
  if (RegExp(r'nervous|scared|afraid|anxious|stress|panic').hasMatch(s)) return 'worried';
  if (RegExp(r'\?|why|how|what|which').hasMatch(s)) return 'curious';
  return 'thinking';
}

String moodFromReply(String t) {
  final s = t.toLowerCase();
  if (RegExp(r'haha|lol|funny|dead\b').hasMatch(s)) return 'laugh';
  if (RegExp(r'proud|nice|great|love|good one|yes\b').hasMatch(s)) return 'happy';
  if (RegExp(r'sorry|ouch|miss you').hasMatch(s)) return 'sad';
  if (RegExp(r'careful|hmm|sus\b|suspicious').hasMatch(s)) return 'suspicious';
  if (s.contains('?')) return 'curious';
  return 'idle';
}

/// Cipher's conversation. Memory lives ONLY on this device (shared preferences). Each message is sent through our server to
/// Gemini with a short slice of the recent chat; the server stores nothing.
class CipherController extends Notifier<CipherState> {
  Timer? _revert, _nap, _think;
  DateTime _lastActive = DateTime.now();
  int _seq = 0;
  bool _disposed = false;

  static const _kMsgs = 'cipher_msgs', _kLoyalty = 'cipher_loyalty', _kTone = 'cipher_tone';
  static const greeting = "Hi, I'm Cipher! Ask me for dare ideas, tips for staying calm on stage, or how anything in DAREWIRE works.";

  @override
  CipherState build() {
    ref.onDispose(() {
      _disposed = true;
      _revert?.cancel();
      _nap?.cancel();
      _think?.cancel();
    });
    _nap = Timer.periodic(const Duration(seconds: 6), (_) {
      if (state.mood == 'idle' && !state.busy && DateTime.now().difference(_lastActive).inSeconds > 90) state = state.copyWith(mood: 'sleepy');
    });
    Future.microtask(_load);
    return const CipherState();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    var msgs = <CMsg>[];
    try {
      final raw = jsonDecode(p.getString(_kMsgs) ?? '[]') as List;
      msgs = raw.whereType<Map>().map((e) => CMsg('${_seq++}', '${e['t']}', mine: e['m'] == true)).toList();
    } catch (_) {}
    if (msgs.isEmpty) msgs = [CMsg('${_seq++}', greeting, mine: false)];
    if (_disposed) return;
    state = state.copyWith(msgs: msgs, loyalty: p.getInt(_kLoyalty) ?? 70, tone: p.getString(_kTone) ?? 'Blunt', loaded: true);
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    final keep = state.msgs.length > 60 ? state.msgs.sublist(state.msgs.length - 60) : state.msgs;
    await p.setString(_kMsgs, jsonEncode([for (final m in keep) {'m': m.mine, 't': m.text}]));
    await p.setInt(_kLoyalty, state.loyalty);
    await p.setString(_kTone, state.tone);
  }

  /// Called whenever the user touches Cipher or the screen: wakes him up.
  void touch() {
    _lastActive = DateTime.now();
    if (state.mood == 'sleepy') state = state.copyWith(mood: 'idle');
  }

  void setTone(String tone) {
    state = state.copyWith(tone: tone);
    _save();
  }

  Future<void> wipe() async {
    state = state.copyWith(msgs: [CMsg('${_seq++}', greeting, mine: false)], loyalty: 70, mood: 'idle');
    await _save();
  }

  void _setMood(String m, {int revertMs = 9000}) {
    if (_disposed) return;
    _revert?.cancel();
    state = state.copyWith(mood: m);
    if (m != 'idle') _revert = Timer(Duration(milliseconds: revertMs), () => _disposed ? null : state = state.copyWith(mood: 'idle'));
  }

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || state.busy || text.length > 400) return;
    touch();
    final mine = CMsg('${_seq++}', text, mine: true);
    state = state.copyWith(msgs: [...state.msgs, mine], busy: true);
    _setMood(moodFromUser(text), revertMs: 30000);
    _think?.cancel();
    _think = Timer(const Duration(milliseconds: 650), () {
      if (state.busy && !state.typing) _setMood('thinking', revertMs: 30000);
    });

    final history = [
      for (final m in (state.msgs.length > 14 ? state.msgs.sublist(state.msgs.length - 14) : state.msgs)) {'role': m.mine ? 'user' : 'cipher', 'text': m.text},
    ];
    final started = DateTime.now();
    CipherReply reply;
    try {
      reply = await ref.read(apiProvider).cipherChat(messages: history, loyalty: state.loyalty, tone: state.tone, hour: DateTime.now().hour);
    } catch (_) {
      reply = const CipherReply(messages: ["I can't connect right now. Try me again in a moment."], mood: 'worried');
    }
    if (_disposed) return;
    final wait = 1400 - DateTime.now().difference(started).inMilliseconds;
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    if (_disposed) return;

    state = state.copyWith(loyalty: (state.loyalty + reply.loyaltyDelta).clamp(0, 100), offline: reply.offline);
    final mood = reply.mood ?? moodFromReply(reply.messages.join(' '));
    for (var i = 0; i < reply.messages.length; i++) {
      final msg = reply.messages[i];
      state = state.copyWith(typing: true);
      if (i == 0) _setMood(mood);
      await Future<void>.delayed(Duration(milliseconds: (350 + msg.length * 24).clamp(600, 1900)));
      if (_disposed) return;
      state = state.copyWith(msgs: [...state.msgs, CMsg('${_seq++}', msg, mine: false)], typing: false);
      await Future<void>.delayed(const Duration(milliseconds: 260));
    }
    state = state.copyWith(busy: false);
    _lastActive = DateTime.now();
    unawaited(_save());
  }
}

final cipherProvider = NotifierProvider<CipherController, CipherState>(CipherController.new);
