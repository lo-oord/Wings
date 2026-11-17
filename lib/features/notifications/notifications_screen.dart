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
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/social_notification.dart';

/// Everything the viewer needs to catch up: new episodes discovered on the
/// device and replies other members wrote on their comments.
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _markEverythingRead());
  }

  Future<void> _markEverythingRead() async {
    await ref.read(notificationsProvider.notifier).refresh();
    await ref.read(notificationsProvider.notifier).markAllRead();
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return;
    try {
      await ref.read(notificationRepositoryProvider).markAllRead(uid);
    } on Object {
      // Offline: the badges clear on the next visit.
    }
  }

  Future<void> _clearAll(String? uid) async {
    await ref.read(notificationsProvider.notifier).clear();
    if (uid == null) return;
    try {
      await ref.read(notificationRepositoryProvider).clear(uid);
    } on Object {
      // Keep what is left for the next attempt.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final uid = ref.watch(authProvider)?.id;
    final local = ref.watch(notificationsProvider);
    final replies = uid == null
        ? const <SocialNotification>[]
        : (ref.watch(socialNotificationsProvider(uid)).value ??
              const <SocialNotification>[]);
    final isEmpty = local.isEmpty && replies.isEmpty;

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Text(l10n.notificationsTitle),
        actions: <Widget>[
          if (!isEmpty)
            TextButton(
              onPressed: () => _clearAll(uid),
              child: Text(l10n.commonClear),
            ),
        ],
      ),
      body: isEmpty
          ? WingsEmptyState(
              icon: Icons.notifications_none_rounded,
              title: l10n.notificationsEmpty,
            )
          : ListView(
              padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
              children: <Widget>[
                if (replies.isNotEmpty) ...<Widget>[
                  _SectionLabel(
                    label: Tr.of(
                      context,
                      ar: 'الردود والتعليقات',
                      en: 'Replies and comments',
                    ),
                    color: palette.textMuted,
                  ),
                  for (final reply in replies)
                    _ReplyTile(
                      notification: reply,
                      onTap: () => context.push(reply.route),
                      onRemove: () async {
                        if (uid == null) return;
                        try {
                          await ref
                              .read(notificationRepositoryProvider)
                              .remove(uid, reply.id);
                        } on Object {
                          // Ignore: it stays until the next attempt.
                        }
                      },
                    ),
                ],
                if (local.isNotEmpty) ...<Widget>[
                  _SectionLabel(
                    label: Tr.of(
                      context,
                      ar: 'الحلقات الجديدة',
                      en: 'New episodes',
                    ),
                    color: palette.textMuted,
                  ),
                  for (final item in local)
                    _NotificationTile(notification: item),
                ],
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.xs,
      ),
      child: Text(
        label,
        style: context.text.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({
    required this.notification,
    required this.onTap,
    required this.onRemove,
  });

  final SocialNotification notification;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final initial = notification.actorName.trim().isEmpty
        ? '?'
        : notification.actorName.trim().characters.first;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 20,
              backgroundColor: palette.surfaceAlt,
              child: Text(
                initial,
                style: context.text.titleSmall?.copyWith(
                  color: palette.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          notification.actorName.isEmpty
                              ? '@${notification.actorUsername}'
                              : notification.actorName,
                          maxLines: 1,
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
                    Tr.of(
                      context,
                      ar: 'ردّ على تعليقك: ${notification.text}',
                      en: 'Replied to your comment: ${notification.text}',
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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
            IconButton(
              tooltip: Tr.of(context, ar: 'إزالة', en: 'Remove'),
              onPressed: onRemove,
              icon: Icon(
                Icons.close_rounded,
                size: 16,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
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
