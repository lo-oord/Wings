import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';
import '../profile/avatar_view.dart';
import 'admin_actions.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// The administrative page of one account. This is also the authorized path to
/// a private profile: an Owner reads `users/{uid}` (staff-only) without touching
/// the privacy setting, and the access is written to the activity log once.
class AdminUserScreen extends ConsumerStatefulWidget {
  const AdminUserScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<AdminUserScreen> createState() => _AdminUserScreenState();
}

class _AdminUserScreenState extends ConsumerState<AdminUserScreen> {
  bool _accessLogged = false;

  Future<void> _logAccess(AdminUserDetail detail) async {
    if (_accessLogged || !detail.summary.privateProfile) return;
    _accessLogged = true;
    final actor = AdminActor.of(ref);
    if (!actor.valid) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .logPrivateProfileAccess(
            targetUid: detail.summary.uid,
            targetLabel: detail.summary.label,
            actorUid: actor.uid,
            actorName: actor.name,
          );
    } on Object {
      // The log is best effort; the access itself already happened.
    }
  }

  Future<void> _removeRestrictions(AdminUserDetail detail) async {
    final now = DateTime.now();
    if (detail.status.activeRestrictions(now).isEmpty) return;
    final confirmed = await WingsDialog.confirm(
      context,
      title: Tr.of(context, ar: 'رفع التقييد', en: 'Lift restrictions'),
      message: Tr.of(
        context,
        ar: 'ستُرفع كل القيود الفعّالة عن هذا الحساب.',
        en: 'All active restrictions will be lifted from this account.',
      ),
      confirmLabel: Tr.of(context, ar: 'رفع', en: 'Lift'),
    );
    if (!confirmed || !mounted) return;
    final actor = AdminActor.of(ref);
    final state = detail.status.isLockedAt(now)
        ? detail.status.state
        : AccountState.active;
    try {
      await ref
          .read(adminRepositoryProvider)
          .applyStatus(
            target: detail.summary,
            status: buildStatusRecord(
              state: state,
              reason: Tr.of(
                context,
                ar: 'رفع التقييد',
                en: 'Restriction lifted',
              ),
              actorUid: actor.uid,
              previousState: detail.status.state,
            ),
            reason: Tr.of(context, ar: 'رفع التقييد', en: 'Restriction lifted'),
            actorUid: actor.uid,
            actorName: actor.name,
            action: AdminAction.unrestrict,
            notificationTitle: Tr.of(
              context,
              ar: 'تم رفع القيود عن حسابك',
              en: 'Restrictions lifted',
            ),
            notificationBody: Tr.of(
              context,
              ar: 'أصبح حسابك في Wings غير مقيّد.',
              en: 'Your Wings account is no longer restricted.',
            ),
          );
      ref.invalidate(adminUserDetailProvider(widget.uid));
      if (mounted) {
        context.showSnack(
          Tr.of(context, ar: 'تم رفع التقييد.', en: 'Restrictions lifted.'),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(error.toString(), isError: true);
      }
    }
  }

  Future<void> _revokeWarning(
    AdminUserDetail detail,
    AdminWarning warning,
  ) async {
    final reason = await promptAdminText(
      context,
      title: Tr.of(context, ar: 'إلغاء التحذير', en: 'Revoke warning'),
      hint: Tr.of(context, ar: 'سبب الإلغاء', en: 'Revocation reason'),
    );
    if (reason == null || !mounted) return;
    final actor = AdminActor.of(ref);
    try {
      await ref
          .read(adminRepositoryProvider)
          .revokeWarning(
            target: detail.summary,
            warningId: warning.id,
            reason: reason,
            actorUid: actor.uid,
            actorName: actor.name,
          );
      ref.invalidate(adminUserDetailProvider(widget.uid));
      if (mounted) {
        context.showSnack(
          Tr.of(context, ar: 'تم إلغاء التحذير.', en: 'Warning revoked.'),
        );
      }
    } on Object catch (error) {
      if (mounted) context.showSnack(error.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(adminUserDetailProvider(widget.uid));
    return AdminGuard(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text(
            Tr.of(context, ar: 'ملف إداري', en: 'Administrative profile'),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: Tr.of(context, ar: 'تحديث', en: 'Refresh'),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () =>
                  ref.invalidate(adminUserDetailProvider(widget.uid)),
            ),
          ],
        ),
        body: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => WingsEmptyState(
            icon: Icons.person_off_outlined,
            title: Tr.of(
              context,
              ar: 'تعذّر تحميل الحساب',
              en: 'Could not load account',
            ),
            message: error.toString(),
            actionLabel: Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry'),
            onAction: () => ref.invalidate(adminUserDetailProvider(widget.uid)),
          ),
          data: (data) {
            _logAccess(data);
            final now = DateTime.now();
            final effective = data.status.effectiveState(now);
            final restrictions = data.status.activeRestrictions(now);
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
                      UserAvatar(
                        uid: data.summary.uid,
                        photoVersion: data.summary.photoVersion,
                        name: data.summary.displayName,
                        size: 62,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              data.summary.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleMedium,
                            ),
                            Text(
                              '@${data.summary.username}',
                              style: context.text.bodySmall?.copyWith(
                                color: context.palette.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                AdminStatusChip(
                                  state: effective,
                                  compact: true,
                                  expiresAt: data.status.expiresAt,
                                ),
                                if (data.summary.privateProfile)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.palette.surfaceHigh,
                                      borderRadius: BorderRadius.circular(
                                        Radii.pill,
                                      ),
                                    ),
                                    child: Text(
                                      Tr.of(
                                        context,
                                        ar: 'ملف خاص',
                                        en: 'Private',
                                      ),
                                      style: context.text.labelSmall?.copyWith(
                                        color: context.palette.textSecondary,
                                      ),
                                    ),
                                  ),
                                if (data.role.isStaff)
                                  OwnerBadge(
                                    compact: true,
                                    label: staffRoleLabel(context, data.role),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: WingsButton(
                          label: Tr.of(context, ar: 'إجراءات', en: 'Actions'),
                          icon: Icons.admin_panel_settings_outlined,
                          onPressed: () =>
                              showAdminActionsSheet(context, ref, data.summary),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: WingsButton(
                          label: Tr.of(
                            context,
                            ar: 'الملف العام',
                            en: 'Open profile',
                          ),
                          icon: Icons.open_in_new_rounded,
                          variant: WingsButtonVariant.outline,
                          onPressed: () => context.push(
                            RoutePaths.publicProfile(widget.uid),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AdminCard(
                  title: Tr.of(context, ar: 'البيانات', en: 'Details'),
                  children: <Widget>[
                    AdminKeyValue(
                      label: Tr.of(context, ar: 'المعرّف', en: 'User ID'),
                      value: data.summary.uid,
                      mono: true,
                    ),
                    AdminKeyValue(
                      label: Tr.of(context, ar: 'التسجيل', en: 'Registered'),
                      value: adminDate(data.summary.createdAt),
                    ),
                    AdminKeyValue(
                      label: Tr.of(context, ar: 'الخصوصية', en: 'Profile'),
                      value: data.summary.privateProfile
                          ? Tr.of(context, ar: 'خاص', en: 'Private')
                          : Tr.of(context, ar: 'عام', en: 'Public'),
                    ),
                    AdminKeyValue(
                      label: Tr.of(context, ar: 'التحذيرات', en: 'Warnings'),
                      value:
                          '${data.warnings.where((item) => item.active).length}',
                    ),
                    if (data.pendingDeletion)
                      AdminKeyValue(
                        label: Tr.of(
                          context,
                          ar: 'حذف معلّق',
                          en: 'Pending deletion',
                        ),
                        value: Tr.of(context, ar: 'نعم', en: 'Yes'),
                        valueColor: context.palette.danger,
                      ),
                    const SizedBox(height: Space.xs),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        alignment: AlignmentDirectional.centerStart,
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: Text(
                        Tr.of(context, ar: 'نسخ المعرّف', en: 'Copy user ID'),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: data.summary.uid),
                        );
                        if (context.mounted) {
                          context.showSnack(
                            Tr.of(context, ar: 'تم النسخ.', en: 'Copied.'),
                          );
                        }
                      },
                    ),
                  ],
                ),
                AdminCard(
                  title: Tr.of(context, ar: 'حالة الحساب', en: 'Account state'),
                  trailing: restrictions.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () => _removeRestrictions(data),
                          child: Text(
                            Tr.of(context, ar: 'رفع التقييد', en: 'Lift'),
                          ),
                        ),
                  children: <Widget>[
                    AdminKeyValue(
                      label: Tr.of(context, ar: 'الحالة', en: 'State'),
                      value: adminStateLabel(context, effective),
                      valueColor: adminStateColor(context, effective),
                    ),
                    if (data.status.reason.isNotEmpty)
                      AdminKeyValue(
                        label: Tr.of(context, ar: 'السبب', en: 'Reason'),
                        value: data.status.reason,
                      ),
                    if (data.status.expiresAt != null)
                      AdminKeyValue(
                        label: Tr.of(context, ar: 'ينتهي', en: 'Expires'),
                        value: adminDate(data.status.expiresAt),
                      ),
                    if (data.status.permanent &&
                        data.status.state == AccountState.suspended)
                      AdminKeyValue(
                        label: Tr.of(context, ar: 'المدة', en: 'Duration'),
                        value: Tr.of(
                          context,
                          ar: 'غير محددة',
                          en: 'Indefinite',
                        ),
                      ),
                    AdminKeyValue(
                      label: Tr.of(context, ar: 'آخر إجراء', en: 'Last action'),
                      value: adminDate(data.status.updatedAt),
                    ),
                    AdminKeyValue(
                      label: Tr.of(
                        context,
                        ar: 'القيود الفعّالة',
                        en: 'Restrictions',
                      ),
                      value: restrictions.isEmpty
                          ? Tr.of(context, ar: 'لا يوجد', en: 'None')
                          : restrictions
                                .map((item) => restrictionLabel(context, item))
                                .join('، '),
                    ),
                  ],
                ),
                if (data.warnings.isNotEmpty)
                  AdminCard(
                    title: Tr.of(context, ar: 'التحذيرات', en: 'Warnings'),
                    children: <Widget>[
                      for (final warning in data.warnings)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(
                                warning.active
                                    ? Icons.report_gmailerrorred_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 16,
                                color: warning.active
                                    ? context.palette.warning
                                    : context.palette.textMuted,
                              ),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      warning.reason,
                                      style: context.text.bodySmall,
                                    ),
                                    Text(
                                      '${warning.category} · ${adminDate(warning.issuedAt)}'
                                      '${warning.active ? '' : ' · ${Tr.of(context, ar: 'ملغى', en: 'revoked')}'}',
                                      style: context.text.labelSmall?.copyWith(
                                        color: context.palette.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (warning.active)
                                IconButton(
                                  tooltip: Tr.of(
                                    context,
                                    ar: 'إلغاء التحذير',
                                    en: 'Revoke',
                                  ),
                                  icon: const Icon(
                                    Icons.undo_rounded,
                                    size: 16,
                                  ),
                                  onPressed: () =>
                                      _revokeWarning(data, warning),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                if (data.reports.isNotEmpty)
                  AdminCard(
                    title: Tr.of(
                      context,
                      ar: 'البلاغات المرتبطة',
                      en: 'Related reports',
                    ),
                    children: <Widget>[
                      for (final report in data.reports)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.flag_outlined,
                                size: 14,
                                color: context.palette.warning,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${report.category} · ${report.details}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall,
                                ),
                              ),
                              Text(
                                report.status,
                                style: context.text.labelSmall?.copyWith(
                                  color: context.palette.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                AdminCard(
                  title: Tr.of(
                    context,
                    ar: 'سجل الحساب',
                    en: 'Account history',
                  ),
                  children: <Widget>[
                    if (data.history.isEmpty)
                      Text(
                        Tr.of(
                          context,
                          ar: 'لا توجد إجراءات إدارية سابقة.',
                          en: 'No previous administrative actions.',
                        ),
                        style: context.text.bodySmall?.copyWith(
                          color: context.palette.textMuted,
                        ),
                      ),
                    for (final entry in data.history)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    adminActionLabel(context, entry.action),
                                    style: context.text.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  adminDate(entry.createdAt),
                                  style: context.text.labelSmall?.copyWith(
                                    color: context.palette.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            if (entry.reason.isNotEmpty)
                              Text(
                                entry.reason,
                                style: context.text.labelSmall?.copyWith(
                                  color: context.palette.textSecondary,
                                ),
                              ),
                            Text(
                              '${entry.actorName.isEmpty ? entry.actorUid : entry.actorName}'
                              '${entry.previousState.isEmpty ? '' : ' · ${entry.previousState} → ${entry.nextState}'}',
                              style: context.text.labelSmall?.copyWith(
                                color: context.palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (data.ownerMessages.isNotEmpty)
                  AdminCard(
                    title: Tr.of(
                      context,
                      ar: 'رسائل المالك',
                      en: 'Owner messages',
                    ),
                    children: <Widget>[
                      for (final message in data.ownerMessages)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                message.title.isEmpty
                                    ? Tr.of(
                                        context,
                                        ar: 'رسالة من المالك',
                                        en: 'Owner message',
                                      )
                                    : message.title,
                                style: context.text.bodySmall?.copyWith(
                                  color: kOwnerGold,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                message.body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelSmall?.copyWith(
                                  color: context.palette.textSecondary,
                                ),
                              ),
                              Text(
                                '${adminDate(message.createdAt)} · '
                                '${message.read ? Tr.of(context, ar: 'مقروءة', en: 'read') : Tr.of(context, ar: 'غير مقروءة', en: 'unread')}',
                                style: context.text.labelSmall?.copyWith(
                                  color: context.palette.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
