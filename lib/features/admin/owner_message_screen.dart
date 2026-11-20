import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import '../profile/avatar_view.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../core/errors/user_facing_error.dart';

/// The signature printed at the bottom of every Owner message.
const String kOwnerSignatureAr = 'مع تحياتي\nمطور Wings';

/// The premium card that separates an Owner message from every other surface.
class OwnerMessageCard extends StatelessWidget {
  const OwnerMessageCard({
    super.key,
    required this.message,
    this.showRecipient = false,
    this.onOpenRecipient,
  });

  final OwnerMessage message;
  final bool showRecipient;
  final VoidCallback? onOpenRecipient;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final gold = palette.isDark ? kOwnerGold : kOwnerGoldDeep;
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: kOwnerGold.withValues(alpha: 0.45)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[
            kOwnerGold.withValues(alpha: palette.isDark ? 0.10 : 0.08),
            palette.surface,
            palette.surface,
          ],
          stops: const <double>[0, 0.35, 1],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kOwnerGold.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: <Color>[kOwnerGold, kOwnerGoldDeep],
                    ),
                  ),
                  child: UserAvatar(
                    uid: message.fromUid,
                    photoVersion: message.fromPhotoVersion,
                    name: message.fromName,
                    size: 38,
                  ),
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
                              message.fromName.isEmpty
                                  ? 'Wings Owner'
                                  : message.fromName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyLarge?.copyWith(
                                color: gold,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const OwnerBadge(compact: true),
                        ],
                      ),
                      Text(
                        message.fromUsername.isEmpty
                            ? '@wings'
                            : '@${message.fromUsername}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: gold.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!message.read)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: kOwnerGold,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: <Widget>[
                Icon(Icons.mail_rounded, size: 13, color: gold),
                const SizedBox(width: 5),
                Text(
                  Tr.of(
                    context,
                    ar: 'رسالة من المالك',
                    en: 'Message from Owner',
                  ),
                  style: context.text.labelSmall?.copyWith(
                    color: gold,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            if (message.title.isNotEmpty) ...<Widget>[
              Text(
                message.title,
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: palette.surfaceAlt.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: kOwnerGold.withValues(alpha: 0.18)),
              ),
              child: Text(
                message.body,
                style: context.text.bodyMedium?.copyWith(height: 1.7),
              ),
            ),
            const SizedBox(height: Space.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (final line in kOwnerSignatureAr.split('\n'))
                    Text(
                      line,
                      style: context.text.labelSmall?.copyWith(
                        color: gold,
                        fontWeight: FontWeight.w600,
                        height: 1.6,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.xs),
            Row(
              children: <Widget>[
                Text(
                  adminDate(message.createdAt),
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const Spacer(),
                if (showRecipient)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                    ),
                    onPressed: onOpenRecipient,
                    child: Text(
                      '@${message.toUsername}',
                      style: context.text.labelSmall,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One message, opened from a notification.
class OwnerMessageScreen extends ConsumerStatefulWidget {
  const OwnerMessageScreen({super.key, required this.messageId});

  final String messageId;

  @override
  ConsumerState<OwnerMessageScreen> createState() => _OwnerMessageScreenState();
}

class _OwnerMessageScreenState extends ConsumerState<OwnerMessageScreen> {
  OwnerMessage? _message;
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = ref.read(authProvider)?.id;
    if (uid == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    try {
      final message = await ref
          .read(adminRepositoryProvider)
          .message(widget.messageId, uid);
      if (!mounted) return;
      setState(() {
        _message = message;
        _loading = false;
      });
      if (message != null && !message.read && uid == message.toUid) {
        try {
          await ref
              .read(adminRepositoryProvider)
              .markMessageRead(widget.messageId, uid);
        } on Object {
          // The badge clears on the next open.
        }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = userFacingError(context, error);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Text(Tr.of(context, ar: 'رسالة من المالك', en: 'Owner message')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _message == null
          ? WingsEmptyState(
              icon: Icons.mail_outline_rounded,
              title: Tr.of(
                context,
                ar: 'الرسالة غير متاحة',
                en: 'Message unavailable',
              ),
              message: _error,
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.xxxl),
              children: <Widget>[
                const SizedBox(height: Space.sm),
                OwnerMessageCard(message: _message!),
              ],
            ),
    );
  }
}

/// The recipient's inbox: every Owner message sent to this account.
class OwnerInboxScreen extends ConsumerWidget {
  const OwnerInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(ownerInboxProvider);
    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Text(Tr.of(context, ar: 'رسائل المالك', en: 'Owner messages')),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () => ref.invalidate(ownerInboxProvider),
          ),
        ],
      ),
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => WingsEmptyState(
          icon: Icons.cloud_off_rounded,
          title: Tr.of(context, ar: 'تعذّر التحميل', en: 'Failed to load'),
          message: loadFailedText(context),
        ),
        data: (items) {
          if (items.isEmpty) {
            return WingsEmptyState(
              icon: Icons.mark_email_read_outlined,
              title: Tr.of(
                context,
                ar: 'لا توجد رسائل من المالك',
                en: 'No Owner messages',
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: Space.xxxl),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final message = items[index];
              return InkWell(
                onTap: () async {
                  await context.push(RoutePaths.ownerMessage(message.id));
                  ref.invalidate(ownerInboxProvider);
                  ref.invalidate(ownerUnreadProvider);
                },
                child: OwnerMessageCard(
                  message: message,
                  onOpenRecipient: () =>
                      context.push(RoutePaths.publicProfile(message.fromUid)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
