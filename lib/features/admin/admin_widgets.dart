import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import 'admin_providers.dart';

/// The Owner's gold. Kept as one constant so the badge, the message card and
/// the identity marks always agree.
const Color kOwnerGold = Color(0xFFD4AF37);
const Color kOwnerGoldDeep = Color(0xFFB8912B);

String adminStateLabel(BuildContext context, AccountState state) {
  return switch (state) {
    AccountState.active => Tr.of(context, ar: 'نشط', en: 'Active'),
    AccountState.warned => Tr.of(
      context,
      ar: 'موجَّه إليه تحذير',
      en: 'Warned',
    ),
    AccountState.restricted => Tr.of(context, ar: 'مقيَّد', en: 'Restricted'),
    AccountState.suspended => Tr.of(
      context,
      ar: 'موقوف مؤقتًا',
      en: 'Suspended',
    ),
    AccountState.banned => Tr.of(context, ar: 'محظور نهائيًا', en: 'Banned'),
    AccountState.underReview => Tr.of(
      context,
      ar: 'قيد المراجعة',
      en: 'Under review',
    ),
    AccountState.deleted => Tr.of(context, ar: 'محذوف', en: 'Deleted'),
  };
}

String adminActionLabel(BuildContext context, AdminAction action) {
  return switch (action) {
    AdminAction.warn => Tr.of(context, ar: 'تحذير', en: 'Warning'),
    AdminAction.revokeWarning => Tr.of(
      context,
      ar: 'إلغاء تحذير',
      en: 'Warning revoked',
    ),
    AdminAction.restrict => Tr.of(context, ar: 'تقييد', en: 'Restriction'),
    AdminAction.unrestrict => Tr.of(
      context,
      ar: 'رفع تقييد',
      en: 'Restriction lifted',
    ),
    AdminAction.suspend => Tr.of(context, ar: 'إيقاف مؤقت', en: 'Suspension'),
    AdminAction.ban => Tr.of(context, ar: 'حظر دائم', en: 'Permanent ban'),
    AdminAction.restore => Tr.of(context, ar: 'استعادة الحساب', en: 'Restored'),
    AdminAction.review => Tr.of(context, ar: 'مراجعة', en: 'Review'),
    AdminAction.deleteAccount => Tr.of(
      context,
      ar: 'حذف حساب',
      en: 'Account deleted',
    ),
    AdminAction.blockEmail => Tr.of(
      context,
      ar: 'حظر بريد',
      en: 'Email blocked',
    ),
    AdminAction.unblockEmail => Tr.of(
      context,
      ar: 'رفع حظر بريد',
      en: 'Email unblocked',
    ),
    AdminAction.blockUsername => Tr.of(
      context,
      ar: 'حظر اسم مستخدم',
      en: 'Username blocked',
    ),
    AdminAction.unblockUsername => Tr.of(
      context,
      ar: 'رفع حظر اسم',
      en: 'Username unblocked',
    ),
    AdminAction.ownerMessage => Tr.of(
      context,
      ar: 'رسالة من المالك',
      en: 'Owner message',
    ),
    AdminAction.reportReview => Tr.of(
      context,
      ar: 'مراجعة بلاغ',
      en: 'Report reviewed',
    ),
    AdminAction.reportResolve => Tr.of(
      context,
      ar: 'إغلاق بلاغ',
      en: 'Report closed',
    ),
    AdminAction.appealDecide => Tr.of(
      context,
      ar: 'قرار طلب مراجعة',
      en: 'Appeal decided',
    ),
    AdminAction.announcement => Tr.of(
      context,
      ar: 'إعلان عام',
      en: 'Announcement',
    ),
    AdminAction.announcementDelete => Tr.of(
      context,
      ar: 'حذف إعلان',
      en: 'Announcement removed',
    ),
    AdminAction.privateProfileAccess => Tr.of(
      context,
      ar: 'اطلاع على ملف خاص',
      en: 'Private profile viewed',
    ),
    AdminAction.deleteComment => Tr.of(
      context,
      ar: 'حذف تعليق',
      en: 'Comment deleted',
    ),
    AdminAction.monitorCheck => Tr.of(
      context,
      ar: 'فحص المصادر',
      en: 'Source check',
    ),
    AdminAction.roleChange => Tr.of(
      context,
      ar: 'تغيير صلاحية',
      en: 'Role changed',
    ),
  };
}

String restrictionLabel(BuildContext context, RestrictionFeature feature) {
  return switch (feature) {
    RestrictionFeature.comment => Tr.of(
      context,
      ar: 'التعليق',
      en: 'Commenting',
    ),
    RestrictionFeature.post => Tr.of(context, ar: 'النشر', en: 'Posting'),
    RestrictionFeature.interact => Tr.of(
      context,
      ar: 'التفاعل',
      en: 'Interactions',
    ),
    RestrictionFeature.community => Tr.of(
      context,
      ar: 'المجتمع',
      en: 'Community',
    ),
    RestrictionFeature.report => Tr.of(
      context,
      ar: 'إرسال البلاغات',
      en: 'Submitting reports',
    ),
  };
}

