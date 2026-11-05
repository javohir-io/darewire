# Design system: calm liquid glass

The structure of this document follows the Design DNA method (define the system as tokens, then the style, then the effects), and the motion rules come from the motion-design skill. Every value below lives in code; the file is named in each row.

## The idea

**Imagery first, glass over it, a live scene behind everything.** The references are the Y2K chrome/holographic board, a lime-on-green meditation app, a dark live-streaming app and a techwear app. What they share, and what the app now does:

1. **Real imagery is the hero.** Full-bleed video and posters (the demo clips) fill the Home hero, the Welcome screen, the Feed and the live-session cards. Glass is only ever laid over something worth looking at.
2. **A live scene behind every screen.** Four large colour fields from the theme drift and swell, an iridescent sheen turns across them, glossy bubbles rise and sparkles twinkle (`gfx/backdrop.dart`). Glass blurs this, so it is visibly glass.
3. **Huge, wide type.** Headlines use Unbounded (wide, futuristic) in capitals: `T.wide`, `T.large`. One word of a headline may carry the holographic gradient (`GradientText`). Small uppercase tracked labels (`T.tech`) add the technical flavour. Body text stays Inter / Plus Jakarta Sans.
4. **Y2K details, used sparingly:** the chrome four-point **sparkle** (`gfx/y2k.dart`, in the logo and as accents), iridescent **holo rings** around hero elements, glossy bubbles, tracked tech labels.
5. **Big pill CTAs** with a vivid gradient and an arrow (`AppButton`), frosted-glass chips over imagery, a floating glass tab bar with a sliding lens and a glowing Create button.
6. **One idea per area.** Colour still carries meaning (primary = the thing to tap, accent = points, accent2 = like and streak, danger = live and stop); the richness comes from imagery, the scene and the glass, not from adding more colours.

## Themes

Switch in *Settings → Appearance*; saved on the device. Neon is the default. The palettes did not change, only how sparingly they are used.

| Theme | Feel | Main colours |
|---|---|---|
| **Neon** (default) | Electric blue, hot pink, acid lime on charcoal | `#3B37FF`, `#FF3DB8`, `#D8FF2A` |
| **Aurora** | Cool blue and violet | `#2563EB`, `#5CE1FF`, `#A78BFF` |
| **Crimson** | Ruby red on black | `#E5202F`, `#FF9A8A` |
| **Spectrum** | Multi-colour on a quiet base | `#7C4DEB`, `#2ED8B6`, `#FF7A45` |

All colours come from `core/theme.dart`: `Pal` (one palette), `C` (tokens that read the active palette), `T` (text styles), `R` (radii), `squircle()` (shape).

## Tokens (`core/theme.dart`)

| Group | Tokens |
|---|---|
| Text | `C.text`, `C.dim` (70%), `C.faint` (50%): three steps of one colour |
| Surfaces | `C.surface` (6%), `C.surfaceHi` (9%), `C.hairline` (9%): white over the scene. Cards are glass panes (`GlassPane`), see below |
| Gradients | `C.brand` (theme colour to a blend with accent2, for CTAs), `C.holo` / `C.holoLinear` / `C.holoColors` (the iridescent pastel sweep) |
| Colour roles | `C.primary` / `primaryHi`, `C.accent`, `C.accent2`, `C.danger`, `C.ok`, `C.warn` |
| Radii | `R.sm 12`, `md 16`, `lg 22`, `xl 30`, `pill`. Drawn as **continuous (squircle) corners** with `RoundedSuperellipseBorder` / `ClipRSuperellipse`, like iOS |
| Type | **Unbounded** for headlines (`T.wide`, and `T.large` which is the same face scaled so the usual sizes fit a phone), **Plus Jakarta Sans** for titles and numbers, **Inter** for reading. `title`, `strong`, `body`, `label`, `num` (tabular figures), `tech` (small uppercase, wide tracking) |
| Spacing | 20 px screen margins, 12 px between cards, 24-28 px between sections |

## Style: the glass (`gfx/glass.dart`)

Bottom to top: the blurred scene; a faint body tint, lighter at the top, with a little dark underneath so text stays readable on bright video; a soft **specular pool** near the light-facing top-left corner; a 1 px **rim** that is bright at the top-left and bottom-right and nearly gone in between; and a soft shadow drawn **outside** the shape only (a normal box shadow shows through the glass and muddies it). `clear: true` is the thinner variant for small controls over video. Nothing in it animates, so lists and scrolling stay smooth. True refraction (as in liquid-glass-js) needs a fragment shader sampling the backdrop and is left out on purpose: it cannot be tested on every device, and the layered version already reads as glass.

