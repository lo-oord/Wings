import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../data/models/account_status.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';

/// Text used for a date + time in the administrative surfaces.
String adminMoment(DateTime? value) {
  if (value == null) return '—';
  final day = formatDate(value);
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day · $hour:$minute';
}

/// Builds the actor of an administrative action from the live session.
AdminActor? adminActorOf(WidgetRef ref) {
  final user = ref.read(authProvider);
  if (user == null) return null;
  final profile = ref.read(profileProvider);
  return AdminActor(
    uid: user.id,
    name: (profile?.displayName.isNotEmpty ?? false)
        ? profile!.displayName
        : (user.displayName.isNotEmpty ? user.displayName : 'Wings Owner'),
    username: profile?.username ?? '',
    role: ref.read(staffRoleProvider).value ?? StaffRole.owner,
  );
}

/// Refuses the screen to anybody who is not the verified Owner.
///
/// This is a convenience for the interface only: every write is independently
/// refused by Firestore rules, so bypassing the widget unlocks nothing.
class OwnerGate extends ConsumerWidget {
  const OwnerGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(staffRoleProvider);
    return role.when(
      loading: () => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: Space.md),
              Text(
                Tr.of(
                  context,
                  ar: 'جارٍ التحقق من صلاحيات المالك…',
                  en: 'Verifying owner privileges…',
                ),
                style: context.text.bodySmall?.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
      error: (_, _) => const _OwnerRequired(),
      data: (value) =>
          value == StaffRole.owner ? child : const _OwnerRequired(),
    );
  }
}

class _OwnerRequired extends StatelessWidget {
  const _OwnerRequired();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.shield_outlined, size: 44, color: palette.danger),
              const SizedBox(height: Space.md),
              Text(
                Tr.of(
                  context,
                  ar: 'هذه الأدوات مخصصة لمالك Wings.',
                  en: 'Developer Tools is restricted to the Wings owner.',
                ),
                textAlign: TextAlign.center,
                style: context.text.titleSmall,
              ),
              const SizedBox(height: Space.sm),
              Text(
                Tr.of(
                  context,
                  ar: 'تم رفض الوصول وتسجيله. عُد إلى الإعدادات.',
                  en: 'Access was declined and returned to a safe screen.',
                ),
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: Space.lg),
              WingsButton(
                label: Tr.of(
                  context,
                  ar: 'العودة إلى الإعدادات',
                  en: 'Back to settings',
                ),
                icon: Icons.settings_rounded,
                onPressed: () => context.go(RoutePaths.settings),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Bordered surface shared by the administrative cards.
class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.md),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: content,
      ),
    );
  }
}

/// One dashboard number.
class AdminStatCard extends StatelessWidget {
  const AdminStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
    this.caption,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color? tone;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = tone ?? palette.primary;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            formatCount(value),
            style: context.text.headlineSmall?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}

/// Coloured pill describing an account state.
class AccountStateChip extends StatelessWidget {
  const AccountStateChip({super.key, required this.state, this.compact = false});

  final AccountState state;
  final bool compact;

  Color _tone(BuildContext context) {
    final palette = context.palette;
    return switch (state) {
      AccountState.active => palette.success,
      AccountState.warned => palette.warning,
      AccountState.restricted => palette.warning,
      AccountState.suspended => palette.danger,
      AccountState.banned => palette.danger,
      AccountState.underReview => BrandColors.developerBlue,
      AccountState.deleted => palette.textMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tone = _tone(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Space.sm : Space.md,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Text(
        Tr.isArabic(context) ? state.arabic : state.english,
        style: context.text.labelSmall?.copyWith(
          color: tone,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 10 : null,
        ),
      ),
    );
  }
}

/// Section title inside the developer screens.
class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, Space.sm),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: context.text.labelMedium?.copyWith(
              color: context.palette.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A single row of an administrative list.
class AdminRow extends StatelessWidget {
  const AdminRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      dense: true,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.md),
      leading:
          leading ??
          (icon == null
              ? null
              : Icon(
                  icon,
                  size: 19,
                  color: danger ? palette.danger : palette.textSecondary,
                )),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodyMedium?.copyWith(
          color: danger ? palette.danger : palette.textPrimary,
          fontSize: 13.5,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
      trailing: trailing,
    );
  }
}

