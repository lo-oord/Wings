import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/app_notification.dart';

/// New-episode alerts generated on the device by the background worker.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(notificationsProvider.notifier).refresh();
      await ref.read(notificationsProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Text(l10n.notificationsTitle),
        actions: <Widget>[
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(notificationsProvider.notifier).clear(),
              child: Text(l10n.commonClear),
            ),
        ],
      ),
      body: items.isEmpty
          ? WingsEmptyState(
              icon: Icons.notifications_none_rounded,
              title: l10n.notificationsEmpty,
            )
          : ListView.separated(
              padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: context.palette.border,
                indent: Space.lg,
                endIndent: Space.lg,
              ),
              itemBuilder: (context, index) =>
                  _NotificationTile(notification: items[index]),
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final body = l10n.notificationsEpisodeBody(notification.episodeNumber);

    return InkWell(
      onTap: () => context.push(
        RoutePaths.watch(
          animeId: notification.animeId,
          episodeId: notification.episodeId,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            WingsImage(
              url: notification.posterUrl,
              width: 52,
              height: 74,
              borderRadius: BorderRadius.circular(Radii.xs),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          notification.animeTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall,
                        ),
                      ),
                      if (!notification.read)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsetsDirectional.only(start: 6),
                          decoration: BoxDecoration(
                            color: palette.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: context.text.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    relativeTime(notification.createdAt, l10n),
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              context.isRtl
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              size: 18,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
