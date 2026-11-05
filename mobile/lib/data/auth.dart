import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The app talks to the server with one bearer token. In production it is a Supabase Auth access token;
/// in local development (no Supabase configured) it is a `dev:<id>:<handle>` token the dev server accepts.
abstract class AuthService {
  bool get signedIn;
  Stream<bool> get changes;
  Future<String?> accessToken();
  Future<void> signOut();
  Future<void> signIn(String email, String password);

  /// Returns a message when the project requires e-mail confirmation before the first sign-in.
  Future<String?> signUp(String email, String password);
  Future<void> devLogin(String handle);
}

class SupabaseAuth implements AuthService {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  bool get signedIn => _auth.currentSession != null;

  @override
  Stream<bool> get changes => _auth.onAuthStateChange.map((e) => e.session != null).distinct();

  @override
  Future<String?> accessToken() async {
    final s = _auth.currentSession;
    if (s == null) return null;
    // Refresh shortly before expiry so a long session never sends a dead token.
    final exp = s.expiresAt;
    if (exp != null && exp * 1000 - DateTime.now().millisecondsSinceEpoch < 60000) {
      try {
        final r = await _auth.refreshSession();
        return r.session?.accessToken ?? s.accessToken;
      } catch (_) {
        return s.accessToken;
      }
    }
    return s.accessToken;
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithPassword(email: email.trim(), password: password);
  }

  @override
  Future<String?> signUp(String email, String password) async {
    final r = await _auth.signUp(email: email.trim(), password: password);
    return r.session == null ? 'Check your inbox to confirm your e-mail, then sign in.' : null;
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> devLogin(String handle) => throw UnsupportedError('Dev login is disabled when Supabase is configured');
}

class DevAuth implements AuthService {
  final SharedPreferences _prefs;
  final _ctl = StreamController<bool>.broadcast();
  DevAuth(this._prefs);

  static const _kId = 'dev_id', _kHandle = 'dev_handle';

  @override
  bool get signedIn => _prefs.getString(_kId) != null;

  @override
  Stream<bool> get changes => _ctl.stream;

  @override
  Future<String?> accessToken() async {
    final id = _prefs.getString(_kId);
    if (id == null) return null;
    return 'dev:$id:${_prefs.getString(_kHandle) ?? 'player'}';
  }

  @override
  Future<void> devLogin(String handle) async {
    final h = handle.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (h.length < 3) throw ArgumentError('Pick a handle of at least 3 letters or digits');
    await _prefs.setString(_kId, 'dev-$h');
    await _prefs.setString(_kHandle, h);
    _ctl.add(true);
  }

  @override
  Future<void> signOut() async {
    await _prefs.remove(_kId);
    _ctl.add(false);
  }

  @override
  Future<void> signIn(String email, String password) => throw UnsupportedError('Use the dev login');

  @override
  Future<String?> signUp(String email, String password) => throw UnsupportedError('Use the dev login');
}
