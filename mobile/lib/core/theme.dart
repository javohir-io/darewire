import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One complete colour theme. Every colour in the app comes from the active [Pal] through [C], so switching theme restyles everything.
class Pal {
  final String id, name, tagline;
  final Color bg, bg2, primary, primaryHi, accent, accent2, danger, ok, warn;

  /// The two colours of the glowing neon edge on glass panels.
  final Color edgeA, edgeB;

  /// Soft light pools drawn behind the glass (the "liquid" part of the look).
  final List<Color> blobs;

  /// Gradient pairs for feature tiles.
  final List<List<Color>> tiles;
  const Pal({
    required this.id,
    required this.name,
    required this.tagline,
    required this.bg,
    required this.bg2,
    required this.primary,
    required this.primaryHi,
    required this.accent,
    required this.accent2,
    required this.danger,
    required this.ok,
    required this.warn,
    required this.edgeA,
    required this.edgeB,
    required this.blobs,
    required this.tiles,
  });
}

/// Default theme. Electric blue, hot pink and acid lime on charcoal.
const palNeon = Pal(
  id: 'neon',
  name: 'Neon',
  tagline: 'Electric blue, hot pink, acid lime',
  bg: Color(0xFF0A0A0D),
  bg2: Color(0xFF131318),
  primary: Color(0xFF3B37FF),
  primaryHi: Color(0xFF7471FF),
  accent: Color(0xFFD8FF2A),
  accent2: Color(0xFFFF3DB8),
  danger: Color(0xFFFF4D6A),
  ok: Color(0xFFB6F23A),
  warn: Color(0xFFFFC53D),
  edgeA: Color(0xFF5B57FF),
  edgeB: Color(0xFFFF3DB8),
  blobs: [Color(0xFF3B37FF), Color(0xFFFF3DB8), Color(0xFFD8FF2A), Color(0xFF3B37FF)],
  tiles: [
    [Color(0xFF3B37FF), Color(0xFF8A3DFF)],
    [Color(0xFFFF3DB8), Color(0xFFFF7A59)],
    [Color(0xFFD8FF2A), Color(0xFF7DDC3B)],
    [Color(0xFF3B37FF), Color(0xFFFF3DB8)],
  ],
);

/// Cool glass: cyan, blue and violet light.
const palAurora = Pal(
  id: 'aurora',
  name: 'Aurora',
  tagline: 'Cool blue and violet glass',
  bg: Color(0xFF05080F),
  bg2: Color(0xFF0C121E),
  primary: Color(0xFF2563EB),
  primaryHi: Color(0xFF8CC8FF),
  accent: Color(0xFF5CE1FF),
  accent2: Color(0xFFA78BFF),
  danger: Color(0xFFFF6B8A),
  ok: Color(0xFF48E0B0),
  warn: Color(0xFFFFC857),
  edgeA: Color(0xFF4FB3FF),
  edgeB: Color(0xFFA78BFF),
  blobs: [Color(0xFF2A6BFF), Color(0xFF8A5CFF), Color(0xFF1CC7E6), Color(0xFF3D8BFF)],
  tiles: [
    [Color(0xFF2563EB), Color(0xFF3B9BE8)],
    [Color(0xFF6D3FE0), Color(0xFF9A78F5)],
    [Color(0xFF0E7FA8), Color(0xFF1FB59A)],
    [Color(0xFF2F6BE8), Color(0xFF8A6BF0)],
  ],
);

/// Warm glass: ruby red on near black.
const palCrimson = Pal(
  id: 'crimson',
  name: 'Crimson',
  tagline: 'Ruby red on black glass',
  bg: Color(0xFF040203),
  bg2: Color(0xFF0E0709),
  primary: Color(0xFFE5202F),
  primaryHi: Color(0xFFFF6672),
  accent: Color(0xFFFF9A8A),
  accent2: Color(0xFFFFC7A8),
  danger: Color(0xFFFF4B5C),
  ok: Color(0xFF4FD18B),
  warn: Color(0xFFF2B24C),
  edgeA: Color(0xFFFF2A3D),
  edgeB: Color(0xFFFF6A4D),
  blobs: [Color(0xFFE5202F), Color(0xFF8A0F1B), Color(0xFFFF5A3C), Color(0xFFE5202F)],
  tiles: [
    [Color(0xFFE5202F), Color(0xFFFF6A4D)],
    [Color(0xFF8A0F1B), Color(0xFFE5202F)],
    [Color(0xFFE5482A), Color(0xFFF08A3C)],
    [Color(0xFFB3121F), Color(0xFFE63A6E)],
  ],
);

