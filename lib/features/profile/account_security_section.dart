import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/auth/auth_error_text.dart';

/// «حالة المصادقة والأمان» on the profile screen.
///
/// It answers one question at a glance — how does this account sign in? — and
/// offers the one action that is still possible: email accounts can add Google,
/// Google-only accounts can add an email with a password. Every path shows its
/// own progress, verification wait and error copy.
class AccountSecuritySection extends ConsumerWidget {
  const AccountSecuritySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    if (user == null) return const SizedBox.shrink();
    final palette = context.palette;
    final email = user.email;
    final both = user.hasPassword && user.hasGoogle;

    return WingsSettingsGroup(
      title: Tr.of(context, ar: 'المصادقة والأمان', en: 'Sign-in & security'),
      children: <Widget>[
        WingsSettingsTile(
          icon: Icons.shield_outlined,
          title: Tr.of(context, ar: 'حالة المصادقة', en: 'Sign-in status'),
          subtitle: user.hasGoogle && user.hasPassword
              ? Tr.of(
                  context,
                  ar: 'متصل بجوجل والبريد الإلكتروني${email.isEmpty ? '' : ' · $email'}',
                  en: 'Google and email${email.isEmpty ? '' : ' · $email'}',
                )
              : user.hasGoogle
              ? Tr.of(
                  context,
                  ar: 'متصل بجوجل${email.isEmpty ? '' : ' · $email'}',
                  en: 'Google${email.isEmpty ? '' : ' · $email'}',
                )
              : Tr.of(
                  context,
                  ar: 'متصل بالبريد الإلكتروني${email.isEmpty ? '' : ' · $email'}',
                  en: 'Email${email.isEmpty ? '' : ' · $email'}',
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _MethodDot(
                active: user.hasPassword,
                icon: Icons.alternate_email_rounded,
                tooltip: Tr.of(context, ar: 'البريد', en: 'Email'),
              ),
              const SizedBox(width: 6),
              _MethodDot(
                active: user.hasGoogle,
                icon: Icons.g_mobiledata_rounded,
                tooltip: Tr.of(context, ar: 'جوجل', en: 'Google'),
              ),
            ],
          ),
        ),
        if (user.hasPassword && !user.emailVerified)
          WingsSettingsTile(
            icon: Icons.mark_email_unread_outlined,
            title: Tr.of(
              context,
              ar: 'البريد غير مؤكد',
              en: 'Email not verified',
            ),
            subtitle: Tr.of(
              context,
              ar: 'أكّد بريدك لإكمال حسابك',
              en: 'Confirm your address to finish the account',
            ),
            showChevron: true,
            onTap: () => context.push(RoutePaths.verify),
          ),
        if (!user.hasGoogle)
          WingsSettingsTile(
            icon: Icons.g_mobiledata_rounded,
            title: Tr.of(
              context,
              ar: 'ربط حساب Google',
              en: 'Link a Google account',
            ),
            subtitle: Tr.of(
              context,
              ar: 'ادخل بجوجل بجانب البريد وكلمة المرور',
              en: 'Sign in with Google as well as email',
            ),
            showChevron: true,
            onTap: () => _linkGoogle(context, ref),
          ),
        if (!user.hasPassword)
          WingsSettingsTile(
            icon: Icons.password_rounded,
            title: Tr.of(
              context,
              ar: 'إضافة بريد وكلمة مرور',
              en: 'Add an email and password',
            ),
            subtitle: Tr.of(
              context,
              ar: 'اربط بريدًا آخر غير مسجل، بعد تأكيده',
              en: 'Link another unregistered email after verifying it',
            ),
            showChevron: true,
            onTap: () => _linkEmail(context, ref),
          ),
        if (both || user.hasGoogle || user.hasPassword)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: palette.textMuted,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    Tr.of(
                      context,
                      ar: 'يمكن استخدام كل طريقة من الطرق المرتبطة لتسجيل الدخول إلى نفس الحساب.',
                      en: 'Every linked method signs in to this same account.',
                    ),
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _linkGoogle(BuildContext context, WidgetRef ref) async {
    final confirmed = await WingsDialog.confirm(
      context,
      title: Tr.of(context, ar: 'ربط حساب Google', en: 'Link Google'),
      message: Tr.of(
        context,
        ar: 'اختر حساب Google الذي تريد ربطه. إذا كان مرتبطًا بحساب Wings آخر فسيُرفض الربط، حتى لا يصل حسابان إلى نفس البريد.',
        en: 'Pick the Google account to link. A Google account that already belongs to another Wings account is refused, so one email never reaches two profiles.',
      ),
      confirmLabel: Tr.of(context, ar: 'متابعة', en: 'Continue'),
    );
    if (!confirmed || !context.mounted) return;
    await _run(
      context,
      message: Tr.of(
        context,
        ar: 'جارٍ ربط حساب Google…',
        en: 'Linking your Google account…',
      ),
      action: () => ref.read(authProvider.notifier).linkGoogleAccount(),
      success: Tr.of(
        context,
        ar: 'تم ربط حساب Google بحسابك.',
        en: 'Google is now linked to your account.',
      ),
    );
  }

  Future<void> _linkEmail(BuildContext context, WidgetRef ref) async {
    final form = await WingsPopup.show<_EmailLinkForm>(
      context: context,
      heightFactor: 0.8,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: const SingleChildScrollView(child: _EmailLinkSheet()),
      ),
    );
    if (form == null || !context.mounted) return;

    Object? error;
    var immediate = false;
    await _run(
      context,
      message: Tr.of(
        context,
        ar: 'جارٍ إرسال رابط التأكيد…',
        en: 'Sending the verification link…',
      ),
      action: () async {
        immediate = await ref
            .read(authProvider.notifier)
            .requestEmailLink(email: form.email, password: form.password);
      },
      onError: (value) => error = value,
      closeAsSoonAsItEnds: true,
    );
    if (!context.mounted) return;
    if (error != null) {
      context.showSnack(authErrorText(context, error!), isError: true);
      return;
    }
    if (immediate) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'تمت إضافة البريد وكلمة المرور إلى حسابك.',
          en: 'The email and password were added to your account.',
        ),
      );
      return;
    }
    await _awaitVerification(context, ref, form.email);
  }

  /// Waits for the verification link, then links the password provider.
  Future<void> _awaitVerification(
    BuildContext context,
    WidgetRef ref,
    String email,
  ) async {
    final linked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmailVerificationDialog(email: email),
    );
    if (!context.mounted || linked != true) return;
    context.showSnack(
      Tr.of(
        context,
        ar: 'تم تأكيد البريد وإضافة كلمة المرور. أصبح بإمكانك الدخول به.',
        en: 'The email is verified and the password is set. You can sign in with it now.',
      ),
    );
  }

  /// Runs [action] behind a modal progress card and reports the outcome.
  Future<void> _run(
    BuildContext context, {
    required String message,
    required Future<void> Function() action,
    String? success,
    void Function(Object error)? onError,
    bool closeAsSoonAsItEnds = false,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _ProgressDialog(message: message),
    );
    Object? failure;
    try {
      await action();
    } on Object catch (error) {
      failure = error;
    }
    // Captured before the await, so a screen that moved on cannot leave the
    // modal card behind.
    if (navigator.canPop()) navigator.pop();
    if (!context.mounted) return;
    if (failure != null) {
      if (onError != null) {
        onError(failure);
      } else {
        context.showSnack(authErrorText(context, failure), isError: true);
      }
      return;
    }
    if (!closeAsSoonAsItEnds && success != null) {
      context.showSnack(success);
    }
  }
}

