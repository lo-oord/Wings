import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/library.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final tasks = ref.watch(downloadTasksProvider);
    final storage = ref.watch(storageUsedProvider);

    final active = tasks
        .where(
          (task) =>
              task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.queued ||
              task.status == DownloadStatus.paused,
        )
        .toList();
    final completed = tasks
        .where((task) => task.status == DownloadStatus.completed)
        .toList();
    final failed = tasks
        .where((task) => task.status == DownloadStatus.failed)
        .toList();

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l10n.downloadsTitle,
              style: context.text.titleLarge?.copyWith(fontSize: 18),
            ),
            Text(
              '${l10n.downloadsStorage}: ${formatBytes(storage)}',
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
      body: tasks.isEmpty
          ? WingsEmptyState(
              icon: Icons.download_outlined,
              title: l10n.downloadsEmpty,
            )
          : ListView(
              padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
              children: <Widget>[
                if (active.isNotEmpty) ...<Widget>[
                  WingsSectionHeader(
                    title: l10n.downloadsActive,
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.md,
                      Space.lg,
                      Space.sm,
                    ),
                  ),
                  for (final task in active) _DownloadCard(task: task),
                ],
                if (failed.isNotEmpty) ...<Widget>[
                  WingsSectionHeader(
                    title: l10n.downloadsFailed,
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.xl,
                      Space.lg,
                      Space.sm,
                    ),
                  ),
                  for (final task in failed) _DownloadCard(task: task),
                ],
                if (completed.isNotEmpty) ...<Widget>[
                  WingsSectionHeader(
                    title: l10n.downloadsCompleted,
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.xl,
                      Space.lg,
                      Space.sm,
                    ),
                  ),
                  for (final task in completed) _DownloadCard(task: task),
                ],
              ],
            ),
    );
  }
}

class _DownloadCard extends ConsumerWidget {
  const _DownloadCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final notifier = ref.read(downloadTasksProvider.notifier);
    final isActive = task.status == DownloadStatus.downloading;
    final isPaused = task.status == DownloadStatus.paused;
    final isQueued = task.status == DownloadStatus.queued;
    final isFailed = task.status == DownloadStatus.failed;
    final isCompleted = task.status == DownloadStatus.completed;

    final statusLabel = switch (task.status) {
      DownloadStatus.downloading =>
        '${l10n.downloadsActive} · ${(task.progress * 100).round()}%',
      DownloadStatus.queued => l10n.downloadsQueued,
      DownloadStatus.paused => l10n.downloadsPaused,
      DownloadStatus.completed =>
        '${formatBytes(task.totalBytes)} · ${l10n.downloadsCompleted}',
      DownloadStatus.failed => l10n.downloadsFailedBody,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(Space.sm + 2),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                WingsImage(
                  url: task.posterUrl,
                  width: 52,
                  height: 74,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        task.animeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.fileName ??
                            '${l10n.commonEpisodeNumber(task.episodeNumber)} · ${task.quality}',
                        style: context.text.labelSmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        statusLabel,
                        style: context.text.labelSmall?.copyWith(
                          color: isFailed
                              ? palette.danger
                              : (isCompleted
                                    ? palette.success
                                    : palette.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  WingsIconButton(
                    icon: Icons.pause_rounded,
                    size: 34,
                    tooltip: l10n.downloadsPause,
                    onPressed: () => notifier.pause(task.id),
                  )
                else if (isPaused || isQueued)
                  WingsIconButton(
                    icon: Icons.play_arrow_rounded,
                    size: 34,
                    tooltip: l10n.downloadsResume,
                    onPressed: () => notifier.resume(task.id),
                  )
                else if (isFailed)
                  WingsIconButton(
                    icon: Icons.refresh_rounded,
                    size: 34,
                    tooltip: l10n.downloadsRetry,
                    onPressed: () => notifier.retry(task.id),
                  )
                else if (isCompleted && task.publicUri != null)
                  WingsIconButton(
                    icon: Icons.open_in_new_rounded,
                    size: 34,
                    tooltip: l10n.commonPlay,
                    onPressed: () async {
                      final opened = await ref
                          .read(storageServiceProvider)
                          .openFile(task.publicUri!);
                      if (!opened && context.mounted) {
                        context.showSnack(
                          l10n.playerPlaybackErrorBody,
                          isError: true,
                        );
                      }
                    },
                  ),
                WingsIconButton(
                  icon: isCompleted
                      ? Icons.delete_outline_rounded
                      : Icons.close_rounded,
                  size: 34,
                  tooltip: isCompleted
                      ? l10n.downloadsDelete
                      : l10n.downloadsCancel,
                  color: isCompleted ? palette.danger : palette.textSecondary,
                  onPressed: () async {
                    if (isCompleted) {
                      final confirmed = await WingsDialog.confirm(
                        context,
                        title: l10n.settingsConfirmClearTitle,
                        message: l10n.downloadsDelete,
                        confirmLabel: l10n.commonDelete,
                        destructive: true,
                      );
                      if (!confirmed) return;
                      await notifier.deleteFile(task.id);
                    } else {
                      await notifier.cancel(task.id);
                    }
                  },
                ),
              ],
            ),
            if (!isCompleted) ...<Widget>[
              const SizedBox(height: Space.sm),
              WingsProgressBar(value: task.progress, height: 4),
              const SizedBox(height: Space.xs),
              Row(
                children: <Widget>[
                  Text(
                    formatBytes(task.receivedBytes),
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    task.totalBytes > 0 ? formatBytes(task.totalBytes) : '—',
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
