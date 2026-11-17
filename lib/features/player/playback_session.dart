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

  bool get playable => animeId.isNotEmpty && episodeId.isNotEmpty;

  PlaybackSession copyWith({
    String? animeTitle,
    String? episodeLabel,
    bool? attached,
  }) => PlaybackSession(
    player: player,
    controller: controller,
    animeId: animeId,
    episodeId: episodeId,
    animeTitle: animeTitle ?? this.animeTitle,
    episodeLabel: episodeLabel ?? this.episodeLabel,
    attached: attached ?? this.attached,
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