/// Result of the shared action composer.
class AdminActionDraft {
  const AdminActionDraft({
    required this.reason,
    this.expiresAt,
    this.restrictions = AccountRestrictions.none,
  });

  final String reason;
  final DateTime? expiresAt;
  final AccountRestrictions restrictions;
}

/// Reason (+ optional duration and restrictions) dialog used by every punitive
/// action. Returns `null` when the owner cancels.
Future<AdminActionDraft?> showAdminActionDialog(
  BuildContext context, {
  required String title,
  String description = '',
  String reasonLabel = 'السبب',
  bool allowDuration = false,
  bool allowRestrictions = false,
  AccountRestrictions initialRestrictions = AccountRestrictions.none,
}) {
  return showDialog<AdminActionDraft>(
    context: context,
    builder: (dialogContext) => _AdminActionDialog(
      title: title,
      description: description,
      reasonLabel: reasonLabel,
      allowDuration: allowDuration,
      allowRestrictions: allowRestrictions,
      initialRestrictions: initialRestrictions,
    ),
  );
}

class _AdminActionDialog extends StatefulWidget {
  const _AdminActionDialog({
    required this.title,
    required this.description,
    required this.reasonLabel,
    required this.allowDuration,
    required this.allowRestrictions,
    required this.initialRestrictions,
  });

  final String title;
  final String description;
  final String reasonLabel;
  final bool allowDuration;
  final bool allowRestrictions;
  final AccountRestrictions initialRestrictions;

  @override
  State<_AdminActionDialog> createState() => _AdminActionDialogState();
}

class _AdminActionDialogState extends State<_AdminActionDialog> {
  static const Map<String, Duration?> _durations = <String, Duration?>{
    'دائم': null,
    'ساعة': Duration(hours: 1),
    '24 ساعة': Duration(hours: 24),
    '3 أيام': Duration(days: 3),
    '7 أيام': Duration(days: 7),
    '30 يومًا': Duration(days: 30),
  };

  final TextEditingController _reason = TextEditingController();
  String _durationKey = '7 أيام';
  late AccountRestrictions _restrictions = widget.initialRestrictions;
  bool _error = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = true);
      return;
    }
    final period = _durations[_durationKey];
    Navigator.of(context).pop(
      AdminActionDraft(
        reason: reason,
        expiresAt: period == null ? null : DateTime.now().add(period),
        restrictions: _restrictions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.description.isNotEmpty) ...<Widget>[
              Text(
                widget.description,
                style: context.text.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: Space.md),
            ],
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: widget.reasonLabel,
                errorText: _error ? 'السبب مطلوب' : null,
                border: const OutlineInputBorder(),
                counterStyle: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ),
            if (widget.allowDuration) ...<Widget>[
              const SizedBox(height: Space.sm),
              Text(
                'المدة',
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: <Widget>[
                  for (final key in _durations.keys)
                    WingsFilterChip(
                      label: key,
                      selected: _durationKey == key,
                      onTap: () => setState(() => _durationKey = key),
                    ),
                ],
              ),
            ],
            if (widget.allowRestrictions) ...<Widget>[
              const SizedBox(height: Space.md),
              Text(
                'تقييد الميزات',
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: <Widget>[
                  for (final entry in _restrictionLabels.entries)
                    WingsFilterChip(
                      label: entry.value,
                      selected: _restrictions.isOn(entry.key),
                      onTap: () => setState(() {
                        _restrictions = _restrictions.withValue(
                          entry.key,
                          !_restrictions.isOn(entry.key),
                        );
                      }),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('تأكيد')),
      ],
    );
  }
}

/// Arabic labels of the restriction keys, shared by the composer and the lists.
const Map<String, String> _restrictionLabels = <String, String>{
  AccountRestrictions.commentKey: 'التعليق',
  AccountRestrictions.postKey: 'النشر',
  AccountRestrictions.interactKey: 'التفاعل',
  AccountRestrictions.communityKey: 'المجتمع',
  AccountRestrictions.reportKey: 'البلاغات',
};

String restrictionLabel(String key) => _restrictionLabels[key] ?? key;
