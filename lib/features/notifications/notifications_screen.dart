import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';

/// Notification centre.
///
/// Only real notifications are surfaced; remote announcements and new-episode
/// alerts require a backend and are therefore not fabricated here.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Text(l10n.notificationsTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: l10n.notificationsSettings,
            onPressed: () => context.go(RoutePaths.settings),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Container(
            margin: const EdgeInsets.all(Space.lg),
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: palette.primary,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'تُنشأ الإشعارات محلياً لتنبيهات التنزيل. تنبيهات الحلقات الجديدة '
                    'تحتاج خدمة خلفية وسيتم تفعيلها عند ربطها.',
                    style: context.text.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: WingsEmptyState(
              icon: Icons.notifications_none_rounded,
              title: l10n.notificationsEmpty,
              actionLabel: l10n.notificationsSettings,
              onAction: () => context.go(RoutePaths.settings),
            ),
          ),
        ],
      ),
    );
  }
}
