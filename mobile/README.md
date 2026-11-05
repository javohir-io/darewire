# DAREWIRE mobile app (Flutter)

```bash
./setup.sh            # Windows: ./setup.ps1  (flutter create, platform permissions, packages, icons)
# edit env.json (API_URL, optionally SUPABASE_URL / SUPABASE_ANON_KEY)
flutter run --dart-define-from-file=env.json
flutter analyze && flutter test
```

Folders: `lib/core` (theme with four palettes, router, config), `lib/data` (models, API client, auth, live media), `lib/state` (Riverpod providers and controllers), `lib/gfx` (backdrop, liquid glass, wordmark, Cipher the living orb), `lib/ui` (screens, game panels, shared widgets), `assets/avatars` (12 avatars), `assets/brand` (app icon).

Design notes are in [`../docs/design-system.md`](../docs/design-system.md).
