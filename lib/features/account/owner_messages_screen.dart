import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import '../../admin/admin_widgets.dart';

/// Personal messages from the Wings owner and the administrative notices
/// written next to every privileged action.
class OwnerMessagesScreen extends ConsumerWidget {
  const OwnerMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final messages = ref.watch(ownerMessagesProvider(authProviderUidProvider));
    final notices = ref.watch(adminNoticesProvider(authProviderUidProvider));
    final unread = ref.watch(ownerUnreadCountProvider(authProviderUidProvider));
    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Row(
          children: <Widget>[
            Icon(
              unread > 0 ? Icons.notifications_active_rounded : Icons.mark_email_read_rounded,
              size: 19,
            ),
            const SizedBox(width: Space.sm),
            Flexible(
              child: RichText(
                text: TextSpan(
                  style: context.text.titleMedium,
                  children: <TextSpan>[
                    TextSpan(
                      text: 'رسائل المالك',
                      children: <TextSpan>[
                        TextSpan(
                          text: unread > 0
                              ? ' · غير مقروءة: $unread'
                              : '',
                          style: context.text.bodySmall?.copyWith(
                            color: palette.textMuted,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: messages.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(
            'تعذّر تحميل رسائل المالك.',
            style: context.text.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.sm,
            Space.lg,
            Space.huge,
          ),
          children: <Widget>[
            if (items.isEmpty && notices.isEmpty)
              AdminCard(
                child: Text(
                  'لا توجد رسائل جديدة من إدارة Wings.',
                  style: context.text.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              )
            else
              ..._sections(items, notices),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(
    List<OwnerMessage> messages,
    List<AdminNotice> notices,
  ) {
    final children = <Widget>[];
    if (messages.isNotEmpty) ...<Widget>[
      AdminSectionTitle('رسائل من مالك Wings'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: AdminCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (final message in messages)
                _MessageRow(
                  message: message,
                  senderName: 'مaloك Wings',
                  onOpen: () => ref
                      .read(adminRepositoryProvider)
                      .markOwnerMessageRead(
                        authProviderUidProvider.value ?? '',
                        message.id,
                      ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: Space.sm),
    ];
    if (notices.isNotEmpty) ...<Widget>[
      AdminSectionTitle('إشعارات الإدارة'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: AdminCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (final notice in notices)
                _NoticeRow(
                  notice: notice,
                  onOpen: () =>
                      ref.read(adminRepositoryProvider)
                          .markAdminNoticeRead(
                            authProviderUidProvider.value ?? '',
                            notice.id,
                          ),
                ),
            ],
          ),
        ),
      ),
    ];
    return children;
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.senderName,
    required this.onOpen,
  });

  final OwnerMessage message;
  final String senderName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final read = message.read;
    return AdminCard(
      padding: EdgeInsets.zero,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  message.title.isEmpty ? 'رسالة من المالك' : message.title,
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                if (!read)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: palette.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      'غير مقروءة',
                      style: context.text.labelSmall?.copyWith(
                        color: palette.warning,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              '${senderName} · ${adminMoment(message.createdAt)}',
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              message.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.notice, required this.onOpen});

  final AdminNotice notice;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AdminCard(
      padding: EdgeInsets.zero,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.xs,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _tone(context, notice.severity)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    _label(context, notice.category),
                    style: context.text.labelSmall?.copyWith(
                      color: _tone(context, notice.severity),
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: RichText(
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      text: notice.title,
                      style: context.text.titleSmall,
                      children: <TextSpan>[
                        if (notice.body.isNotEmpty)
                          TextSpan(
                            text: '\n${notice.body}',
                            style: context.text.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              '${_label(context, notice.category)} · ${adminMoment(notice.createdAt)}',
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            if (!notice.read) ...<Widget>[
              const SizedBox(height: Space.xs),
              Text(
                'غير مقروءة',
                style: context.text.labelSmall?.copyWith(
                  color: palette.warning,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _tone(BuildContext context, String severity) => switch (severity) {
    'critical' => context.palette.danger,
    'warning' => context.palette.warning,
    _ => context.palette.primary,
  };

  String _label(BuildContext context, String category) => switch (category) {
    'account-status' => 'حالةالحساب',
    'warning' => 'إنذار',
    'restriction' => 'قيود',
    'message' => 'رسالة',
    'deletion' => 'حذف',
    _ => 'إشعار',
  };
}

// A read-only view of the signed-in account id, shared by the mail and
// notice streams.
final authProviderUidProvider = Provider<String?>((ref) => ref.watch(authProvider)?.id);
