import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../data/models/account_status.dart';
import '../admin/admin_widgets.dart';

/// Shown to an account the owner suspended, banned or deleted.
///
/// The state is enforced by `firestore.rules` for every write, so this screen is
/// an explanation, not the only barrier.
class AccountStatusScreen extends ConsumerWidget {
  const AccountStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final user = ref.watch(authProvider);
    final standing = ref.watch(myStandingProvider);
    if (user == null) {
      return Scaffold(
        body: Center(
          child: WingsButton(
            label: 'العودة',
            onPressed: () => context.go(RoutePaths.latest),
          ),
        ),
      );
    }
    if (standing == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final state = standing.effectiveState;
    if (!state.blocksAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(RoutePaths.latest);
      });
    }
    final tone = state == AccountState.deleted
        ? palette.textMuted
        : palette.danger;
    final icon = switch (state) {
      AccountState.banned => Icons.gavel_rounded,
      AccountState.deleted => Icons.person_off_rounded,
      _ => Icons.pause_circle_rounded,
    };
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.xl,
            Space.huge,
            Space.xl,
            Space.xxl,
          ),
          children: <Widget>[
            Center(
              child: Container(
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: tone),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              switch (state) {
                AccountState.banned => 'حسابك محظور نهائيًا',
                AccountState.deleted => 'هذا الحساب محذوف',
                _ => 'حسابك موقوف مؤقتًا',
              },
              textAlign: TextAlign.center,
              style: context.text.headlineSmall,
            ),
            const SizedBox(height: Space.sm),
            Text(
              switch (state) {
                AccountState.banned =>
                  'منعت إدارة Wings هذا الحساب من استخدام التطبيق. '
                      'لا ينتهي الحظر تلقائيًا، ويمكن للمالك رفعه.',
                AccountState.deleted =>
                  'حُذف هذا الحساب ولم يعد قادرًا على استخدام Wings.',
                _ =>
                  'أوقفت إدارة Wings هذا الحساب مؤقتًا. سيعود تلقائيًا عند '
                      'انتهاء المدة دون أي إجراء منك.',
              },
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: Space.xl),
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        'التفاصيل',
                        style: context.text.titleSmall?.copyWith(fontSize: 13),
                      ),
                      const Spacer(),
                      AccountStateChip(state: state, compact: true),
                    ],
                  ),
                  if (standing.reason.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Space.sm),
                    Text(
                      'السبب: ${standing.reason}',
                      style: context.text.bodySmall,
                    ),
                  ],
                  if (standing.expiresAt != null) ...<Widget>[
                    const SizedBox(height: Space.xs),
                    Text(
                      'تنتهي المدة: ${adminMoment(standing.expiresAt)}',
                      style: context.text.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                  if (standing.activeRestrictions.any) ...<Widget>[
                    const SizedBox(height: Space.sm),
                    Text(
                      'الميزات المقيّدة: '
                      '${standing.activeRestrictions.enabledKeys.map(restrictionLabel).join('، ')}',
                      style: context.text.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              'إذا كنت تعتقد أن هذا الإجراء غير صحيح، تواصل مع دعم Wings. '
              'كل الإجراءات الإدارية مسجّلة ويمكن مراجعتها.',
              textAlign: TextAlign.center,
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: Space.xl),
            WingsButton(
              label: 'تسجيل الخروج',
              icon: Icons.logout_rounded,
              variant: WingsButtonVariant.outline,
              onPressed: () async {
                await ref.read(authProvider.notifier).signOut();
                if (context.mounted) context.go(RoutePaths.welcome);
              },
            ),
          ],
        ),
      ),
    );
  }
}
