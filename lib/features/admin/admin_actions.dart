import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../core/errors/user_facing_error.dart';

/// The signed-in administrator, copied onto every action for the audit log.
class AdminActor {
  const AdminActor({
    required this.uid,
    required this.name,
    required this.username,
    required this.photoVersion,
  });

  final String uid;
  final String name;
  final String username;
  final int photoVersion;

  bool get valid => uid.isNotEmpty;

  factory AdminActor.of(WidgetRef ref) {
    final user = ref.read(authProvider);
    final profile = ref.read(profileProvider);
    return AdminActor(
      uid: user?.id ?? '',
      name: (profile?.displayName.isNotEmpty ?? false)
          ? profile!.displayName
          : (user?.displayName.isNotEmpty ?? false)
          ? user!.displayName
          : 'Wings Owner',
      username: (profile?.username.isNotEmpty ?? false)
          ? profile!.username
          : 'wings',
      photoVersion: profile?.photoVersion ?? 0,
    );
  }
}

String _featuresSummary(
  BuildContext context,
  Set<RestrictionFeature> features,
) {
  if (features.isEmpty) return '—';
  return features.map((item) => restrictionLabel(context, item)).join('، ');
}

String _expirySummary(BuildContext context, DateTime? expiry, bool permanent) {
  if (permanent || expiry == null) {
    return Tr.of(context, ar: 'غير محددة المدة', en: 'Indefinite');
  }
  return adminDate(expiry);
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) => WingsDialog.confirm(
  context,
  title: title,
  message: message,
  confirmLabel: confirmLabel,
  destructive: destructive,
);

Future<void> _report(
  BuildContext context,
  Future<void> future,
  String success,
) async {
  try {
    await future;
    if (context.mounted) {
      context.showSnack(success);
    }
  } on Object catch (error) {
    if (context.mounted) {
      context.showSnack(userFacingError(context, error), isError: true);
    }
  }
}

// --------------------------------------------------------------- actions sheet

Future<void> showAdminActionsSheet(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final actor = AdminActor.of(ref);
  if (!actor.valid) {
    context.showSnack(
      Tr.of(context, ar: 'سجّل الدخول أولاً.', en: 'Sign in first.'),
      isError: true,
    );
    return;
  }
  await WingsSheet.show<void>(
    context,
    title: Tr.of(context, ar: 'إجراءات إدارية', en: 'Administrative actions'),
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SheetAction(
          icon: Icons.mail_outline_rounded,
          label: Tr.of(context, ar: 'رسالة من المالك', en: 'Owner message'),
          onTap: () {
            Navigator.of(sheetContext).pop();
            sendOwnerMessage(context, ref, target);
          },
        ),
        _SheetAction(
          icon: Icons.report_gmailerrorred_rounded,
          label: Tr.of(context, ar: 'توجيه تحذير', en: 'Warn'),
          onTap: () {
            Navigator.of(sheetContext).pop();
            issueWarning(context, ref, target);
          },
        ),
        _SheetAction(
          icon: Icons.tune_rounded,
          label: Tr.of(context, ar: 'تقييد ميزات', en: 'Restrict features'),
          onTap: () {
            Navigator.of(sheetContext).pop();
            applyRestriction(context, ref, target);
          },
        ),
        _SheetAction(
          icon: Icons.timer_outlined,
          label: Tr.of(context, ar: 'إيقاف مؤقت', en: 'Temporary suspension'),
          onTap: () {
            Navigator.of(sheetContext).pop();
            suspendUser(context, ref, target);
          },
        ),
        _SheetAction(
          icon: Icons.search_rounded,
          label: Tr.of(
            context,
            ar: 'وضع الحساب قيد المراجعة',
            en: 'Place under review',
          ),
          onTap: () {
            Navigator.of(sheetContext).pop();
            reviewUser(context, ref, target);
          },
        ),
        _SheetAction(
          icon: Icons.block_rounded,
          label: Tr.of(context, ar: 'حظر دائم', en: 'Permanent ban'),
          destructive: true,
          onTap: () {
            Navigator.of(sheetContext).pop();
            banUser(context, ref, target);
          },
        ),
        _SheetAction(
          icon: Icons.shield_outlined,
          label: Tr.of(
            context,
            ar: 'استعادة / رفع الحظر',
            en: 'Lift restrictions',
          ),
          onTap: () {
            Navigator.of(sheetContext).pop();
            restoreUser(context, ref, target);
          },
        ),
        _SheetAction(
          icon: Icons.mail_lock_outlined,
          label: Tr.of(context, ar: 'حظر البريد الإلكتروني', en: 'Block email'),
          destructive: true,
          onTap: () {
            Navigator.of(sheetContext).pop();
            blockUserEmail(context, ref, target);
          },
        ),
        _SheetAction(
          icon: Icons.alternate_email_rounded,
          label: Tr.of(context, ar: 'حظر اسم المستخدم', en: 'Block username'),
          destructive: true,
          onTap: () {
            Navigator.of(sheetContext).pop();
            blockUserUsername(context, ref, target);
          },
        ),
        _SheetAction(
          icon: Icons.delete_outline_rounded,
          label: Tr.of(context, ar: 'حذف الحساب', en: 'Delete account'),
          destructive: true,
          onTap: () {
            Navigator.of(sheetContext).pop();
            deleteUserAccount(context, ref, target);
          },
        ),
      ],
    ),
  );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return WingsSettingsTile(
      icon: icon,
      title: label,
      destructive: destructive,
      showChevron: true,
      onTap: onTap,
    );
  }
}

