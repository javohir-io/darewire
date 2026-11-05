# One-time project setup (Windows PowerShell). Requires Flutter 3.22+ on PATH.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
flutter create . --project-name darewire --org com.darewire --platforms=android,ios
dart run tool/patch_platforms.dart
flutter pub get
dart run flutter_launcher_icons
if (-not (Test-Path env.json)) { Copy-Item env.example.json env.json }
Write-Host "Done. Edit env.json, then:  flutter run --dart-define-from-file=env.json"
