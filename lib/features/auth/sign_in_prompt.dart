import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';

/// The floating gate shown when a guest taps something that needs an account.
///
/// It names the blocked action, then offers the two real exits — sign in or
/// create an account — and leaves the reader on the screen they came from.
Future<void> showSignInPrompt(
  BuildContext context, {
  required String message,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (sheetContext) => _SignInSheet(message: message),
  );
  if (!context.mounted) return;
  if (choice == 'login') context.push(RoutePaths.login);
  if (choice == 'register') context.push(RoutePaths.register);
}

class _SignInSheet extends StatelessWidget {
  const _SignInSheet({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.borderStrong,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ),
            ),
            const SizedBox(height: Space.xl),
            Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: palette.brandGradient,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: palette.onPrimary,
                  size: 27,
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              Tr.of(context, ar: 'سجّل الدخول أولًا', en: 'Sign in first'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: palette.textSecondary,
                height: 1.55,
              ),
            ),
            const SizedBox(height: Space.xl),
            WingsButton(
              label: Tr.of(context, ar: 'تسجيل الدخول', en: 'Sign in'),
              icon: Icons.login_rounded,
              expand: true,
              onPressed: () => Navigator.of(context).pop('login'),
            ),
            const SizedBox(height: Space.sm),
            WingsButton(
              label: Tr.of(
                context,
                ar: 'إنشاء حساب جديد',
                en: 'Create an account',
              ),
              icon: Icons.person_add_alt_1_rounded,
              variant: WingsButtonVariant.outline,
              expand: true,
              onPressed: () => Navigator.of(context).pop('register'),
            ),
            const SizedBox(height: Space.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(Tr.of(context, ar: 'لاحقًا', en: 'Later')),
            ),
          ],
        ),
      ),
    );
  }
}
