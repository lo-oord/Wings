import 'package:flutter/material.dart';
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
import 'admin_actions.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// Owner inbox for reports and appeals.
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(adminReportsProvider.notifier).refresh(),
    );
  }

  Future<void> _decide(AdminReport report) async {
    final status = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(
          Tr.of(context, ar: 'تحديث حالة البلاغ', en: 'Update report'),
        ),
        children: <Widget>[
          for (final option in const <(String, String, String)>[
            ('review', 'قيد المراجعة', 'Under review'),
            ('resolved', 'تم الحل', 'Resolved'),
            ('rejected', 'مرفوض', 'Rejected'),
            ('pending', 'إعادة إلى الانتظار', 'Back to pending'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(option.$1),
              child: Text(Tr.isArabic(context) ? option.$2 : option.$3),
            ),
        ],
      ),
    );
    if (status == null || !mounted) return;
    final note = await promptAdminText(
      context,
      title: Tr.of(context, ar: 'ملاحظة داخلية', en: 'Internal note'),
      hint: Tr.of(
        context,
        ar: 'ملاحظة للمشرفين (اختياري)',
        en: 'Note (optional)',
      ),
      required: false,
    );
    if (note == null || !mounted) return;
    final actor = AdminActor.of(ref);
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateReport(
            report: report,
            status: status,
            note: note,
            actorUid: actor.uid,
            actorName: actor.name,
            decision: note,
          );
      ref.read(adminReportsProvider.notifier).refresh();
      if (mounted) {
        context.showSnack(Tr.of(context, ar: 'تم التحديث.', en: 'Updated.'));
      }
    } on Object catch (error) {
      if (mounted) context.showSnack(error.toString(), isError: true);
    }
  }

  Future<void> _decideAppeal(AdminAppeal appeal) async {
    final decision = await promptAdminText(
      context,
      title: Tr.of(context, ar: 'قرار طلب المراجعة', en: 'Appeal decision'),
      hint: Tr.of(
        context,
        ar: 'اشرح القرار للعضو',
        en: 'Explain the decision to the member',
      ),
    );
    if (decision == null || !mounted) return;
    final accepted = await WingsDialog.confirm(
      context,
      title: Tr.of(context, ar: 'قبول الطلب؟', en: 'Accept the appeal?'),
      message: Tr.of(
        context,
        ar: 'اختر «قبول» لرفع الإجراء، أو «رفض» لإبقائه.',
        en: 'Choose Accept to lift the action, or Reject to keep it.',
      ),
      confirmLabel: Tr.of(context, ar: 'قبول', en: 'Accept'),
    );
    if (!mounted) return;
    final actor = AdminActor.of(ref);
    try {
      await ref
          .read(adminRepositoryProvider)
          .decideAppeal(
            appeal: appeal,
            status: accepted ? 'accepted' : 'rejected',
            decision: decision,
            actorUid: actor.uid,
            actorName: actor.name,
          );
      ref.read(adminReportsProvider.notifier).refresh();
      if (mounted) {
        context.showSnack(
          Tr.of(context, ar: 'تم تسجيل القرار.', en: 'Decision saved.'),
        );
      }
    } on Object catch (error) {
      if (mounted) context.showSnack(error.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminReportsProvider);
    final controller = ref.read(adminReportsProvider.notifier);
    return AdminGuard(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: WingsAppBar(
            showBack: true,
            title: Text(
              Tr.of(
                context,
                ar: 'البلاغات والمراجعات',
                en: 'Reports & appeals',
              ),
            ),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: controller.refresh,
              ),
            ],
            bottom: TabBar(
              tabs: <Widget>[
                Tab(
                  text: Tr.of(context, ar: 'البلاغات', en: 'Reports'),
                ),
                Tab(
                  text: Tr.of(context, ar: 'المراجعات', en: 'Appeals'),
                ),
              ],
            ),
          ),
          body: TabBarView(
            children: <Widget>[
              Column(
                children: <Widget>[
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.lg,
                        vertical: Space.xs,
                      ),
                      children: <Widget>[
                        for (final option in const <(String, String, String)>[
                          ('pending', 'معلّقة', 'Pending'),
                          ('review', 'قيد المراجعة', 'Reviewing'),
                          ('resolved', 'محلولة', 'Resolved'),
                          ('rejected', 'مرفوضة', 'Rejected'),
                          ('all', 'الكل', 'All'),
                        ])
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: Space.xs,
                            ),
                            child: WingsFilterChip(
                              label: Tr.isArabic(context)
                                  ? option.$2
                                  : option.$3,
                              selected: state.status == option.$1,
                              onTap: () => controller.setStatus(option.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: state.loading
                        ? const Center(child: CircularProgressIndicator())
                        : state.error.isNotEmpty && state.items.isEmpty
                        ? WingsEmptyState(
                            icon: Icons.cloud_off_rounded,
                            title: Tr.of(
                              context,
                              ar: 'تعذّر التحميل',
                              en: 'Failed',
                            ),
                            message: state.error,
                            actionLabel: Tr.of(
                              context,
                              ar: 'إعادة المحاولة',
                              en: 'Retry',
                            ),
                            onAction: controller.refresh,
                          )
                        : state.items.isEmpty
                        ? WingsEmptyState(
                            icon: Icons.inbox_outlined,
                            title: Tr.of(
                              context,
                              ar: 'لا توجد بلاغات',
                              en: 'No reports',
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: Space.xxxl),
                            itemCount: state.items.length,
                            itemBuilder: (context, index) {
                              final report = state.items[index];
                              return AdminCard(
                                title: report.category.isEmpty
                                    ? Tr.of(context, ar: 'بلاغ', en: 'Report')
                                    : report.category,
                                trailing: Text(
                                  report.status,
                                  style: context.text.labelSmall?.copyWith(
                                    color: context.palette.textMuted,
                                  ),
                                ),
                                children: <Widget>[
                                  Text(
                                    report.details,
                                    style: context.text.bodySmall,
                                  ),
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    '${Tr.of(context, ar: 'المُبلِّغ', en: 'Reporter')}: '
                                    '${report.reporterName.isEmpty ? report.reporterUid : report.reporterName}'
                                    ' · ${adminDate(report.createdAt)}',
                                    style: context.text.labelSmall?.copyWith(
                                      color: context.palette.textMuted,
                                    ),
                                  ),
                                  if (report.note.isNotEmpty)
                                    Text(
                                      '${Tr.of(context, ar: 'ملاحظة', en: 'Note')}: ${report.note}',
                                      style: context.text.labelSmall?.copyWith(
                                        color: context.palette.textSecondary,
                                      ),
                                    ),
                                  const SizedBox(height: Space.xs),
                                  Wrap(
                                    spacing: Space.xs,
                                    runSpacing: Space.xs,
                                    children: <Widget>[
                                      TextButton(
                                        onPressed: () => _decide(report),
                                        child: Text(
                                          Tr.of(
                                            context,
                                            ar: 'تحديث الحالة',
                                            en: 'Update status',
                                          ),
                                        ),
                                      ),
                                      if (report.targetUid.isNotEmpty)
                                        TextButton(
                                          onPressed: () => context.push(
                                            RoutePaths.adminUser(
                                              report.targetUid,
                                            ),
                                          ),
                                          child: Text(
                                            Tr.of(
                                              context,
                                              ar: 'حساب المُبلَّغ عنه',
                                              en: 'Reported account',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
              state.appeals.isEmpty
                  ? WingsEmptyState(
                      icon: Icons.gavel_rounded,
                      title: Tr.of(
                        context,
                        ar: 'لا توجد طلبات مراجعة',
                        en: 'No appeals',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: Space.xxxl),
                      itemCount: state.appeals.length,
                      itemBuilder: (context, index) {
                        final appeal = state.appeals[index];
                        return AdminCard(
                          title: '@${appeal.username}',
                          trailing: Text(
                            appeal.status,
                            style: context.text.labelSmall?.copyWith(
                              color: context.palette.textMuted,
                            ),
                          ),
                          children: <Widget>[
                            Text(appeal.message, style: context.text.bodySmall),
                            Text(
                              adminDate(appeal.createdAt),
                              style: context.text.labelSmall?.copyWith(
                                color: context.palette.textMuted,
                              ),
                            ),
                            if (appeal.decision.isNotEmpty)
                              Text(
                                appeal.decision,
                                style: context.text.labelSmall?.copyWith(
                                  color: context.palette.textSecondary,
                                ),
                              ),
                            const SizedBox(height: Space.xs),
                            Wrap(
                              spacing: Space.xs,
                              children: <Widget>[
                                TextButton(
                                  onPressed: () => _decideAppeal(appeal),
                                  child: Text(
                                    Tr.of(context, ar: 'قرار', en: 'Decide'),
                                  ),
                                ),
                                if (appeal.uid.isNotEmpty)
                                  TextButton(
                                    onPressed: () => context.push(
                                      RoutePaths.adminUser(appeal.uid),
                                    ),
                                    child: Text(
                                      Tr.of(
                                        context,
                                        ar: 'الحساب',
                                        en: 'Account',
                                      ),
                                    ),
                                  ),
                              ],
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
