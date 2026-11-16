import 'package:flutter/material.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../data/models/anime.dart';
import '../../data/models/library.dart';
import '../utils/formatters.dart';
import 'wings_buttons.dart';
import 'wings_feedback.dart';
import 'wings_image.dart';
import 'wings_layout.dart';

/// Portrait poster card used in horizontal rails and grids.
class WingsPosterCard extends StatelessWidget {
  const WingsPosterCard({
    super.key,
    required this.anime,
    this.onTap,
    this.width = 132,
    this.showTitle = true,
    this.badge,
    this.rank,
  });

  final Anime anime;
  final VoidCallback? onTap;
  final double width;
  final bool showTitle;
  final Widget? badge;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
                  height: 1.35,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Horizontal row item used by search results and library lists.
class WingsAnimeListTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = <String>[
      if (anime.type != null) anime.type!,
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
                      if (anime.status != null)
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
class WingsEpisodeCard extends StatelessWidget {
  const WingsEpisodeCard({
    super.key,
    required this.episode,
    this.watched = false,
    this.onPlay,
    this.onDownload,
    this.showThumbnail = true,
  });

  final AnimeEpisode episode;
  final bool watched;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;
  final bool showThumbnail;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onPlay,
      child: Padding(
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
                    url: episode.thumbnailUrl,
                    width: 104,
                    height: 60,
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
                    style: context.text.titleSmall?.copyWith(fontSize: 13.5),
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
            if (onDownload != null)
              WingsIconButton(
                icon: Icons.download_rounded,
                size: 36,
                onPressed: onDownload,
                color: palette.textSecondary,
              ),
            WingsIconButton(
              icon: Icons.play_circle_fill_rounded,
              size: 36,
              onPressed: onPlay,
              color: palette.primary,
            ),
          ],
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

/// Large editorial banner for the home screen.
class WingsFeaturedBanner extends StatelessWidget {
  const WingsFeaturedBanner({
    super.key,
    required this.anime,
    required this.onWatch,
    required this.onDetails,
  });

  final Anime anime;
  final VoidCallback onWatch;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final meta = <String>[
      if (anime.rating != null) '★ ${anime.rating!.toStringAsFixed(1)}',
      if (anime.year != null) '${anime.year}',
      if (anime.type != null) anime.type!,
      if (anime.episodeCount != null)
        '${anime.episodeCount} ${l10n.detailsEpisodes}',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
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
                      palette.overlay.withValues(alpha: 0.25),
                      palette.overlay.withValues(alpha: 0.55),
                      palette.overlay.withValues(alpha: 0.96),
                    ],
                    stops: const <double>[0, 0.45, 1],
                  ),
                ),
              ),
              PositionedDirectional(
                top: Space.lg,
                start: Space.lg,
                child: WingsBadge(
                  l10n.homeFeatured,
                  style: WingsBadgeStyle.brand,
                  icon: Icons.auto_awesome_rounded,
                ),
              ),
              PositionedDirectional(
                start: Space.lg,
                end: Space.lg,
                bottom: Space.lg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontSize: 23,
                        height: 1.25,
                      ),
                    ),
                    if (meta.isNotEmpty) ...<Widget>[
                      const SizedBox(height: Space.sm),
                      Text(
                        meta.join('  •  '),
                        style: context.text.labelMedium?.copyWith(
                          color: Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (anime.synopsis != null) ...<Widget>[
                      const SizedBox(height: Space.sm),
                      Text(
                        anime.synopsis!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          color: Colors.white70,
                          height: 1.55,
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.lg),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: WingsButton(
                            label: l10n.homeWatchNow,
                            icon: Icons.play_arrow_rounded,
                            onPressed: onWatch,
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: WingsButton(
                            label: l10n.homeMoreDetails,
                            variant: WingsButtonVariant.tonal,
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
        ),
      ),
    );
  }
}
