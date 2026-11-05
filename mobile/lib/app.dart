import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'gfx/backdrop.dart';

class DarewireApp extends ConsumerWidget {
  const DarewireApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider); // rebuild the whole app when the theme changes
    return MaterialApp.router(
      title: 'DAREWIRE',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      // One animated backdrop behind every screen: all Scaffolds are transparent.
      // Material(transparency) gives every screen the Material ancestor that TextField, ListTile, etc. require,
      // while keeping the backdrop visible.
      builder: (context, child) => ColoredBox(
        color: C.bg,
        child: Stack(fit: StackFit.expand, children: [
          const AppBackdrop(),
          if (child != null) Material(type: MaterialType.transparency, child: child),
        ]),
      ),
    );
  }
}
