import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import '../profile/avatar_view.dart';
import 'admin_widgets.dart';

/// Private Owner control center.
class DeveloperToolsScreen extends ConsumerStatefulWidget {
  const DeveloperToolsScreen({super.key});

  @override
  ConsumerState<DeveloperToolsScreen> createState() =>
      _DeveloperToolsScreenState();
}

class _DeveloperToolsScreenState extends ConsumerState<DeveloperToolsScreen> {
  Future<AdminDashboardStats>? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _stats = ref.read(adminRepositoryProvider).dashboard();
    });
  }

  Future<void> _refresh() async {
    final future = ref.read(adminRepositoryProvider).dashboard();
    setState(() => _stats = future);
    try {
      await future;
    } on Object {
      // The error state is rendered from the future itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return OwnerGate(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Row(
            children: <Widget>[
              const Icon(Icons.admin_panel_settings_rounded, size: 19),
              const SizedBox(width: Space.sm),
              Flexible(
                child: Text(
                  'أدوات المطور',
                  style: context.text.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _refresh,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          color: palette.primary,
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.huge),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.lg,
                  0,
                ),
                child: AdminCard(
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(Space.sm),
                        decoration: BoxDecoration(
                          gradient: BrandColors.royalGradient,
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'مركز تحكم مالك Wings',
                              style: context.text.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'كل الإجراءات مسجّلة ومحمية بقواعد Firestore.',
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const AdminSectionTitle('نظرة عامة'),
              FutureBuilder<AdminDashboardStats>(
                future: _stats,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(Space.xxl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.lg,
                      ),
                      child: AdminCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'تعذّر تحميل الإحصاءات',
                              style: context.text.titleSmall,
                            ),
                            const SizedBox(height: Space.xs),
                            Text(
                              'قد تكون قواعد Firestore القديمة ما زالت منشورة، '
                              'أو تحتاج فهرس المستخدمين الجديد. راجع رسالة الخطأ '
                              'في السجل ثم أعد المحاولة.\n${snapshot.error}',
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                            const SizedBox(height: Space.md),
                            TextButton(
                              onPressed: _load,
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final stats = snapshot.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _StatGrid(stats: stats),
                      const AdminSectionTitle('إجراءات سريعة'),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.lg,
                        ),
                        child: Column(
                          children: <Widget>[
                            AdminCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: <Widget>[
                                  AdminRow(
                                    icon: Icons.people_alt_rounded,
                                    title: 'إدارة المستخدمين',
                                    subtitle:
                                        'بحث، تصفح، تقييد، إيقاف، حظر وحذف',
                                    onTap: () => context.push(
                                      RoutePaths.developerUsers,
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: palette.border,
                                    indent: Space.md,
                                    endIndent: Space.md,
                                  ),
                                  AdminRow(
                                    icon: Icons.flag_outlined,
                                    title: 'البلاغات',
                                    subtitle: stats.pendingReports == 0
                                        ? 'لا توجد بلاغات معلّقة'
                                        : '${stats.pendingReports} بلاغًا بانتظار المراجعة',
                                    onTap: () => context.push(
                                      RoutePaths.developerReports,
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: palette.border,
                                    indent: Space.md,
                                    endIndent: Space.md,
                                  ),
                                  AdminRow(
                                    icon: Icons.block_rounded,
                                    title: 'قوائم الحظر',
                                    subtitle: 'بريد إلكتروني وأسماء مستخدمين',
                                    onTap: () => context.push(
                                      RoutePaths.developerBlocks,
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    color: palette.border,
                                    indent: Space.md,
                                    endIndent: Space.md,
                                  ),
                                  AdminRow(
                                    icon: Icons.history_rounded,
                                    title: 'سجل الإجراءات',
                                    subtitle: 'كل ما نفّذه فريق الإدارة',
                                    onTap: () =>
                                        context.push(RoutePaths.developerLog),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      AdminSectionTitle(
                        'أحدث المسجّلين',
                        trailing: Text(
                          '${stats.loadedAt.hour.toString().padLeft(2, '0')}:'
                          '${stats.loadedAt.minute.toString().padLeft(2, '0')}',
                          style: context.text.labelSmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                      if (stats.recentUsers.isEmpty)
                        const _EmptyHint('لا يوجد مستخدمون بعد.')
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.lg,
                          ),
                          child: AdminCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: <Widget>[
                                for (final user in stats.recentUsers)
                                  AdminRow(
                                    leading: UserAvatar(
                                      uid: user.uid,
                                      photoVersion: user.photoVersion,
                                      name: user.displayName,
                                      size: 34,
                                    ),
                                    title: user.displayName.isEmpty
                                        ? user.handle
                                        : user.displayName,
                                    subtitle:
                                        '${user.handle} · ${adminMoment(user.createdAt)}',
                                    trailing: AccountStateChip(
                                      state: user.standing.effectiveState,
                                      compact: true,
                                    ),
                                    onTap: () => context.push(
                                      RoutePaths.developerUser(user.uid),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const AdminSectionTitle('أحدث الإجراءات الإدارية'),
                      if (stats.recentActions.isEmpty)
                        const _EmptyHint('لا توجد إجراءات مسجّلة بعد.')
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.lg,
                          ),
                          child: AdminCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: <Widget>[
                                for (final action in stats.recentActions)
                                  AdminRow(
                                    icon: Icons.bolt_rounded,
                                    title: _actionLabel(action.action),
                                    subtitle:
                                        '${action.targetUsername.isEmpty ? action.targetUid : '@${action.targetUsername}'}'
                                        ' · ${adminMoment(action.createdAt)}',
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.lg,
                          Space.xl,
                          Space.lg,
                          0,
                        ),
                        child: Text(
                          'الإحصاءات محسوبة باستعلامات تجميع (count) ولا تُحمّل '
                          'مستندات المستخدمين. «نشط» = إجمالي الحسابات ناقص '
                          'الموقوفة والمحظورة والمقيّدة والمحذوفة.',
                          style: context.text.labelSmall?.copyWith(
                            color: palette.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _actionLabel(String action) => switch (action) {
  'warning' => 'إنذار',
  'warning-revoked' => 'إلغاء إنذار',
  'restrict' => 'تقييد ميزات',
  'suspend' => 'إيقاف مؤقت',
  'ban' => 'حظر دائم',
  'restore' => 'استعادة حساب',
  'account-deleted' => 'حذف حساب',
  'owner-message' => 'رسالة من المالك',
  'email-block' => 'حظر بريد',
  'email-unblock' => 'رفع حظر بريد',
  'username-block' => 'حظر اسم مستخدم',
  'username-unblock' => 'رفع حظر اسم',
  'under-review' => 'قيد المراجعة',
  _ => action,
};

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final AdminDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cards = <Widget>[
      AdminStatCard(
        label: 'إجمالي المستخدمين',
        value: stats.totalUsers,
        icon: Icons.people_alt_rounded,
        caption: 'كل الحسابات',
      ),
      AdminStatCard(
        label: 'سجّلوا اليوم',
        value: stats.registeredToday,
        icon: Icons.person_add_alt_1_rounded,
        tone: palette.success,
      ),
      AdminStatCard(
        label: 'خلال آخر 7 أيام',
        value: stats.registeredThisWeek,
        icon: Icons.calendar_month_rounded,
        tone: palette.success,
      ),
      AdminStatCard(
        label: 'حسابات نشطة',
        value: stats.activeAccounts,
        icon: Icons.check_circle_rounded,
        tone: palette.success,
      ),
      AdminStatCard(
        label: 'موقوفة مؤقتًا',
        value: stats.suspendedAccounts,
        icon: Icons.pause_circle_rounded,
        tone: palette.danger,
      ),
      AdminStatCard(
        label: 'محظورة دائمًا',
        value: stats.bannedAccounts,
        icon: Icons.gavel_rounded,
        tone: palette.danger,
      ),
      AdminStatCard(
        label: 'مقيّدة الميزات',
        value: stats.restrictedAccounts,
        icon: Icons.do_not_disturb_on_rounded,
        tone: palette.warning,
      ),
      AdminStatCard(
        label: 'قيد المراجعة',
        value: stats.underReviewAccounts,
        icon: Icons.hourglass_top_rounded,
        tone: BrandColors.developerBlue,
      ),
      AdminStatCard(
        label: 'حسابات محذوفة',
        value: stats.deletedAccounts,
        icon: Icons.person_off_rounded,
        tone: palette.textMuted,
      ),
      AdminStatCard(
        label: 'بلاغات معلّقة',
        value: stats.pendingReports,
        icon: Icons.flag_rounded,
        tone: palette.warning,
      ),
      AdminStatCard(
        label: 'بلاغات تمت مراجعتها',
        value: stats.reviewedReports,
        icon: Icons.visibility_rounded,
        tone: BrandColors.developerBlue,
      ),
      AdminStatCard(
        label: 'بلاغات محلولة',
        value: stats.resolvedReports,
        icon: Icons.task_alt_rounded,
        tone: palette.success,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - Space.md) / 2;
          return Wrap(
            spacing: Space.md,
            runSpacing: Space.md,
            children: <Widget>[
              for (final card in cards) SizedBox(width: width, child: card),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
    child: AdminCard(
      child: Text(
        text,
        style: context.text.bodySmall?.copyWith(
          color: context.palette.textMuted,
        ),
      ),
    ),
  );
}
