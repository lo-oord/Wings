import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

/// The Owner dashboard. Every number is an aggregation over real documents.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(adminOverviewProvider);
    final role = ref.watch(staffRoleProvider).value ?? StaffRole.user;

    return AdminGuard(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  Tr.of(context, ar: 'أدوات المطوّر', en: 'Developer tools'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Space.sm),
              if (role.isOwner) const OwnerBadge(compact: true),
            ],
          ),
          actions: <Widget>[
            IconButton(
              tooltip: Tr.of(context, ar: 'تحديث', en: 'Refresh'),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () => ref.invalidate(adminOverviewProvider),
            ),
          ],
        ),
        body: overview.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => WingsEmptyState(
            icon: Icons.cloud_off_rounded,
            title: Tr.of(
              context,
              ar: 'تعذّر تحميل البيانات',
              en: 'Could not load',
            ),
            message: error.toString(),
            actionLabel: Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry'),
            onAction: () => ref.invalidate(adminOverviewProvider),
          ),
          data: (data) {
            final stats = data.stats;
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(adminOverviewProvider),
              child: ListView(
                padding: const EdgeInsets.only(bottom: Space.xxxl),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.sm,
                      Space.lg,
                      Space.xs,
                    ),
                    child: Text(
                      Tr.of(
                        context,
                        ar: 'نظرة عامة على Wings',
                        en: 'Wings overview',
                      ),
                      style: context.text.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    child: Text(
                      Tr.of(
                        context,
                        ar: 'أرقام حقيقية محسوبة على الخادم. آخر تحديث: ${adminDate(stats.loadedAt)}',
                        en: 'Real server-side counts. Updated: ${adminDate(stats.loadedAt)}',
                      ),
                      style: context.text.labelSmall?.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.md,
                      Space.lg,
                      0,
                    ),
                    child: GridView.count(
                      crossAxisCount: context.isCompact ? 2 : 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: Space.sm,
                      mainAxisSpacing: Space.sm,
                      childAspectRatio: 1.55,
                      children: <Widget>[
                        AdminStatCard(
                          label: Tr.of(
                            context,
                            ar: 'إجمالي الأعضاء',
                            en: 'Members',
                          ),
                          value: stats.totalUsers,
                          icon: Icons.people_alt_outlined,
                        ),
                        AdminStatCard(
                          label: Tr.of(context, ar: 'اليوم', en: 'Today'),
                          value: stats.registeredToday,
                          icon: Icons.person_add_alt_1_rounded,
                          color: context.palette.accent,
                        ),
                        AdminStatCard(
                          label: Tr.of(
                            context,
                            ar: 'هذا الأسبوع',
                            en: 'This week',
                          ),
                          value: stats.registeredThisWeek,
                          icon: Icons.date_range_rounded,
                          color: context.palette.mint,
                        ),
                        AdminStatCard(
                          label: Tr.of(
                            context,
                            ar: 'بلاغات معلّقة',
                            en: 'Pending reports',
                          ),
                          value: stats.pendingReports,
                          icon: Icons.flag_outlined,
                          color: context.palette.warning,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.sm,
                      Space.lg,
                      0,
                    ),
                    child: GridView.count(
                      crossAxisCount: context.isCompact ? 2 : 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: Space.sm,
                      mainAxisSpacing: Space.sm,
                      childAspectRatio: 1.55,
                      children: <Widget>[
                        AdminStatCard(
                          label: Tr.of(
                            context,
                            ar: 'حسابات سليمة',
                            en: 'Active',
                          ),
                          value: stats.activeAccounts,
                          icon: Icons.check_circle_outline_rounded,
                          color: context.palette.success,
                        ),
                        AdminStatCard(
                          label: Tr.of(context, ar: 'موقوفة', en: 'Suspended'),
                          value: stats.suspendedAccounts,
                          icon: Icons.timer_outlined,
                          color: context.palette.danger,
                        ),
                        AdminStatCard(
                          label: Tr.of(context, ar: 'محظورة', en: 'Banned'),
                          value: stats.bannedAccounts,
                          icon: Icons.block_rounded,
                          color: context.palette.danger,
                        ),
                        AdminStatCard(
                          label: Tr.of(context, ar: 'مقيّدة', en: 'Restricted'),
                          value: stats.restrictedAccounts,
                          icon: Icons.tune_rounded,
                          color: context.palette.warning,
                        ),
                      ],
                    ),
                  ),
                  AdminCard(
                    title: Tr.of(context, ar: 'قسم الإدارة', en: 'Sections'),
                    children: <Widget>[
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: <Widget>[
                          _NavChip(
                            icon: Icons.people_outline_rounded,
                            label: Tr.of(
                              context,
                              ar: 'إدارة الأعضاء',
                              en: 'Users',
                            ),
                            onTap: () => context.push(RoutePaths.adminUsers),
                          ),
                          _NavChip(
                            icon: Icons.policy_outlined,
                            label: Tr.of(
                              context,
                              ar: 'سياسات الحساب',
                              en: 'Policies',
                            ),
                            onTap: () => context.push(RoutePaths.adminPolicies),
                          ),
                          _NavChip(
                            icon: Icons.inbox_outlined,
                            label: Tr.of(
                              context,
                              ar: 'البلاغات والمراجعات',
                              en: 'Reports',
                            ),
                            onTap: () => context.push(RoutePaths.adminReports),
                          ),
                          _NavChip(
                            icon: Icons.mark_email_unread_outlined,
                            label: Tr.of(
                              context,
                              ar: 'رسائل المالك',
                              en: 'Owner messages',
                            ),
                            onTap: () => context.push(RoutePaths.adminMessages),
                          ),
                          _NavChip(
                            icon: Icons.campaign_outlined,
                            label: Tr.of(
                              context,
                              ar: 'الإشعارات',
                              en: 'Notifications',
                            ),
                            onTap: () =>
                                context.push(RoutePaths.adminAnnouncements),
                          ),
                          _NavChip(
                            icon: Icons.monitor_heart_outlined,
                            label: Tr.of(
                              context,
                              ar: 'مراقبة النظام',
                              en: 'System monitor',
                            ),
                            onTap: () => context.push(RoutePaths.adminMonitor),
                          ),
                          _NavChip(
                            icon: Icons.history_rounded,
                            label: Tr.of(
                              context,
                              ar: 'سجل النشاط',
                              en: 'Activity log',
                            ),
                            onTap: () => context.push(RoutePaths.adminLog),
                          ),
                        ],
                      ),
                    ],
                  ),
                  AdminCard(
                    title: Tr.of(
                      context,
                      ar: 'أحدث التسجيلات',
                      en: 'Recent registrations',
                    ),
                    trailing: TextButton(
                      onPressed: () => context.push(RoutePaths.adminUsers),
                      child: Text(Tr.of(context, ar: 'الكل', en: 'All')),
                    ),
                    children: <Widget>[
                      if (data.recentUsers.isEmpty)
                        Text(
                          Tr.of(
                            context,
                            ar: 'لا توجد حسابات بعد.',
                            en: 'No accounts yet.',
                          ),
                          style: context.text.bodySmall?.copyWith(
                            color: context.palette.textMuted,
                          ),
                        ),
                      for (final user in data.recentUsers)
                        InkWell(
                          onTap: () =>
                              context.push(RoutePaths.adminUser(user.uid)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: <Widget>[
                                UserAvatar(
                                  uid: user.uid,
                                  photoVersion: user.photoVersion,
                                  name: user.displayName,
                                  size: 32,
                                ),
                                const SizedBox(width: Space.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        user.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.text.bodySmall,
                                      ),
                                      Text(
                                        '@${user.username} · ${adminDateShort(user.createdAt)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.text.labelSmall
                                            ?.copyWith(
                                              color: context.palette.textMuted,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                AdminStatusChip(
                                  state: user.status,
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  AdminCard(
                    title: Tr.of(
                      context,
                      ar: 'أحدث الإجراءات',
                      en: 'Recent actions',
                    ),
                    trailing: TextButton(
                      onPressed: () => context.push(RoutePaths.adminLog),
                      child: Text(Tr.of(context, ar: 'الكل', en: 'All')),
                    ),
                    children: <Widget>[
                      if (data.recentActions.isEmpty)
                        Text(
                          Tr.of(
                            context,
                            ar: 'لا توجد إجراءات مسجّلة بعد.',
                            en: 'No actions recorded yet.',
                          ),
                          style: context.text.bodySmall?.copyWith(
                            color: context.palette.textMuted,
                          ),
                        ),
                      for (final entry in data.recentActions)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.bolt_rounded,
                                size: 14,
                                color: context.palette.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${adminActionLabel(context, entry.action)}'
                                  '${entry.targetLabel.isEmpty ? '' : ' · ${entry.targetLabel}'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall,
                                ),
                              ),
                              Text(
                                adminDateShort(entry.createdAt),
                                style: context.text.labelSmall?.copyWith(
                                  color: context.palette.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
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
                        ar: 'العدّادات محسوبة على الخادم عبر count() وتشمل فقط المستندات التي تحمل الحالة المذكورة؛ الحسابات القديمة بلا حالة تُعتبر «نشطة».',
                        en: 'Counters use server-side count() and only include documents carrying that status; older accounts without a status count as active.',
                      ),
                      style: context.text.labelSmall?.copyWith(
                        color: context.palette.textMuted,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 15, color: palette.primary),
            const SizedBox(width: 6),
            Text(label, style: context.text.labelMedium),
          ],
        ),
      ),
    );
  }
}
