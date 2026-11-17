import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/services/picture_in_picture.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_cards.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/anime.dart';
import '../../data/models/library.dart';
import '../social/episode_social_section.dart';
import 'playback_session.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.animeId,
    required this.episodeId,
    this.initialAnime,
  });

  final String animeId;
  final String episodeId;
  final Anime? initialAnime;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  PlaybackSession? _session;
  bool _viewRegistered = false;
  Timer? _viewTimer;

  /// Position to restore when the floating player is expanded again, so the
  /// viewer continues exactly where they were instead of restarting.
  Duration _resumeFrom = Duration.zero;

  Anime? _anime;
  List<AnimeEpisode> _episodes = const <AnimeEpisode>[];
  AnimeEpisode? _episode;
  List<StreamServer> _servers = const <StreamServer>[];
  String? _activeQuality;
  String? _activeServerName;
  List<StreamServer> _candidates = const <StreamServer>[];
  int _candidateIndex = 0;
  bool _fallbackInProgress = false;

  bool _loading = true;
  Object? _error;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  bool _completed = false;
  bool _seeking = false;
  double _seekValue = 0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  String? _playbackError;
  double _speed = 1;

  Timer? _hideTimer;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Reuse the live session when the viewer expands the floating window;
    // otherwise this screen starts a new one.
    final session = ref
        .read(playbackSessionProvider.notifier)
        .acquire(animeId: widget.animeId, episodeId: widget.episodeId);
    _session = session;
    _player = session.player;
    _videoController = session.controller;
    _resumeFrom =
        session.attached && session.player.state.position > Duration.zero
        ? session.player.state.position
        : Duration.zero;
    unawaited(PictureInPictureService.setEnabled(true));
    _attachStreams();
    _bootstrap();
    _saveTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
    _scheduleHide();
  }

  void _attachStreams() {
    _subscriptions.add(
      _player.stream.playing.listen((value) {
        if (mounted) setState(() => _playing = value);
      }),
    );
    _subscriptions.add(
      _player.stream.position.listen((value) {
        if (mounted && !_seeking) setState(() => _position = value);
      }),
    );
    _subscriptions.add(
      _player.stream.duration.listen((value) {
        if (mounted) setState(() => _duration = value);
      }),
    );
    _subscriptions.add(
      _player.stream.buffering.listen((value) {
        if (mounted) setState(() => _buffering = value);
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((value) {
        if (value && mounted) _onCompleted();
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((value) {
        if (!mounted || value.isEmpty) return;
        setState(() => _playbackError = value);
        // A stream that fails on one server is retried on the next one.
        unawaited(_tryNextServer());
      }),
    );
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(animeRepositoryProvider);
      final anime =
          widget.initialAnime ?? await repository.details(widget.animeId);
      final episodes = await repository.episodes(anime);
      final episode =
          episodes.cast<AnimeEpisode?>().firstWhere(
            (item) => item?.id == widget.episodeId,
            orElse: () => null,
          ) ??
          (episodes.isNotEmpty ? episodes.first : null);
      if (!mounted) return;
      setState(() {
        _anime = anime;
        _episodes = episodes;
        _episode = episode;
      });
      ref
          .read(playbackSessionProvider.notifier)
          .updateMeta(
            animeTitle: anime.title,
            episodeLabel: episode == null
                ? ''
                : AppLocalizations.of(context)
                      .commonEpisodeNumber(episode.number),
          );
      if (episode == null) {
        setState(() {
          _loading = false;
          _error = const _NoEpisodes();
        });
        return;
      }
      await _loadEpisode(episode, initial: true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadEpisode(
    AnimeEpisode episode, {
    bool initial = false,
  }) async {
    final anime = _anime;
    if (anime == null) return;
    if (!initial) {
      await _saveProgress(force: true);
      await _player.pause();
    }
    setState(() {
      _loading = true;
      _error = null;
      _playbackError = null;
      _completed = false;
      _episode = episode;
      _position = Duration.zero;
      _duration = Duration.zero;
    });

    try {
      final repository = ref.read(animeRepositoryProvider);
      final servers = await repository.servers(anime, episode);
      // Sources and mirrors often publish the same link twice; keeping one copy
      // per quality+flavour stops the server picker from showing duplicates.
      final unique = <String, StreamServer>{};
      for (final server in servers) {
        unique.putIfAbsent(
          '${server.quality}|${server.flavor.name}|${server.url}',
          () => server,
        );
      }
      _servers = unique.values.toList(growable: false);
      final settings = ref.read(settingsProvider);
      _candidates = _orderCandidates(servers, settings.preferredQuality);
      _candidateIndex = 0;

      var started = false;
      for (var index = 0; index < _candidates.length; index++) {
        if (await _openCandidate(index)) {
          started = true;
          break;
        }
      }
      if (!mounted) return;
      if (!started) {
        setState(() {
          _loading = false;
          _error = const _NoPlayableServer();
        });
        return;
      }
      if (settings.playbackSpeed != 1) {
        _speed = settings.playbackSpeed;
        await _player.setRate(_speed);
      }
      final history = ref
          .read(libraryProvider)
          .history
          .cast<WatchHistoryEntry?>()
          .firstWhere(
            (entry) =>
                entry?.animeId == anime.id && entry?.episodeId == episode.id,
            orElse: () => null,
          );
      if (_resumeFrom > Duration.zero) {
        await _player.seek(_resumeFrom);
        _resumeFrom = Duration.zero;
      } else if (settings.rememberPosition &&
          history != null &&
          history.position.inSeconds > 5 &&
          !history.completed) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _player.seek(history.position);
      }
      if (!mounted) return;
      setState(() => _loading = false);
      if (!_viewRegistered) {
        // A view is only counted for a signed-in account and only after the
        // stream has been running for a moment, so opening and closing an
        // episode by mistake no longer inflates the counter. The repository
        // also stores one viewer document per account, so repeats are free.
        final uid = ref.read(authProvider)?.id ?? '';
        if (uid.isNotEmpty) {
          _viewTimer?.cancel();
          _viewTimer = Timer(const Duration(seconds: 15), () {
            if (!mounted || _viewRegistered) return;
            _viewRegistered = true;
            unawaited(
              ref
                  .read(viewsRepositoryProvider)
                  .registerPlayback(
                    episodeId: episode.id,
                    animeId: anime.id,
                    uid: uid,
                  ),
            );
          });
        }
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  List<StreamServer> _orderCandidates(
    List<StreamServer> servers,
    String preferredQuality,
  ) {
    final candidates = servers
        .where((server) => !server.requiresBrowser)
        .toList(growable: true);
    candidates.sort((a, b) {
      final aPreferred = a.quality == preferredQuality ? 0 : 1;
      final bPreferred = b.quality == preferredQuality ? 0 : 1;
      if (aPreferred != bPreferred) return aPreferred.compareTo(bPreferred);
      return b.qualityRank.compareTo(a.qualityRank);
    });
    return candidates;
  }

  /// Opens one candidate stream, returning whether it could be resolved.
  Future<bool> _openCandidate(int index) async {
    if (index < 0 || index >= _candidates.length) return false;
    _candidateIndex = index;
    final server = _candidates[index];
    final resolved = await ref.read(animeRepositoryProvider).resolve(server);
    if (resolved == null || !mounted) return false;
    setState(() {
      _activeQuality = server.quality;
      _activeServerName = server.name;
      _playbackError = null;
    });
    await _player.open(
      Media(resolved.url, httpHeaders: resolved.headers),
      play: true,
    );
    return true;
  }

  /// Automatic server fallback used when the current stream fails.
  Future<void> _tryNextServer() async {
    if (_fallbackInProgress) return;
    final next = _candidateIndex + 1;
    if (next >= _candidates.length) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _error ?? const _NoPlayableServer();
        });
      }
      return;
    }
    _fallbackInProgress = true;
    try {
      for (var index = next; index < _candidates.length; index++) {
        if (!mounted) return;
        setState(() => _loading = true);
        if (await _openCandidate(index)) {
          if (mounted) setState(() => _loading = false);
          return;
        }
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _error = const _NoPlayableServer();
        });
      }
    } finally {
      _fallbackInProgress = false;
    }
  }

  Future<void> _switchQuality(StreamServer server) async {
    final position = _position;
    final resolved = await ref.read(animeRepositoryProvider).resolve(server);
    if (resolved == null) {
      if (mounted) {
        context.showSnack(
          AppLocalizations.of(context).playerPlaybackErrorBody,
          isError: true,
        );
      }
      return;
    }
    final candidateIndex = _candidates.indexOf(server);
    if (candidateIndex >= 0) _candidateIndex = candidateIndex;
    setState(() {
      _activeQuality = server.quality;
      _activeServerName = server.name;
      _loading = true;
      _playbackError = null;
    });
    await _player.open(
      Media(resolved.url, httpHeaders: resolved.headers),
      play: true,
    );
    await _player.setRate(_speed);
    if (position > Duration.zero) await _player.seek(position);
    if (mounted) setState(() => _loading = false);
  }

  void _onCompleted() {
    if (_completed) return;
    _completed = true;
    unawaited(_saveProgress(force: true));
    final settings = ref.read(settingsProvider);
    final next = _nextEpisode;
    if (settings.autoplayNext && next != null) {
      unawaited(_loadEpisode(next));
    }
  }

  AnimeEpisode? get _nextEpisode {
    final episode = _episode;
    if (episode == null) return null;
    final index = _episodes.indexWhere((item) => item.id == episode.id);
    if (index < 0 || index + 1 >= _episodes.length) return null;
    return _episodes[index + 1];
  }

  AnimeEpisode? get _previousEpisode {
    final episode = _episode;
    if (episode == null) return null;
    final index = _episodes.indexWhere((item) => item.id == episode.id);
    if (index <= 0) return null;
    return _episodes[index - 1];
  }

  Future<void> _saveProgress({bool force = false}) async {
    final anime = _anime;
    final episode = _episode;
    if (anime == null || episode == null) return;
    if (!ref.read(settingsProvider).rememberPosition && !force) return;
    if (_position <= Duration.zero && _duration <= Duration.zero) return;
    final entry = WatchHistoryEntry(
      animeId: anime.id,
      animeTitle: anime.title,
      posterUrl: anime.imageUrl,
      contentPath: anime.contentPath,
      episodeId: episode.id,
      episodeNumber: episode.number,
      episodeTitle: episode.title,
      position: _position,
      duration: _duration,
      completed: _completed,
      updatedAt: DateTime.now(),
    );
    await ref
        .read(libraryProvider.notifier)
        .saveProgress(entry, completed: _completed);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (_playing) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      unawaited(_saveProgress(force: true));
    } else {
      await _player.play();
    }
    _scheduleHide();
  }

  Future<void> _seekBy(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration && _duration > Duration.zero
              ? _duration
              : target);
    await _player.seek(clamped);
    if (mounted) setState(() => _position = clamped);
    _scheduleHide();
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_saveProgress(force: true));
    }
    // Leaving the app keeps the episode in a system picture-in-picture window
    // when the platform supports it; otherwise the session is kept alive for
    // the in-app floating player.
    if (state == AppLifecycleState.paused && _playing && !_fullscreen) {
      unawaited(PictureInPictureService.enter());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _viewTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    unawaited(_saveProgress(force: true));
    // Leaving the episode hands the live stream to the floating player when it
    // is still playing; a finished or failed playback is closed right away.
    final session = _session;
    if (session != null) {
      final keepAlive =
          _playing && !_completed && _error == null && _playbackError == null;
      if (keepAlive) {
        ref.read(playbackSessionProvider.notifier).detach();
      } else {
        unawaited(ref.read(playbackSessionProvider.notifier).close());
      }
    }
    unawaited(PictureInPictureService.setEnabled(false));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final surface = _PlayerSurface(
      videoController: _videoController,
      playing: _playing,
      buffering: _buffering,
      position: _seeking
          ? Duration(milliseconds: _seekValue.round())
          : _position,
      duration: _duration,
      controlsVisible: _controlsVisible,
      fullscreen: _fullscreen,
      loading: _loading,
      error:
          _error ??
          (_playbackError == null ? null : _PlaybackFailure(_playbackError!)),
      compact: !_fullscreen,
      title: _anime?.title ?? '',
      episodeLabel: _episode == null
          ? ''
          : AppLocalizations.of(context).commonEpisodeNumber(_episode!.number),
      onTapSurface: _toggleControls,
      onTogglePlay: _togglePlay,
      onSeekBack: () => _seekBy(-10),
      onSeekForward: () => _seekBy(10),
      onSeekStart: (value) {
        setState(() {
          _seeking = true;
          _seekValue = value;
        });
      },
      onSeekChanged: (value) => setState(() => _seekValue = value),
      onSeekEnd: (value) async {
        setState(() => _seeking = false);
        await _player.seek(Duration(milliseconds: value.round()));
      },
      onToggleFullscreen: _toggleFullscreen,
      onRetry: _bootstrap,
      onBack: () => Navigator.of(context).maybePop(),
      onComments: _openComments,
      onQuality: _showQualitySheet,
      onSpeed: _showSpeedSheet,
      onDownload: _episode == null
          ? null
          : () => _showDownloadSheet(_anime!, _episode!),
      onPrevious: _previousEpisode == null
          ? null
          : () => _loadEpisode(_previousEpisode!),
      onNext: _nextEpisode == null ? null : () => _loadEpisode(_nextEpisode!),
      onAutoplay: () => ref
          .read(settingsProvider.notifier)
          .update(
            (current) => current.copyWith(autoplayNext: !current.autoplayNext),
          ),
      autoplay: settings.autoplayNext,
      activeQuality: _activeQuality,
    );

    if (_fullscreen) {
      return PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            SystemChrome.setPreferredOrientations(<DeviceOrientation>[
              DeviceOrientation.portraitUp,
            ]);
          }
        },
        child: Scaffold(backgroundColor: Colors.black, body: surface),
      );
    }

    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            AspectRatio(aspectRatio: 16 / 9, child: surface),
            Expanded(child: _buildEpisodePanel(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodePanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final anime = _anime;
    final episode = _episode;
    if (anime == null) {
      return const SizedBox.shrink();
    }
    final library = ref.watch(libraryProvider);
    final watched = library.watchedEpisodeIds(anime.id);

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.md,
            Space.lg,
            Space.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium,
                    ),
                    const SizedBox(height: Space.xs + 2),
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        if (episode != null)
                          Text(
                            l10n.commonEpisodeNumber(episode.number),
                            style: context.text.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        if (episode != null)
                          _EpisodeViews(episodeId: episode.id),
                        _StreamChip(
                          label: _streamLabel(l10n),
                          onTap: _showQualitySheet,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              WingsIconButton(
                icon: _fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: palette.textSecondary,
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
        ),
        // YouTube-style block: reactions, share, download, save and the
        // comments sit directly under the video, then the episode list.
        if (episode != null) ...<Widget>[
          const SizedBox(height: Space.xs),
          EpisodeSocialSection(
            episodeId: episode.id,
            episodeTitle: l10n.commonEpisodeNumber(episode.number),
            embedded: true,
            savedToLibrary: library.entryFor(anime.id) != null,
            onDownload: () => _showDownloadSheet(anime, episode),
            onToggleSave: () => _toggleLibrary(anime),
          ),
          Divider(height: 1, color: palette.border),
        ],
        WingsSectionHeader(
          title: l10n.detailsEpisodes,
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.lg,
            Space.lg,
            Space.sm,
          ),
        ),
        for (var index = 0; index < _episodes.length; index++) ...<Widget>[
          Container(
            color: _episodes[index].id == _episode?.id
                ? palette.surfaceAlt
                : null,
            child: WingsEpisodeCard(
              episode: _episodes[index],
              fallbackImageUrl: anime.imageUrl,
              watched: watched.contains(_episodes[index].id),
              onPlay: () => _loadEpisode(_episodes[index]),
              onDownload: () => _showDownloadSheet(anime, _episodes[index]),
            ),
          ),
          if (index != _episodes.length - 1)
            Divider(
              height: 1,
              color: palette.border,
              indent: Space.lg + 104 + Space.md,
              endIndent: Space.lg,
            ),
        ],
      ],
    );
  }

  /// Adds the anime to the library or removes it, so the save button under the
  /// player works without leaving the episode.
  Future<void> _toggleLibrary(Anime anime) async {
    final notifier = ref.read(libraryProvider.notifier);
    final existing = ref.read(libraryProvider).entryFor(anime.id);
    if (existing == null) {
      await notifier.setStatus(anime, LibraryStatus.planToWatch);
    } else {
      await notifier.removeFromLibrary(anime.id);
    }
    if (!mounted) return;
    final saved = ref.read(libraryProvider).entryFor(anime.id) != null;
    context.showSnack(
      saved
          ? Tr.of(context, ar: 'أضيف إلى المكتبة', en: 'Added to library')
          : Tr.of(context, ar: 'أزيل من المكتبة', en: 'Removed from library'),
    );
  }

  Future<void> _showDownloadSheet(Anime anime, AnimeEpisode episode) async {
    final l10n = AppLocalizations.of(context);
    List<StreamServer> servers;
    if (episode.id == _episode?.id && _servers.isNotEmpty) {
      servers = _servers;
    } else {
      try {
        servers = await ref
            .read(animeRepositoryProvider)
            .servers(anime, episode);
      } on Object {
        servers = const <StreamServer>[];
      }
    }
    if (!mounted) return;
    final downloadable = servers
        .where((server) => !server.requiresBrowser)
        .toList(growable: false);

    await WingsSheet.show<void>(
      context,
      title: l10n.detailsDownloadSheetTitle,
      builder: (dialogContext) {
        if (downloadable.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: Text(
              l10n.detailsNoDownloads,
              style: dialogContext.text.bodySmall,
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final server in downloadable)
              WingsSettingsTile(
                icon: Icons.high_quality_rounded,
                title: server.quality,
                subtitle: server.name,
                trailing: const Icon(Icons.download_rounded, size: 18),
                onTap: () async {
                  Navigator.of(dialogContext).pop();
                  final resolved = await ref
                      .read(animeRepositoryProvider)
                      .resolve(server);
                  if (resolved == null) {
                    if (mounted) {
                      context.showSnack(l10n.detailsNoDownloads, isError: true);
                    }
                    return;
                  }
                  final task = DownloadTask(
                    id: '${anime.id}:${episode.id}:${server.quality}:${DateTime.now().millisecondsSinceEpoch}',
                    animeId: anime.id,
                    animeTitle: anime.title,
                    posterUrl: anime.imageUrl,
                    episodeId: episode.id,
                    episodeNumber: episode.number,
                    episodeTitle: episode.title,
                    quality: server.quality,
                    url: resolved.url,
                    headers: resolved.headers,
                    status: DownloadStatus.queued,
                    createdAt: DateTime.now(),
                  );
                  await ref.read(downloadTasksProvider.notifier).enqueue(task);
                  if (mounted) context.showSnack(l10n.downloadsQueued);
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _showSpeedSheet() async {
    final l10n = AppLocalizations.of(context);
    await WingsSheet.show<void>(
      context,
      title: l10n.playerSpeed,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final speed in const <double>[0.5, 0.75, 1, 1.25, 1.5, 2])
            WingsSettingsTile(
              title: speed == 1 ? '1.0×' : '$speed×',
              trailing: _speed == speed
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: sheetContext.palette.primary,
                    )
                  : null,
              onTap: () async {
                setState(() => _speed = speed);
                await _player.setRate(speed);
                await ref
                    .read(settingsProvider.notifier)
                    .update(
                      (current) => current.copyWith(playbackSpeed: speed),
                    );
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  String _streamLabel(AppLocalizations l10n) {
    final quality = _activeQuality;
    final server = _activeServerName;
    if (server == null && quality == null) return l10n.playerServers;
    if (server == null || quality == null) return server ?? quality!;
    return '$server • $quality';
  }

  void _openComments() {
    final episode = _episode;
    if (episode == null) return;
    final label = AppLocalizations.of(context)
        .commonEpisodeNumber(episode.number);
    context.push(
      '/episode/${Uri.encodeComponent(episode.id)}/comments',
      extra: label,
    );
  }

  Future<void> _showQualitySheet() async {
    final l10n = AppLocalizations.of(context);
    await WingsSheet.show<void>(
      context,
      title: l10n.playerSelectServer,
      builder: (sheetContext) {
        if (_servers.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: Text(
              l10n.playerNoServers,
              style: context.text.bodyMedium?.copyWith(
                color: sheetContext.palette.textSecondary,
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final server in _servers)
              WingsSettingsTile(
                icon: server.requiresBrowser
                    ? Icons.open_in_browser_rounded
                    : Icons.play_circle_outline_rounded,
                title: server.quality,
                subtitle: server.requiresBrowser
                    ? l10n.playerOpenInBrowser
                    : l10n.playerDirect,
                trailing:
                    !server.requiresBrowser && server.quality == _activeQuality
                    ? Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: sheetContext.palette.primary,
                      )
                    : null,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  if (server.requiresBrowser) {
                    final uri = Uri.tryParse(server.url);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                    return;
                  }
                  await _switchQuality(server);
                },
              ),
          ],
        );
      },
    );
  }
}

class _NoEpisodes implements Exception {
  const _NoEpisodes();
}

class _NoPlayableServer implements Exception {
  const _NoPlayableServer();
}

class _PlaybackFailure implements Exception {
  const _PlaybackFailure(this.details);

  final String details;
}

class _PlayerSurface extends StatelessWidget {
  const _PlayerSurface({
    required this.videoController,
    required this.compact,
    required this.playing,
    required this.buffering,
    required this.position,
    required this.duration,
    required this.controlsVisible,
    required this.fullscreen,
    required this.loading,
    required this.error,
    required this.title,
    required this.episodeLabel,
    required this.onTapSurface,
    required this.onTogglePlay,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onToggleFullscreen,
    required this.onRetry,
    required this.onBack,
    required this.onComments,
    required this.onQuality,
    required this.onSpeed,
    required this.onDownload,
    required this.onPrevious,
    required this.onNext,
    required this.onAutoplay,
    required this.autoplay,
    required this.activeQuality,
  });

  final VideoController videoController;

  /// Portrait layout: only playback controls stay on top of the video.
  final bool compact;
  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final bool controlsVisible;
  final bool fullscreen;
  final bool loading;
  final Object? error;
  final String title;
  final String episodeLabel;
  final VoidCallback onTapSurface;
  final VoidCallback onTogglePlay;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final VoidCallback onComments;
  final VoidCallback onQuality;
  final VoidCallback onSpeed;
  final VoidCallback? onDownload;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onAutoplay;
  final bool autoplay;
  final String? activeQuality;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maxMs = duration.inMilliseconds.toDouble();
    final progress = maxMs <= 0 ? 0.0 : position.inMilliseconds / maxMs;
    // Loading and buffering are shown on the play/pause control itself, and
    // that control stays visible while the video is not ready yet.
    final busy = buffering || loading;
    final showToggle = controlsVisible || busy;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: Video(
              controller: videoController,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              fill: Colors.black,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTapSurface,
            onDoubleTapDown: (details) {
              final width = context.size?.width ?? 1;
              final dx = details.localPosition.dx;
              final isRtl = Directionality.of(context) == TextDirection.rtl;
              final forwardSide = isRtl ? dx < width / 2 : dx > width / 2;
              if (forwardSide) {
                onSeekForward();
              } else {
                onSeekBack();
              }
            },
            child: const SizedBox.expand(),
          ),
          if (error != null)
            _PlayerError(
              message: _errorMessage(context, error!),
              onRetry: onRetry,
            ),
          AnimatedOpacity(
            opacity: controlsVisible ? 1 : 0,
            duration: Motion.fast,
            child: IgnorePointer(
              ignoring: !controlsVisible,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black54,
                      Colors.transparent,
                      Colors.black87,
                    ],
                    stops: <double>[0, 0.45, 1],
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.sm,
                        Space.sm,
                        Space.md,
                        0,
                      ),
                      child: Row(
                        children: <Widget>[
                          WingsIconButton(
                            icon: Icons.arrow_back_rounded,
                            tooltip: l10n.commonClose,
                            color: Colors.white,
                            onPressed: onBack,
                          ),
                          // In portrait the action bar under the video already
                          // owns the comments command, so the overlay only adds
                          // it in fullscreen where that bar is hidden.
                          if (!compact) ...<Widget>[
                            WingsIconButton(
                              icon: Icons.mode_comment_outlined,
                              tooltip: Tr.of(
                                context,
                                ar: 'التعليقات',
                                en: 'Comments',
                              ),
                              color: Colors.white,
                              onPressed: onComments,
                            ),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.titleSmall?.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (episodeLabel.isNotEmpty)
                                    Text(
                                      episodeLabel,
                                      style: context.text.labelSmall?.copyWith(
                                        color: Colors.white70,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (activeQuality != null)
                              WingsBadge(
                                activeQuality!,
                                style: WingsBadgeStyle.overlay,
                                compact: true,
                              ),
                          ],
                        ],
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _RoundControl(
                          icon: Icons.replay_10_rounded,
                          onTap: onSeekBack,
                        ),
                        const SizedBox(width: Space.xl),
                        // The real play/pause control lives in its own layer
                        // below so it can stay visible while the video loads.
                        const SizedBox(width: 58, height: 58),
                        const SizedBox(width: Space.xl),
                        _RoundControl(
                          icon: Icons.forward_10_rounded,
                          onTap: onSeekForward,
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (!compact)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.md,
                          0,
                          Space.md,
                          Space.xs,
                        ),
                        child: Row(
                          children: <Widget>[
                            Text(
                              formatDuration(position),
                              style: context.text.labelSmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 2.5,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: SliderComponentShape.noOverlay,
                                  activeTrackColor: context.palette.primary,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: context.palette.primary,
                                ),
                                child: Slider(
                                  value: (progress.clamp(0.0, 1.0)) * maxMs,
                                  max: maxMs <= 0 ? 1 : maxMs,
                                  onChangeStart: onSeekStart,
                                  onChanged: onSeekChanged,
                                  onChangeEnd: onSeekEnd,
                                ),
                              ),
                            ),
                            Text(
                              formatDuration(duration),
                              style: context.text.labelSmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!compact)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.sm,
                          0,
                          Space.sm,
                          Space.sm,
                        ),
                        child: Row(
                          children: <Widget>[
                            WingsIconButton(
                              icon: Icons.skip_previous_rounded,
                              color: Colors.white,
                              onPressed: onPrevious,
                            ),
                            WingsIconButton(
                              icon: Icons.speed_rounded,
                              color: Colors.white,
                              tooltip: l10n.playerSpeed,
                              onPressed: onSpeed,
                            ),
                            WingsIconButton(
                              icon: Icons.hd_outlined,
                              color: Colors.white,
                              tooltip: l10n.playerQuality,
                              onPressed: onQuality,
                            ),
                            WingsIconButton(
                              icon: Icons.download_rounded,
                              color: Colors.white,
                              tooltip: l10n.commonDownload,
                              onPressed: onDownload,
                            ),
                            WingsIconButton(
                              icon: autoplay
                                  ? Icons.playlist_play_rounded
                                  : Icons.playlist_remove_rounded,
                              color: autoplay
                                  ? context.palette.primary
                                  : Colors.white,
                              tooltip: l10n.playerAutoNext,
                              onPressed: onAutoplay,
                            ),
                            const Spacer(),
                            WingsIconButton(
                              icon: Icons.skip_next_rounded,
                              color: Colors.white,
                              onPressed: onNext,
                            ),
                            WingsIconButton(
                              icon: fullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              color: Colors.white,
                              onPressed: onToggleFullscreen,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: showToggle ? 1 : 0,
            duration: Motion.fast,
            child: IgnorePointer(
              ignoring: !showToggle,
              child: Center(
                child: _RoundControl(
                  icon: playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 58,
                  busy: busy,
                  onTap: onTogglePlay,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _errorMessage(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context);
    if (error is _NoEpisodes) return l10n.detailsNoEpisodes;
    if (error is _NoPlayableServer) return l10n.playerNoServers;
    return l10n.playerPlaybackErrorBody;
  }
}

/// Episode view counter, shown next to the episode number under the video.
/// The number comes from the cached counter, so re-opening a screen costs no
/// extra reads.
class _EpisodeViews extends ConsumerWidget {
  const _EpisodeViews({required this.episodeId});

  final String episodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return FutureBuilder<int>(
      future: ref.watch(viewsRepositoryProvider).episodeViews(episodeId),
      builder: (context, snapshot) {
        final views = snapshot.data ?? 0;
        if (views <= 0) {
          return Text(
            Tr.of(context, ar: 'أول مشاهدة', en: 'First view'),
            style: context.text.labelSmall?.copyWith(color: palette.textMuted),
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.visibility_outlined, size: 13, color: palette.textMuted),
            const SizedBox(width: 4),
            Text(
              '${formatCount(views)} ${Tr.of(context, ar: 'مشاهدة', en: 'views')}',
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StreamChip extends StatelessWidget {
  const _StreamChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm + 2,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.hd_outlined, size: 14, color: palette.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: context.text.labelMedium?.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 14, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  /// Shows the loading state in place of the icon while the video loads.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black38,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: busy
            ? Center(
                child: SizedBox(
                  width: size * 0.4,
                  height: size * 0.4,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
              )
            : Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white70,
              size: 28,
            ),
            const SizedBox(height: Space.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: Space.md),
            WingsButton(
              label: l10n.commonRetry,
              variant: WingsButtonVariant.tonal,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