class _MethodDot extends StatelessWidget {
  const _MethodDot({
    required this.active,
    required this.icon,
    required this.tooltip,
  });

  final bool active;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: Motion.normal,
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? palette.primary.withValues(alpha: 0.15)
              : palette.surfaceAlt,
          border: Border.all(color: active ? palette.primary : palette.border),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active ? palette.primary : palette.textMuted,
        ),
      ),
    );
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopScope(
      canPop: false,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: Space.xxl),
          padding: const EdgeInsets.all(Space.xl),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: Radii.dialog,
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: palette.primary,
                ),
              ),
              const SizedBox(width: Space.md),
              Flexible(
                child: Text(
                  message,
                  style: context.text.bodySmall?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmailLinkForm {
  const _EmailLinkForm({required this.email, required this.password});

  final String email;
  final String password;
}

/// Email + password for a Google-only account.
class _EmailLinkSheet extends StatefulWidget {
  const _EmailLinkSheet();

  @override
  State<_EmailLinkSheet> createState() => _EmailLinkSheetState();
}

class _EmailLinkSheetState extends State<_EmailLinkSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscured = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(
      context,
    ).pop(_EmailLinkForm(email: _email.text.trim(), password: _password.text));
  }

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
        child: Form(
          key: _formKey,
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
              const SizedBox(height: Space.lg),
              Text(
                Tr.of(
                  context,
                  ar: 'إضافة بريد وكلمة مرور',
                  en: 'Add an email and password',
                ),
                style: context.text.titleSmall,
              ),
              const SizedBox(height: Space.xs),
              Text(
                Tr.of(
                  context,
                  ar: 'استخدم بريدًا غير مسجل في Wings. سنرسل رابط تأكيد، ولا تُضاف كلمة المرور إلا بعد فتحه.',
                  en: 'Use an email that is not registered in Wings. We send a verification link and only add the password after it is opened.',
                ),
                style: context.text.bodySmall?.copyWith(
                  color: palette.textSecondary,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: Tr.of(
                    context,
                    ar: 'البريد الإلكتروني',
                    en: 'Email',
                  ),
                  prefixIcon: const Icon(
                    Icons.alternate_email_rounded,
                    size: 18,
                  ),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (!text.contains('@') || !text.contains('.')) {
                    return Tr.of(
                      context,
                      ar: 'أدخل بريدًا إلكترونيًا صالحًا.',
                      en: 'Enter a valid email address.',
                    );
                  }
                  return null;
                },
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _password,
                obscureText: _obscured,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: Tr.of(
                    context,
                    ar: 'كلمة المرور الجديدة',
                    en: 'New password',
                  ),
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ),
                validator: (value) => (value ?? '').length < 8
                    ? Tr.of(
                        context,
                        ar: 'استخدم 8 أحرف على الأقل.',
                        en: 'Use at least 8 characters.',
                      )
                    : null,
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _confirm,
                obscureText: _obscured,
                decoration: InputDecoration(
                  labelText: Tr.of(
                    context,
                    ar: 'تأكيد كلمة المرور',
                    en: 'Confirm password',
                  ),
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                ),
                validator: (value) => value != _password.text
                    ? Tr.of(
                        context,
                        ar: 'كلمتا المرور غير متطابقتين.',
                        en: 'The passwords do not match.',
                      )
                    : null,
              ),
              const SizedBox(height: Space.lg),
              WingsButton(
                label: Tr.of(
                  context,
                  ar: 'إرسال رابط التأكيد',
                  en: 'Send verification link',
                ),
                expand: true,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Waits for the Firebase email link, then finishes the link.
class _EmailVerificationDialog extends ConsumerStatefulWidget {
  const _EmailVerificationDialog({required this.email});

  final String email;

  @override
  ConsumerState<_EmailVerificationDialog> createState() =>
      _EmailVerificationDialogState();
}

class _EmailVerificationDialogState
    extends ConsumerState<_EmailVerificationDialog> {
  Timer? _timer;
  bool _checking = false;
  bool _linked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _check(false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check(bool manual) async {
    if (_checking || _linked) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final verified = await ref
          .read(authProvider.notifier)
          .emailLinkVerified();
      if (!mounted) return;
      if (!verified) {
        if (manual) {
          setState(
            () => _error = Tr.of(
              context,
              ar: 'لم يتم تأكيد البريد بعد. افتح الرابط في رسالة البريد ثم حاول مجددًا.',
              en: 'The address is not verified yet. Open the link in the email, then try again.',
            ),
          );
        }
        return;
      }
      await ref.read(authProvider.notifier).completeEmailLink();
      if (!mounted) return;
      setState(() => _linked = true);
      _timer?.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = authErrorText(context, error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopScope(
      canPop: _linked,
      child: Dialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: Radii.dialog),
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedSwitcher(
                duration: Motion.normal,
                switchInCurve: Curves.easeOutBack,
                child: _linked
                    ? Container(
                        key: const ValueKey<String>('done'),
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.success,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      )
                    : SizedBox(
                        key: const ValueKey<String>('waiting'),
                        width: 46,
                        height: 46,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: palette.primary,
                        ),
                      ),
              ),
              const SizedBox(height: Space.lg),
              Text(
                _linked
                    ? Tr.of(
                        context,
                        ar: 'تم التأكيد والربط',
                        en: 'Verified and linked',
                      )
                    : Tr.of(
                        context,
                        ar: 'بانتظار تأكيد البريد',
                        en: 'Waiting for verification',
                      ),
                textAlign: TextAlign.center,
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                widget.email,
                textAlign: TextAlign.center,
                style: context.text.labelMedium?.copyWith(
                  color: palette.primary,
                ),
              ),
              const SizedBox(height: Space.sm),
              Text(
                Tr.of(
                  context,
                  ar: 'افتح الرابط في رسالة التأكيد. ستُضاف كلمة المرور تلقائيًا بعد التأكيد.',
                  en: 'Open the link in the verification email. The password is added automatically once it is confirmed.',
                ),
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  color: palette.textSecondary,
                  height: 1.5,
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: Space.sm),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: context.text.labelSmall?.copyWith(
                    color: palette.danger,
                  ),
                ),
              ],
              const SizedBox(height: Space.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: WingsButton(
                      label: Tr.of(context, ar: 'إلغاء', en: 'Cancel'),
                      variant: WingsButtonVariant.outline,
                      onPressed: _linked
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: WingsButton(
                      label: Tr.of(context, ar: 'تحققت', en: 'I verified'),
                      loading: _checking,
                      onPressed: _linked || _checking
                          ? null
                          : () => _check(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
