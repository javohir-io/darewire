#!/usr/bin/env bash
# One-time project setup. Requires Flutter 3.22+ on PATH.
set -euo pipefail
cd "$(dirname "$0")"
flutter create . --project-name darewire --org com.darewire --platforms=android,ios
rm -f test/widget_test.dart   # the sample test that `flutter create` adds refers to a MyApp this app does not have
dart run tool/patch_platforms.dart
flutter pub get
dart run flutter_launcher_icons
[ -f env.json ] || cp env.example.json env.json
echo "Done. Edit env.json, then:  flutter run --dart-define-from-file=env.json"
