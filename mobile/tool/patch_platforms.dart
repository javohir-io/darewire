// Run once after `flutter create`:  dart run tool/patch_platforms.dart
// Adds the permissions DAREWIRE needs (camera, microphone, photo library for profile pictures, network) to the generated Android and iOS projects.
// Idempotent: safe to run again.
import 'dart:io';

bool _patch(String path, String Function(String) edit, String marker) {
  final f = File(path);
  if (!f.existsSync()) {
    stdout.writeln('skip   $path (not found)');
    return false;
  }
  final src = f.readAsStringSync();
  if (src.contains(marker)) {
    stdout.writeln('ok     $path (already patched)');
    return true;
  }
  final out = edit(src);
  if (out == src) {
    stdout.writeln('WARN   $path (pattern not found, patch by hand: see README)');
    return false;
  }
  f.writeAsStringSync(out);
  stdout.writeln('patch  $path');
  return true;
}

void main() {
  const androidPerms = '''
    <!-- DAREWIRE: live video (LiveKit / WebRTC) -->
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false"/>
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
''';

  _patch('android/app/src/main/AndroidManifest.xml', (s) {
    final i = s.indexOf('<application');
    return i < 0 ? s : s.replaceRange(i, i, '$androidPerms\n    ');
  }, 'DAREWIRE: live video');

  // Plain http://10.0.2.2 (the dev server) is only allowed in DEBUG builds.
  _patch('android/app/src/debug/AndroidManifest.xml', (s) {
    final i = s.indexOf('</manifest>');
    return i < 0 ? s : s.replaceRange(i, i, '    <application android:usesCleartextTraffic="true"/>\n');
  }, 'usesCleartextTraffic');

  _patch('ios/Runner/Info.plist', (s) {
    final i = s.lastIndexOf('</dict>');
    if (i < 0) return s;
    const add = '''
	<key>NSCameraUsageDescription</key>
	<string>DAREWIRE uses your camera so the audience can watch you take on a dare. It is only on while you are the player.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>DAREWIRE lets you pick a photo from your library as your profile picture. It is only used when you choose one.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>DAREWIRE uses your microphone so the audience can hear you while you are the player.</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
''';
    return s.replaceRange(i, i, add);
  }, 'NSCameraUsageDescription');

  _patch('ios/Podfile', (s) {
    final re = RegExp(r"#?\s*platform :ios, '[0-9.]+'");
    return re.hasMatch(s) ? s.replaceFirst(re, "platform :ios, '13.0'") : s;
  }, "platform :ios, '13.0'");

  stdout.writeln('\nDone. Next: flutter pub get && dart run flutter_launcher_icons');
}
