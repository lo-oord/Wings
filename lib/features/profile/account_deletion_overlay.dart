import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';

/// Runs [delete] behind a blocking window.
///
/// The window explains that the account is being removed, then switches to the
/// green check and «تم الحذف», and only afterwards dissolves. The router has
/// already redirected to the sign-in screen when the account disappeared, so
/// the fade reveals that screen instead of snapping into it. Returns the error
/// when the deletion failed, or null on success.
Future<Object?> showAccountDeletionOverlay(
  BuildContext context,
  Future<void> Function() delete,
) {
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return showGeneralDialog<Object?>(
    context: context,
    barrierDismissible: false,
    barrierLabel: Tr.of(context, ar: 'حذف الحساب', en: 'Delete account'),
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: reduceMotion ? Duration.zero : Motion.normal,
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        _AccountDeletionDialog(delete: delete, reduceMotion: reduceMotion),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.enter,
        reverseCurve: Motion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

enum _DeletionPhase { deleting, deleted, failed }

class _AccountDeletionDialog extends StatefulWidget {
  const _AccountDeletionDialog({
    required this.delete,
    required this.reduceMotion,
  });

  final Future<void> Function() delete;
  final bool reduceMotion;

  @override
  State<_AccountDeletionDialog> createState() => _AccountDeletionDialogState();
}

class _AccountDeletionDialogState extends State<_AccountDeletionDialog> {
  _DeletionPhase _phase = _DeletionPhase.deleting;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await widget.delete();
      if (!mounted) return;
      setState(() => _phase = _DeletionPhase.deleted);
      // Long enough to read the confirmation, short enough to feel instant.
      await Future<void>.delayed(
        widget.reduceMotion
            ? const Duration(milliseconds: 600)
            : const Duration(milliseconds: 1600),
      );
      await _exit();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _phase = _DeletionPhase.failed);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      await _exit(error);
    }
  }

  /// Fades and shrinks the window before popping it, so the screen underneath
  /// is revealed softly.
  Future<void> _exit([Object? result]) async {
    if (!mounted) return;
    setState(() => _leaving = true);
    await Future<void>.delayed(
      widget.reduceMotion ? Duration.zero : Motion.normal,
    );
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = switch (_phase) {
      _DeletionPhase.deleting => Tr.of(
        context,
        ar: 'جارٍ حذف الحساب…',
        en: 'Deleting your account…',
      ),
      _DeletionPhase.deleted => Tr.of(context, ar: 'تم الحذف', en: 'Deleted'),
      _DeletionPhase.failed => Tr.of(
        context,
        ar: 'تعذر الحذف',
        en: 'Deletion failed',
      ),
    };
    final body = switch (_phase) {
      _DeletionPhase.deleting => Tr.of(
        context,
        ar: 'نزيل ملفك وتعليقاتك ومكتبتك نهائيًا. لا تغلق التطبيق.',
        en: 'Removing your profile, comments and library for good. Do not close the app.',
      ),
      _DeletionPhase.deleted => Tr.of(
        context,
        ar: 'تم حذف حسابك نهائيًا. إلى اللقاء 👋',
        en: 'Your account has been removed. See you soon 👋',
      ),
      _DeletionPhase.failed => Tr.of(
        context,
        ar: 'لم يُحذف الحساب. حاول مرة أخرى.',
        en: 'The account was not deleted. Please try again.',
      ),
    };

    return PopScope(
      canPop: false,
      child: Center(
        child: AnimatedOpacity(
          opacity: _leaving ? 0 : 1,
          duration: widget.reduceMotion ? Duration.zero : Motion.normal,
          curve: Motion.exit,
          child: AnimatedScale(
            scale: _leaving ? 0.96 : 1,
            duration: widget.reduceMotion ? Duration.zero : Motion.normal,
            curve: Motion.exit,
            child: Container(
              width: 304,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.xxl,
                vertical: Space.xxl,
              ),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: Radii.dialog,
                border: Border.all(color: palette.border),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 32,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 68,
                    height: 68,
                    child: AnimatedSwitcher(
                      duration: widget.reduceMotion
                          ? Duration.zero
                          : Motion.slow,
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      child: switch (_phase) {
                        _DeletionPhase.deleting => const _Spinner(),
                        _DeletionPhase.deleted => _ResultMark(
                          icon: Icons.check_rounded,
                          color: palette.success,
                        ),
                        _DeletionPhase.failed => _ResultMark(
                          icon: Icons.priority_high_rounded,
                          color: palette.danger,
                        ),
                      },
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  AnimatedSwitcher(
                    duration: widget.reduceMotion
                        ? Duration.zero
                        : Motion.normal,
                    child: Text(
                      title,
                      key: ValueKey<String>('title-${_phase.name}'),
                      textAlign: TextAlign.center,
                      style: context.text.titleSmall?.copyWith(
                        color: _phase == _DeletionPhase.failed
                            ? palette.danger
                            : palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  AnimatedSwitcher(
                    duration: widget.reduceMotion
                        ? Duration.zero
                        : Motion.normal,
                    child: Text(
                      body,
                      key: ValueKey<String>('body-${_phase.name}'),
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall?.copyWith(
                        color: palette.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey<String>('spinner'),
      child: SizedBox(
        width: 46,
        height: 46,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: context.palette.primary,
        ),
      ),
    );
  }
}

/// The finished state: a filled circle with the mark popping in.
class _ResultMark extends StatelessWidget {
  const _ResultMark({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('mark-${icon.codePoint}'),
      tween: Tween<double>(begin: 0.6, end: 1),
      duration: Motion.slow,
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0, 1), child: child),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, size: 36, color: Colors.white),
      ),
    );
  }
}
