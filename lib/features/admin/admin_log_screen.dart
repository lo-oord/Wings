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
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// The immutable administrative activity log. There is no edit or delete
/// affordance anywhere, and the rules refuse both for every client.
class AdminLogScreen extends ConsumerStatefulWidget {
  const AdminLogScreen({super.key});

  @override
  ConsumerState<AdminLogScreen> createState() => _AdminLogScreenState();
}

class _AdminLogScreenState extends ConsumerState<AdminLogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(adminLogProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminLogProvider);
    final controller = ref.read(adminLogProvider.notifier);
    return AdminGuard(
      requireOwner: true,
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text(Tr.of(context, ar: 'سجل النشاط', en: 'Activity log')),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: controller.refresh,
            ),
          ],
        ),
        body: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.error.isNotEmpty && state.items.isEmpty
            ? WingsEmptyState(
                icon: Icons.cloud_off_rounded,
                title: Tr.of(
                  context,
                  ar: 'تعذّر التحميل',
                  en: 'Failed to load',
                ),
                message: state.error,
                actionLabel: Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry'),
                onAction: controller.refresh,
              )
            : state.items.isEmpty
            ? WingsEmptyState(
                icon: Icons.history_rounded,
                title: Tr.of(context, ar: 'السجل فارغ', en: 'The log is empty'),
              )
            : RefreshIndicator(
                onRefresh: controller.refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: Space.xxxl),
                  itemCount: state.items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == state.items.length) {
                      if (!state.hasMore) {
                        return Padding(
                          padding: const EdgeInsets.all(Space.lg),
                          child: Center(
                            child: Text(
                              Tr.of(
                                context,
                                ar: 'تم عرض كل السجلات',
                                en: 'All records shown',
                              ),
                              style: context.text.labelSmall?.copyWith(
                                color: context.palette.textMuted,
                              ),
                            ),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.all(Space.lg),
                        child: WingsButton(
                          label: state.loadingMore
                              ? Tr.of(context, ar: '…', en: '…')
                              : Tr.of(context, ar: 'المزيد', en: 'Load more'),
                          variant: WingsButtonVariant.outline,
                          onPressed: state.loadingMore
                              ? null
                              : controller.loadMore,
                        ),
                      );
                    }
                    final entry = state.items[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.lg,
                        vertical: Space.xs,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(Space.md),
                        decoration: BoxDecoration(
                          color: context.palette.surface,
                          borderRadius: BorderRadius.circular(Radii.sm),
                          border: Border.all(color: context.palette.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    adminActionLabel(context, entry.action),
                                    style: context.text.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
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
                            const SizedBox(height: 2),
                            Text(
                              '${entry.actorName.isEmpty ? entry.actorUid : entry.actorName}'
                              '${entry.targetLabel.isEmpty ? '' : ' → ${entry.targetLabel}'}',
                              style: context.text.labelSmall?.copyWith(
                                color: context.palette.textSecondary,
                              ),
                            ),
                            if (entry.reason.isNotEmpty)
                              Text(
                                entry.reason,
                                style: context.text.labelSmall,
                              ),
                            if (entry.details.isNotEmpty)
                              Text(
                                entry.details,
                                style: context.text.labelSmall?.copyWith(
                                  color: context.palette.textMuted,
                                ),
                              ),
                            if (entry.targetUid.isNotEmpty)
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 28),
                                  ),
                                  onPressed: () => context.push(
                                    RoutePaths.adminUser(entry.targetUid),
                                  ),
                                  child: Text(
                                    Tr.of(
                                      context,
                                      ar: 'فتح الحساب',
                                      en: 'Open account',
                                    ),
                                    style: context.text.labelSmall,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