/// Multi-colour gradient tiles on a quiet dark base.
const palSpectrum = Pal(
  id: 'spectrum',
  name: 'Spectrum',
  tagline: 'Multi-colour gradient tiles',
  bg: Color(0xFF08080B),
  bg2: Color(0xFF121217),
  primary: Color(0xFF7C4DEB),
  primaryHi: Color(0xFFC4A8FF),
  accent: Color(0xFF2ED8B6),
  accent2: Color(0xFFFF7A45),
  danger: Color(0xFFFF5A6E),
  ok: Color(0xFF2ED8B6),
  warn: Color(0xFFE6D52B),
  edgeA: Color(0xFF9B6CFF),
  edgeB: Color(0xFF2ED8B6),
  blobs: [Color(0xFF9B6CFF), Color(0xFF2ED8B6), Color(0xFFFF7A45), Color(0xFFE6D52B)],
  tiles: [
    [Color(0xFF7C4DEB), Color(0xFFB45CD8)],
    [Color(0xFF14A58A), Color(0xFF2A74C9)],
    [Color(0xFFE5482A), Color(0xFFEF8A2E)],
    [Color(0xFF8BA80F), Color(0xFF3F9E34)],
  ],
);

const palettes = [palNeon, palAurora, palCrimson, palSpectrum];
Pal palById(String? id) => palettes.firstWhere((p) => p.id == id, orElse: () => palNeon);

/// Design tokens. These are getters on the ACTIVE palette, so never use them in `const` expressions.
class C {
  static Pal pal = palNeon;

  static Color get bg => pal.bg;
  static Color get bg2 => pal.bg2;
  static Color get primary => pal.primary;
  static Color get primaryHi => pal.primaryHi;
  static Color get accent => pal.accent;
  static Color get accent2 => pal.accent2;
  static Color get danger => pal.danger;
  static Color get ok => pal.ok;
  static Color get warn => pal.warn;
  static Color get edgeA => pal.edgeA;
  static Color get edgeB => pal.edgeB;
  static const text = Color(0xFFF6F7FB);

  /// Colour with opacity, without the deprecated Color.withOpacity.
  static Color a(Color c, double opacity) => c.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());

  // Text: three steps of the same colour, so hierarchy comes from tone and size, not from extra colours.
  static Color get dim => a(text, 0.70);
  static Color get faint => a(text, 0.50);

  // Surfaces. Content sits on FLAT surfaces (no blur, no glow). Only things that float over content use real glass (see gfx/glass.dart).
  static Color get surface => a(Colors.white, 0.055);
  static Color get surfaceHi => a(Colors.white, 0.09);
  static Color get hairline => a(Colors.white, 0.09);
  static Color get scrim => a(Colors.black, 0.55);

  // Older names, kept so every screen reads from the same three values above.
  static Color get glass => surface;
  static Color get glassHi => surfaceHi;
  static Color get border => hairline;
  static Color get borderHi => a(Colors.white, 0.22);

  /// The primary button fill: the theme colour with a whisper of light at the top (no neon, no glow).
  static LinearGradient get brand => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(primary, Colors.white, 0.16)!, primary, Color.lerp(primary, accent2, 0.62)!]);

  /// The Y2K iridescent sheen (pink, lilac, ice blue, mint, butter). Used for rims, the create button, one word of a headline. Never as a fill for text blocks.
  static const List<Color> holoColors = [Color(0xFFFF9AD5), Color(0xFFB79CFF), Color(0xFF7DE3FF), Color(0xFF9CFFD9), Color(0xFFFFF08A), Color(0xFFFF9AD5)];
  static const SweepGradient holo = SweepGradient(colors: holoColors);
  static const LinearGradient holoLinear = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: holoColors);

  /// Readable text colour on top of a bright colour (lime and similar accents need dark text).
  static Color onColor(Color c) => c.computeLuminance() > 0.55 ? const Color(0xFF101014) : Colors.white;
}

/// Profile accent colours, chosen by each user and validated on the server.
const accentKeys = ['neon', 'pink', 'lime', 'blue', 'violet', 'aqua', 'coral'];
({Color main, Color hi}) accentOf(String key) => switch (key) {
      'pink' => (main: const Color(0xFFFF3DB8), hi: const Color(0xFFFF8AD6)),
      'lime' => (main: const Color(0xFFB6F23A), hi: const Color(0xFFE2FF7A)),
      'blue' => (main: const Color(0xFF3D8BFF), hi: const Color(0xFF9AD1FF)),
      'violet' => (main: const Color(0xFF8B5CFF), hi: const Color(0xFFC3A6FF)),
      'aqua' => (main: const Color(0xFF2ED8B6), hi: const Color(0xFF8FF0DA)),
      'coral' => (main: const Color(0xFFFF6B57), hi: const Color(0xFFFFA08F)),
      _ => (main: C.primary, hi: C.primaryHi), // 'neon' follows the current theme
    };

