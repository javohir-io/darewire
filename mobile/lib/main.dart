import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config.dart';
import 'core/perf.dart';
import 'core/theme.dart';
import 'gfx/backdrop.dart';
import 'data/auth.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light, systemNavigationBarColor: Colors.transparent));

  await loadSavedTheme();
  await GlassClock.load();
  await Perf.load();

  final AuthService auth;
  if (Env.useSupabase) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    auth = SupabaseAuth();
  } else {
    auth = DevAuth(await SharedPreferences.getInstance());
  }

  runApp(ProviderScope(overrides: [authServiceProvider.overrideWithValue(auth)], child: const DarewireApp()));
}
