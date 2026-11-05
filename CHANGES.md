# What changed in this update

## Update 9: performance pass

Blur is now used only for a few large panels; small controls over video use tinted glass (no blur), cards have no shadow blur, the animated scene runs at 15 fps and stops while the Feed is open, and a new **Smooth mode** (Settings → Performance, Auto / On / Off) turns blur and animation off, automatically in Auto when frames are slow. See `docs/design-system.md`.

## Update 8: following, chat, activity

**New features.** Follow and unfollow with Followers / Following lists and a **Following** tab in the Dares feed; **Messages** (inbox, message requests, chat thread); an **Activity** page with red-dot badges on Home; **Find people** (search and suggestions); **Blocked accounts**; a **Safety centre**. Profiles now show Following / Followers counts and Follow and Message buttons.

**Teen safety first.** Everything respects the age bands (teens and adults never follow or message each other). Teens can only chat with mutual followers, re-checked on every message. A message filter blocks links, phone numbers and @handles for everyone and meet-up talk, personal questions and "move to another app" for teens. Reporting from a chat attaches the last messages. Blocking ends following both ways. See `docs/threat-model.md`.

**Code.** `server/src/social/graph.ts` (all the rules), `chat-policy.ts` (message filter), repo methods for follows, conversations, messages and notifications (memory and Postgres), 18 routes, migration `0008_follows_chat_activity.sql`. 10 new server tests (93 in total) and 3 new client test groups. In the app: `ui/screens/social_screens.dart`, new providers and models. **Run migration 0008 once.** The Postgres versions of the new queries have not been run against a live database.

## Update 7: ages 16+, teen safety, calmer liquid-glass design, demo videos

**Ages.** The minimum age is now **16** (was 18). Accounts are *teen* (16-17) or *adult* (18+), derived from the date of birth on every request. Teen accounts get a content floor on every dare (level 3 maximum; no social-courage, romance or dark-humor dares; extra word checks), and teens and adults never share a live session, duel, user search, profile, leaderboard or Dares feed. Teens pick duels from curated ideas (no free text). Cipher uses a teen persona for teens. The age answer is now write-once (a teen could otherwise re-enter an adult birthday), and an under-age answer is remembered. The birthday screen is neutral and does not reveal the minimum age. A one-time "Your teen account" sheet explains the protections. **Supabase users run `supabase/migrations/0007_age_16.sql` once.** See the README table and `docs/threat-model.md`.

**Design.** Rebuilt around imagery: a live video hero on Home, a full-bleed video Welcome screen, vivid poster-style live cards, giant wide (Unbounded) headlines, frosted glass over real content, a floating glass tab bar with a sliding lens, big gradient pill buttons, and a live backdrop (drifting colour fields, iridescent sheen, glossy bubbles, sparkles) from the Y2K / liquid-glass references. New motion system (`core/motion.dart`). See `docs/design-system.md`.

**Demo videos.** The five clips you supplied are the demo Feed (dinosaur costume, karaoke, surprise splash, fountain walk, slackline). They are re-encoded for streaming (12 MB down to 3.7 MB), served by the dev server at `/demo` with poster frames, shown instantly while the video loads, and used for the Home "Trending dares" row, profile thumbnails and the Welcome screen.

**Code.** `server/src/profile/age.ts` (bands), `policy` (teen floor and word rules), `engine` (session band), `realtime/manager.ts` and `http/app.ts` (separation), `social/service.ts`. 14 new server tests (83 total). Renamed `adultVerifiedAt` to `ageVerifiedAt` (API field and DB column).

## Update 6
- **Performance**: only the highlighted panels (tab bar, Cipher card, Go live and Duel tiles, profile-style highlights) animate; quiet panels are painted once. All blur filters in the animation were removed, the animation runs at ~30 fps, and glass blur is lighter. Settings has a switch, *Animated background and glow*, to turn all motion off.
- **Wires**: the wires themselves now wave (a gentle wave travels along each curve and the curve bends with it), in the background and inside panels. The travelling white sparks are gone.
- **Profile**: rebuilt in a minimal short-video-app layout: avatar, three numbers (Completed, Points, Likes), Edit profile / Rewards / share buttons, bio, then icon tabs (Videos, Rounds, Badges) over a tight 3-column video grid. No glow cards.

