import 'dart:async';

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
import '../profile/avatar_view.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../core/errors/user_facing_error.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(adminUsersProvider.notifier).refresh(),
    );
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 320) {
        ref.read(adminUsersProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      ref.read(adminUsersProvider.notifier).search(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminUsersProvider);
    final controller = ref.read(adminUsersProvider.notifier);

    return AdminGuard(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text(
            Tr.of(context, ar: 'إدارة الأعضاء', en: 'User management'),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: Tr.of(context, ar: 'ترتيب', en: 'Sort'),
              icon: Icon(
                state.oldestFirst
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 20,
              ),
              onPressed: () =>
                  controller.setOrder(oldestFirst: !state.oldestFirst),
            ),
            IconButton(
              tooltip: Tr.of(context, ar: 'تحديث', en: 'Refresh'),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: controller.refresh,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                Space.xs,
              ),
              child: TextField(
                controller: _search,
                onChanged: _onQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: Tr.of(
                    context,
                    ar: 'ابحث باسم المستخدم (يبدأ بـ…)',
                    en: 'Search by username (prefix)',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: state.query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            _search.clear();
                            controller.search('');
                          },
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: Space.xs),
                    child: WingsFilterChip(
                      label: Tr.of(context, ar: 'الكل', en: 'All'),
                      selected: state.status == null,
                      onTap: () => controller.setStatus(null),
                    ),
                  ),
                  for (final status in <AccountState>[
                    AccountState.restricted,
                    AccountState.suspended,
                    AccountState.banned,
                    AccountState.underReview,
                    AccountState.warned,
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: Space.xs),
                      child: WingsFilterChip(
                        label: adminStateLabel(context, status),
                        selected: state.status == status,
                        onTap: () => controller.setStatus(status),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.xs),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : state.error.isNotEmpty && state.items.isEmpty
                  ? WingsEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: Tr.of(
                        context,
                        ar: 'تعذّر التحميل',
                        en: 'Load failed',
                      ),
                      message: loadFailedText(context),
                      actionLabel: Tr.of(
                        context,
                        ar: 'إعادة المحاولة',
                        en: 'Retry',
                      ),
                      onAction: controller.refresh,
                    )
                  : state.items.isEmpty
                  ? WingsEmptyState(
                      icon: Icons.person_search_outlined,
                      title: Tr.of(
                        context,
                        ar: 'لا توجد نتائج',
                        en: 'No results',
                      ),
                      message: state.query.isEmpty
                          ? Tr.of(
                              context,
                              ar: 'لم يُسجَّل أي حساب بعد.',
                              en: 'No accounts registered yet.',
                            )
                          : null,
                    )
                  : RefreshIndicator(
                      onRefresh: controller.refresh,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.only(bottom: Space.xxxl),
                        itemCount: state.items.length + 1,
                        itemBuilder: (context, index) {
                          if (index == state.items.length) {
                            return Padding(
                              padding: const EdgeInsets.all(Space.lg),
                              child: Center(
                                child: state.loadingMore
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : state.hasMore
                                    ? WingsButton(
                                        label: Tr.of(
                                          context,
                                          ar: 'تحميل المزيد',
                                          en: 'Load more',
                                        ),
                                        variant: WingsButtonVariant.outline,
                                        onPressed: controller.loadMore,
                                      )
                                    : Text(
                                        Tr.of(
                                          context,
                                          ar: 'تم عرض كل النتائج',
                                          en: 'All results shown',
                                        ),
                                        style: context.text.labelSmall
                                            ?.copyWith(
                                              color: context.palette.textMuted,
                                            ),
                                      ),
                              ),
                            );
                          }
                          return _UserRow(
                            user: state.items[index],
                            onTap: () => context.push(
                              RoutePaths.adminUser(state.items[index].uid),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, required this.onTap});

  final AdminUserSummary user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        child: Row(
          children: <Widget>[
            UserAvatar(
              uid: user.uid,
              photoVersion: user.photoVersion,
              name: user.displayName,
              size: 42,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          user.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyLarge?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (user.role == StaffRole.owner) ...<Widget>[
                        const SizedBox(width: 4),
                        const OwnerBadge(compact: true),
                      ],
                      if (user.privateProfile) ...<Widget>[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 12,
                          color: palette.textMuted,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username} · ${adminDateShort(user.createdAt)}'
                    '${user.warningCount > 0 ? ' · ⚠ ${user.warningCount}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.xs),
            AdminStatusChip(state: user.status, compact: true),
          ],
        ),
      ),
    );
  }
}
