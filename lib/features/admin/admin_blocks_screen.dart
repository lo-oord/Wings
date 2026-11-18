import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import '../../data/username/username_rules.dart';
import 'admin_widgets.dart';

/// Email and username denylists.
///
/// Both survive the deletion of the account that used them: the email list is
/// keyed by a hash and the username list by the normalized handle, never by a
/// uid.
class AdminBlocksScreen extends ConsumerStatefulWidget {
  const AdminBlocksScreen({super.key});

  @override
  ConsumerState<AdminBlocksScreen> createState() => _AdminBlocksScreenState();
}

class _AdminBlocksScreenState extends ConsumerState<AdminBlocksScreen> {
  bool _emails = true;
  bool _loading = true;
  String? _error;
  List<BlockedEmail> _blockedEmails = const <BlockedEmail>[];
  List<BlockedUsername> _blockedUsernames = const <BlockedUsername>[];

  final TextEditingController _usernameSearch = TextEditingController();
  String? _checkMessage;
  bool _checkedBlocked = false;
  bool _checkedReserved = false;
  String _checkedNormalized = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(adminRepositoryProvider);
      final results = await Future.wait<Object>(<Future<Object>>[
        repository.blockedEmails(),
        repository.blockedUsernames(),
      ]);
      if (!mounted) return;
      setState(() {
        _blockedEmails = results[0] as List<BlockedEmail>;
        _blockedUsernames = results[1] as List<BlockedUsername>;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل قوائم الحظر. تأكد من نشر أحدث قواعد Firestore.';
      });
    }
  }

  Future<void> _addEmail() async {
    final email = TextEditingController();
    final reason = TextEditingController();
    final draft = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حظر بريد إلكتروني'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Space.sm),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'السبب',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final address = email.text.trim();
              final text = reason.text.trim();
              if (!address.contains('@') || text.isEmpty) return;
              Navigator.of(dialogContext).pop((address, text));
            },
            child: const Text('حظر'),
          ),
        ],
      ),
    );
    if (draft == null) return;
    final actor = adminActorOf(ref);
    if (actor == null) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .blockEmail(actor: actor, email: draft.$1, reason: draft.$2);
      if (!mounted) return;
      context.showSnack('أُضيف البريد إلى قائمة الحظر.');
      await _load();
    } on Object {
      if (mounted) context.showSnack('تعذّر حظر البريد.', isError: true);
    }
  }

  Future<void> _unblockEmail(BlockedEmail email) async {
    final confirmed = await WingsDialog.confirm(
      context,
      title: 'رفع حظر البريد',
      message:
          'سيُسمح بالتسجيل بهذا البريد مجددًا. البصمة: ${email.hash.substring(0, 12)}…',
      confirmLabel: 'رفع الحظر',
      destructive: true,
    );
    if (!confirmed) return;
    final actor = adminActorOf(ref);
    if (actor == null) return;
    try {
      await ref.read(adminRepositoryProvider).unblockEmail(
        actor: actor,
        hash: email.hash,
        reason: 'رفع الحظر بواسطة المالك',
      );
      if (!mounted) return;
      context.showSnack('رُفع حظر البريد.');
      await _load();
    } on Object {
      if (mounted) context.showSnack('تعذّر رفع الحظر.', isError: true);
    }
  }

  Future<void> _checkUsername(String raw) async {
    final validation = UsernameRules.validate(raw);
    if (!validation.ok) {
      setState(() {
        _checkMessage = 'اسم غير صالح: استخدم 3–20 حرفًا إنجليزيًا أو رقمًا أو _';
        _checkedBlocked = false;
        _checkedReserved = false;
      });
      return;
    }
    final repository = ref.read(adminRepositoryProvider);
    try {
      final blocked = await repository.findBlockedUsername(
        validation.normalized,
      );
      final reserved = await ref
          .read(usernameRepositoryProvider)
          .isAvailable(validation.normalized);
      if (!mounted) return;
      setState(() {
        _checkedNormalized = validation.normalized;
        _checkedBlocked = blocked != null;
        _checkedReserved = !reserved && blocked == null;
        _checkMessage = blocked != null
            ? 'محظور بواسطة المالك: ${blocked.reason}'
            : reserved
            ? 'متاح للتسجيل'
            : 'محجوز لحساب حالي';
      });
    } on Object {
      if (mounted) {
        setState(() {
          _checkMessage = 'تعذّر الفحص الآن.';
          _checkedBlocked = false;
          _checkedReserved = false;
        });
      }
    }
  }

  Future<void> _blockCheckedUsername() async {
    if (_checkedNormalized.isEmpty) return;
    final actor = adminActorOf(ref);
    if (actor == null) return;
    final draft = await showAdminActionDialog(
      context,
      title: 'حظر @$_checkedNormalized',
      description:
          'لن يستطيع أي حساب جديد أو حالي حجز هذا الاسم، حتى لو حُذف صاحبه.',
    );
    if (draft == null) return;
    try {
      await ref.read(adminRepositoryProvider).blockUsername(
        actor: actor,
        username: _checkedNormalized,
        reason: draft.reason,
      );
      if (!mounted) return;
      context.showSnack('حُظر اسم المستخدم.');
      setState(() {
        _checkedBlocked = true;
        _checkMessage = 'محظور بواسطة المالك: ${draft.reason}';
      });
      await _load();
    } on Object {
      if (mounted) context.showSnack('تعذّر حظر الاسم.', isError: true);
    }
  }

  Future<void> _unblockUsername(BlockedUsername username) async {
    final confirmed = await WingsDialog.confirm(
      context,
      title: 'رفع حظر @${username.normalized}',
      message: 'سيصبح الاسم متاحًا للحجز من جديد.',
      confirmLabel: 'رفع الحظر',
      destructive: true,
    );
    if (!confirmed) return;
    final actor = adminActorOf(ref);
    if (actor == null) return;
    try {
      await ref.read(adminRepositoryProvider).unblockUsername(
        actor: actor,
        normalized: username.normalized,
        reason: 'رفع الحظر بواسطة المالك',
      );
      if (!mounted) return;
      context.showSnack('رُفع حظر الاسم.');
      await _load();
    } on Object {
      if (mounted) context.showSnack('تعذّر رفع الحظر.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return OwnerGate(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text('قوائم الحظر', style: context.text.titleMedium),
          actions: <Widget>[
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
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: WingsFilterChip(
                      label: 'البريد الإلكتروني',
                      leadingIcon: Icons.mail_outline_rounded,
                      selected: _emails,
                      onTap: () => setState(() => _emails = true),
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: WingsFilterChip(
                      label: 'أسماء المستخدمين',
                      leadingIcon: Icons.alternate_email_rounded,
                      selected: !_emails,
                      onTap: () => setState(() => _emails = false),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Text(
                  _error!,
                  style: context.text.bodySmall?.copyWith(
                    color: palette.danger,
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _emails
                  ? _emailList()
                  : _usernameList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emailList() => ListView(
    padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.huge),
    children: <Widget>[
      WingsButton(
        label: 'حظر بريد إلكتروني',
        icon: Icons.add_rounded,
        onPressed: _addEmail,
      ),
      const SizedBox(height: Space.md),
      if (_blockedEmails.isEmpty)
        AdminCard(
          child: Text(
            'لا توجد عناوين محظورة.',
            style: context.text.bodySmall?.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        )
      else
        for (final email in _blockedEmails) ...<Widget>[
          AdminCard(
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 20,
                  color: context.palette.danger,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        email.domain.isEmpty
                            ? 'بصمة ${email.hash.substring(0, 12)}…'
                            : email.domain,
                        style: context.text.titleSmall?.copyWith(
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${email.reason.isEmpty ? 'بدون سبب مسجّل' : email.reason} · ${adminMoment(email.createdAt)}',
                        style: context.text.labelSmall?.copyWith(
                          color: context.palette.textMuted,
                        ),
                      ),
                      Text(
                        email.hash,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: context.palette.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _unblockEmail(email),
                  child: const Text('رفع'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
    ],
  );

  Widget _usernameList() => ListView(
    padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.huge),
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _usernameSearch,
              textInputAction: TextInputAction.search,
              onSubmitted: _checkUsername,
              decoration: const InputDecoration(
                hintText: 'اسم مستخدم للفحص أو الحظر…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          WingsButton(
            label: 'فحص',
            icon: Icons.search_rounded,
            onPressed: () => _checkUsername(_usernameSearch.text),
          ),
        ],
      ),
      if (_checkMessage != null) ...<Widget>[
        const SizedBox(height: Space.sm),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(_checkMessage!, style: context.text.bodySmall),
              if (!_checkedBlocked) ...<Widget>[
                const SizedBox(height: Space.sm),
                WingsButton(
                  label: 'حظر هذا الاسم',
                  icon: Icons.block_rounded,
                  variant: WingsButtonVariant.outline,
                  onPressed: _blockCheckedUsername,
                ),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: Space.md),
      if (_blockedUsernames.isEmpty)
        AdminCard(
          child: Text(
            'لا توجد أسماء محظورة.',
            style: context.text.bodySmall?.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        )
      else
        for (final username in _blockedUsernames) ...<Widget>[
          AdminCard(
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.block_rounded,
                  size: 19,
                  color: context.palette.danger,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '@${username.normalized}',
                        style: context.text.titleSmall?.copyWith(
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${username.reason.isEmpty ? 'بدون سبب مسجّل' : username.reason} · ${adminMoment(username.createdAt)}',
                        style: context.text.labelSmall?.copyWith(
                          color: context.palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _unblockUsername(username),
                  child: const Text('رفع'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
    ],
  );
}