## Update 5
- Every panel now has a light that runs around its frame, and the wires inside panels (Cipher, Go live, Duel and all the others) sway and carry a travelling spark of light. Highlighted panels are brighter, quiet panels fainter. Each panel moves out of step with the others.
- The background wires move more, with sparks travelling along them.
- One shared animation clock drives all of it. It stops when the phone's reduced-motion setting is on.

## Update 4
- Avatars replaced by the 12 from `avatars.zip` (`a01` to `a12`). Supabase users run `supabase/migrations/0006_avatars_v3.sql` once.
- Flying dots removed. The background now has long curved light streaks instead.
- Home matches the red reference: one header pill (points, theme, settings), tinted glass feature tiles with a swoosh and chevron button, outlined Chat button, section headers with chevrons.

## Update 3
- Neon outline and light streaks now appear only on key panels (tab bar, Cipher card, profile card, points banner, duels waiting on you). All other cards are quiet glass.
- The background is alive: flowing pools of colour, a light beam that sweeps across, and floating twinkling particles. It loops seamlessly and stops moving if the phone's reduced-motion setting is on.

## Update 2 (look and feel)
- **Logo**: the W symbol is gone. DAREWIRE is now just the word.
- **Cipher**: now a faceless, living 3D orb (no eyes or mouth). He breathes, his surface ripples, a ring orbits him, he tilts toward your finger, squishes when tapped, and his colour and motion show his mood.
- **Avatars**: the ones you crossed out are removed. 10 remain (`a01` to `a12`, renumbered). Supabase users run `supabase/migrations/0005_avatars_v2.sql` once.
- **UI**: every panel is now black glass with a glowing neon edge and curved light streaks (colours per theme), a glossy 3D Create button with a glow ring, a glowing active tab, outline icons, a rebuilt profile (double-ring avatar, glowing points banner, icon stat tiles) and a quick theme button on Home. It applies to every screen and all four themes.

## Update 1

**Branding**: the game is DAREWIRE everywhere (no AFTERDARK tag, no night-only wording). New app icon: a wire-shaped W.

**Design**: four themes in a liquid-glass style, chosen in Settings (Neon is the default): Neon, Aurora, Crimson, Spectrum. New floating tab bar (Home, Feed, a raised Create button, Duels, Profile), new icons, gradient feature tiles, professional fonts (Plus Jakarta Sans and Inter, normal case), and rewritten copy.

**Cipher** now has a face: big shiny eyes, cheeks, a mouth, a glass visor and an antenna. He blinks, his eyes follow your finger, and tapping him squishes him and throws hearts. 11 moods change his expression. Tap him on Home, or open the chat.

**Avatars**: the old 12 are gone. 10 new ones (`a01` to `a12`) cut from your two sheets, plus **choose a photo from your gallery** (Edit profile, first tile).

**Feed** now has two pages you can swipe between: **Live** (people doing dares right now, grouped by "doing dares now" and "waiting for a player") and **Dares** (recorded dare videos). Each video has a Duel button for its author.

**Duels**: challenge any player. Pick one of the ideas (which already respect their boundaries) or write your own (checked by the safety rules). They accept, do it, submit; you approve. Both earn points.

**Points and quests**: points for completed duels and daily quests, a streak calendar, leaderboard and activity list under *Rewards*. There is **no cash-out**; the app says so. See `docs/points-and-rewards.md` before ever adding one.

## First run after replacing your project

1. `cd server && npm install && npm test` (69 tests should pass).
2. Supabase users: run `supabase/migrations/0004_social.sql`.
3. `cd mobile && flutter pub get` (adds `image_picker`), then `dart run tool/patch_platforms.dart` (adds the photo permission on iOS), then `flutter analyze`.
4. If `flutter analyze` reports anything, send it to me. The Flutter code was written without a Flutter SDK and has not been compiled or run.