String staffRoleLabel(BuildContext context, StaffRole role) {
  return switch (role) {
    StaffRole.user => Tr.of(context, ar: 'عضو', en: 'Member'),
    StaffRole.moderator => Tr.of(context, ar: 'مشرف', en: 'Moderator'),
    StaffRole.admin => Tr.of(context, ar: 'مدير', en: 'Admin'),
    StaffRole.owner => Tr.of(context, ar: 'المالك', en: 'Owner'),
  };
}

Color adminStateColor(BuildContext context, AccountState state) {
  final palette = context.palette;
  return switch (state) {
    AccountState.active => palette.success,
    AccountState.warned => palette.warning,
    AccountState.restricted => palette.warning,
    AccountState.suspended => palette.danger,
    AccountState.banned => palette.danger,
    AccountState.underReview => palette.accent,
    AccountState.deleted => palette.textMuted,
  };
}

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({
    super.key,
    required this.state,
    this.compact = false,
    this.expiresAt,
  });

  final AccountState state;
  final bool compact;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final color = adminStateColor(context, state);
    final expiry = expiresAt;
    final suffix = expiry == null
        ? ''
        : ' · ${expiry.year}/${expiry.month.toString().padLeft(2, '0')}/${expiry.day.toString().padLeft(2, '0')}';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Space.xs + 2 : Space.sm,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '${adminStateLabel(context, state)}$suffix',
            style: context.text.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gold "Owner" marker used in the console and on Owner messages.
class OwnerBadge extends StatelessWidget {
  const OwnerBadge({super.key, this.label, this.compact = false});

  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Space.xs + 1 : Space.sm,
        vertical: compact ? 1 : 3,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        gradient: LinearGradient(
          colors: <Color>[
            kOwnerGold.withValues(alpha: palette.isDark ? 0.28 : 0.22),
            kOwnerGoldDeep.withValues(alpha: palette.isDark ? 0.16 : 0.12),
          ],
        ),
        border: Border.all(color: kOwnerGold.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.verified_rounded,
            size: compact ? 10 : 12,
            color: kOwnerGold,
          ),
          const SizedBox(width: 4),
          Text(
            label ?? Tr.of(context, ar: 'المالك', en: 'OWNER'),
            style: context.text.labelSmall?.copyWith(
              color: palette.isDark ? kOwnerGold : kOwnerGoldDeep,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              fontSize: compact ? 9 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// A calm grouped card matching the settings groups.
class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    this.title,
    this.trailing,
    required this.children,
    this.padding = const EdgeInsets.all(Space.md),
  });

  final String? title;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title!,
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class AdminStatCard extends StatelessWidget {
  const AdminStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = color ?? palette.primary;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 15, color: tone),
              const Spacer(),
              Text(
                '$value',
                style: context.text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs + 2),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class AdminKeyValue extends StatelessWidget {
  const AdminKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: context.text.bodySmall?.copyWith(
                color: valueColor ?? palette.textPrimary,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hides every administrative screen from a non-Owner, with a clear refusal
/// instead of a blank page. The server re-checks each action independently, so
/// this is the UX layer, not the security layer.
class AdminGuard extends ConsumerWidget {
  const AdminGuard({super.key, required this.child, this.requireOwner = false});

  final Widget child;
  final bool requireOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(staffRoleProvider);
    if (role.isLoading) {
      return Scaffold(
        appBar: WingsAppBar(showBack: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final value = role.value ?? StaffRole.user;
    final allowed = requireOwner ? value.isOwner : value.isAdmin;
    if (!allowed) {
      return Scaffold(
        appBar: WingsAppBar(showBack: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.lock_outline_rounded,
                  size: 40,
                  color: context.palette.textMuted,
                ),
                const SizedBox(height: Space.md),
                Text(
                  Tr.of(
                    context,
                    ar: 'هذه المنطقة مخصّصة لإدارة Wings فقط.',
                    en: 'This area is reserved for Wings administration.',
                  ),
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium,
                ),
                const SizedBox(height: Space.lg),
                WingsButton(
                  label: Tr.of(context, ar: 'العودة', en: 'Go back'),
                  variant: WingsButtonVariant.outline,
                  onPressed: () => context.go(RoutePaths.settings),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return child;
  }
}

/// Simple text prompt used by every administrative action that needs a reason.
Future<String?> promptAdminText(
  BuildContext context, {
  required String title,
  required String hint,
  String initialValue = '',
  bool required = true,
  int maxLines = 3,
  String? description,
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      String? error;
      return StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (description != null) ...<Widget>[
                Text(
                  description,
                  style: dialogContext.text.bodySmall?.copyWith(
                    color: dialogContext.palette.textSecondary,
                  ),
                ),
                const SizedBox(height: Space.sm),
              ],
              TextField(
                controller: controller,
                maxLines: maxLines,
                autofocus: true,
                decoration: InputDecoration(hintText: hint, errorText: error),
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
                final value = controller.text.trim();
                if (required && value.isEmpty) {
                  setState(
                    () => error = Tr.of(context, ar: 'مطلوب', en: 'Required'),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: Text(Tr.of(context, ar: 'متابعة', en: 'Continue')),
            ),
          ],
        ),
      );
    },
  );
}

/// Formats an administrative timestamp without pulling a locale formatter in.
String adminDate(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String adminDateShort(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)}';
}
