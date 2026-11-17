import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// One playback owned by the app rather than by a single screen.
///
/// Keeping the media_kit player alive is what makes the floating window work:
/// leaving the episode detaches the screen but not the stream, so the video
/// keeps playing in the mini player and resumes seamlessly when the viewer
/// expands it again.
class PlaybackSession {
  const PlaybackSession({
    required this.player,
    required this.controller,
    required this.animeId,
    required this.episodeId,
    required this.animeTitle,
    required this.episodeLabel,
    this.attached = true,
    this.surfaceEpoch = 0,
  });

  final Player player;
  final VideoController controller;
  final String animeId;
  final String episodeId;
  final String animeTitle;
  final String episodeLabel;

  /// True while the full player screen is on top. The floating window is only
  /// rendered when this is false.
  final bool attached;

  /// Bumped when the platform destroys the video surface (for example when the
  /// app comes back from picture-in-picture). Re-keying the [controller] widget
  /// re-attaches the texture instead of leaving a black floating window.
  final int surfaceEpoch;

  bool get playable => animeId.isNotEmpty && episodeId.isNotEmpty;

  PlaybackSession copyWith({
    String? animeTitle,
    String? episodeLabel,
    bool? attached,
    int? surfaceEpoch,
  }) => PlaybackSession(
    player: player,
    controller: controller,
    animeId: animeId,
    episodeId: episodeId,
    animeTitle: animeTitle ?? this.animeTitle,
    episodeLabel: episodeLabel ?? this.episodeLabel,
    attached: attached ?? this.attached,
    surfaceEpoch: surfaceEpoch ?? this.surfaceEpoch,
  );
}

/// Owns the single active session. Creating a session for another episode
/// disposes the previous player instead of leaking a decoder.
class PlaybackSessionController extends Notifier<PlaybackSession?> {
  @override
  PlaybackSession? build() {
    ref.onDispose(() => state?.player.dispose());
    return null;
  }

  PlaybackSession acquire({
    required String animeId,
    required String episodeId,
    String animeTitle = '',
    String episodeLabel = '',
  }) {
    final current = state;
    if (current != null && current.episodeId == episodeId) {
      final next = current.copyWith(
        animeTitle: animeTitle.isEmpty ? current.animeTitle : animeTitle,
        episodeLabel: episodeLabel.isEmpty
            ? current.episodeLabel
            : episodeLabel,
        attached: true,
      );
      state = next;
      return next;
    }
    current?.player.dispose();
    final player = Player(
      configuration: const PlayerConfiguration(title: 'Wings'),
    );
    final session = PlaybackSession(
      player: player,
      controller: VideoController(player),
      animeId: animeId,
      episodeId: episodeId,
      animeTitle: animeTitle,
      episodeLabel: episodeLabel,
    );
    state = session;
    return session;
  }

  void updateMeta({String? animeTitle, String? episodeLabel}) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      animeTitle: animeTitle,
      episodeLabel: episodeLabel,
    );
  }

  /// Called when the player screen is left: the session survives so the video
  /// keeps playing in the floating window.
  void detach() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(attached: false);
  }

  void markAttached() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(attached: true);
  }

  /// Forces the floating window to rebuild its video surface.
  ///
  /// Android releases the surface when the activity moves into
  /// picture-in-picture; without a rebuild the mini player came back blank or
  /// was skipped entirely on the way home.
  void refreshSurface() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(surfaceEpoch: current.surfaceEpoch + 1);
  }

  Future<void> close() async {
    final current = state;
    state = null;
    await current?.player.dispose();
  }
}

final playbackSessionProvider =
    NotifierProvider<PlaybackSessionController, PlaybackSession?>(
      PlaybackSessionController.new,
    );
