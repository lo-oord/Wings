import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../profile/avatar_view.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../core/errors/user_facing_error.dart';

/// History of the messages the Owner sent. Only staff can read this list: the
/// recipient sees their own copy, nobody else's.
class AdminMessagesScreen extends ConsumerWidget {
  const AdminMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sent = ref.watch(adminSentMessagesProvider);
    return AdminGuard(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text(Tr.of(context, ar: 'رسائل المالك', en: 'Owner messages')),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () => ref.invalidate(adminSentMessagesProvider),
            ),
          ],
        ),
        body: sent.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => WingsEmptyState(
            icon: Icons.cloud_off_rounded,
            title: Tr.of(context, ar: 'تعذّر التحميل', en: 'Failed to load'),
            message: loadFailedText(context),
          ),
          data: (page) {
            if (page.items.isEmpty) {
              return WingsEmptyState(
                icon: Icons.mail_outline_rounded,
                title: Tr.of(
                  context,
                  ar: 'لم ترسل أي رسالة بعد',
                  en: 'No messages sent yet',
                ),
                message: Tr.of(
                  context,
                  ar: 'أرسل رسالة من صفحة أي عضو.',
                  en: 'Send a message from any member page.',
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: Space.xxxl),
              itemCount: page.items.length,
              itemBuilder: (context, index) {
                final message = page.items[index];
                return AdminCard(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        UserAvatar(
                          uid: message.toUid,
                          name: message.toUsername,
                          size: 34,
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Flexible(
                                    child: Text(
                                      message.title.isEmpty
                                          ? Tr.of(
                                              context,
                                              ar: 'رسالة من المالك',
                                              en: 'Owner message',
                                            )
                                          : message.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.text.bodySmall?.copyWith(
                                        color: kOwnerGold,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '@${message.toUsername} · ${adminDate(message.createdAt)}',
                                style: context.text.labelSmall?.copyWith(
                                  color: context.palette.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            message.read
                                ? Tr.of(context, ar: 'مقروءة', en: 'Read')
                                : Tr.of(
                                    context,
                                    ar: 'غير مقروءة',
                                    en: 'Unread',
                                  ),
                            style: context.text.labelSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      message.body,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(height: 1.5),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () =>
                            context.push(RoutePaths.adminUser(message.toUid)),
                        child: Text(
                          Tr.of(
                            context,
                            ar: 'فتح حساب المستلم',
                            en: 'Open recipient',
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
