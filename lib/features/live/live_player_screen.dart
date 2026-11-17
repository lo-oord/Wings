import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../data/models/live_channel.dart';
import '../../data/sources/live_source.dart';
import 'live_widgets.dart';

/// Full-screen live television playback with the channel's published schedule.
///
/// The stream is opened directly (HLS) with the referer the provider requires;
/// there is no download, seek bar or progress, because the source is live.
class LivePlayerScreen extends ConsumerStatefulWidget {
  const LivePlayerScreen({super.key, required this.channelId, this.channel});

  final String channelId;
  final LiveChannel? channel;

  @override
  ConsumerState<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends ConsumerState<LivePlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  LiveChannel? _channel;
  Object? _error;
  bool _playing = false;
  bool _buffering = true;
  bool _controlsVisible = true;
  bool _muted = false;
  Timer? _hideControls;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _player = Player(configuration: const PlayerConfiguration(title: 'Wings'));
    _controller = VideoController(_player);
    _player.stream.playing.listen((value) {
      if (mounted) setState(() => _playing = value);
    });
    _player.stream.buffering.listen((value) {
      if (mounted) setState(() => _buffering = value);
    });
    _player.stream.error.listen((value) {
      if (!mounted || value.isEmpty) return;
      setState(() => _error = value);
    });
    _player.stream.volume.listen((value) {
      if (!mounted) return;
      final muted = value <= 0;
      if (muted != _muted) setState(() => _muted = muted);
    });
    _scheduleHideControls();
    unawaited(
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final channel = await _resolveChannel();
    if (!mounted) return;
    setState(() {
      _channel = channel;
      _error = null;
    });
    if (channel == null || !channel.hasStream) {
      setState(() => _error = 'live-unavailable');
      return;
    }
    try {
      await _player.open(
        Media(channel.streamUrl, httpHeaders: channel.headers),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<LiveChannel?> _resolveChannel() async {
    final provided = widget.channel;
    if (provided != null && provided.hasStream) {
      // Fill in the schedule in the background; playback can start at once.
      unawaited(_refreshSchedule());
      return provided;
    }
    try {
      final channels = await ref.read(liveSourceProvider).channels();
      for (final channel in channels) {
        if (channel.id == widget.channelId) return channel;
      }
    } on Object {
      // Fall through to the pinned channel.
    }
    for (final channel in LiveSource.seeds) {
      if (channel.id == widget.channelId) return channel;
    }
    return null;
  }

  Future<void> _refreshSchedule() async {
    try {
      final channels = await ref.read(liveSourceProvider).channels(force: true);
      if (!mounted) return;
      for (final channel in channels) {
        if (channel.id == widget.channelId) {
          setState(() => _channel = channel);
          return;
        }
      }
    } on Object {
      // A channel without a schedule still plays.
    }
  }

  /// Controls fade out on their own, like a television overlay, so the live
  /// picture is never covered by a permanent bar.
  void _scheduleHideControls() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    _scheduleHideControls();
  }

  Future<void> _toggleMute() async {
    await _player.setVolume(_muted ? 100 : 0);
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    _player.dispose();
    unawaited(
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = _channel;
    final palette = context.palette;
    final programs = channel?.upcoming ?? const <LiveProgram>[];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(
                    color: Colors.black,
                    child: _error != null
                        ? _LiveError(onRetry: _start)
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleControls,
                            // No timeline: a live stream has no start or end to
                            // scrub, so the controls are play, mute and retry
                            // only — the seek bar of the shared player is gone.
                            child: Video(
                              controller: _controller,
                              controls: NoVideoControls,
                              fill: Colors.black,
                            ),
                          ),
                  ),
                  AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          PositionedDirectional(
                            top: Space.sm,
                            start: Space.sm,
                            child: _OverlayButton(
                              icon: Icons.arrow_back_rounded,
                              onTap: () => Navigator.of(context).maybePop(),
                            ),
                          ),
                          if (channel != null)
                            PositionedDirectional(
                              top: Space.sm,
                              end: Space.sm,
                              child: Row(
                                children: <Widget>[
                                  const LiveBadge(),
                                  const SizedBox(width: Space.xs),
                                  _OverlayButton(
                                    icon: Icons.refresh_rounded,
                                    onTap: _start,
                                  ),
                                ],
                              ),
                            ),
                          Center(
                            child: _OverlayButton(
                              icon: _playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 30,
                              padding: 14,
                              onTap: _togglePlay,
                            ),
                          ),
                          PositionedDirectional(
                            bottom: Space.sm,
                            start: Space.sm,
                            child: Row(
                              children: <Widget>[
                                _OverlayButton(
                                  icon: _muted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  onTap: _toggleMute,
                                ),
                                const SizedBox(width: Space.xs),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Space.sm,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(
                                      Radii.pill,
                                    ),
                                  ),
                                  child: Text(
                                    Tr.of(context, ar: 'مباشر', en: 'Live'),
                                    style: context.text.labelSmall?.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_buffering && _error == null)
                    const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: palette.background,
                child: ListView(
                  padding: const EdgeInsets.all(Space.lg),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            channel?.name ??
                                Tr.of(context, ar: 'قناة مباشرة', en: 'Live'),
                            style: context.text.titleLarge,
                          ),
                        ),
                        if (channel != null)
                          IconButton(
                            tooltip: Tr.of(
                              context,
                              ar: _playing ? 'إيقاف مؤقت' : 'تشغيل',
                              en: _playing ? 'Pause' : 'Play',
                            ),
                            onPressed: () =>
                                _playing ? _player.pause() : _player.play(),
                            icon: Icon(
                              _playing
                                  ? Icons.pause_circle_rounded
                                  : Icons.play_circle_rounded,
                              size: 34,
                              color: palette.primary,
                            ),
                          ),
                      ],
                    ),
                    if (channel != null && channel.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Text(
                          channel.description,
                          style: context.text.bodySmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    const SizedBox(height: Space.lg),
                    Text(
                      Tr.of(context, ar: 'جدول اليوم', en: 'Today'),
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: Space.sm),
                    if (programs.isEmpty)
                      Text(
                        Tr.of(
                          context,
                          ar: 'لا يوجد جدول منشور لهذه القناة الآن.',
                          en: 'No schedule is published for this channel yet.',
                        ),
                        style: context.text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      )
                    else
                      for (final program in programs)
                        _ScheduleRow(
                          program: program,
                          isCurrent: channel?.currentProgram == program,
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.program, required this.isCurrent});

  final LiveProgram program;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 46,
            child: Text(
              program.timeLabel,
              style: context.text.labelSmall?.copyWith(
                color: isCurrent ? palette.primary : palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (isCurrent) ...<Widget>[
                      const LiveBadge(compact: true),
                      const SizedBox(width: Space.xs),
                    ],
                    Expanded(
                      child: Text(
                        program.title,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (program.episodeNumber != null)
                  Text(
                    Tr.of(
                      context,
                      ar: 'الحلقة ${program.episodeNumber}',
                      en: 'Episode ${program.episodeNumber}',
                    ),
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.onTap,
    this.size = 19,
    this.padding = 7,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Icon(icon, size: size, color: Colors.white),
        ),
      ),
    );
  }
}

class _LiveError extends StatelessWidget {
  const _LiveError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.live_tv_rounded, color: Colors.white70, size: 32),
          const SizedBox(height: Space.sm),
          Text(
            Tr.of(
              context,
              ar: 'تعذّر تشغيل البث لهذه القناة الآن.',
              en: 'This live stream could not be played right now.',
            ),
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            child: Text(Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry')),
          ),
        ],
      ),
    );
  }
}
