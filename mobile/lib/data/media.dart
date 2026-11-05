import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';
import 'api.dart';

/// Live video through LiveKit. The server decides who may publish: it only returns a publish-capable token to the
/// current Player of the session, and it can cut the stream at any time (moderator action or Safety Stop path).
class LiveMedia extends ChangeNotifier {
  final ApiClient api;
  final String sessionId;
  LiveMedia(this.api, this.sessionId);

  Room? _room;
  bool canPublish = false;
  bool connecting = false;
  String? error; // shown as a calm placeholder: the game continues without video
  bool _disposed = false;

  VideoTrack? get track {
    final room = _room;
    if (room == null) return null;
    final lp = room.localParticipant;
    if (canPublish && lp != null) {
      final t = _firstVideo(lp);
      if (t != null) return t;
    }
    for (final p in room.remoteParticipants.values) {
      final t = _firstVideo(p);
      if (t != null) return t;
    }
    return null;
  }

  VideoTrack? _firstVideo(Participant p) {
    for (final pub in p.trackPublications.values) {
      final t = pub.track;
      if (pub.kind == TrackType.VIDEO && t is VideoTrack && !pub.muted) return t;
    }
    return null;
  }

  /// Connect (or reconnect when the user's role changed). Safe to call repeatedly.
  Future<void> connect({required bool wantPublish}) async {
    if (_disposed || connecting) return;
    if (_room != null && canPublish == wantPublish) return;
    connecting = true;
    error = null;
    notifyListeners();
    try {
      await _close();
      final t = await api.mediaToken(sessionId);
      final room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      room.addListener(_onRoomChange);
      await room.connect(t.url, t.token);
      _room = room;
      canPublish = t.canPublish;
      if (t.canPublish) {
        try {
          await room.localParticipant?.setCameraEnabled(true);
          await room.localParticipant?.setMicrophoneEnabled(true);
        } catch (_) {
          error = 'Camera or microphone permission was denied. Enable them in Settings to go live.';
        }
      }
    } on ApiException catch (e) {
      error = e.code == 'media_unavailable' ? 'Live video is not configured on this server. The game still works.' : e.message;
    } catch (_) {
      error = 'Could not connect to live video.';
    }
    connecting = false;
    if (!_disposed) notifyListeners();
  }

  void _onRoomChange() {
    if (!_disposed) notifyListeners();
  }

  Future<void> flipCamera() async {
    final pub = _room?.localParticipant?.videoTrackPublications.firstOrNull;
    final t = pub?.track;
    if (t is LocalVideoTrack) {
      final pos = t.currentOptions is CameraCaptureOptions ? (t.currentOptions as CameraCaptureOptions).cameraPosition : CameraPosition.front;
      await t.setCameraPosition(pos == CameraPosition.front ? CameraPosition.back : CameraPosition.front);
    }
  }

  Future<void> _close() async {
    final r = _room;
    _room = null;
    if (r != null) {
      r.removeListener(_onRoomChange);
      try {
        await r.disconnect();
        await r.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _close();
    super.dispose();
  }
}
