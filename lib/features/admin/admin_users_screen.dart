import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/account_status.dart';
import '../../data/models/admin_models.dart';
import '../profile/avatar_view.dart';
import 'admin_widgets.dart';

/// Browsable, filterable, paginated account list.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  String _query = '';
  AccountState? _status;
  bool _newestFirst = true;

  final List<AdminUser> _users = <AdminUser>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  List<AdminUser> _searchResults = const <AdminUser>[];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(adminRepositoryProvider)
          .usersPage(
            status: _status,
            newestFirst: _newestFirst,
            limit: 20,
          );
      if (!mounted) return;
      setState(() {
        _users
          ..clear()
          ..addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _explain(error);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(adminRepositoryProvider)
          .usersPage(
            status: _status,
            newestFirst: _newestFirst,
            cursor: _cursor,
            limit: 20,
          );
      if (!mounted) return;
      setState(() {
        _users.addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on Object {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _searchResults = const <AdminUser>[];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await ref
            .read(adminRepositoryProvider)
            .searchUsers(query);
        if (!mounted || _search.text.trim() != query) return;
        setState(() {
          _query = query;
          _searchResults = results;
          _searching = false;
        });
      } on Object {
        if (!mounted) return;
        setState(() {
          _searchResults = const <AdminUser>[];
          _searching = false;
        });
      }
    });
  }

  String _explain(Object error) {
    if (error is FirebaseException && error.code == 'failed-precondition') {
      return 'أضف فهرس Firestore الجديد: المجموعة users بحقلَي '
          'accountStatus و createdAt، ثم أعد المحاولة.';
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'رفض الخادم القراءة. انشر firestore.rules المحدّثة أولًا.';
    }
    return 'تعذّر تحميل المستخدمين. تحقق من الاتصال وحاول مجددًا.';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return OwnerGate(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text('المستخدمون', style: context.text.titleMedium),
          actions: <Widget>[
            IconButton(
              tooltip: _newestFirst ? 'الأحدث أولًا' : 'الأقدم أولًا',
              icon: Icon(
                _newestFirst
                    ? Icons.sort_rounded
                    : Icons.sort_rounded,
                size: 20,
              ),
              onPressed: () {
                setState(() => _newestFirst = !_newestFirst);
                _load();
              },
            ),
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _load,
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
                Space.sm,
              ),
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث باسم المستخدم…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 19),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _search.clear();
                            _onSearchChanged('');
                          },
                        ),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                children: <Widget>[
                  WingsFilterChip(
                    label: 'الكل',
                    selected: _status == null,
                    onTap: () {
                      setState(() => _status = null);
                      _load();
                    },
                  ),
                  const SizedBox(width: Space.xs),
                  for (final state in <AccountState>[
                    AccountState.active,
                    AccountState.warned,
                    AccountState.restricted,
                    AccountState.suspended,
                    AccountState.banned,
                    AccountState.underReview,
                    AccountState.deleted,
                  ]) ...<Widget>[
                    WingsFilterChip(
                      label: state.arabic,
                      selected: _status == state,
                      onTap: () {
                        setState(() => _status = state);
                        _load();
                      },
                    ),
                    const SizedBox(width: Space.xs),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Expanded(child: _buildBody(palette)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(dynamic palette) {
    if (_query.isNotEmpty) {
      if (_searching) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_searchResults.isEmpty) {
        return _Empty(
          icon: Icons.person_search_rounded,
          text: 'لا يوجد مستخدم يطابق «$_query».',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.huge),
        itemCount: _searchResults.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, index) =>
            _UserTile(user: _searchResults[index]),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: context.palette.danger,
              ),
              const SizedBox(height: Space.md),
              Text(
                error,
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
              const SizedBox(height: Space.md),
              WingsButton(
                label: 'إعادة المحاولة',
                icon: Icons.refresh_rounded,
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }
    if (_users.isEmpty) {
      return _Empty(
        icon: Icons.people_outline_rounded,
        text: 'لا توجد حسابات بهذا التصنيف.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.huge),
      itemCount: _users.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, index) {
        if (index >= _users.length) {
          return Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: WingsButton(
              label: _loadingMore ? 'جارٍ التحميل…' : 'تحميل المزيد',
              variant: WingsButtonVariant.outline,
              loading: _loadingMore,
              onPressed: _loadingMore ? null : _loadMore,
            ),
          );
        }
        return _UserTile(user: _users[index]);
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = user.standing.effectiveState;
    return AdminCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push(RoutePaths.developerUser(user.uid)),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          children: <Widget>[
            UserAvatar(
              uid: user.uid,
              photoVersion: user.photoVersion,
              name: user.displayName,
              size: 44,
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
                          user.displayName.isEmpty
                              ? user.handle
                              : user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall?.copyWith(
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (!user.showProfile) ...<Widget>[
                        const SizedBox(width: Space.xs),
                        Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: palette.textMuted,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${user.handle} · ${adminMoment(user.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                AccountStateChip(state: state, compact: true),
                if (user.standing.warningsCount > 0) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    '${user.standing.warningsCount} إنذار',
                    style: context.text.labelSmall?.copyWith(
                      color: palette.warning,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 38, color: context.palette.textMuted),
        const SizedBox(height: Space.sm),
        Text(
          text,
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(
            color: context.palette.textMuted,
          ),
        ),
      ],
    ),
  );
}
