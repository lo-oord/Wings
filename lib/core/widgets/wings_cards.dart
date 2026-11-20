import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../data/models/anime.dart';
import '../../data/models/library.dart';
import '../utils/formatters.dart';
import 'wings_buttons.dart';
import 'wings_feedback.dart';
import 'wings_image.dart';
import 'wings_layout.dart';

/// The short line under a poster: rating, library status and type.
///
/// It uses a small, readable size so a 144 px card never overflows, and the
/// status only appears for titles that are actually in the library.
class AnimeCardMeta extends StatelessWidget {
  const AnimeCardMeta({
    super.key,
    required this.anime,
    this.status,
    this.compact = false,
  });

  final Anime anime;
  final LibraryStatus? status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = status == null ? null : animeStatusLabel(context, status!);
    final type = animeTypeLabel(context, anime.type);
    final bits = <String>[
      if (anime.rating != null) anime.rating!.toStringAsFixed(1),
      ?label,
      if (type.isNotEmpty) type,
    ];
    if (bits.isEmpty) return const SizedBox.shrink();
    // One line only: a poster card is narrow, so a second metadata line used to
    // grow the card past its rail and clip the title on small phones.
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        if (anime.rating != null) ...<Widget>[
          Icon(Icons.star_rounded, size: 11, color: palette.warning),
          const SizedBox(width: 2),
        ],
        Flexible(
          child: Text(
            bits.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style(
              context,
              color: status == LibraryStatus.completed ? palette.primary : null,
            ),
          ),
        ),
      ],
    );
  }

  TextStyle? _style(BuildContext context, {Color? color}) =>
      context.text.labelSmall?.copyWith(
        fontSize: compact ? 10 : 10.5,
        height: 1.15,
        fontWeight: FontWeight.w500,
        color: color ?? context.palette.textMuted,
      );
}

/// Localized type of a title, e.g. مسلسل / فيلم.
String animeTypeLabel(BuildContext context, String? type) {
  final lower = (type ?? '').trim().toLowerCase();
  if (lower.isEmpty) return '';
  final arabic = Localizations.localeOf(context).languageCode == 'ar';
  if (lower.contains('movie') || lower.contains('film')) {
    return arabic ? 'فيلم' : 'Movie';
  }
  if (lower.contains('ova')) return 'OVA';
  if (lower.contains('ona')) return 'ONA';
  if (lower.contains('special')) return arabic ? 'خاص' : 'Special';
  return arabic ? 'مسلسل' : 'Series';
}

/// Localized library status, e.g. مستمر / مكتمل.
String animeStatusLabel(BuildContext context, LibraryStatus status) {
  final l10n = AppLocalizations.of(context);
  return switch (status) {
    LibraryStatus.watching => l10n.detailsWatching,
    LibraryStatus.completed => l10n.detailsCompleted,
    LibraryStatus.planToWatch => l10n.detailsPlanToWatch,
    LibraryStatus.onHold => l10n.detailsOnHold,
    LibraryStatus.dropped => l10n.detailsDropped,
  };
}

/// Shared responsive poster grid.
///
/// The cell height is derived from the real column width and the reader's text
/// scale, so a title can never overflow its cell and the column count adapts to
/// the screen instead of using one fixed aspect ratio everywhere.
abstract final class AnimeGrid {
  static int columnsFor(double availableWidth) {
    if (availableWidth <= 0) return 2;
    final columns = (availableWidth / (PosterCardMetrics.maxWidth + Space.md))
        .ceil();
    return columns.clamp(2, 8);
  }

  static SliverGridDelegate delegate(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final available = media.width - Space.lg * 2;
    final columns = columnsFor(available);
    final cell = (available - (columns - 1) * Space.md) / columns;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: Space.lg,
      crossAxisSpacing: Space.md,
      mainAxisExtent: cell <= 0
          ? null
          : PosterCardMetrics.heightFor(
              cell,
              textScale: MediaQuery.textScalerOf(context).scale(1),
            ),
    );
  }
}