// ------------------------------------------------------------------ warning

Future<void> issueWarning(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final repository = ref.read(adminRepositoryProvider);
  final actor = AdminActor.of(ref);
  final decision = await showDialog<_WarningDecision>(
    context: context,
    builder: (_) => const _WarningDialog(),
  );
  if (decision == null || !context.mounted) return;
  AdminUserDetail? detail;
  try {
    detail = await repository.loadUser(target.uid);
  } on Object {
    detail = null;
  }
  if (!context.mounted) return;
  final body = Tr.of(
    context,
    ar: 'تم توجيه تحذير رسمي إلى حسابك في Wings.\n\nالسبب: ${decision.reason}\nالتصنيف: ${decision.category}\n\nالتحذير لا يوقف ميزات حسابك، لكن تكرار المخالفة قد يؤدي إلى إجراء إضافي.',
    en: 'An official warning has been issued on your Wings account.\n\nReason: ${decision.reason}\nCategory: ${decision.category}\n\nA warning alone does not disable your account, but repeated violations may lead to further action.',
  );
  await _report(
    context,
    repository.issueWarning(
      target: target,
      detail: detail ?? AdminUserDetail(summary: target, role: StaffRole.user),
      category: decision.category,
      reason: decision.reason,
      actorUid: actor.uid,
      actorName: actor.name,
      notificationTitle: Tr.of(
        context,
        ar: 'تحذير رسمي من إدارة Wings',
        en: 'Official warning from Wings',
      ),
      notificationBody: body,
    ),
    Tr.of(context, ar: 'تم توجيه التحذير.', en: 'Warning issued.'),
  );
  ref.invalidate(adminUserDetailProvider(target.uid));
}

class _WarningDecision {
  const _WarningDecision(this.category, this.reason);
  final String category;
  final String reason;
}

class _WarningDialog extends StatefulWidget {
  const _WarningDialog();

  @override
  State<_WarningDialog> createState() => _WarningDialogState();
}

