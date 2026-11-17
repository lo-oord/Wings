import 'package:flutter/services.dart';

/// Android picture-in-picture bridge.
///
/// The in-app floating player covers navigation inside Wings; this bridge is
/// what keeps the episode visible when the viewer leaves the app entirely, the
/// same way YouTube shrinks a video into the system window. Everything is
/// best-effort: a platform without PiP simply returns false and the app keeps
/// its own mini player.
class PictureInPictureService {
  const PictureInPictureService._();

  static const MethodChannel _channel = MethodChannel('wings/pip');

  /// The system window is only requested while a playback session exists.
  static Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on PlatformException {
      // Desktop or an Android version without PiP support.
    } on MissingPluginException {
      // Same as above: the app still works with the in-app mini player.
    }
  }

  /// Asks Android to shrink the activity into the floating window.
  static Future<bool> enter() async {
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