/// Portrait poster card used in horizontal rails and grids.
class WingsPosterCard extends ConsumerWidget {
  const WingsPosterCard({
    super.key,
    required this.anime,
    this.onTap,
    this.width = PosterCardMetrics.width,
    this.showTitle = true,
    this.badge,
    this.rank,
  });

  /// Height a rail needs so these cards never clip their own titles.
  static double railHeightFor(BuildContext context) =>
      PosterCardMetrics.railHeightFor(context);

  final Anime anime;
  final VoidCallback? onTap;
  final double width;
  final bool showTitle;
  final Widget? badge;
  final int? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final status = ref.watch(libraryProvider).entryFor(anime.id)?.status;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AspectRatio(
              aspectRatio: Ratios.poster,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  WingsImage(
                    url: anime.imageUrl,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  if (badge != null)
                    PositionedDirectional(
                      top: Space.sm,
                      end: Space.sm,
                      child: badge!,
                    ),
                  if (rank != null)
                    PositionedDirectional(
                      top: 0,
                      start: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: palette.overlay,
                          borderRadius: const BorderRadiusDirectional.only(
                            topStart: Radius.circular(Radii.sm),
                            bottomEnd: Radius.circular(Radii.sm),
                          ),
                        ),
                        child: Text(
                          '$rank',
                          style: context.text.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(
                        Space.sm,
                        Space.xxl,
                        Space.sm,
                        Space.sm,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(Radii.sm),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.transparent,
                            palette.overlay.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          if (anime.rating != null) ...<Widget>[
                            Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: palette.warning,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              anime.rating!.toStringAsFixed(1),
                              style: context.text.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (anime.episodeCount != null)
                            Text(
                              '${anime.episodeCount}',
                              style: context.text.labelSmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showTitle) ...<Widget>[
              const SizedBox(height: Space.sm),
              Text(
                anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleSmall?.copyWith(
                  height: 1.4,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              AnimeCardMeta(anime: anime, status: status, compact: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// Horizontal row item used by search results and library lists.
class WingsAnimeListTile extends ConsumerWidget {
  const WingsAnimeListTile({
    super.key,
    required this.anime,
    this.onTap,
    this.subtitle,
    this.trailing,
    this.badge,
  });

  final Anime anime;
  final VoidCallback? onTap;
  final String? subtitle;
  final Widget? trailing;
  final Widget? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final status = ref.watch(libraryProvider).entryFor(anime.id)?.status;
    final meta = <String>[
      if (anime.type != null) animeTypeLabel(context, anime.type),
      if (anime.year != null) '${anime.year}',
      if (anime.genres.isNotEmpty) anime.genres.first,
    ].join(' • ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm + 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                WingsImage(
                  url: anime.imageUrl,
                  width: 62,
                  height: 92,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                if (badge != null)
                  PositionedDirectional(
                    top: Space.xs,
                    start: Space.xs,
                    child: badge!,
                  ),
              ],
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    anime.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    subtitle ?? meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: Space.xs + 2),
                  Row(
                    children: <Widget>[
                      if (anime.rating != null) ...<Widget>[
                        WingsRatingLabel(rating: anime.rating!, compact: true),
                        const SizedBox(width: Space.sm),
                      ],
                      if (status != null)
                        Flexible(
                          child: Text(
                            animeStatusLabel(context, status),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(
                              color: palette.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (status == null && anime.status != null)
                        Flexible(
                          child: Text(
                            anime.status!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: Space.sm),
                child: trailing!,
              ),
          ],
        ),
      ),
    );
  }
}

/// Small horizontal card for a freshly published episode.
class WingsLatestEpisodeCard extends StatelessWidget {
  const WingsLatestEpisodeCard({
    super.key,
    required this.item,
    this.onTap,
    this.onPlay,
    this.width = 236,
  });

  final LatestEpisode item;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: Ratios.episodeThumb,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  WingsImage(
                    url: item.episode.thumbnailUrl ?? item.anime.imageUrl,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  PositionedDirectional(
                    top: Space.sm,
                    start: Space.sm,
                    child: WingsBadge(
                      l10n.commonEpisodeNumber(item.episode.number),
                      style: WingsBadgeStyle.overlay,
                      compact: true,
                    ),
                  ),
                  Center(
                    child: GestureDetector(
                      onTap: onPlay ?? onTap,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: palette.overlay.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              item.anime.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              item.releasedAt == null
                  ? l10n.homeNewBadge
                  : relativeTime(item.releasedAt, l10n),
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Episode row used inside the details screen.
class WingsEpisodeCard extends StatefulWidget {
  const WingsEpisodeCard({
    super.key,
    required this.episode,
    this.watched = false,
    this.onPlay,
    this.onDownload,
    this.onShare,
    this.fallbackImageUrl,
    this.showThumbnail = true,
  });

  final AnimeEpisode episode;
  final bool watched;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;
  final VoidCallback? onShare;

  /// Shown when the episode has no artwork of its own.
  final String? fallbackImageUrl;
  final bool showThumbnail;

  @override
  State<WingsEpisodeCard> createState() => _WingsEpisodeCardState();
}

class _WingsEpisodeCardState extends State<WingsEpisodeCard> {
  /// Tapping the card opens it like a YouTube episode row: the cover grows to
  /// its full frame and the actions slide in underneath.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final episode = widget.episode;
    final watched = widget.watched;
    final showThumbnail = widget.showThumbnail;
    final imageUrl = (episode.thumbnailUrl?.trim().isNotEmpty ?? false)
        ? episode.thumbnailUrl
        : widget.fallbackImageUrl;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: showThumbnail
            ? () => setState(() => _expanded = !_expanded)
            : widget.onPlay,
        child: AnimatedSize(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    0,
                  ),
                  child: AspectRatio(
                    aspectRatio: Ratios.episodeThumb,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        WingsImage(
                          url: imageUrl,
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onPlay,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.overlay.withValues(alpha: 0.24),
                                borderRadius: BorderRadius.circular(Radii.sm),
                              ),
                              child: Icon(
                                watched
                                    ? Icons.replay_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm,
                ),
                child: Row(
                  children: <Widget>[
                    if (showThumbnail)
                      Stack(
                        children: <Widget>[
                          WingsImage(
                            url: imageUrl,
                            width: 104,
                            height: 104 * 9 / 16,
                            borderRadius: BorderRadius.circular(Radii.xs),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.overlay.withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(Radii.xs),
                              ),
                              child: Icon(
                                watched
                                    ? Icons.replay_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: palette.surfaceAlt,
                          borderRadius: BorderRadius.circular(Radii.xs),
                          border: Border.all(color: palette.border),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${episode.number}',
                          style: context.text.titleSmall,
                        ),
                      ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.commonEpisodeNumber(episode.number),
                            style: context.text.titleSmall?.copyWith(
                              fontSize: 13.5,
                            ),
                          ),
                          if (episode.title != null &&
                              episode.title!.trim().isNotEmpty) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              episode.title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                          if (watched) ...<Widget>[
                            const SizedBox(height: Space.xs),
                            Row(
                              children: <Widget>[
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 12,
                                  color: palette.success,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.detailsEpisodeWatched,
                                  style: context.text.labelSmall?.copyWith(
                                    color: palette.success,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.onShare != null)
                      WingsIconButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        size: 34,
                        tooltip: l10n.detailsShare,
                        onPressed: widget.onShare,
                        color: palette.textSecondary,
                      ),
                    if (widget.onDownload != null)
                      WingsIconButton(
                        icon: Icons.download_rounded,
                        size: 34,
                        tooltip: l10n.commonDownload,
                        onPressed: widget.onDownload,
                        color: palette.textSecondary,
                      ),
                    WingsIconButton(
                      icon: Icons.play_circle_fill_rounded,
                      size: 36,
                      tooltip: l10n.detailsWatch,
                      onPressed: widget.onPlay,
                      color: palette.primary,
                    ),
                    if (showThumbnail)
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: palette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Continue-watching entry with real playback progress.
class WingsContinueCard extends StatelessWidget {
  const WingsContinueCard({
    super.key,
    required this.entry,
    this.onTap,
    this.width = 220,
  });

  final WatchHistoryEntry entry;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: Ratios.episodeThumb,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  WingsImage(
                    url: entry.posterUrl,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  PositionedDirectional(
                    start: Space.sm,
                    bottom: Space.sm,
                    child: WingsBadge(
                      l10n.commonEpisodeNumber(entry.episodeNumber),
                      style: WingsBadgeStyle.overlay,
                      compact: true,
                    ),
                  ),
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: 0,
                    child: WingsProgressBar(value: entry.progress, height: 3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              entry.animeTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              l10n.libraryProgress((entry.progress * 100).round()),
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Swipeable featured carousel for the home screen.
class WingsFeaturedBanner extends StatefulWidget {
  const WingsFeaturedBanner({
    super.key,
    required this.items,
    required this.onWatch,
    required this.onDetails,
  });

  final List<Anime> items;
  final ValueChanged<Anime> onWatch;
  final ValueChanged<Anime> onDetails;

  @override
  State<WingsFeaturedBanner> createState() => _WingsFeaturedBannerState();
}

class _WingsFeaturedBannerState extends State<WingsFeaturedBanner> {
  final PageController _controller = PageController(viewportFraction: 0.92);
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final height = (width * 0.56).clamp(184.0, 252.0);

    return Column(
      children: <Widget>[
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            itemCount: widget.items.length,
            onPageChanged: (index) {
              setState(() => _index = index);
            },
            itemBuilder: (context, index) {
              final anime = widget.items[index];
              return Padding(
                padding: EdgeInsetsDirectional.only(
                  start: index == 0 ? Space.lg : Space.sm,
                  end: index == widget.items.length - 1 ? Space.lg : 0,
                ),
                child: _FeaturedCard(
                  anime: anime,
                  onWatch: () => widget.onWatch(anime),
                  onDetails: () => widget.onDetails(anime),
                ),
              );
            },
          ),
        ),
        if (widget.items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var dot = 0; dot < widget.items.length; dot++)
                  AnimatedContainer(
                    duration: Motion.normal,
                    curve: Motion.standard,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: dot == _index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: dot == _index
                          ? palette.primary
                          : palette.borderStrong,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.anime,
    required this.onWatch,
    required this.onDetails,
  });

  final Anime anime;
  final VoidCallback onWatch;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final meta = <String>[
      if (anime.rating != null) '★ ${anime.rating!.toStringAsFixed(1)}',
      if (anime.year != null) '${anime.year}',
      if (anime.type != null) anime.type!,
      if (anime.episodeCount != null)
        '${anime.episodeCount} ${l10n.detailsEpisodes}',
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          WingsImage(
            url: anime.backdropUrl ?? anime.posterUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  palette.overlay.withValues(alpha: 0.05),
                  palette.overlay.withValues(alpha: 0.45),
                  palette.overlay.withValues(alpha: 0.94),
                ],
                stops: const <double>[0, 0.45, 1],
              ),
            ),
          ),
          PositionedDirectional(
            top: Space.md,
            start: Space.md,
            child: WingsBadge(
              l10n.homeFeatured,
              style: WingsBadgeStyle.brand,
              icon: Icons.auto_awesome_rounded,
              compact: true,
            ),
          ),
          PositionedDirectional(
            start: Space.md,
            end: Space.md,
            bottom: Space.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  anime.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleLarge?.copyWith(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.3,
                  ),
                ),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    meta.join('  •  '),
                    style: context.text.labelSmall?.copyWith(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: Space.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: WingsButton(
                        label: l10n.homeWatchNow,
                        icon: Icons.play_arrow_rounded,
                        height: 38,
                        onPressed: onWatch,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      flex: 2,
                      child: WingsButton(
                        label: l10n.homeMoreDetails,
                        variant: WingsButtonVariant.tonal,
                        height: 38,
                        onPressed: onDetails,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
