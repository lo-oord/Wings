import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/router/app_router.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/picture_in_picture.dart';
import '../../core/utils/tr.dart';
import 'playback_session.dart';

/// Hosts the floating window above every route.
///
/// The session itself lives outside the widget tree, so navigating away from
/// the episode only hides the full screen — the stream keeps playing here,
/// exactly like a YouTube mini player, with close and expand actions.
class MiniPlayerHost extends ConsumerStatefulWidget {
  const MiniPlayerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MiniPlayerHost> createState() => _MiniPlayerHostState();
}

class _MiniPlayerHostState extends ConsumerState<MiniPlayerHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPip());
  }

  /// Picture-in-picture follows the session, not the player screen.
  ///
  /// It used to be disabled when the full player was left, which is exactly
  /// when the floating window appears — so leaving the app closed the video
  /// instead of shrinking it.
  void _syncPip() {
    if (!mounted) return;
    final session = ref.read(playbackSessionProvider);
    unawaited(PictureInPictureService.setEnabled(session?.playable ?? false));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(playbackSessionProvider);
    ref.listen(playbackSessionProvider, (previous, next) {
      unawaited(PictureInPictureService.setEnabled(next?.playable ?? false));
    });
    final visible = session != null && !session.attached;
    return Stack(
      children: <Widget>[
        widget.child,
        // [_MiniPlayer] builds a `Positioned`, so it must be a direct child of
        // the Stack. Wrapping it in TweenAnimationBuilder/Transform (as it used
        // to be) put a render object between the two, which Flutter rejects as
        // invalid parent data: the Stack never laid out again and the whole app
        // turned into a grey screen until it was restarted.
        if (visible)
          _MiniPlayer(
            key: ValueKey<String>(session.episodeId),
            session: session,
          ),
      ],
    );
  }
}

class _MiniPlayer extends ConsumerStatefulWidget {
  const _MiniPlayer({super.key, required this.session});

  final PlaybackSession session;

  @override
  ConsumerState<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<_MiniPlayer> {
  static const double _width = 208;
  static const double _height = 117;

  Offset? _offset;
  double _dragDy = 0;

  void _expand() {
    ref.read(playbackSessionProvider.notifier).markAttached();
    ref
        .read(routerProvider)
        .push(
          RoutePaths.watch(
            animeId: widget.session.animeId,
            episodeId: widget.session.episodeId,
          ),
        );
  }

  Future<void> _close() async {
    await ref.read(playbackSessionProvider.notifier).close();
  }

  Future<void> _toggle() async {
    final player = widget.session.player;
    if (player.state.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final media = MediaQuery.sizeOf(context);
    final offset =
        _offset ??
        Offset(media.width - _width - Space.md, media.height - _height - 96);

    return Positioned(
      left: offset.dx.clamp(0, (media.width - _width).clamp(0, media.width)),
      top: offset.dy.clamp(0, (media.height - _height).clamp(0, media.height)),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.85, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Transform.scale(
          scale: value,
          alignment: AlignmentDirectional.bottomEnd,
          child: Opacity(opacity: value.clamp(0, 1), child: child),
        ),
        child: GestureDetector(
          onPanStart: (_) => setState(() => _dragDy = 0),
          onPanUpdate: (details) {
            setState(() {
              _dragDy += details.delta.dy;
              _offset = Offset(
                (offset.dx + details.delta.dx).clamp(
                  0,
                  (media.width - _width).clamp(0, media.width),
                ),
                (offset.dy + details.delta.dy).clamp(
                  0,
                  (media.height - _height).clamp(0, media.height),
                ),
              );
            });
          },
          // YouTube's gestures: swipe up to go full screen, swipe down to dismiss
          // the window while keeping the session's position for later.
          onPanEnd: (details) async {
            final dy = _dragDy;
            setState(() => _dragDy = 0);
            if (dy < -70) {
              await AppFeedback.tap();
              if (mounted) _expand();
            } else if (dy > 70) {
              await AppFeedback.tap();
              if (mounted) await _close();
            }
          },
          onTap: _expand,
          child: Material(
            elevation: 12,
            color: Colors.black,
            borderRadius: BorderRadius.circular(Radii.md),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: _width,
              height: _height,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Video(
                    key: ValueKey<String>(
                      '${widget.session.episodeId}:${widget.session.surfaceEpoch}',
                    ),
                    controller: widget.session.controller,
                    controls: NoVideoControls,
                    fit: BoxFit.cover,
                    fill: Colors.black,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.45),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: 2,
                    end: 2,
                    child: _MiniButton(
                      icon: Icons.close_rounded,
                      tooltip: Tr.of(context, ar: 'إلغاء', en: 'Close'),
                      onTap: _close,
                    ),
                  ),
                  PositionedDirectional(
                    bottom: 2,
                    start: 2,
                    child: _MiniButton(
                      icon: Icons.open_in_full_rounded,
                      tooltip: Tr.of(context, ar: 'توسيع', en: 'Expand'),
                      onTap: _expand,
                    ),
                  ),
                  PositionedDirectional(
                    bottom: 2,
                    end: 2,
                    child: _MiniButton(
                      icon: Icons.play_arrow_rounded,
                      tooltip: Tr.of(context, ar: 'تشغيل', en: 'Play'),
                      player: widget.session.player,
                      onTap: _toggle,
                    ),
                  ),
                  PositionedDirectional(
                    start: Space.sm,
                    bottom: Space.sm + 24,
                    end: Space.sm,
                    child: Text(
                      widget.session.episodeLabel.isEmpty
                          ? widget.session.animeTitle
                          : widget.session.episodeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        shadows: <Shadow>[
                          Shadow(color: palette.overlay, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.player,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Player? player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player?.stream.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        final resolved = icon == Icons.play_arrow_rounded
            ? (playing ? Icons.pause_rounded : Icons.play_arrow_rounded)
            : icon;
        return Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.pill),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(resolved, size: 17, color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}
