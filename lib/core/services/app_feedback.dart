import 'package:flutter/services.dart';

/// Short, throttled audio and haptic cues for small interactions.
///
/// Everything here is deliberately restrained: one system click plus one light
/// haptic pulse, never a burst of sounds, and repeated taps inside [_window]
/// are ignored so scrolling a list or hammering a button cannot turn into a
/// barrage. The platform already silences system sounds when the device is in
/// silent mode, so the app never needs its own volume control.
class AppFeedback {
  const AppFeedback._();

  /// Minimum gap between two cues, shared by every caller.
  static const Duration _window = Duration(milliseconds: 110);

  static DateTime? _last;

  static bool get _ready {
    final now = DateTime.now();
    final last = _last;
    if (last != null && now.difference(last) < _window) return false;
    _last = now;
    return true;
  }

  static Future<void> _cue({required bool sound, required bool strong}) async {
    if (!_ready) return;
    try {
      if (sound) await SystemSound.play(SystemSoundType.click);
      if (strong) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.selectionClick();
      }
    } on Object {
      // A device without a speaker or vibrator simply stays quiet.
    }
  }

  /// A reaction was added (like or dislike).
  static Future<void> reaction() => _cue(sound: true, strong: true);

  /// A reaction was removed.
  static Future<void> reactionRemoved() => _cue(sound: false, strong: false);

  /// A comment or a reply was published.
  static Future<void> publish() => _cue(sound: true, strong: true);

  /// A comment or a reply was deleted.
  static Future<void> remove() => _cue(sound: false, strong: true);

  /// A light confirmation for secondary actions (save, copy, share).
  static Future<void> tap() => _cue(sound: false, strong: false);
}
