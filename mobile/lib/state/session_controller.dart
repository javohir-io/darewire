import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/config.dart';
import '../data/models.dart';
import 'providers.dart';

enum Conn { connecting, live, reconnecting, closed }

/// (session id, "watcher" | "player" | "observer"). A record, so it has value equality and works as a provider family key.
typedef SessionArgs = ({String id, String want});

@immutable
class SessionUi {
  final SessionView? view;
  final Conn conn;
  final String? fatal; // a reason the session can't continue (shown full-screen)
  final List<ChatMessage> chat;
  final int offsetMs; // serverTime - localTime, so countdowns follow the SERVER clock
  const SessionUi({this.view, this.conn = Conn.connecting, this.fatal, this.chat = const [], this.offsetMs = 0});

  SessionUi copyWith({SessionView? view, Conn? conn, String? fatal, List<ChatMessage>? chat, int? offsetMs}) =>
      SessionUi(view: view ?? this.view, conn: conn ?? this.conn, fatal: fatal ?? this.fatal, chat: chat ?? this.chat, offsetMs: offsetMs ?? this.offsetMs);

  int get serverNow => DateTime.now().millisecondsSinceEpoch + offsetMs;
}

const _fatalMessages = {
  'age_required': 'Confirm your birthday to join.',
  'suspended': 'Your account is suspended.',
  'blocked': 'You cannot join this session.',
  'ended': 'This session has ended.',
  'not_found': 'This session no longer exists.',
  'banned': 'You were removed from this session.',
  'profile_incomplete': 'Finish setting up your profile first.',
  'full': 'This session is full.',
  'forbidden': 'You are not allowed in this session.',
  'account_deleted': 'This account was deleted.',
};

/// One live session connection. It renders the server's authoritative state and sends the commands the server permits.
/// It never decides a vote, a winner, a timer or a score. On a dropped connection it reconnects and the server replies with a
/// fresh snapshot, so the UI always resumes from the real current state.
class SessionController extends AutoDisposeFamilyNotifier<SessionUi, SessionArgs> {
  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _disposed = false;
  bool _fatal = false;
  int _seq = 0;
  final _acks = <String, Completer<String?>>{};
  final _events = StreamController<ServerEvent>.broadcast();

  Stream<ServerEvent> get events => _events.stream;

  @override
  SessionUi build(SessionArgs arg) {
    ref.onDispose(_teardown);
    Future.microtask(_connect);
    return const SessionUi();
  }

  void _teardown() {
    _disposed = true;
    _retry?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    for (final c in _acks.values) {
      if (!c.isCompleted) c.complete('Disconnected');
    }
    _events.close();
  }

  Future<void> _connect() async {
    if (_disposed || _fatal) return;
    state = state.copyWith(conn: _attempt == 0 ? Conn.connecting : Conn.reconnecting);
    try {
      final token = await ref.read(authServiceProvider).accessToken();
      if (token == null) return _fail('Signed out');
      final ch = WebSocketChannel.connect(Uri.parse(Env.wsUrl));
      await ch.ready;
      if (_disposed) {
        ch.sink.close();
        return;
      }
      _ch = ch;
      _sub = ch.stream.listen(_onMessage, onDone: _onClosed, onError: (Object _) => _onClosed());
      ch.sink.add(jsonEncode({'type': 'auth', 'data': {'token': token, 'sessionId': arg.id, 'want': arg.want}}));
    } catch (_) {
      _onClosed();
    }
  }

  void _onClosed() {
    if (_disposed || _fatal) return;
    _sub?.cancel();
    _ch = null;
    state = state.copyWith(conn: Conn.reconnecting);
    final secs = (1 << _attempt.clamp(0, 3)); // 1,2,4,8 seconds
    _attempt++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: secs), _connect);
  }

  void _fail(String message) {
    if (_disposed) return;
    _fatal = true;
    state = state.copyWith(conn: Conn.closed, fatal: message);
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    final Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
    } catch (_) {
      return;
    }
    final type = m['type'] as String? ?? '';
    final data = m['data'] is Map ? Map<String, dynamic>.from(m['data'] as Map) : <String, dynamic>{};
    switch (type) {
      case 'ready':
        _attempt = 0;
        state = state.copyWith(conn: Conn.live);
      case 'session:state':
        final v = SessionView.fromJson(data);
        final cur = state.view;
        if (cur != null && cur.id == v.id && v.rev < cur.rev) return; // stale snapshot: ignore
        state = state.copyWith(view: v, conn: Conn.live, offsetMs: v.serverTime - DateTime.now().millisecondsSinceEpoch);
        if (v.phase == 'SESSION_END') _events.add(ServerEvent('session:ended', {'reason': v.endedReason}));
      case 'ack':
        final c = _acks.remove(m['id']?.toString());
        if (c != null && !c.isCompleted) {
          c.complete(data['ok'] == true ? null : ((data['error'] as Map?)?['message']?.toString() ?? 'Not allowed'));
        }
      case 'error':
        final code = data['code']?.toString() ?? '';
        if (code == 'auth_failed' && _attempt < 3) return; // token may have just refreshed: the socket closes and we retry
        if (_fatalMessages.containsKey(code)) _fail(_fatalMessages[code]!);
      case 'chat:message':
        final msg = ChatMessage.fromJson(data);
        final next = [...state.chat, msg];
        state = state.copyWith(chat: next.length > 60 ? next.sublist(next.length - 60) : next);
      case 'chat:history':
        final list = m['data'];
        if (list is List) {
          state = state.copyWith(chat: list.whereType<Map>().map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e))).toList());
        }
      case 'chat:deleted':
        state = state.copyWith(chat: state.chat.where((c) => c.id != data['id']).toList());
      default:
        if (!_events.isClosed) _events.add(ServerEvent(type, data));
    }
  }

  /// Sends a command. Resolves to null on success or to a human-readable error from the server.
  Future<String?> send(String type, [Map<String, dynamic> data = const {}]) {
    final ch = _ch;
    if (ch == null) return Future.value('Reconnecting. Try again in a moment.');
    final id = '${++_seq}';
    final c = Completer<String?>();
    _acks[id] = c;
    try {
      ch.sink.add(jsonEncode({'type': type, 'id': id, 'data': data}));
    } catch (_) {
      _acks.remove(id);
      return Future.value('Not connected');
    }
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _acks.remove(id);
      return 'The server did not answer';
    });
  }

  Future<void> leave() async {
    await send('session:leave');
  }
}

final sessionProvider = NotifierProvider.autoDispose.family<SessionController, SessionUi, SessionArgs>(SessionController.new);
