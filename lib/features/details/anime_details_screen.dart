import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_cards.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/anime.dart';
import '../../data/models/library.dart';
import '../community/anime_community_section.dart';
import 'details_providers.dart';

class AnimeDetailsScreen extends ConsumerStatefulWidget {
  const AnimeDetailsScreen({super.key, required this.animeId});

  final String animeId;

  @override
  ConsumerState<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

/// Real views for the whole title, shown on the details screen.
///
/// Only the app's own unique-viewer counter is shown. The catalogue's `views`
/// figure is an estimate from an external source (often a very large, invented
/// number), so adding it here made the counter look fake.
class _TitleViews extends ConsumerWidget {
  const _TitleViews({required this.animeId});

  final String animeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return FutureBuilder<int>(
      future: ref.watch(viewsRepositoryProvider).animeViews(animeId),
      builder: (context, snapshot) {
        final total = snapshot.data ?? 0;
        return Row(
          children: <Widget>[
            Icon(Icons.visibility_outlined, size: 14, color: palette.textMuted),
            const SizedBox(width: 4),
            Text(
              total <= 0
                  ? Tr.of(context, ar: 'لا مشاهدات بعد', en: 'No views yet')
                  : '${formatCount(total)} ${Tr.of(context, ar: 'مشاهدة', en: 'views')}',
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

class _AnimeDetailsScreenState extends ConsumerState<AnimeDetailsScreen> {
  bool _synopsisExpanded = false;
  bool _ascending = true;

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(detailsBundleProvider(widget.animeId));

    return Scaffold(
      body: bundle.when(
        loading: () => const _DetailsSkeleton(),
        error: (error, _) => SafeArea(
          child: Column(
            children: <Widget>[
              WingsAppBar(showBack: true),
              Expanded(
                child: WingsErrorState(
                  failure: error,
                  onRetry: () =>
                      ref.invalidate(detailsBundleProvider(widget.animeId)),
                ),
              ),
            ],
          ),
        ),
        data: (data) => _buildContent(context, data),
      ),
    );
  }

  Widget _buildContent(BuildContext context, DetailsBundle bundle) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final anime = bundle.anime;
    final library = ref.watch(libraryProvider);
    final entry = library.entryFor(anime.id);
    final watched = library.watchedEpisodeIds(anime.id);
    final episodes = _ascending
        ? bundle.episodes
        : bundle.episodes.reversed.toList(growable: false);
    final lastWatched = library.lastFor(anime.id);
    // Hero height follows the screen instead of a single 300 px block that was
    // too tall on small phones and too short on tablets.
    final heroHeight = (MediaQuery.sizeOf(context).width * 0.8).clamp(
      220.0,
      340.0,
    );

    final info = <(String, String)>[
      if (anime.releaseDate != null)
        (l10n.detailsReleaseDate, anime.releaseDate!),
      if (anime.episodeCount != null)
        (l10n.detailsEpisodesCount, '${anime.episodeCount}'),
      if (anime.season != null) (l10n.detailsSeason, anime.season!),
      if (anime.studios.isNotEmpty)
        (l10n.detailsStudio, anime.studios.join('، ')),
      if (anime.status != null) (l10n.detailsStatus, anime.status!),
      if (anime.type != null) (l10n.detailsType, anime.type!),
      if (anime.rating != null)
        (l10n.detailsRating, '★ ${anime.rating!.toStringAsFixed(1)}'),
      if (anime.durationMinutes != null)
        (l10n.detailsEpisodes, '${anime.durationMinutes} د'),
    ];

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: heroHeight,
          pinned: true,
          stretch: false,
          backgroundColor: palette.background,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          leadingWidth: 56,
          leading: Padding(
            padding: const EdgeInsetsDirectional.only(start: Space.sm),
            child: WingsIconButton(
              icon: context.isRtl
                  ? Icons.arrow_forward_rounded
                  : Icons.arrow_back_rounded,
              tooltip: l10n.commonBack,
              filled: true,
              onPressed: () {
                final router = GoRouter.maybeOf(context);
                if (router == null) {
                  Navigator.of(context).maybePop();
                  return;
                }
                if (router.canPop()) {
                  router.pop();
                } else {
                  router.go(RoutePaths.latest);
                }
              },
            ),
          ),
          actions: <Widget>[
            WingsIconButton(
              icon: Icons.share_outlined,
              filled: true,
              onPressed: () => ref.read(shareServiceProvider).shareAnime(anime),
            ),
            const SizedBox(width: Space.sm),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.sm),
              child: WingsIconButton(
                icon: entry?.isFavorite == true
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                filled: true,
                color: entry?.isFavorite == true
                    ? palette.danger
                    : palette.textPrimary,
                onPressed: () async {
                  await ref
                      .read(libraryProvider.notifier)
                      .toggleFavorite(anime);
                  if (!context.mounted) return;
                  final added =
                      ref
                          .read(libraryProvider)
                          .entryFor(anime.id)
                          ?.isFavorite ??
                      false;
                  context.showSnack(
                    added ? l10n.detailsAdded : l10n.detailsRemoved,
                  );
                },
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                WingsImage(
                  url: anime.backdropUrl ?? anime.posterUrl,
                  fit: BoxFit.cover,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        palette.overlay.withValues(alpha: 0.35),
                        palette.overlay.withValues(alpha: 0.35),
                        palette.background,
                      ],
                      stops: const <double>[0, 0.55, 1],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.xs,
              Space.lg,
              Space.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                WingsImage(
                  url: anime.posterUrl,
                  width: 104,
                  height: 156,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        anime.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.headlineSmall?.copyWith(
                          fontSize: 20,
                          height: 1.3,
                        ),
                      ),
                      if (anime.englishTitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          anime.englishTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                      const SizedBox(height: Space.sm),
                      Wrap(
                        spacing: Space.xs,
                        runSpacing: Space.xs,
                        children: <Widget>[
                          if (anime.rating != null)
                            WingsBadge(
                              anime.rating!.toStringAsFixed(1),
                              style: WingsBadgeStyle.warning,
                              icon: Icons.star_rounded,
                            ),
                          if (anime.year != null) WingsBadge('${anime.year}'),
                          if (anime.type != null) WingsBadge(anime.type!),
                          if (anime.status != null)
                            WingsBadge(
                              anime.status!,
                              style: anime.status!.contains('مكتمل')
                                  ? WingsBadgeStyle.success
                                  : WingsBadgeStyle.brand,
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                      _TitleViews(animeId: anime.id),
                      const SizedBox(height: Space.sm),
                      if (anime.genres.isNotEmpty)
                        Wrap(
                          spacing: Space.xs,
                          runSpacing: Space.xs,
                          children: <Widget>[
                            for (final genre in anime.genres.take(4))
                              GestureDetector(
                                onTap: () =>
                                    context.push(RoutePaths.genre(genre)),
                                child: Text(
                                  genre,
                                  style: context.text.labelSmall?.copyWith(
                                    color: palette.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: WingsButton(
              label: episodes.isEmpty
                  ? l10n.detailsNoEpisodes
                  : (lastWatched != null
                        ? l10n.libraryHistoryContinue
                        : l10n.homeWatchNow),
              icon: Icons.play_arrow_rounded,
              expand: true,
              onPressed: episodes.isEmpty
                  ? null
                  : () => _watch(
                      anime,
                      episodes: bundle.episodes,
                      lastWatched: lastWatched,
                    ),
            ),
          ),
        ),
        // One library action opens the status sheet, which already contains
        // «مكتمل». A second, separate completed button duplicated that option.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xs),
            child: WingsButton(
              label: entry != null
                  ? l10n.detailsInLibrary
                  : l10n.detailsAddToLibrary,
              icon: entry != null
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              variant: WingsButtonVariant.tonal,
              expand: true,
              onPressed: () => _showStatusSheet(anime, entry),
            ),
          ),
        ),
        if (anime.synopsis != null)
          SliverToBoxAdapter(
            child: _Section(
              title: l10n.detailsSynopsis,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AnimatedSize(
                    duration: Motion.normal,
                    curve: Motion.standard,
                    alignment: AlignmentDirectional.topCenter,
                    child: Text(
                      anime.synopsis!,
                      maxLines: _synopsisExpanded ? null : 4,
                      overflow: _synopsisExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                        height: 1.75,
                      ),
                    ),
                  ),
                  if (anime.synopsis!.length > 160)
                    GestureDetector(
                      onTap: () => setState(
                        () => _synopsisExpanded = !_synopsisExpanded,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Text(
                          _synopsisExpanded
                              ? l10n.detailsLess
                              : l10n.detailsMore,
                          style: context.text.labelMedium?.copyWith(
                            color: palette.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (info.isNotEmpty)
          SliverToBoxAdapter(
            child: _Section(
              title: l10n.detailsInfo,
              child: Column(
                children: <Widget>[
                  for (var index = 0; index < info.length; index++) ...<Widget>[
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 110,
                          child: Text(
                            info[index].$1,
                            style: context.text.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            info[index].$2,
                            style: context.text.bodySmall?.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (index != info.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.sm),
                        child: Divider(color: palette.border, height: 1),
                      ),
                  ],
                ],
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.xl,
              Space.lg,
              Space.sm,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  l10n.detailsEpisodes,
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: Space.sm),
                WingsBadge('${bundle.episodes.length}'),
                const Spacer(),
                if (bundle.episodes.length > 1)
                  WingsIconButton(
                    icon: Icons.swap_vert_rounded,
                    size: 34,
                    tooltip: l10n.commonSort,
                    onPressed: () => setState(() => _ascending = !_ascending),
                  ),
              ],
            ),
          ),
        ),
        if (bundle.episodesError != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: WingsErrorState(
                failure: bundle.episodesError!,
                onRetry: () =>
                    ref.invalidate(detailsBundleProvider(widget.animeId)),
              ),
            ),
          )
        else if (bundle.episodes.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: WingsEmptyState(
                icon: Icons.playlist_remove_rounded,
                title: l10n.detailsNoEpisodes,
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final episode = episodes[index];
              return WingsEpisodeCard(
                episode: episode,
                fallbackImageUrl: anime.imageUrl,
                watched: watched.contains(episode.id),
                onPlay: () =>
                    _watch(anime, episode: episode, episodes: bundle.episodes),
                onDownload: () => _openDownloadSheet(anime, episode),
              );
            },
          ),
        SliverToBoxAdapter(child: AnimeCommunitySection(anime: anime)),
        if (bundle.related.isNotEmpty) ...<Widget>[
          SliverToBoxAdapter(
            child: WingsSectionHeader(title: l10n.detailsRelated),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              // Tall enough for a full two-line title under the 2:3 poster.
              height: WingsPosterCard.railHeightFor(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                itemCount: bundle.related.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.md),
                itemBuilder: (context, index) {
                  final related = bundle.related[index];
                  return WingsPosterCard(
                    anime: related,
                    onTap: () =>
                        context.pushReplacement(RoutePaths.anime(related.id)),
                  );
                },
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Space.xxxl)),
      ],
    );
  }

  void _watch(
    Anime anime, {
    AnimeEpisode? episode,
    required List<AnimeEpisode> episodes,
    WatchHistoryEntry? lastWatched,
  }) {
    if (episodes.isEmpty) return;
    var target = episode;
    if (target == null && lastWatched != null) {
      for (final item in episodes) {
        if (item.id == lastWatched.episodeId) {
          target = item;
          break;
        }
      }
    }
    target ??= episodes.first;
    context.push(
      RoutePaths.watch(animeId: anime.id, episodeId: target.id),
      extra: anime,
    );
  }

  Future<void> _showStatusSheet(Anime anime, LibraryEntry? entry) async {
    final l10n = AppLocalizations.of(context);
    await WingsSheet.show<void>(
      context,
      title: l10n.libraryChangeStatus,
      builder: (sheetContext) {
        Widget tile(String label, LibraryStatus status, IconData icon) {
          final selected = entry?.status == status;
          return WingsSettingsTile(
            icon: icon,
            title: label,
            trailing: selected
                ? Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: sheetContext.palette.primary,
                  )
                : null,
            onTap: () async {
              await ref.read(libraryProvider.notifier).setStatus(anime, status);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (mounted) context.showSnack(l10n.detailsAdded);
            },
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            tile(
              l10n.detailsWatching,
              LibraryStatus.watching,
              Icons.play_circle_outline_rounded,
            ),
            tile(
              l10n.detailsPlanToWatch,
              LibraryStatus.planToWatch,
              Icons.bookmark_border_rounded,
            ),
            tile(
              l10n.detailsCompleted,
              LibraryStatus.completed,
              Icons.check_circle_outline_rounded,
            ),
            tile(
              l10n.detailsOnHold,
              LibraryStatus.onHold,
              Icons.pause_circle_outline_rounded,
            ),
            tile(
              l10n.detailsDropped,
              LibraryStatus.dropped,
              Icons.remove_circle_outline_rounded,
            ),
            if (entry != null)
              WingsSettingsTile(
                icon: Icons.delete_outline_rounded,
                title: l10n.libraryRemove,
                destructive: true,
                onTap: () async {
                  await ref
                      .read(libraryProvider.notifier)
                      .removeFromLibrary(anime.id);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _openDownloadSheet(Anime anime, AnimeEpisode episode) async {
    final l10n = AppLocalizations.of(context);
    await WingsSheet.show<void>(
      context,
      title: l10n.detailsDownloadSheetTitle,
      builder: (_) => _DownloadSheet(anime: anime, episode: episode),
    );
  }
}

class _DownloadSheet extends ConsumerStatefulWidget {
  const _DownloadSheet({required this.anime, required this.episode});

  final Anime anime;
  final AnimeEpisode episode;

  @override
  ConsumerState<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<_DownloadSheet> {
  int? _busyIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final servers = ref.watch(
      episodeServersProvider((
        animeId: widget.anime.id,
        episodeId: widget.episode.id,
      )),
    );

    return servers.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.xxl),
        child: WingsLoading(),
      ),
      error: (error, _) => WingsErrorState(failure: error),
      data: (items) {
        final downloadable = items
            .where((server) => !server.requiresBrowser)
            .toList();
        if (downloadable.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: Text(
              l10n.detailsNoDownloads,
              style: context.text.bodyMedium?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var index = 0; index < downloadable.length; index++)
              WingsSettingsTile(
                icon: Icons.high_quality_rounded,
                title:
                    '${l10n.commonEpisodeNumber(widget.episode.number)} · ${downloadable[index].quality}',
                subtitle: l10n.commonDownload,
                trailing: _busyIndex == index
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                onTap: _busyIndex != null
                    ? null
                    : () => _startDownload(downloadable[index], index),
              ),
          ],
        );
      },
    );
  }

  Future<void> _startDownload(StreamServer server, int index) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busyIndex = index);
    final resolved = await ref.read(animeRepositoryProvider).resolve(server);
    if (!mounted) return;
    setState(() => _busyIndex = null);
    if (resolved == null) {
      context.showSnack(l10n.detailsNoDownloads, isError: true);
      return;
    }
    final task = DownloadTask(
      id: '${widget.anime.id}:${widget.episode.id}:${server.quality}:${DateTime.now().millisecondsSinceEpoch}',
      animeId: widget.anime.id,
      animeTitle: widget.anime.title,
      posterUrl: widget.anime.imageUrl,
      episodeId: widget.episode.id,
      episodeNumber: widget.episode.number,
      episodeTitle: widget.episode.title,
      quality: server.quality,
      url: resolved.url,
      headers: resolved.headers,
      status: DownloadStatus.queued,
      createdAt: DateTime.now(),
    );
    await ref.read(downloadTasksProvider.notifier).enqueue(task);
    if (!mounted) return;
    Navigator.of(context).pop();
    context.showSnack(l10n.downloadsQueued);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: context.text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: palette.border),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: <Widget>[
          const WingsSkeleton(
            height: 220,
            borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
          ),
          const SizedBox(height: Space.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const WingsSkeleton(width: 104, height: 152),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const <Widget>[
                    WingsSkeleton(height: 18, width: 200),
                    SizedBox(height: Space.sm),
                    WingsSkeleton(height: 12, width: 140),
                    SizedBox(height: Space.md),
                    WingsSkeleton(height: 26, width: 180),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          const WingsSkeleton(height: 44),
          const SizedBox(height: Space.xxl),
          const WingsSkeleton(height: 14, width: 100),
          const SizedBox(height: Space.md),
          const WingsSkeleton(height: 90),
        ],
      ),
    );
  }
}
