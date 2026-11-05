import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the app smooth on slower phones.
///
/// The expensive things in this design are real-time blur (every blurred panel is re-blurred whenever what is behind it changes:
/// a playing video, the animated scene) and the animated background itself. "Smooth mode" turns those down:
/// no blur (panels become tinted glass) and a still background. Videos always play: a muted video is cheap, blur over it is not.
///
/// * Auto (default): the app watches its own frame times in release/profile builds and switches smooth mode on by itself,
///   for good, if too many frames are slow. (Debug builds are always slow and are not used for this.)
/// * On / Off: the person's choice in Settings.
class Perf {
  /// True when smooth mode is active right now. Widgets listen to this.
  static final ValueNotifier<bool> lite = ValueNotifier<bool>(false);

  /// 'auto', 'on' or 'off'.
  static final ValueNotifier<String> mode = ValueNotifier<String>('auto');

  static const _modeKey = 'perf_mode';
  static const _autoKey = 'perf_auto_lite';
  static bool _autoLite = false;
  static int _seen = 0;
  static final List<bool> _slow = [];

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    // In a browser the blur and the animated scene are much slower than on a phone, so smooth mode starts on there (change it in Settings).
    mode.value = p.getString(_modeKey) ?? (kIsWeb ? 'on' : 'auto');
    _autoLite = p.getBool(_autoKey) ?? false;
    _apply();
    if (!kDebugMode) SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static Future<void> setMode(String m) async {
    mode.value = m;
    if (m == 'auto') {
      _autoLite = false;
      _slow.clear();
      _seen = 0;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_modeKey, m);
    await p.setBool(_autoKey, _autoLite);
    _apply();
  }

  static void _apply() => lite.value = mode.value == 'on' || (mode.value == 'auto' && _autoLite);

  /// Frames that take longer than 24 ms (a 60 Hz frame is 16.7 ms) count as slow. If a third of the last 90 frames are slow,
  /// switch to smooth mode. The first 60 frames (startup) are ignored.
  static void _onTimings(List<FrameTiming> timings) {
    if (mode.value != 'auto' || _autoLite) return;
    for (final t in timings) {
      if (++_seen <= 60) continue;
      _slow.add(t.totalSpan.inMicroseconds > 24000);
      if (_slow.length > 90) _slow.removeAt(0);
    }
    if (_slow.length >= 90 && _slow.where((s) => s).length > 30) {
      _autoLite = true;
      _apply();
      SharedPreferences.getInstance().then((p) => p.setBool(_autoKey, true));
    }
  }
}