/// Corner radii. Shapes are drawn as continuous "squircle" corners (see [squircle]) like iOS, so these read softer than plain rounded rectangles.
class R {
  static const sm = 12.0, md = 16.0, lg = 22.0, xl = 30.0, pill = 999.0;
}

/// A continuous-corner (iOS-style) rounded shape. Use it instead of RoundedRectangleBorder for cards, buttons and glass.
ShapeBorder squircle(double radius, {BorderSide side = BorderSide.none}) => RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius), side: side);

/// Typography: Plus Jakarta Sans for headings and numbers, Inter for reading. Normal case everywhere.
class T {
  static const _tabular = [FontFeature.tabularFigures()];

  /// The wide, futuristic display face (Unbounded) for headlines. Big, bold, a little Y2K. Sized in "normal" points; it is naturally about 20% wider.
  static TextStyle wide([double size = 28]) => GoogleFonts.unbounded(color: C.text, fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -size * 0.02, height: 1.08);

  /// Large screen title. Uses the wide face, scaled down so the same numbers still fit a phone.
  static TextStyle large([double size = 32]) => wide(size * 0.78);

  /// Small uppercase technical label with wide tracking ("LIVE NOW", "TRENDING"), like the labels in the Y2K reference.
  static TextStyle tech([double size = 10.5]) => GoogleFonts.inter(color: C.dim, fontSize: size, fontWeight: FontWeight.w700, letterSpacing: size * 0.16, height: 1.2);
  static TextStyle display([double size = 28]) => GoogleFonts.plusJakartaSans(color: C.text, fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.12);
  static TextStyle title([double size = 20]) => GoogleFonts.plusJakartaSans(color: C.text, fontSize: size, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.2);
  static TextStyle body([double size = 15]) => GoogleFonts.inter(color: C.dim, fontSize: size, height: 1.4);
  static TextStyle strong([double size = 15]) => GoogleFonts.inter(color: C.text, fontSize: size, fontWeight: FontWeight.w600);
  static TextStyle label([double size = 12]) => GoogleFonts.inter(color: C.faint, fontSize: size, fontWeight: FontWeight.w600, letterSpacing: 0.1);
  static TextStyle num([double size = 16]) => GoogleFonts.plusJakartaSans(color: C.text, fontSize: size, fontWeight: FontWeight.w800, fontFeatures: _tabular);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: c, width: w));
  final field = C.a(Colors.white, 0.07);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent, // the backdrop shows through every screen
    colorScheme: ColorScheme.dark(primary: C.primary, onPrimary: Colors.white, secondary: C.accent, surface: C.bg2, onSurface: C.text, error: C.danger),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: C.text, displayColor: C.text),
    // No ink splashes: pressed states are a quiet scale and brightness change instead (see Pressable), like iOS.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    dividerColor: C.hairline,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),   // the iOS push with swipe-back
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: true, titleTextStyle: T.title(17)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      hintStyle: T.body().copyWith(color: C.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(C.a(C.primaryHi, 0.9), 1.2),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E1E25),
      contentTextStyle: T.strong(14),
      behavior: SnackBarBehavior.floating,
      shape: squircle(R.md, side: BorderSide(color: C.border)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.primary : C.a(Colors.white, 0.18)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: C.primaryHi, thumbColor: Colors.white, inactiveTrackColor: C.a(Colors.white, 0.16), overlayColor: C.a(C.primary, 0.16), trackHeight: 4),
    dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF1A1A21), shape: squircle(R.lg, side: BorderSide(color: C.border)), titleTextStyle: T.title(18)),
    popupMenuTheme: PopupMenuThemeData(color: const Color(0xFF1E1E25), shape: squircle(R.md, side: BorderSide(color: C.border))),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: C.primaryHi),
  );
}

const _kTheme = 'theme_id';

/// The chosen theme, remembered on this device. Changing it repaints the whole app.
class ThemeController extends Notifier<String> {
  @override
  String build() => C.pal.id;

  Future<void> choose(String id) async {
    if (id == state) return;
    C.pal = palById(id);
    state = id;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTheme, id);
    // Widgets read colours from static tokens, so ask every element to rebuild once.
    WidgetsBinding.instance.addPostFrameCallback((_) => rebuildEverything());
  }
}

final themeProvider = NotifierProvider<ThemeController, String>(ThemeController.new);

/// Loads the saved theme before the first frame.
Future<void> loadSavedTheme() async {
  final p = await SharedPreferences.getInstance();
  C.pal = palById(p.getString(_kTheme));
}

void rebuildEverything() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}
