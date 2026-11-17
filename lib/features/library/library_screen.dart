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
import '../../core/widgets/wings_cards.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/library.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _search = TextEditingController();
  bool _sortByTitle = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LibraryEntry> _filterEntries(List<LibraryEntry> items) {
    final query = _search.text.trim().toLowerCase();
    final list = query.isEmpty
        ? List<LibraryEntry>.of(items)
        : items
              .where(
                (entry) =>
                    entry.anime.title.toLowerCase().contains(query) ||
                    (entry.anime.englishTitle ?? '').toLowerCase().contains(
                      query,
                    ),
              )
              .toList();
    list.sort(
      _sortByTitle
          ? (a, b) => a.anime.title.compareTo(b.anime.title)
          : (a, b) => b.updatedAt.compareTo(a.updatedAt),
    );
    return list;
  }

  List<WatchHistoryEntry> _filterHistory(List<WatchHistoryEntry> items) {
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty
        ? items
        : items
              .where((entry) => entry.animeTitle.toLowerCase().contains(query))
              .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = ref.watch(libraryProvider);
    final palette = context.palette;
    final downloads = ref
        .watch(downloadTasksProvider)
        .where((task) => task.status == DownloadStatus.completed)
        .toList();

    return DefaultTabController(
      length: 8,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.md,
                  Space.lg,
                  Space.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Text(l10n.libraryTitle, style: context.text.headlineSmall),
                    const Spacer(),
                    if (ref.watch(authProvider) != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: Space.xs,
                        ),
                        child: WingsIconButton(
                          icon: Icons.sync_rounded,
                          tooltip: Tr.of(
                            context,
                            ar: 'مزامنة المكتبة',
                            en: 'Sync library',
                          ),
                          onPressed: () async {
                            await ref
                                .read(authProvider.notifier)
                                .syncNow(force: true);
                            if (context.mounted) {
                              context.showSnack(
                                Tr.of(
                                  context,
                                  ar: 'تمت مزامنة مكتبتك.',
                                  en: 'Your library is synced.',
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    WingsIconButton(
                      icon: Icons.download_done_rounded,
                      tooltip: l10n.downloadsTitle,
                      onPressed: () => context.push(RoutePaths.downloads),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          style: context.text.bodyMedium,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l10n.librarySearchHint,
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: palette.textMuted,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 38,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: Space.sm,
                              vertical: Space.sm,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    WingsIconButton(
                      icon: _sortByTitle
                          ? Icons.sort_by_alpha_rounded
                          : Icons.schedule_rounded,
                      tooltip: _sortByTitle
                          ? l10n.librarySortTitle
                          : l10n.librarySortDate,
                      filled: true,
                      onPressed: () =>
                          setState(() => _sortByTitle = !_sortByTitle),
                    ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                tabs: <Widget>[
                  Tab(text: l10n.libraryFavorites),
                  Tab(text: l10n.libraryWatching),
                  Tab(text: l10n.libraryCompleted),
                  Tab(text: l10n.libraryPlan),
                  Tab(text: l10n.libraryOnHold),
                  Tab(text: l10n.libraryDropped),
                  Tab(text: l10n.libraryHistory),
                  Tab(text: l10n.libraryDownloaded),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _EntriesTab(
                      entries: _filterEntries(library.favorites),
                      emptyTitle: l10n.libraryEmptyFavorites,
                      onChanged: _refresh,
                    ),
                    _EntriesTab(
                      entries: _filterEntries(
                        library.byStatus(LibraryStatus.watching),
                      ),
                      emptyTitle: l10n.libraryEmptyGeneric,
                      onChanged: _refresh,
                    ),
                    _EntriesTab(
                      entries: _filterEntries(
                        library.byStatus(LibraryStatus.completed),
                      ),
                      emptyTitle: l10n.libraryEmptyGeneric,
                      onChanged: _refresh,
                    ),
                    _EntriesTab(
                      entries: _filterEntries(
                        library.byStatus(LibraryStatus.planToWatch),
                      ),
                      emptyTitle: l10n.libraryEmptyGeneric,
                      onChanged: _refresh,
                    ),
                    _EntriesTab(
                      entries: _filterEntries(
                        library.byStatus(LibraryStatus.onHold),
                      ),
                      emptyTitle: l10n.libraryEmptyGeneric,
                      onChanged: _refresh,
                    ),
                    _EntriesTab(
                      entries: _filterEntries(
                        library.byStatus(LibraryStatus.dropped),
                      ),
                      emptyTitle: l10n.libraryEmptyGeneric,
                      onChanged: _refresh,
                    ),
                    _HistoryTab(
                      entries: _filterHistory(library.history),
                      onChanged: _refresh,
                    ),
                    _DownloadsTab(tasks: downloads),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _refresh() => setState(() {});
}

class _EntriesTab extends ConsumerWidget {
  const _EntriesTab({
    required this.entries,
    required this.emptyTitle,
    required this.onChanged,
  });

  final List<LibraryEntry> entries;
  final String emptyTitle;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (entries.isEmpty) {
      return WingsEmptyState(
        icon: Icons.video_library_outlined,
        title: emptyTitle,
        actionLabel: l10n.exploreTitle,
        onAction: () => context.go(RoutePaths.explore),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxl),
      itemCount: entries.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: context.palette.border,
        indent: Space.lg,
        endIndent: Space.lg,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return WingsAnimeListTile(
          anime: entry.anime,
          onTap: () => context.push(RoutePaths.anime(entry.anime.id)),
          subtitle: _statusLabel(context, entry.status),
          trailing: PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              size: 18,
              color: context.palette.textMuted,
            ),
            onSelected: (value) async {
              final controller = ref.read(libraryProvider.notifier);
              switch (value) {
                case 'favorite':
                  await controller.toggleFavorite(entry.anime);
                  break;
                case 'remove':
                  await controller.removeFromLibrary(entry.anime.id);
                  break;
                default:
                  final status = LibraryStatus.values.firstWhere(
                    (item) => item.name == value,
                    orElse: () => entry.status,
                  );
                  await controller.setStatus(entry.anime, status);
                  break;
              }
              onChanged();
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'favorite',
                child: Text(
                  entry.isFavorite
                      ? l10n.detailsRemoved
                      : l10n.detailsFavorites,
                ),
              ),
              for (final status in LibraryStatus.values)
                PopupMenuItem<String>(
                  value: status.name,
                  child: Text(_statusLabel(context, status)),
                ),
              PopupMenuItem<String>(
                value: 'remove',
                child: Text(l10n.libraryRemove),
              ),
            ],
          ),
        );
      },
    );
  }

  String _statusLabel(BuildContext context, LibraryStatus status) {
    final l10n = AppLocalizations.of(context);
    return switch (status) {
      LibraryStatus.watching => l10n.detailsWatching,
      LibraryStatus.completed => l10n.detailsCompleted,
      LibraryStatus.planToWatch => l10n.detailsPlanToWatch,
      LibraryStatus.onHold => l10n.detailsOnHold,
      LibraryStatus.dropped => l10n.detailsDropped,
    };
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.entries, required this.onChanged});

  final List<WatchHistoryEntry> entries;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    if (entries.isEmpty) {
      return WingsEmptyState(
        icon: Icons.history_rounded,
        title: l10n.libraryEmptyHistory,
        actionLabel: l10n.exploreTitle,
        onAction: () => context.go(RoutePaths.explore),
      );
    }
    return Column(
      children: <Widget>[
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () async {
              final confirmed = await WingsDialog.confirm(
                context,
                title: l10n.settingsConfirmClearTitle,
                message: l10n.libraryClearHistoryBody,
                confirmLabel: l10n.commonClear,
                destructive: true,
              );
              if (!confirmed) return;
              await ref.read(libraryProvider.notifier).clearHistory();
              onChanged();
            },
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            label: Text(l10n.libraryClearHistory),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: Space.xxl),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return InkWell(
                onTap: () => context.push(
                  RoutePaths.watch(
                    animeId: entry.animeId,
                    episodeId: entry.episodeId,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.sm + 2,
                  ),
                  child: Row(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.xs),
                        child: SizedBox(
                          width: 88,
                          height: 50,
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              WingsImage(url: entry.posterUrl),
                              PositionedDirectional(
                                bottom: Space.xs,
                                start: Space.xs,
                                child: WingsBadge(
                                  '${entry.episodeNumber}',
                                  style: WingsBadgeStyle.overlay,
                                  compact: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              entry.animeTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${AppLocalizations.of(context).commonEpisodeNumber(entry.episodeNumber)} · ${relativeTime(entry.updatedAt, l10n)}',
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!entry.completed) ...<Widget>[
                              const SizedBox(height: Space.xs),
                              WingsProgressBar(
                                value: entry.progress,
                                height: 3,
                              ),
                            ],
                          ],
                        ),
                      ),
                      WingsIconButton(
                        icon: Icons.close_rounded,
                        size: 32,
                        onPressed: () async {
                          await ref
                              .read(libraryProvider.notifier)
                              .removeHistoryEntry(entry.key);
                          onChanged();
                        },
                        color: palette.textMuted,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab({required this.tasks});

  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (tasks.isEmpty) {
      return WingsEmptyState(
        icon: Icons.download_outlined,
        title: l10n.libraryEmptyGeneric,
        message: l10n.downloadsEmpty,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxl),
      itemCount: tasks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.sm,
              Space.lg,
              Space.sm,
            ),
            child: Row(
              children: <Widget>[
                Text(l10n.libraryDownloaded, style: context.text.titleSmall),
                const Spacer(),
                TextButton(
                  onPressed: () => context.push(RoutePaths.downloads),
                  child: Text(l10n.downloadsTitle),
                ),
              ],
            ),
          );
        }
        final task = tasks[index - 1];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.xs,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xs),
            child: WingsImage(url: task.posterUrl, width: 44, height: 62),
          ),
          title: Text(task.animeTitle, style: context.text.titleSmall),
          subtitle: Text(
            '${l10n.commonEpisodeNumber(task.episodeNumber)} · ${formatBytes(task.totalBytes)}',
            style: context.text.bodySmall,
          ),
          trailing: Icon(
            Icons.offline_pin_rounded,
            color: context.palette.success,
            size: 20,
          ),
        );
      },
    );
  }
}
