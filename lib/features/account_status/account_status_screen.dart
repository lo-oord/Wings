import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import '../admin/admin_providers.dart';
import '../admin/admin_widgets.dart';

/// What the affected member sees: the state, the reason, the restrictions and
/// the review request. It never reveals internal notes.
class AccountStatusScreen extends ConsumerStatefulWidget {
  const AccountStatusScreen({super.key});

  @override
  ConsumerState<AccountStatusScreen> createState() =>
      _AccountStatusScreenState();
}

class _AccountStatusScreenState extends ConsumerState<AccountStatusScreen> {
  Future<void> _requestReview() async {
    final user = ref.read(authProvider);
    if (user == null) return;
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Tr.of(context, ar: 'طلب مراجعة', en: 'Request a review')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              Tr.of(
                context,
                ar: 'اشرح سبب اعتقادك أن الإجراء غير صحيح.',
                en: 'Explain why you believe the action was incorrect.',
              ),
              style: dialogContext.text.bodySmall,
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: controller,
              maxLines: 4,
              autofocus: true,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'رسالتك', en: 'Your message'),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.of(dialogContext).pop(text);
            },
            child: Text(Tr.of(context, ar: 'إرسال', en: 'Send')),
          ),
        ],
      ),
    );
    if (message == null || !mounted) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .submitAppeal(
            uid: user.id,
            username: ref.read(profileProvider)?.username ?? user.username,
            message: message,
          );
      if (mounted) {
        context.showSnack(
          Tr.of(context, ar: 'تم إرسال طلب المراجعة.', en: 'Review requested.'),
        );
      }
    } on Object catch (error) {
      if (mounted) context.showSnack(error.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(myAccountStatusProvider);
    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Text(Tr.of(context, ar: 'حالة الحساب', en: 'Account status')),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.mail_outline_rounded, size: 20),
            tooltip: Tr.of(context, ar: 'رسائل المالك', en: 'Owner messages'),
            onPressed: () => context.push(RoutePaths.ownerMessages),
          ),
        ],
      ),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => WingsEmptyState(
          icon: Icons.cloud_off_rounded,
          title: Tr.of(context, ar: 'تعذّر التحميل', en: 'Failed to load'),
          message: error.toString(),
        ),
        data: (record) {
          final now = DateTime.now();
          final effective = record.effectiveState(now);
          final restrictions = record.activeRestrictions(now);
          return ListView(
            padding: const EdgeInsets.only(bottom: Space.xxxl),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.lg,
                  Space.xs,
                ),
                child: Row(
                  children: <Widget>[
                    AdminStatusChip(
                      state: effective,
                      expiresAt: record.expiresAt,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      onPressed: () => ref.invalidate(myAccountStatusProvider),
                    ),
                  ],
                ),
              ),
              AdminCard(
                title: Tr.of(context, ar: 'تفاصيل الحالة', en: 'State details'),
                children: <Widget>[
                  AdminKeyValue(
                    label: Tr.of(context, ar: 'الحالة', en: 'State'),
                    value: adminStateLabel(context, effective),
                    valueColor: adminStateColor(context, effective),
                  ),
                  if (record.reason.isNotEmpty)
                    AdminKeyValue(
                      label: Tr.of(context, ar: 'السبب', en: 'Reason'),
                      value: record.reason,
                    ),
                  if (record.expiresAt != null)
                    AdminKeyValue(
                      label: Tr.of(context, ar: 'ينتهي', en: 'Expires'),
                      value: adminDate(record.expiresAt),
                    ),
                  AdminKeyValue(
                    label: Tr.of(context, ar: 'القيود', en: 'Restrictions'),
                    value: restrictions.isEmpty
                        ? Tr.of(context, ar: 'لا يوجد', en: 'None')
                        : restrictions
                              .map((item) => restrictionLabel(context, item))
                              .join('، '),
                  ),
                ],
              ),
              if (effective != AccountState.active &&
                  effective != AccountState.warned)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.md,
                    Space.lg,
                    0,
                  ),
                  child: WingsButton(
                    label: Tr.of(
                      context,
                      ar: 'طلب مراجعة',
                      en: 'Request a review',
                    ),
                    icon: Icons.gavel_rounded,
                    expand: true,
                    variant: WingsButtonVariant.tonal,
                    onPressed: _requestReview,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.md,
                  Space.lg,
                  0,
                ),
                child: Text(
                  Tr.of(
                    context,
                    ar: 'تُطبَّق القيود على عمليات التطبيق نفسها من جهة الخادم، لا على الأزرار فقط. إذا انتهت مدة الإيقاف يعود الحساب للعمل تلقائيًا.',
                    en: 'Restrictions are enforced on the app operations themselves, not only on buttons. A temporary suspension ends by itself when its time is up.',
                  ),
                  style: context.text.labelSmall?.copyWith(
                    color: context.palette.textMuted,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Compact banner shown on the account surfaces when something is in force.
class AccountStatusBanner extends ConsumerWidget {
  const AccountStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(myAccountStatusProvider).value;
    if (record == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final effective = record.effectiveState(now);
    if (effective == AccountState.active || effective == AccountState.warned) {
      return const SizedBox.shrink();
    }
    final color = adminStateColor(context, effective);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: () => context.push(RoutePaths.accountStatus),
          child: Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.info_outline_rounded, size: 16, color: color),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    Tr.of(
                      context,
                      ar: 'حسابك ${adminStateLabel(context, effective)}. اضغط لعرض التفاصيل.',
                      en: 'Your account is ${adminStateLabel(context, effective)}. Tap for details.',
                    ),
                    style: context.text.labelSmall?.copyWith(color: color),
                  ),
                ),
                Icon(
                  context.isRtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 16,
                  color: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen block for a banned or deleted account.
class AccountBlockedScreen extends ConsumerWidget {
  const AccountBlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(myAccountStatusProvider).value;
    final state = record?.effectiveState(DateTime.now()) ?? AccountState.active;
    final deleted = state == AccountState.deleted;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                deleted ? Icons.person_off_outlined : Icons.block_rounded,
                size: 44,
                color: context.palette.danger,
              ),
              const SizedBox(height: Space.lg),
              Text(
                deleted
                    ? Tr.of(
                        context,
                        ar: 'تم حذف هذا الحساب',
                        en: 'This account was deleted',
                      )
                    : Tr.of(
                        context,
                        ar: 'هذا الحساب محظور',
                        en: 'This account is banned',
                      ),
                textAlign: TextAlign.center,
                style: context.text.titleMedium,
              ),
              const SizedBox(height: Space.sm),
              if ((record?.reason ?? '').isNotEmpty)
                Text(
                  record!.reason,
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              const SizedBox(height: Space.lg),
              WingsButton(
                label: Tr.of(
                  context,
                  ar: 'تفاصيل الحساب',
                  en: 'Account details',
                ),
                variant: WingsButtonVariant.outline,
                onPressed: () => context.push(RoutePaths.accountStatus),
              ),
              const SizedBox(height: Space.sm),
              TextButton(
                onPressed: () async {
                  await ref.read(authProvider.notifier).signOut();
                  if (context.mounted) context.go(RoutePaths.welcome);
                },
                child: Text(Tr.of(context, ar: 'خروج', en: 'Sign out')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
