import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';

/// One video, one player.
///
/// Every instance owns its `media_kit` player and disposes it when the widget
/// leaves the tree, so a feed can never keep a pile of decoders alive. Playback
/// is driven by [active] and by the app lifecycle: when the card scrolls away,
/// another card becomes active, or Wings goes to the background, the stream is
/// paused instead of decoding out of sight.
class CommunityVideo extends StatefulWidget {
  const CommunityVideo({
    super.key,
    this.url,
    this.localPath,
    this.aspectRatio,
    this.active = true,
    this.loop = false,
    this.startMuted = false,
    this.fit = BoxFit.cover,
    this.showChrome = true,
    this.onPlayedThreeSeconds,
    this.posterUrl,
  });

  final String? url;
  final String? localPath;
  final double? aspectRatio;

  /// The video is allowed to play. Reels flip this per page.
  final bool active;

  final bool loop;
  final bool startMuted;
  final BoxFit fit;

  /// Compact cards hide the progress bar until the first tap.
  final bool showChrome;

  /// Called once, after three seconds of real playback.
  final VoidCallback? onPlayedThreeSeconds;

  final String? posterUrl;

  @override
  State<CommunityVideo> createState() => _CommunityVideoState();
}

class _CommunityVideoState extends State<CommunityVideo>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;

  bool _ready = false;
  bool _buffering = true;
  bool _failed = false;
  bool _muted = false;
  bool _playing = false;
  bool _counted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _wasPlayingBeforeBackground = false;

  String get _source {
    final local = widget.localPath;
    if (local != null && local.isNotEmpty) return Uri.file(local).toString();
    return widget.url ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _muted = widget.startMuted;
    _player = Player();
    _controller = VideoController(_player);
    _bind();
    unawaited(_open());
  }

  void _bind() {
    _positionSub = _player.stream.position.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
      if (!_counted &&
          position.inMilliseconds >= 3000 &&
          _playing &&
          widget.onPlayedThreeSeconds != null) {
        _counted = true;
        widget.onPlayedThreeSeconds!();
      }
    });
    _completedSub = _player.stream.completed.listen((completed) {
      if (!mounted || !completed) return;
      if (widget.loop) {
        unawaited(_player.seek(Duration.zero));
        unawaited(_player.play());
      } else {
        setState(() => _playing = false);
      }
    });
    _errorSub = _player.stream.error.listen((message) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _buffering = false;
      });
    });
    _player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _buffering = buffering);
    });
    _player.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });
  }

  Future<void> _open() async {
    final source = _source;
    if (source.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _failed = false;
      _ready = false;
      _buffering = true;
    });
    try {
      await _player.open(Media(source), play: false);
      if (!mounted) return;
      await _player.setVolume(_muted ? 0 : 100);
      setState(() => _ready = true);
      if (widget.active) unawaited(_player.play());
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _buffering = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant CommunityVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        unawaited(_player.play());
      } else {
        unawaited(_player.pause());
      }
    }
    if (oldWidget.url != widget.url ||
        oldWidget.localPath != widget.localPath) {
      unawaited(_open());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_wasPlayingBeforeBackground && widget.active) {
        unawaited(_player.play());
      }
      return;
    }
    _wasPlayingBeforeBackground = _playing;
    unawaited(_player.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_positionSub?.cancel());
    unawaited(_completedSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  void _toggle() {
    if (_failed) {
      unawaited(_open());
      return;
    }
    if (!_ready) return;
    unawaited(_player.playOrPause());
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    unawaited(_player.setVolume(_muted ? 0 : 100));
  }

  @override
  Widget build(BuildContext context) {
    final ratio =
        widget.aspectRatio ?? (_duration.inMilliseconds > 0 ? 16 / 9 : 16 / 9);
    return AspectRatio(
      aspectRatio: ratio <= 0 ? 16 / 9 : ratio,
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(
              color: Colors.black,
              child: _failed
                  ? const SizedBox.shrink()
                  : Video(
                      controller: _controller,
                      fit: widget.fit,
                      controls: NoVideoControls,
                    ),
            ),
            if (!_ready && !_failed)
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            if (_buffering && _ready)
              const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_failed) _errorState(context),
            if (_ready && !_failed)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _toggle,
                    child: AnimatedOpacity(
                      opacity: _playing ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.18),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 54,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_ready && widget.showChrome)
              PositionedDirectional(
                end: 6,
                bottom: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _ChromeButton(
                      icon: _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      onTap: _toggleMute,
                    ),
                    if (widget.url != null && widget.url!.isNotEmpty)
                      _ChromeButton(
                        icon: Icons.fullscreen_rounded,
                        onTap: () => _openFullscreen(context),
                      ),
                  ],
                ),
              ),
            if (_ready && _duration.inMilliseconds > 0)
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: (_position.inMilliseconds / _duration.inMilliseconds)
                      .clamp(0.0, 1.0),
                  minHeight: 2,
                  backgroundColor: Colors.white24,
                ),
              ),
            if (!_ready && !_failed && (widget.posterUrl ?? '').isNotEmpty)
              const IgnorePointer(child: SizedBox.shrink()),
            if (_duration > Duration.zero && !_playing)
              PositionedDirectional(
                start: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _format(_position, _duration),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(BuildContext context) => Container(
    color: Colors.black,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(Space.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.videocam_off_outlined,
          color: Colors.white70,
          size: 26,
        ),
        const SizedBox(height: Space.sm),
        Text(
          Tr.of(
            context,
            ar: 'تعذّر تشغيل الفيديو.',
            en: 'This video could not be played.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: Space.xs),
        TextButton(
          onPressed: _open,
          child: Text(
            Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry'),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Future<void> _openFullscreen(BuildContext context) async {
    final url = widget.url;
    if (url == null || url.isEmpty) return;
    unawaited(_player.pause());
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) =>
            _FullscreenVideo(url: url, aspectRatio: widget.aspectRatio),
      ),
    );
    if (mounted && widget.active) unawaited(_player.play());
  }

  static String _format(Duration position, Duration duration) {
    String two(int value) => value.toString().padLeft(2, '0');
    final total = duration.inSeconds;
    final now = position.inSeconds.clamp(0, total);
    return '${two(now ~/ 60)}:${two(now % 60)} / '
        '${two(total ~/ 60)}:${two(total % 60)}';
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}

class _FullscreenVideo extends StatelessWidget {
  const _FullscreenVideo({required this.url, this.aspectRatio});

  final String url;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            context.isRtl
                ? Icons.arrow_forward_rounded
                : Icons.arrow_back_rounded,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: CommunityVideo(
          url: url,
          aspectRatio: aspectRatio,
          fit: BoxFit.contain,
          active: true,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: Text(
            Tr.of(context, ar: 'ملء الشاشة', en: 'Full screen'),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted, fontSize: 10),
          ),
        ),
      ),
    );
  }
}
