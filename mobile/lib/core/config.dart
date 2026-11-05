import 'package:flutter/foundation.dart';

/// Build-time configuration. Pass with:  flutter run --dart-define-from-file=env.json
/// Only PUBLIC values live here (API URL, Supabase URL and anon key). The Gemini key, the LiveKit secret and the
/// Supabase service key exist only on the server and must never be added to the app.
class Env {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const devAuthFlag = String.fromEnvironment('DEV_AUTH');

  static bool get useSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Development login: on in debug builds when Supabase is not configured (or when DEV_AUTH=true).
  static bool get devAuth {
    if (useSupabase) return false;
    final f = devAuthFlag.toLowerCase();
    if (f == 'true') return true;
    if (f == 'false') return false;
    return kDebugMode;
  }

  static String get wsUrl {
    final u = apiUrl.replaceFirst(RegExp(r'^http'), 'ws');
    return '$u/v1/ws';
  }
}

/// Shown at the bottom of Settings so you can tell which build is running.
const buildTag = 'v8';

/// The youngest age DAREWIRE allows. The SERVER decides and enforces it (server/src/profile/age.ts); this copy is only for the app's own logic and wording.
const minAge = 16;

/// Whole years between a birth date and a day.
int ageOn(DateTime birth, DateTime day) {
  final hadBirthday = day.month > birth.month || (day.month == birth.month && day.day >= birth.day);
  return day.year - birth.year - (hadBirthday ? 0 : 1);
}
