# One-time project setup (Windows PowerShell). Requires Flutter 3.22+ on PATH.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
flutter create . --project-name darewire --org com.darewire --platforms=android,ios
Remove-Item test/widget_test.dart -ErrorAction SilentlyContinue   # the sample test that `flutter create` adds refers to a MyApp this app does not have
dart run tool/patch_platforms.dart
flutter pub get
dart run flutter_launcher_icons
if (-not (Test-Path env.json)) { Copy-Item env.example.json env.json }
Write-Host "Done. Edit env.json, then:  flutter run --dart-define-from-file=env.json"