class _WarningDialogState extends State<_WarningDialog> {
  static const List<(String, String, String)> _categories =
      <(String, String, String)>[
        ('general', 'مخالفة عامة', 'General violation'),
        ('spam', 'إزعاج أو سبام', 'Spam'),
        ('harassment', 'إساءة أو تنمّر', 'Harassment'),
        ('content', 'محتوى غير لائق', 'Inappropriate content'),
        ('impersonation', 'انتحال شخصية', 'Impersonation'),
        ('reportAbuse', 'إساءة استخدام البلاغات', 'Report abuse'),
      ];
  final TextEditingController _reason = TextEditingController();
  String _category = 'general';
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arabic = Tr.isArabic(context);
    return AlertDialog(
      title: Text(Tr.of(context, ar: 'توجيه تحذير', en: 'Issue warning')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'التصنيف', en: 'Category'),
              ),
              items: <DropdownMenuItem<String>>[
                for (final item in _categories)
                  DropdownMenuItem<String>(
                    value: item.$1,
                    child: Text(arabic ? item.$2 : item.$3),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _category = value ?? 'general'),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'السبب', en: 'Reason'),
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
        ),
        TextButton(
          onPressed: () {
            final reason = _reason.text.trim();
            if (reason.isEmpty) {
              setState(
                () => _error = Tr.of(
                  context,
                  ar: 'السبب مطلوب',
                  en: 'Reason required',
                ),
              );
              return;
            }
            Navigator.of(context).pop(_WarningDecision(_category, reason));
          },
          child: Text(Tr.of(context, ar: 'إرسال التحذير', en: 'Send warning')),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- restriction

class _RestrictionDecision {
  const _RestrictionDecision({
    required this.reason,
    required this.features,
    required this.permanent,
    this.expiresAt,
  });

  final String reason;
  final Set<RestrictionFeature> features;
  final bool permanent;
  final DateTime? expiresAt;
}

Future<void> applyRestriction(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final repository = ref.read(adminRepositoryProvider);
  final actor = AdminActor.of(ref);
  final decision = await showDialog<_RestrictionDecision>(
    context: context,
    builder: (_) => const _RestrictionDialog(),
  );
  if (decision == null || !context.mounted) return;
  if (decision.features.isEmpty) {
    context.showSnack(
      Tr.of(
        context,
        ar: 'اختر ميزة واحدة على الأقل.',
        en: 'Pick at least one feature.',
      ),
      isError: true,
    );
    return;
  }
  AdminUserDetail? detail;
  try {
    detail = await repository.loadUser(target.uid);
  } on Object {
    detail = null;
  }
  if (!context.mounted) return;
  final previous = detail?.status ?? const AccountStatusRecord();
  final permanentText = decision.permanent
      ? Tr.of(context, ar: 'دائم', en: 'permanent')
      : Tr.of(
          context,
          ar: 'حتى ${adminDate(decision.expiresAt)}',
          en: 'until ${adminDate(decision.expiresAt)}',
        );
  final body = Tr.of(
    context,
    ar: 'تم تقييد بعض ميزات حسابك في Wings.\n\nالسبب: ${decision.reason}\nالميزات المقيّدة: ${_featuresSummary(context, decision.features)}\nالمدة: $permanentText',
    en: 'Some features of your Wings account have been restricted.\n\nReason: ${decision.reason}\nRestricted: ${_featuresSummary(context, decision.features)}\nDuration: $permanentText',
  );
  final status = buildStatusRecord(
    state: AccountState.restricted,
    reason: decision.reason,
    actorUid: actor.uid,
    previousState: previous.effectiveState(DateTime.now()),
    restrictions: decision.features,
    restrictionsPermanent: decision.permanent,
    restrictionsExpireAt: decision.expiresAt,
    expiresAt: decision.expiresAt,
    permanent: decision.permanent,
  );
  await _report(
    context,
    repository.applyStatus(
      target: target,
      status: status,
      reason: decision.reason,
      actorUid: actor.uid,
      actorName: actor.name,
      action: AdminAction.restrict,
      notificationTitle: Tr.of(
        context,
        ar: 'تقييد ميزات في حسابك',
        en: 'Restrictions applied to your account',
      ),
      notificationBody: body,
    ),
    Tr.of(context, ar: 'تم تطبيق التقييد.', en: 'Restriction applied.'),
  );
  ref.invalidate(adminUserDetailProvider(target.uid));
}

class _RestrictionDialog extends StatefulWidget {
  const _RestrictionDialog();

  @override
  State<_RestrictionDialog> createState() => _RestrictionDialogState();
}

class _RestrictionDialogState extends State<_RestrictionDialog> {
  final TextEditingController _reason = TextEditingController();
  final Set<RestrictionFeature> _features = <RestrictionFeature>{
    RestrictionFeature.comment,
  };
  bool _permanent = false;
  int _days = 7;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = const <(RestrictionFeature, String, String)>[
      (RestrictionFeature.comment, 'التعليق', 'Commenting'),
      (RestrictionFeature.post, 'النشر', 'Posting'),
      (
        RestrictionFeature.interact,
        'التفاعل (إعجاب/عدم إعجاب)',
        'Interactions',
      ),
      (RestrictionFeature.community, 'المجتمع', 'Community'),
      (RestrictionFeature.report, 'إرسال البلاغات', 'Submitting reports'),
    ];
    return AlertDialog(
      title: Text(Tr.of(context, ar: 'تقييد ميزات', en: 'Restrict features')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final option in options)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _features.contains(option.$1),
                title: Text(Tr.isArabic(context) ? option.$2 : option.$3),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _features.add(option.$1);
                  } else {
                    _features.remove(option.$1);
                  }
                }),
              ),
            const Divider(),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _permanent,
              title: Text(
                Tr.of(context, ar: 'تقييد دائم', en: 'Permanent restriction'),
              ),
              onChanged: (value) => setState(() => _permanent = value),
            ),
            if (!_permanent)
              DropdownButtonFormField<int>(
                initialValue: _days,
                decoration: InputDecoration(
                  labelText: Tr.of(context, ar: 'المدة', en: 'Duration'),
                ),
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem<int>(
                    value: 1,
                    child: Text('24 ساعة / 1 day'),
                  ),
                  DropdownMenuItem<int>(value: 7, child: Text('7 أيام / days')),
                  DropdownMenuItem<int>(
                    value: 30,
                    child: Text('30 يومًا / days'),
                  ),
                  DropdownMenuItem<int>(
                    value: 90,
                    child: Text('90 يومًا / days'),
                  ),
                ],
                onChanged: (value) => setState(() => _days = value ?? 7),
              ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'السبب', en: 'Reason'),
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
        ),
        TextButton(
          onPressed: () {
            if (_reason.text.trim().isEmpty) {
              setState(
                () => _error = Tr.of(
                  context,
                  ar: 'السبب مطلوب',
                  en: 'Reason required',
                ),
              );
              return;
            }
            Navigator.of(context).pop(
              _RestrictionDecision(
                reason: _reason.text.trim(),
                features: Set<RestrictionFeature>.of(_features),
                permanent: _permanent,
                expiresAt: _permanent
                    ? null
                    : DateTime.now().add(Duration(days: _days)),
              ),
            );
          },
          child: Text(Tr.of(context, ar: 'تطبيق', en: 'Apply')),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- suspension

class _SuspensionDecision {
  const _SuspensionDecision({
    required this.reason,
    required this.permanent,
    required this.features,
    this.expiresAt,
  });

  final String reason;
  final bool permanent;
  final Set<RestrictionFeature> features;
  final DateTime? expiresAt;
}

Future<void> suspendUser(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final repository = ref.read(adminRepositoryProvider);
  final actor = AdminActor.of(ref);
  final decision = await showDialog<_SuspensionDecision>(
    context: context,
    builder: (_) => const _SuspensionDialog(),
  );
  if (decision == null || !context.mounted) return;
  final details = decision.features.isEmpty
      ? Tr.of(context, ar: 'إيقاف كامل للحساب', en: 'Full account access')
      : _featuresSummary(context, decision.features);
  final duration = _expirySummary(
    context,
    decision.expiresAt,
    decision.permanent,
  );
  final summary = Tr.of(
    context,
    ar: 'سيتم إيقاف حساب ${target.label}.\n\nالسبب: ${decision.reason}\nالمدة: $duration\nالميزات المتأثرة: $details',
    en: '${target.label} will be suspended.\n\nReason: ${decision.reason}\nDuration: $duration\nAffected: $details',
  );
  final confirmed = await _confirm(
    context,
    title: Tr.of(context, ar: 'تأكيد الإيقاف', en: 'Confirm suspension'),
    message: summary,
    confirmLabel: Tr.of(context, ar: 'تأكيد', en: 'Confirm'),
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  final previous = await _previousStatus(repository, target.uid);
  if (!context.mounted) return;
  final body = Tr.of(
    context,
    ar: 'تم إيقاف حسابك في Wings بواسطة مالك Wings.\n\nالسبب:\n${decision.reason}\n\nالميزات المتأثرة:\n$details\n\nالمدة:\n$duration\n\nإذا كنت تعتقد أن هذا الإجراء غير صحيح، يمكنك تقديم طلب مراجعة من داخل التطبيق.',
    en: 'Your Wings account has been suspended by the Wings Owner.\n\nReason:\n${decision.reason}\n\nAffected:\n$details\n\nDuration:\n$duration\n\nIf you believe this was a mistake, you can request a review inside the app.',
  );
  await _report(
    context,
    repository.applyStatus(
      target: target,
      status: buildStatusRecord(
        state: AccountState.suspended,
        reason: decision.reason,
        actorUid: actor.uid,
        previousState: previous.effectiveState(DateTime.now()),
        expiresAt: decision.expiresAt,
        permanent: decision.permanent,
        restrictions: decision.features,
        restrictionsPermanent: decision.permanent,
        restrictionsExpireAt: decision.expiresAt,
      ),
      reason: decision.reason,
      actorUid: actor.uid,
      actorName: actor.name,
      action: AdminAction.suspend,
      notificationTitle: Tr.of(
        context,
        ar: 'تم إيقاف حسابك في Wings',
        en: 'Your Wings account has been suspended',
      ),
      notificationBody: body,
    ),
    Tr.of(context, ar: 'تم إيقاف الحساب.', en: 'Account suspended.'),
  );
  ref.invalidate(adminUserDetailProvider(target.uid));
}

Future<AccountStatusRecord> _previousStatus(
  AdminRepository repository,
  String uid,
) async {
  try {
    final detail = await repository.loadUser(uid);
    return detail.status;
  } on Object {
    return const AccountStatusRecord();
  }
}

class _SuspensionDialog extends StatefulWidget {
  const _SuspensionDialog();

  @override
  State<_SuspensionDialog> createState() => _SuspensionDialogState();
}

class _SuspensionDialogState extends State<_SuspensionDialog> {
  final TextEditingController _reason = TextEditingController();
  final Set<RestrictionFeature> _features = <RestrictionFeature>{};
  String _duration = '24h';
  DateTime? _custom;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  DateTime? _resolveExpiry() {
    final now = DateTime.now();
    return switch (_duration) {
      '1h' => now.add(const Duration(hours: 1)),
      '24h' => now.add(const Duration(hours: 24)),
      '3d' => now.add(const Duration(days: 3)),
      '7d' => now.add(const Duration(days: 7)),
      '30d' => now.add(const Duration(days: 30)),
      'custom' => _custom,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final indefinite = _duration == 'indefinite';
    return AlertDialog(
      title: Text(Tr.of(context, ar: 'إيقاف مؤقت', en: 'Temporary suspension')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _duration,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'المدة', en: 'Duration'),
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: '1h',
                  child: Text('ساعة / 1 hour'),
                ),
                DropdownMenuItem<String>(
                  value: '24h',
                  child: Text('24 ساعة / hours'),
                ),
                DropdownMenuItem<String>(
                  value: '3d',
                  child: Text('3 أيام / days'),
                ),
                DropdownMenuItem<String>(
                  value: '7d',
                  child: Text('7 أيام / days'),
                ),
                DropdownMenuItem<String>(
                  value: '30d',
                  child: Text('30 يومًا / days'),
                ),
                DropdownMenuItem<String>(
                  value: 'custom',
                  child: Text('تاريخ مخصص / custom date'),
                ),
                DropdownMenuItem<String>(
                  value: 'indefinite',
                  child: Text('غير محدد / indefinite'),
                ),
              ],
              onChanged: (value) => setState(() => _duration = value ?? '24h'),
            ),
            if (_duration == 'custom')
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_rounded, size: 16),
                  label: Text(
                    _custom == null
                        ? Tr.of(context, ar: 'اختر التاريخ', en: 'Pick a date')
                        : adminDate(_custom),
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                      initialDate: now.add(const Duration(days: 7)),
                    );
                    if (picked == null) return;
                    setState(() {
                      _custom = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                        23,
                        59,
                      );
                    });
                  },
                ),
              ),
            const SizedBox(height: Space.sm),
            Text(
              Tr.of(
                context,
                ar: 'تقييد ميزات إضافي',
                en: 'Additional restrictions',
              ),
              style: context.text.labelSmall?.copyWith(
                color: context.palette.textMuted,
              ),
            ),
            for (final feature in RestrictionFeature.values)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _features.contains(feature),
                title: Text(restrictionLabel(context, feature)),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _features.add(feature);
                  } else {
                    _features.remove(feature);
                  }
                }),
              ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'السبب', en: 'Reason'),
                errorText: _error,
              ),
            ),
            if (indefinite)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  Tr.of(
                    context,
                    ar: 'الإيقاف غير المحدد يبقى فعّالاً حتى يرفعه المالك.',
                    en: 'An indefinite suspension stays in force until the Owner lifts it.',
                  ),
                  style: context.text.labelSmall?.copyWith(
                    color: context.palette.warning,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
        ),
        TextButton(
          onPressed: () {
            final reason = _reason.text.trim();
            if (reason.isEmpty) {
              setState(
                () => _error = Tr.of(
                  context,
                  ar: 'السبب مطلوب',
                  en: 'Reason required',
                ),
              );
              return;
            }
            Navigator.of(context).pop(
              _SuspensionDecision(
                reason: reason,
                permanent: indefinite,
                features: Set<RestrictionFeature>.of(_features),
                expiresAt: indefinite ? null : _resolveExpiry(),
              ),
            );
          },
          child: Text(Tr.of(context, ar: 'متابعة', en: 'Continue')),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- review/ban

Future<void> reviewUser(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final repository = ref.read(adminRepositoryProvider);
  final actor = AdminActor.of(ref);
  final reason = await promptAdminText(
    context,
    title: Tr.of(
      context,
      ar: 'وضع الحساب قيد المراجعة',
      en: 'Place under review',
    ),
    hint: Tr.of(context, ar: 'سبب المراجعة', en: 'Review reason'),
  );
  if (reason == null || !context.mounted) return;
  final previous = await _previousStatus(repository, target.uid);
  if (!context.mounted) return;
  await _report(
    context,
    repository.applyStatus(
      target: target,
      status: buildStatusRecord(
        state: AccountState.underReview,
        reason: reason,
        actorUid: actor.uid,
        previousState: previous.state,
        restrictions: previous.restrictions,
        restrictionsPermanent: previous.restrictionsPermanent,
        restrictionsExpireAt: previous.restrictionsExpireAt,
      ),
      reason: reason,
      actorUid: actor.uid,
      actorName: actor.name,
      action: AdminAction.review,
      notificationTitle: Tr.of(
        context,
        ar: 'حسابك قيد المراجعة',
        en: 'Your account is under review',
      ),
      notificationBody: Tr.of(
        context,
        ar: 'تم وضع حسابك في Wings قيد المراجعة الإدارية.\n\nالسبب: $reason\n\nسيتواصل معك فريق Wings بعد انتهاء المراجعة.',
        en: 'Your Wings account has been placed under administrative review.\n\nReason: $reason\n\nThe Wings team will follow up once the review is complete.',
      ),
    ),
    Tr.of(
      context,
      ar: 'تم وضع الحساب قيد المراجعة.',
      en: 'Account placed under review.',
    ),
  );
  ref.invalidate(adminUserDetailProvider(target.uid));
}

Future<void> banUser(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final repository = ref.read(adminRepositoryProvider);
  final actor = AdminActor.of(ref);
  final reason = await promptAdminText(
    context,
    title: Tr.of(context, ar: 'حظر دائم', en: 'Permanent ban'),
    hint: Tr.of(context, ar: 'سبب الحظر', en: 'Ban reason'),
    description: Tr.of(
      context,
      ar: 'الحظر الدائم لا ينتهي تلقائيًا، ويُرفع يدويًا فقط.',
      en: 'A permanent ban never expires; it is lifted manually only.',
    ),
  );
  if (reason == null || !context.mounted) return;
  final confirmed = await _confirm(
    context,
    title: Tr.of(
      context,
      ar: 'تأكيد الحظر الدائم',
      en: 'Confirm permanent ban',
    ),
    message: Tr.of(
      context,
      ar: 'سيُمنع ${target.label} من استخدام Wings حتى ترفع الحظر.\n\nالسبب: $reason',
      en: '${target.label} will be unable to use Wings until the ban is lifted.\n\nReason: $reason',
    ),
    confirmLabel: Tr.of(context, ar: 'حظر دائم', en: 'Ban permanently'),
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  final previous = await _previousStatus(repository, target.uid);
  if (!context.mounted) return;
  await _report(
    context,
    repository.applyStatus(
      target: target,
      status: buildStatusRecord(
        state: AccountState.banned,
        reason: reason,
        actorUid: actor.uid,
        previousState: previous.state,
        permanent: true,
        restrictions: RestrictionFeature.values.toSet(),
        restrictionsPermanent: true,
      ),
      reason: reason,
      actorUid: actor.uid,
      actorName: actor.name,
      action: AdminAction.ban,
      notificationTitle: Tr.of(
        context,
        ar: 'تم حظر حسابك في Wings نهائيًا',
        en: 'Your Wings account has been permanently banned',
      ),
      notificationBody: Tr.of(
        context,
        ar: 'تم حظر حسابك في Wings نهائيًا بواسطة مالك Wings.\n\nالسبب:\n$reason\n\nالحظر يمنع الوصول إلى حسابك حتى ترفعه الإدارة.\n\nإذا كنت تعتقد أن هذا الإجراء غير صحيح، يمكنك تقديم طلب مراجعة من داخل التطبيق.',
        en: 'Your Wings account has been permanently banned by the Wings Owner.\n\nReason:\n$reason\n\nThis ban blocks access to your account until it is lifted.\n\nIf you believe this was a mistake, you can request a review inside the app.',
      ),
    ),
    Tr.of(context, ar: 'تم حظر الحساب.', en: 'Account banned.'),
  );
  ref.invalidate(adminUserDetailProvider(target.uid));
}

Future<void> restoreUser(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final repository = ref.read(adminRepositoryProvider);
  final actor = AdminActor.of(ref);
  final previous = await _previousStatus(repository, target.uid);
  if (!context.mounted) return;
  final reason = await promptAdminText(
    context,
    title: Tr.of(context, ar: 'استعادة الحساب', en: 'Restore account'),
    hint: Tr.of(
      context,
      ar: 'سبب الاستعادة (اختياري)',
      en: 'Reason (optional)',
    ),
    required: false,
  );
  if (reason == null || !context.mounted) return;

  // A restore never blindly forces `active`: restrictions that are still in
  // force keep the account restricted.
  final now = DateTime.now();
  final keepRestrictions = previous.restrictionsPermanent
      ? previous.restrictions
      : (previous.restrictionsExpireAt != null &&
                previous.restrictionsExpireAt!.isAfter(now)
            ? previous.restrictions
            : const <RestrictionFeature>{});
  final next = keepRestrictions.isEmpty
      ? AccountState.active
      : AccountState.restricted;
  final confirmed = await _confirm(
    context,
    title: Tr.of(context, ar: 'تأكيد الاستعادة', en: 'Confirm restore'),
    message: Tr.of(
      context,
      ar: 'سيُرفع الحظر/الإيقاف عن ${target.label} وتعود الحالة إلى «${adminStateLabel(context, next)}».\n\nالقيود التي تبقى فعّالة: ${_featuresSummary(context, keepRestrictions)}',
      en: '${target.label} will be restored to “${adminStateLabel(context, next)}”.\n\nRestrictions still in force: ${_featuresSummary(context, keepRestrictions)}',
    ),
    confirmLabel: Tr.of(context, ar: 'استعادة', en: 'Restore'),
  );
  if (!confirmed || !context.mounted) return;
  await _report(
    context,
    repository.applyStatus(
      target: target,
      status: buildStatusRecord(
        state: next,
        reason: reason.isEmpty
            ? Tr.of(context, ar: 'استعادة إدارية', en: 'Administrative restore')
            : reason,
        actorUid: actor.uid,
        previousState: previous.state,
        restrictions: keepRestrictions,
        restrictionsPermanent:
            previous.restrictionsPermanent && keepRestrictions.isNotEmpty,
        restrictionsExpireAt: keepRestrictions.isEmpty
            ? null
            : previous.restrictionsExpireAt,
      ),
      reason: reason,
      actorUid: actor.uid,
      actorName: actor.name,
      action: AdminAction.restore,
      notificationTitle: Tr.of(
        context,
        ar: 'تمت استعادة حسابك',
        en: 'Your account has been restored',
      ),
      notificationBody: Tr.of(
        context,
        ar:
            'تمت استعادة حسابك في Wings.\n\nالحالة الحالية: ${adminStateLabel(context, next)}'
            '${keepRestrictions.isEmpty ? '' : '\nالقيود المتبقية: ${_featuresSummary(context, keepRestrictions)}'}',
        en:
            'Your Wings account has been restored.\n\nCurrent state: ${adminStateLabel(context, next)}'
            '${keepRestrictions.isEmpty ? '' : '\nRemaining restrictions: ${_featuresSummary(context, keepRestrictions)}'}',
      ),
    ),
    Tr.of(context, ar: 'تمت استعادة الحساب.', en: 'Account restored.'),
  );
  ref.invalidate(adminUserDetailProvider(target.uid));
}

// -------------------------------------------------------------------- delete

Future<void> deleteUserAccount(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final repository = ref.read(adminRepositoryProvider);
  final actor = AdminActor.of(ref);
  final reason = await promptAdminText(
    context,
    title: Tr.of(context, ar: 'حذف الحساب', en: 'Delete account'),
    hint: Tr.of(context, ar: 'سبب الحذف', en: 'Deletion reason'),
    description: Tr.of(
      context,
      ar: 'سيُحذف ملف الحساب وبياناته وتعليقاته ويُلغى حجز اسم المستخدم. لا يمكن التراجع.',
      en: 'The profile, its data and its comments are removed and the username reservation is released. This cannot be undone.',
    ),
  );
  if (reason == null || !context.mounted) return;
  final confirmed = await _confirm(
    context,
    title: Tr.of(context, ar: 'تأكيد الحذف', en: 'Confirm deletion'),
    message: Tr.of(
      context,
      ar: 'سيتم حذف حساب ${target.label} نهائيًا.\n\nالسبب: $reason',
      en: '${target.label} will be deleted permanently.\n\nReason: $reason',
    ),
    confirmLabel: Tr.of(context, ar: 'حذف نهائي', en: 'Delete permanently'),
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  String result = '';
  try {
    final blocked = await repository.deleteAccount(
      target: target,
      reason: reason,
      actorUid: actor.uid,
      actorName: actor.name,
      notificationTitle: Tr.of(
        context,
        ar: 'تم حذف حسابك في Wings',
        en: 'Your Wings account has been deleted',
      ),
      notificationBody: Tr.of(
        context,
        ar: 'تم حذف حسابك في Wings بواسطة مالك Wings.\n\nالسبب:\n$reason\n\nتاريخ الحذف: ${adminDate(DateTime.now())}',
        en: 'Your Wings account has been deleted by the Wings Owner.\n\nReason:\n$reason\n\nDeleted at: ${adminDate(DateTime.now())}',
      ),
    );
    if (!context.mounted) return;
    // Never name the internal records that were skipped: the owner only needs
    // to know that a few items are still pending.
    result = blocked.isEmpty
        ? ''
        : Tr.of(
            context,
            ar: ' (بقيت بعض العناصر المرتبطة، ويمكن إعادة المحاولة لاحقًا)',
            en: ' (some related items remain; retry later)',
          );
  } on Object catch (error) {
    if (context.mounted) {
      context.showSnack(userFacingError(context, error), isError: true);
    }
    return;
  }
  ref.invalidate(adminUserDetailProvider(target.uid));
  ref.invalidate(adminUsersProvider);
  if (context.mounted) {
    context.showSnack(
      Tr.of(context, ar: 'تم حذف الحساب$result', en: 'Account deleted$result'),
    );
  }
}

// -------------------------------------------------------------- owner message

Future<void> sendOwnerMessage(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final repository = ref.read(adminRepositoryProvider);
  final actor = AdminActor.of(ref);
  final decision = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _OwnerMessageDialog(target: target),
  );
  if (decision == null || !context.mounted) return;
  await _report(
    context,
    repository.sendOwnerMessage(
      target: target,
      title: decision.$1,
      body: decision.$2,
      actorUid: actor.uid,
      actorName: actor.name,
      actorUsername: actor.username,
      actorPhotoVersion: actor.photoVersion,
    ),
    Tr.of(context, ar: 'تم إرسال الرسالة.', en: 'Message sent.'),
  );
  ref.invalidate(adminSentMessagesProvider);
}

class _OwnerMessageDialog extends StatefulWidget {
  const _OwnerMessageDialog({required this.target});

  final AdminUserSummary target;

  @override
  State<_OwnerMessageDialog> createState() => _OwnerMessageDialogState();
}

class _OwnerMessageDialogState extends State<_OwnerMessageDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Tr.of(context, ar: 'رسالة من المالك', en: 'Owner message')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '→ ${widget.target.label}',
              style: context.text.labelLarge?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: Tr.of(
                  context,
                  ar: 'عنوان (اختياري)',
                  en: 'Title (optional)',
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _body,
              maxLines: 7,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'نص الرسالة', en: 'Message'),
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
        ),
        TextButton(
          onPressed: () {
            final body = _body.text.trim();
            if (body.isEmpty) {
              setState(
                () => _error = Tr.of(
                  context,
                  ar: 'النص مطلوب',
                  en: 'Message required',
                ),
              );
              return;
            }
            Navigator.of(context).pop((_title.text.trim(), body));
          },
          child: Text(Tr.of(context, ar: 'إرسال', en: 'Send')),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- email blocks

Future<void> blockUserEmail(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final repository = ref.read(adminRepositoryProvider);
  final actor = AdminActor.of(ref);
  final email = await promptAdminText(
    context,
    title: Tr.of(context, ar: 'حظر بريد إلكتروني', en: 'Block email'),
    hint: 'name@example.com',
    description: Tr.of(
      context,
      ar: 'يُطبَّق الحظر على البريد نفسه ولو حُذف الحساب أو غيّر اسم المستخدم. يُخزَّن البريد بصيغة موحّدة داخل مستند غير قابل للسرد.',
      en: 'The block applies to the address itself even if the account is deleted or renamed. The address is stored normalized in a document that cannot be listed.',
    ),
  );
  if (email == null || !context.mounted) return;
  if (!email.contains('@')) {
    context.showSnack(
      Tr.of(context, ar: 'بريد غير صالح.', en: 'Invalid email.'),
      isError: true,
    );
    return;
  }
  await _report(
    context,
    repository.blockEmail(
      email: email,
      reason: 'owner-console',
      actorUid: actor.uid,
      actorName: actor.name,
    ),
    Tr.of(context, ar: 'تم حظر البريد.', en: 'Email blocked.'),
  );
  ref.invalidate(blockedEmailsProvider);
}

Future<void> blockUserUsername(
  BuildContext context,
  WidgetRef ref,
  AdminUserSummary target,
) async {
  final repository = ref.read(adminRepositoryProvider);
  final actor = AdminActor.of(ref);
  final username = await promptAdminText(
    context,
    title: Tr.of(context, ar: 'حظر اسم مستخدم', en: 'Block username'),
    hint: target.username,
    initialValue: target.username,
    description: Tr.of(
      context,
      ar: 'لن يستطيع أي حساب حجز هذا الاسم، حتى بعد حذف الحساب الذي يملكه.',
      en: 'The handle can no longer be reserved by any account, even after its current owner is deleted.',
    ),
  );
  if (username == null || !context.mounted) return;
  await _report(
    context,
    repository.blockUsername(
      username: username,
      reason: 'owner-console',
      actorUid: actor.uid,
      actorName: actor.name,
    ),
    Tr.of(context, ar: 'تم حظر الاسم.', en: 'Username blocked.'),
  );
  ref.invalidate(blockedUsernamesProvider);
}
