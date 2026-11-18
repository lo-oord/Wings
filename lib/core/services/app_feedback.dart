import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Short, distinctive audio + haptic cues for small interactions.
///
/// Each cue is its own tiny WAV shipped in `assets/sounds`, played through a
/// pooled low-latency player: a rising two-note chime for a like, a muted
/// falling note for a dislike, a soft wooden pop for a published comment and a
/// feather-light tick when something is removed. One pooled player per clip
/// means a repeated tap restarts the clip instead of stacking players, and
/// [Future.wait] never lets a missing speaker block the haptic.
///
/// Everything here stays restrained: taps inside [_window] are ignored, so
/// scrolling a comment list or hammering a reaction button never turns into a
/// barrage.
class AppFeedback {
  const AppFeedback._();

  /// Minimum gap between two cues, shared by every caller.
  static const Duration _window = Duration(milliseconds: 110);

  static DateTime? _last;

  /// One reusable player per clip.
  static final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};

  static bool get _ready {
    final now = DateTime.now();
    final last = _last;
    if (last != null && now.difference(last) < _window) return false;
    _last = now;
    return true;
  }

  static Future<void> _play(String clip) async {
    try {
      final player = _players.putIfAbsent(
        clip,
        () => AudioPlayer(playerId: 'wings-sfx-$clip'),
      );
      await player.stop();
      await player.setVolume(0.55);
      await player.play(
        AssetSource('sounds/$clip.wav'),
        mode: PlayerMode.lowLatency,
      );
    } on Object {
      // A device without a speaker simply stays quiet.
    }
  }

  static Future<void> _cue({String? clip, required bool strong}) async {
    if (!_ready) return;
    final cues = <Future<void>>[
      if (clip != null) _play(clip),
      strong ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick(),
    ];
    for (final cue in cues) {
      try {
        await cue;
      } on Object {
        // Haptics and sound are independent: never let one silence the other.
      }
    }
  }

  /// A like was added: a bright two-note rise.
  static Future<void> reaction() => _cue(clip: 'like', strong: true);

  /// A dislike was added: one short, duller falling note.
  static Future<void> dislike() => _cue(clip: 'dislike', strong: true);

  /// A reaction was removed (or a reaction was switched to the other one).
  static Future<void> reactionRemoved() => _cue(clip: 'undo', strong: false);

  /// A comment or a reply was published: a soft pop.
  static Future<void> publish() => _cue(clip: 'comment', strong: true);

  /// A comment or a reply was deleted.
  static Future<void> remove() => _cue(clip: 'undo', strong: true);

  /// A light confirmation for secondary actions (save, copy, share).
  static Future<void> tap() => _cue(strong: false);
}
