import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import '../../data/username/username_rules.dart';
import 'admin_actions.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// Email and username policies. A block survives the deletion of the account
/// that owned the address or the handle.
class AdminPoliciesScreen extends ConsumerStatefulWidget {
  const AdminPoliciesScreen({super.key});

  @override
  ConsumerState<AdminPoliciesScreen> createState() =>
      _AdminPoliciesScreenState();
}

class _AdminPoliciesScreenState extends ConsumerState<AdminPoliciesScreen> {
  final TextEditingController _filter = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _addEmail() async {
    final actor = AdminActor.of(ref);
    final email = await promptAdminText(
      context,
      title: Tr.of(context, ar: 'حظر بريد إلكتروني', en: 'Block an email'),
      hint: 'name@example.com',
      description: Tr.of(
        context,
        ar: 'يُمنع التسجيل بهذا البريد، ويُخزَّن بصيغة موحّدة في مستند لا يمكن سرد القائمة منه.',
        en: 'Registration with this address is refused. It is stored normalized in a document that cannot be enumerated.',
      ),
    );
    if (email == null || !mounted) return;
    if (!email.contains('@')) {
      context.showSnack(
        Tr.of(context, ar: 'بريد غير صالح.', en: 'Invalid email.'),
      );
      return;
    }
    try {
      await ref
          .read(adminRepositoryProvider)
          .blockEmail(
            email: email,
            reason: 'owner-console',
            actorUid: actor.uid,
            actorName: actor.name,
          );
      ref.invalidate(blockedEmailsProvider);
      if (mounted) {
        context.showSnack(Tr.of(context, ar: 'تم الحظر.', en: 'Blocked.'));
      }
    } on Object catch (error) {
      if (mounted) context.showSnack(error.toString(), isError: true);
    }
  }

  Future<void> _addUsername() async {
    final actor = AdminActor.of(ref);
    final username = await promptAdminText(
      context,
      title: Tr.of(context, ar: 'حظر اسم مستخدم', en: 'Block a username'),
      hint: 'name',
      description: Tr.of(
        context,
        ar: 'لن يستطيع أي حساب حجز هذا الاسم أو التغيير إليه. تتم المطابقة بعد التوحيد (حروف صغيرة).',
        en: 'No account can reserve or rename to this handle. Matching uses the normalized (lower-case) form.',
      ),
    );
    if (username == null || !mounted) return;
    final validation = UsernameRules.validate(username);
    if (!validation.ok && validation.normalized.length < 3) {
      context.showSnack(
        Tr.of(context, ar: 'اسم غير صالح.', en: 'Invalid username.'),
        isError: true,
      );
      return;
    }
    try {
      await ref
          .read(adminRepositoryProvider)
          .blockUsername(
            username: username,
            reason: 'owner-console',
            actorUid: actor.uid,
            actorName: actor.name,
          );
      ref.invalidate(blockedUsernamesProvider);
      if (mounted) {
        context.showSnack(Tr.of(context, ar: 'تم الحظر.', en: 'Blocked.'));
      }
    } on Object catch (error) {
      if (mounted) context.showSnack(error.toString(), isError: true);
    }
  }

  Future<void> _unblock(String key, {required bool email}) async {
    final confirmed = await WingsDialog.confirm(
      context,
      title: Tr.of(context, ar: 'رفع الحظر', en: 'Remove block'),
      message: key,
      confirmLabel: Tr.of(context, ar: 'رفع', en: 'Remove'),
    );
    if (!confirmed || !mounted) return;
    final actor = AdminActor.of(ref);
    try {
      final repository = ref.read(adminRepositoryProvider);
      if (email) {
        await repository.unblockEmail(
          email: key,
          actorUid: actor.uid,
          actorName: actor.name,
        );
        ref.invalidate(blockedEmailsProvider);
      } else {
        await repository.unblockUsername(
          username: key,
          actorUid: actor.uid,
          actorName: actor.name,
        );
        ref.invalidate(blockedUsernamesProvider);
      }
      if (mounted) {
        context.showSnack(
          Tr.of(context, ar: 'تم رفع الحظر.', en: 'Unblocked.'),
        );
      }
    } on Object catch (error) {
      if (mounted) context.showSnack(error.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emails = ref.watch(blockedEmailsProvider);
    final usernames = ref.watch(blockedUsernamesProvider);
    return AdminGuard(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: WingsAppBar(
            showBack: true,
            title: Text(
              Tr.of(context, ar: 'سياسات الحساب', en: 'Account policies'),
            ),
            bottom: TabBar(
              tabs: <Widget>[
                Tab(
                  text: Tr.of(context, ar: 'البريد المحظور', en: 'Emails'),
                ),
                Tab(
                  text: Tr.of(context, ar: 'الأسماء المحظورة', en: 'Usernames'),
                ),
              ],
            ),
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
                  controller: _filter,
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: Tr.of(
                      context,
                      ar: 'تصفية القائمة',
                      en: 'Filter list',
                    ),
                    prefixIcon: const Icon(Icons.filter_list_rounded, size: 18),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _BlockList(
                      source: emails,
                      email: true,
                      query: _query,
                      addLabel: Tr.of(
                        context,
                        ar: 'حظر بريد',
                        en: 'Block email',
                      ),
                      onAdd: _addEmail,
                      onRemove: (key) => _unblock(key, email: true),
                      emptyTitle: Tr.of(
                        context,
                        ar: 'لا توجد بريدات محظورة',
                        en: 'No blocked emails',
                      ),
                    ),
                    _BlockList(
                      source: usernames,
                      email: false,
                      query: _query,
                      addLabel: Tr.of(
                        context,
                        ar: 'حظر اسم',
                        en: 'Block username',
                      ),
                      onAdd: _addUsername,
                      onRemove: (key) => _unblock(key, email: false),
                      emptyTitle: Tr.of(
                        context,
                        ar: 'لا توجد أسماء محظورة',
                        en: 'No blocked usernames',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockList extends StatelessWidget {
  const _BlockList({
    required this.source,
    required this.email,
    required this.query,
    required this.addLabel,
    required this.onAdd,
    required this.onRemove,
    required this.emptyTitle,
  });

  final AsyncValue<List<BlockedIdentity>> source;
  final bool email;
  final String query;
  final String addLabel;
  final VoidCallback onAdd;
  final void Function(String key) onRemove;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    return source.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => WingsEmptyState(
        icon: Icons.cloud_off_rounded,
        title: Tr.of(context, ar: 'تعذّر التحميل', en: 'Failed to load'),
        message: error.toString(),
      ),
      data: (items) {
        final filtered = query.isEmpty
            ? items
            : items.where((item) => item.key.contains(query)).toList();
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.xs,
                Space.lg,
                Space.xs,
              ),
              child: WingsButton(
                label: addLabel,
                icon: Icons.add_rounded,
                expand: true,
                variant: WingsButtonVariant.tonal,
                onPressed: onAdd,
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? WingsEmptyState(
                      icon: email
                          ? Icons.mail_outline_rounded
                          : Icons.alternate_email_rounded,
                      title: emptyTitle,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: Space.xxxl),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return ListTile(
                          title: Text(item.key),
                          subtitle: Text(
                            '${adminDate(item.createdAt)}'
                            '${item.reason.isEmpty ? '' : ' · ${item.reason}'}',
                            style: context.text.labelSmall?.copyWith(
                              color: context.palette.textMuted,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: Tr.of(
                              context,
                              ar: 'رفع الحظر',
                              en: 'Remove',
                            ),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            onPressed: () => onRemove(item.key),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
