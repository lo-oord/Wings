import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/account_status.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';
import '../profile/avatar_view.dart';
import 'admin_widgets.dart';

/// Full administrative profile of one account, including a private profile.
class AdminUserDetailsScreen extends ConsumerStatefulWidget {
  const AdminUserDetailsScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<AdminUserDetailsScreen> createState() =>
      _AdminUserDetailsScreenState();
}

class _AdminUserDetailsScreenState
    extends ConsumerState<AdminUserDetailsScreen> {
  AdminUserDetails? _details;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final details = await ref
          .read(adminRepositoryProvider)
          .userDetails(widget.uid);
      if (!mounted) return;
      setState(() {
        _details = details;
        _loading = false;
        _error = details == null ? 'لا يوجد حساب بهذا المعرّف.' : null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل بيانات الحساب. تحقق من القواعد والاتصال.';
      });
    }
  }

  String _errorText(Object error) => error is FirebaseException
      ? 'رفض الخادم الإجراء (${error.code}). انشر أحدث قواعد Firestore.'
      : 'تعذّر تنفيذ الإجراء. حاول مرة أخرى.';

  Future<void> _run(
    Future<void> Function(AdminActor actor) action, {
    String success = 'تم تنفيذ الإجراء وتوثيقه.',
  }) async {
    final actor = adminActorOf(ref);
    if (actor == null) return;
    setState(() => _busy = true);
    try {
      await action(actor);
      if (!mounted) return;
      context.showSnack(success);
      await _reload();
    } on Object catch (error) {
      if (mounted) context.showSnack(_errorText(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  AdminUser? get _user => _details?.user;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return OwnerGate(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text('ملف إداري', style: context.text.titleMedium),
          actions: <Widget>[
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _reload,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              )
            : _buildBody(context, _details!),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AdminUserDetails details) {
    final palette = context.palette;
    final user = details.user;
    final standing = user.standing;
    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: _reload,
          color: palette.primary,
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.huge),
            children: <Widget>[
              _header(context, user),
              const AdminSectionTitle('حالة الحساب'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          AccountStateChip(state: standing.effectiveState),
                          const Spacer(),
                          if (standing.expiresAt != null)
                            Text(
                              'ينتهي: ${adminMoment(standing.expiresAt)}',
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                        ],
                      ),
                      if (standing.reason.isNotEmpty) ...<Widget>[
                        const SizedBox(height: Space.sm),
                        Text(
                          'السبب: ${standing.reason}',
                          style: context.text.bodySmall,
                        ),
                      ],
                      if (standing.updatedAt != null) ...<Widget>[
                        const SizedBox(height: Space.xs),
                        Text(
                          'آخر تحديث: ${adminMoment(standing.updatedAt)}',
                          style: context.text.labelSmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                      if (standing.activeRestrictions.any) ...<Widget>[
                        const SizedBox(height: Space.md),
                        Wrap(
                          spacing: Space.xs,
                          runSpacing: Space.xs,
                          children: <Widget>[
                            for (final key
                                in standing.activeRestrictions.enabledKeys)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Space.sm,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.warning.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    Radii.pill,
                                  ),
                                ),
                                child: Text(
                                  'ممنوع: ${restrictionLabel(key)}',
                                  style: context.text.labelSmall?.copyWith(
                                    color: palette.warning,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (standing.restrictionsExpireAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Text(
                              'تنتهي القيود: ${adminMoment(standing.restrictionsExpireAt)}',
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ),
                      ],
                      if (standing.suspensionExpired)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.sm),
                          child: Text(
                            'انتهى الإيقاف تلقائيًا؛ لم يعد مفعّلًا.',
                            style: context.text.labelSmall?.copyWith(
                              color: palette.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const AdminSectionTitle('بيانات الحساب'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: AdminCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      AdminRow(
                        icon: Icons.badge_outlined,
                        title: 'اسم المستخدم',
                        subtitle: user.handle,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.person_outline_rounded,
                        title: 'الاسم الظاهر',
                        subtitle: user.displayName.isEmpty
                            ? '—'
                            : user.displayName,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.fingerprint_rounded,
                        title: 'معرّف المستخدم',
                        subtitle: user.uid,
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 17),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: user.uid),
                            );
                            if (context.mounted) {
                              context.showSnack('تم نسخ المعرّف.');
                            }
                          },
                        ),
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.event_available_rounded,
                        title: 'تاريخ التسجيل',
                        subtitle: adminMoment(user.createdAt),
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: user.showProfile
                            ? Icons.public_rounded
                            : Icons.lock_rounded,
                        title: 'حالة الملف',
                        subtitle: user.showProfile
                            ? 'عام — يظهر للجميع'
                            : 'خاص — مخفي عن المستخدمين',
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.warning_amber_rounded,
                        title: 'الإنذارات',
                        subtitle:
                            '${standing.warningsCount} إنذار مسجّل · '
                            '${details.warnings.where((w) => w.active).length} نشط',
                      ),
                    ],
                  ),
                ),
              ),
              const AdminSectionTitle('مراجعة الملف الخاص'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'هذه البيانات تُقرأ من مستند الحساب الأصلي ولا تُغيّر إعداد '
                        'الخصوصية ولا تجعل الملف عامًا.',
                        style: context.text.labelSmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      _kv(context, 'نبذة', user.bio.isEmpty ? '—' : user.bio),
                      _kv(
                        context,
                        'الدولة',
                        user.country.isEmpty ? '—' : user.country,
                      ),
                      _kv(
                        context,
                        'الفئة العمرية',
                        user.ageGroup.isEmpty ? '—' : user.ageGroup,
                      ),
                      _kv(
                        context,
                        'المفضلة',
                        user.favorites.isEmpty
                            ? '—'
                            : user.favorites.take(6).join('، '),
                      ),
                      _kv(
                        context,
                        'الإحصاءات',
                        user.stats.isEmpty
                            ? '—'
                            : 'أنمي: ${formatCount(user.stats['animeWatched'])} · '
                                  'حلقات: ${formatCount(user.stats['episodesWatched'])} · '
                                  'مفضلة: ${formatCount(user.stats['favorites'])}',
                      ),
                    ],
                  ),
                ),
              ),
              const AdminSectionTitle('الإجراءات'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: AdminCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      AdminRow(
                        icon: Icons.mail_outline_rounded,
                        title: 'إرسال رسالة من المالك',
                        subtitle: 'تظهر للعضو بهوية Wings الرسمية',
                        onTap: _busy ? null : _sendMessage,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.warning_amber_rounded,
                        title: 'إنذار رسمي',
                        subtitle: 'لا يعطّل أي ميزة بمفرده',
                        onTap: _busy ? null : _warn,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.do_not_disturb_on_outlined,
                        title: 'تقييد ميزات',
                        subtitle: 'تعليق، نشر، تفاعل، مجتمع أو بلاغات',
                        onTap: _busy ? null : _restrict,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.pause_circle_outline_rounded,
                        title: 'إيقاف مؤقت',
                        subtitle: 'ينتهي تلقائيًا في الموعد المحدد',
                        onTap: _busy ? null : _suspend,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.gavel_rounded,
                        title: 'حظر دائم',
                        subtitle: 'لا ينتهي إلا بقرار يدوي',
                        danger: true,
                        onTap: _busy ? null : _ban,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.hourglass_top_rounded,
                        title: 'وضع قيد المراجعة',
                        subtitle: 'دون تعطيل تلقائي لأي ميزة',
                        onTap: _busy ? null : _underReview,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.restore_rounded,
                        title: 'استعادة / رفع الحظر',
                        subtitle: 'يعيد الحساب لأعلى حالة ما زالت تنطبق',
                        onTap: _busy ? null : _restore,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.public_rounded,
                        title: 'فتح الملف العام',
                        subtitle: 'كما يراه المستخدمون',
                        onTap: () => context.push('/user/${user.uid}'),
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.alternate_email_rounded,
                        title: 'حظر اسم المستخدم',
                        subtitle: user.handle,
                        onTap: _busy ? null : _blockUsername,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.mark_email_read_outlined,
                        title: 'حظر بريد الحساب',
                        subtitle: user.emailHash.isEmpty
                            ? 'لا يوجد بصمة بريد مسجّلة لهذا الحساب'
                            : 'بصمة محفوظة — الحظر يمنع التسجيل مجددًا',
                        onTap: _busy ? null : _blockEmail,
                      ),
                      _divider(palette.border),
                      AdminRow(
                        icon: Icons.delete_forever_rounded,
                        title: 'حذف الحساب',
                        subtitle: 'مسح المحتوى وكل البيانات المرتبطة',
                        danger: true,
                        onTap: _busy ? null : _delete,
                      ),
                    ],
                  ),
                ),
              ),
              if (details.warnings.isNotEmpty) ...<Widget>[
                const AdminSectionTitle('الإنذارات'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: AdminCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        for (final warning in details.warnings)
                          AdminRow(
                            icon: warning.active
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded,
                            title: warning.reason.isEmpty
                                ? warning.category
                                : warning.reason,
                            subtitle:
                                '${warning.category} · ${adminMoment(warning.createdAt)}'
                                '${warning.active ? '' : ' · ملغى'}',
                            trailing: warning.active
                                ? TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _revokeWarning(warning),
                                    child: const Text('إلغاء'),
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const AdminSectionTitle('سجل الإجراءات على هذا الحساب'),
              if (details.actions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: AdminCard(
                    child: Text(
                      'لا توجد إجراءات سابقة.',
                      style: context.text.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: AdminCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        for (final action in details.actions)
                          AdminRow(
                            icon: Icons.bolt_rounded,
                            title: action.action,
                            subtitle:
                                '${adminMoment(action.createdAt)}'
                                '${action.reason.isEmpty ? '' : ' · ${action.reason}'}',
                          ),
                      ],
                    ),
                  ),
                ),
              const AdminSectionTitle('بلاغات مرتبطة'),
              if (details.reports.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: AdminCard(
                    child: Text(
                      'لا توجد بلاغات تشير إلى هذا الحساب.',
                      style: context.text.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: AdminCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        for (final report in details.reports.take(10))
                          AdminRow(
                            icon: Icons.flag_outlined,
                            title:
                                '${report.status} · ${report.targetType.isEmpty ? 'بلاغ' : report.targetType}',
                            subtitle:
                                '${adminMoment(report.createdAt)} · ${report.reason}',
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.25),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _divider(Color color) =>
      Divider(height: 1, color: color, indent: Space.md, endIndent: Space.md);

  Widget _header(BuildContext context, AdminUser user) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: AdminCard(
        child: Row(
          children: <Widget>[
            UserAvatar(
              uid: user.uid,
              photoVersion: user.photoVersion,
              name: user.displayName,
              size: 62,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    user.displayName.isEmpty ? user.handle : user.displayName,
                    style: context.text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.handle,
                    style: context.text.labelSmall?.copyWith(
                      color: palette.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Wrap(
                    spacing: Space.xs,
                    children: <Widget>[
                      AccountStateChip(
                        state: user.standing.effectiveState,
                        compact: true,
                      ),
                      if (!user.showProfile)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: palette.surfaceHigh,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text(
                            'ملف خاص',
                            style: context.text.labelSmall?.copyWith(
                              color: palette.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(value, style: context.text.bodySmall),
        ),
      ],
    ),
  );

  // ----------------------------------------------------------------- actions

  Future<void> _sendMessage() async {
    final user = _user;
    if (user == null) return;
    final draft = await _showMessageDialog(user);
    if (draft == null) return;
    await _run(
      (actor) => ref
          .read(adminRepositoryProvider)
          .sendOwnerMessage(
            actor: actor,
            target: user,
            title: draft.$1,
            body: draft.$2,
          ),
      success: 'أُرسلت رسالة المالك.',
    );
  }

  Future<(String, String)?> _showMessageDialog(AdminUser user) {
    final title = TextEditingController();
    final body = TextEditingController();
    return showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رسالة من مالك Wings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'العنوان (اختياري)',
                  border: OutlineInputBorder(),
                ),
                maxLength: 120,
              ),
              const SizedBox(height: Space.sm),
              TextField(
                controller: body,
                minLines: 4,
                maxLines: 8,
                maxLength: 3000,
                decoration: const InputDecoration(
                  labelText: 'نص الرسالة',
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
              final text = body.text.trim();
              if (text.isEmpty) return;
              Navigator.of(dialogContext).pop((title.text.trim(), text));
            },
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
  }

  Future<void> _warn() async {
    final user = _user;
    if (user == null) return;
    final draft = await _showWarningDialog();
    if (draft == null) return;
    await _run(
      (actor) => ref
          .read(adminRepositoryProvider)
          .warn(
            actor: actor,
            target: user,
            category: draft.$1,
            reason: draft.$2,
          ),
      success: 'سُجّل الإنذار وأُرسل للعضو.',
    );
  }

  Future<(String, String)?> _showWarningDialog() {
    String category = 'policy';
    final reason = TextEditingController();
    return showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('إنذار رسمي'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('التصنيف'),
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  children: <Widget>[
                    for (final entry in const <String, String>{
                      'policy': 'سياسة المنصة',
                      'spam': 'إزعاج',
                      'abuse': 'إساءة',
                      'content': 'محتوى',
                      'impersonation': 'انتحال',
                      'copyright': 'حقوق نشر',
                      'report-abuse': 'إساءة بلاغات',
                    }.entries)
                      WingsFilterChip(
                        label: entry.value,
                        selected: category == entry.key,
                        onTap: () =>
                            setDialogState(() => category = entry.key),
                      ),
                  ],
                ),
                const SizedBox(height: Space.md),
                TextField(
                  controller: reason,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
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
                final text = reason.text.trim();
                if (text.isEmpty) return;
                Navigator.of(dialogContext).pop((category, text));
              },
              child: const Text('إصدار الإنذار'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restrict() async {
    final user = _user;
    if (user == null) return;
    final draft = await showAdminActionDialog(
      context,
      title: 'تقييد ميزات',
      description:
          'اختر الميزات التي ستُعطَّل. يستطيع العضو متابعة استخدام Wings '
          'باقي الميزات.',
      allowDuration: true,
      allowRestrictions: true,
      initialRestrictions: user.standing.restrictions,
    );
    if (draft == null) return;
    if (!draft.restrictions.any) {
      context.showSnack('اختر ميزة واحدة على الأقل.', isError: true);
      return;
    }
    final labels = draft.restrictions.enabledKeys
        .map(restrictionLabel)
        .toList(growable: false);
    await _run(
      (actor) => ref
          .read(adminRepositoryProvider)
          .applyState(
            actor: actor,
            target: user,
            state: AccountState.restricted,
            reason: draft.reason,
            action: 'restrict',
            restrictions: draft.restrictions,
            restrictionsExpireAt: draft.expiresAt,
            title: 'تم تقييد بعض ميزات حسابك',
            body:
                'قيّدت إدارة Wings بعض الميزات في حسابك.\n\n'
                'السبب: ${draft.reason}\n'
                'الميزات المقيّدة: ${labels.join('، ')}\n'
                'المدة: ${draft.expiresAt == null ? 'دائم' : adminMoment(draft.expiresAt)}\n\n'
                'بقية التطبيق تعمل بشكل طبيعي.',
            category: 'restriction',
            severity: 'warning',
            restrictionLabels: labels,
            details: <String, dynamic>{'labels': labels},
          ),
      success: 'طُبّق التقييد وأُرسل إشعار للعضو.',
    );
  }

  Future<void> _suspend() async {
    final user = _user;
    if (user == null) return;
    final draft = await showAdminActionDialog(
      context,
      title: 'إيقاف مؤقت',
      description:
          'يُمنع الحساب من استخدام Wings حتى انتهاء المدة، ثم يعود تلقائيًا '
          'دون أي إجراء إضافي. اختر «دائم» فقط إذا كانت السياسة تسمح.',
      allowDuration: true,
    );
    if (draft == null) return;
    await _run(
      (actor) => ref
          .read(adminRepositoryProvider)
          .applyState(
            actor: actor,
            target: user,
            state: AccountState.suspended,
            reason: draft.reason,
            action: 'suspend',
            expiresAt: draft.expiresAt,
            title: 'تم إيقاف حسابك مؤقتًا',
            body:
                'أوقفت إدارة Wings حسابك مؤقتًا.\n\n'
                'السبب: ${draft.reason}\n'
                'المدة: ${draft.expiresAt == null ? 'غير محددة' : adminMoment(draft.expiresAt)}\n\n'
                'لن تستطيع استخدام التطبيق حتى انتهاء المدة. إذا كنت تعتقد أن '
                'هذا الإجراء غير صحيح فتواصل مع دعم Wings.',
            category: 'account-status',
            severity: 'critical',
          ),
      success: 'أُوقف الحساب وأُرسل إشعار للعضو.',
    );
  }

  Future<void> _ban() async {
    final user = _user;
    if (user == null) return;
    final draft = await showAdminActionDialog(
      context,
      title: 'حظر دائم',
      description:
          'يمنع الحساب من استخدام التطبيق نهائيًا. لا ينتهي تلقائيًا؛ فقط '
          '«استعادة / رفع الحظر» يرفعه.',
    );
    if (draft == null) return;
    final confirmed = await WingsDialog.confirm(
      context,
      title: 'تأكيد الحظر الدائم',
      message:
          'سيُحظر @${user.username} نهائيًا. لن يستطيع استخدام Wings حتى ترفع '
          'الحظر يدويًا. هل تريد المتابعة؟',
      confirmLabel: 'حظر نهائي',
      destructive: true,
    );
    if (!confirmed) return;
    await _run(
      (actor) => ref
          .read(adminRepositoryProvider)
          .applyState(
            actor: actor,
            target: user,
            state: AccountState.banned,
            reason: draft.reason,
            action: 'ban',
            restrictions: const AccountRestrictions(
              comment: true,
              post: true,
              interact: true,
              community: true,
              report: true,
            ),
            title: 'تم حظر حسابك نهائيًا',
            body:
                'حظرت إدارة Wings حسابك نهائيًا.\n\n'
                'السبب: ${draft.reason}\n\n'
                'الحظر لا ينتهي تلقائيًا. إذا كنت تعتقد أن هذا الإجراء غير صحيح '
                'فتواصل مع دعم Wings.',
            category: 'account-status',
            severity: 'critical',
            restrictionLabels: const <String>[
              'التعليق',
              'النشر',
              'التفاعل',
              'المجتمع',
              'البلاغات',
            ],
          ),
      success: 'حُظر الحساب نهائيًا.',
    );
  }

  Future<void> _underReview() async {
    final user = _user;
    if (user == null) return;
    final draft = await showAdminActionDialog(
      context,
      title: 'وضع قيد المراجعة',
      description: 'لا يعطّل أي ميزة تلقائيًا؛ يمكنك إضافة تقييد منفصل.',
    );
    if (draft == null) return;
    await _run(
      (actor) => ref
          .read(adminRepositoryProvider)
          .applyState(
            actor: actor,
            target: user,
            state: AccountState.underReview,
            reason: draft.reason,
            action: 'under-review',
            title: 'حسابك قيد المراجعة',
            body:
                'وضعت إدارة Wings حسابك قيد المراجعة.\n\n'
                'السبب: ${draft.reason}\n\n'
                'لا تتغير ميزات حسابك تلقائيًا أثناء المراجعة.',
            category: 'account-status',
            severity: 'info',
          ),
      success: 'نُقل الحساب إلى قيد المراجعة.',
    );
  }

  Future<void> _restore() async {
    final user = _user;
    if (user == null) return;
    final draft = await showAdminActionDialog(
      context,
      title: 'استعادة الحساب',
      description:
          'يرفع الحظر أو الإيقاف ويعيد الحساب إلى «مقيّد» أو «موعوظ» أو '
          '«نشط» حسب ما تبقّى من قيود وإنذارات.',
    );
    if (draft == null) return;
    await _run(
      (actor) => ref
          .read(adminRepositoryProvider)
          .restore(actor: actor, target: user, reason: draft.reason),
      success: 'استُعيد الحساب.',
    );
  }

  Future<void> _revokeWarning(AdminWarning warning) async {
    final user = _user;
    if (user == null) return;
    final draft = await showAdminActionDialog(
      context,
      title: 'إلغاء إنذار',
      description: 'يبقى السجل محفوظًا لأغراض التدقيق.',
    );
    if (draft == null) return;
    await _run(
      (actor) => ref
          .read(adminRepositoryProvider)
          .revokeWarning(
            actor: actor,
            target: user,
            warning: warning,
            reason: draft.reason,
          ),
      success: 'أُلغي الإنذار مع الاحتفاظ بالسجل.',
    );
  }

  Future<void> _blockUsername() async {
    final user = _user;
    if (user == null) return;
    final confirmed = await WingsDialog.confirm(
      context,
      title: 'حظر اسم المستخدم',
      message:
          'لن يكون @${user.username} متاحًا لأي حساب جديد أو لعملية تغيير اسم، '
          'حتى لو حُذف هذا الحساب.',
      confirmLabel: 'حظر الاسم',
      destructive: true,
    );
    if (!confirmed) return;
    await _run(
      (actor) => ref
          .read(adminRepositoryProvider)
          .blockUsername(
            actor: actor,
            username: user.username,
            reason: 'حظر بواسطة المالك من ملف الحساب',
          ),
      success: 'حُظر اسم المستخدم.',
    );
  }

  Future<void> _blockEmail() async {
    final user = _user;
    if (user == null) return;
    final confirmed = await WingsDialog.confirm(
      context,
      title: 'حظر بريد الحساب',
      message:
          'سيُضاف بريد هذا الحساب (بصمته المشفرة) إلى قائمة الحظر، فلا يمكن '
          'التسجيل به مجددًا حتى ترفع الحظر.',
      confirmLabel: 'حظر البريد',
      destructive: true,
    );
    if (!confirmed) return;
    await _run(
      (actor) => user.emailHash.isEmpty
          ? ref
                .read(adminRepositoryProvider)
                .blockUsername(
                  actor: actor,
                  username: user.username,
                  reason: 'لا توجد بصمة بريد؛ حُظر الاسم بدلًا منها',
                )
          : ref
                .read(adminRepositoryProvider)
                .blockEmailHash(
                  actor: actor,
                  hash: user.emailHash,
                  reason: 'حظر بواسطة المالك من ملف الحساب',
                ),
      success: 'أُضيف البريد إلى قائمة الحظر.',
    );
  }

  Future<void> _delete() async {
    final user = _user;
    if (user == null) return;
    final draft = await showAdminActionDialog(
      context,
      title: 'حذف الحساب',
      description:
          'تُحذف التعليقات والردود والمكتبة والسجل والشارات والملف واسم '
          'المستخدم. تبقى الإعجابات كما هي، ويُحفظ سجل الإجراء.',
    );
    if (draft == null) return;
    final confirmed = await WingsDialog.confirm(
      context,
      title: 'تأكيد حذف @${user.username}',
      message:
          'لا يمكن التراجع عن هذا الإجراء. سيُغلق الحساب فورًا وتُمسح بياناته، '
          'وسيُضاف بريده واسمه إلى قوائم الحظر لمنع إعادة إنشائه.\n\n'
          'ملاحظة: حذف سجل Firebase Authentication نفسه يتم من لوحة Firebase '
          'لأن Admin SDK يتطلب خطة مدفوعة.',
      confirmLabel: 'حذف نهائي',
      destructive: true,
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      final actor = adminActorOf(ref);
      if (actor == null) return;
      final report = await ref
          .read(adminRepositoryProvider)
          .deleteUser(actor: actor, target: user, reason: draft.reason);
      if (!mounted) return;
      await _showDeletionReport(report);
      await _reload();
    } on Object catch (error) {
      if (mounted) context.showSnack(_errorText(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDeletionReport(AdminDeletionReport report) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تم حذف الحساب'),
        content: Text(
          'أُغلق الحساب ومُسحت بياناته.'
          '${report.kept.isEmpty ? '' : '\n\nتعذّر حذف: ${report.kept.join(', ')}'}'
          '${report.authRecordPending ? '\n\nالخطوة الأخيرة: احذف مستخدم Firebase Authentication من لوحة Firebase '
                    '(Authentication ← Users) لإلغاء الجلسات القديمة نهائيًا.' : ''}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }
}