| Piece | File | Notes |
|---|---|---|
| Scene | `gfx/backdrop.dart` | Four large colour fields from the active palette drifting and swelling on a 36-second loop at 24 fps (the idea behind shadergradient), a slow iridescent sheen, five glossy bubbles rising and six twinkling sparkles, on a near-black base. Static when the OS asks for reduced motion or when switched off in Settings |
| Glass | `gfx/glass.dart` | `Glass` (real blur: tab bar, sheets, chips over video), `GlassPane` (the same look without the blur, so any number of cards fit: this is what `Surface` is), `GlassOrb`, `PersonChip` |
| Y2K pieces | `gfx/y2k.dart` | `Sparkle` (chrome four-point star), `GradientText`, `HoloRing` |
| Home hero | `ui/widgets/hero_reel.dart` | Trending dares playing live (muted, auto-advancing, one player at a time, paused off-tab) behind glass chips and a giant title |
| Welcome | `ui/screens/auth_screens.dart` | A bundled looping dare video (`assets/demo/welcome.mp4`) behind a huge headline and a glass sign-in card |
| Floating tab bar | `ui/screens/home_screens.dart` | A glass capsule. A **lens** (a lighter capsule) slides behind the selected tab; Create is a solid circle in the middle; the Duels badge is a small pill |
| Components | `ui/widgets/kit.dart` | `Surface`, `GroupedList` + `ListRow` (iOS inset lists), `IconBadge`, `ScreenHeader`, `AppButton` (primary / glass / danger / quiet), `Tag`, `Pips`, `Segmented`, `Avatar`, `PointsPill`, `EmptyState`, `ProgressBar`, `showGlassSheet` |
| Posters | `ui/widgets/clip_thumb.dart`, `live_card.dart` | A dare as a poster card; a live session as a card over a soft colour field |
| Cipher | `gfx/cipher_face.dart` | The mascot: a faceless, living 3D orb |
| Logo | `gfx/brand.dart` | The chrome sparkle plus DAREWIRE in the wide face, "WIRE" in the theme colour |

## Motion (`core/motion.dart`)

Archetype: **Premium with Playful accents**.

| Rule | Value |
|---|---|
| Signature curve | `cubic(0.4, 0, 0.2, 1)`, no overshoot, for about 80% of motion |
| Entrance / exit | `cubic(0.05, 0.7, 0.1, 1)` decelerates in, `cubic(0.3, 0, 1, 1)` accelerates out |
| Durations | 160 ms (press, toggle), 340 ms (cards, chips, tab lens), 520 ms (page level) |
| Stagger | 50 ms apart, 300 ms at most in total; elements rise 16 px, well under a third of the screen |
| Playful moments only | `Curves.easeOutBack`: the double-tap heart, the Cipher mascot |
| Reduced motion | `Reveal`, the backdrop and the tab lens all respect the OS setting |

## Performance

The costly things are real-time blur (a blurred panel is re-blurred every time what is behind it changes, such as a playing video) and the animated scene. So:

* Real blur is used only for a few large panels: the tab bar, sheets, the chat composer and the sign-in card. Small controls over video (chips, the action rail, the segmented switch) get a tinted glass body with no blur.
* Cards (`Surface` / `GlassPane`) have no blur and no drop shadow.
* The scene repaints at 15 fps, and stops completely while the Feed (full-screen video) is open.
* **Smooth mode** (`core/perf.dart`, Settings → Performance: Auto / On / Off) removes blur and freezes the scene to two still colour fields. Videos keep playing. In Auto it switches itself on if a third of the last 90 frames take longer than 24 ms (release and profile builds only: debug builds are always slow).
* Always judge speed with `flutter run --profile` or `--release`, on a real phone. Debug mode and emulators without GPU acceleration are far slower than the real app.

## Accessibility

Reduced motion is respected. Every tappable control has a semantic label. Contrast is unit-tested for body text and button text in every theme; small labels over video sit on a dark scrim or a dark translucent chip.

## Avatars

12 built-in avatars (`assets/avatars/a01.png` to `a12.png`, cut from your two sheets, transparent background) shown on a soft gradient disc. Players can also pick a photo from their gallery (`image_picker`), which is shrunk to 512 px on the phone and uploaded to `PUT /v1/me/avatar`.
