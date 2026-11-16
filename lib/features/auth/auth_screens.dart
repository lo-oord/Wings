import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/app_failure.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            children: <Widget>[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: WingsIconButton(
                  icon: Icons.close_rounded,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.lg),
                child: Image.asset(
                  'assets/branding/wings_icon.png',
                  width: 88,
                  height: 88,
                ),
              ),
              const SizedBox(height: Space.lg),
              Text(
                l10n.authWelcomeTitle,
                textAlign: TextAlign.center,
                style: context.text.headlineMedium,
              ),
              const SizedBox(height: Space.sm),
              Text(
                l10n.authWelcomeBody,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              const Spacer(),
              WingsButton(
                label: l10n.authLogin,
                expand: true,
                onPressed: () => context.push(RoutePaths.login),
              ),
              const SizedBox(height: Space.sm),
              WingsButton(
                label: l10n.authRegister,
                variant: WingsButtonVariant.outline,
                expand: true,
                onPressed: () => context.push(RoutePaths.register),
              ),
              const SizedBox(height: Space.sm),
              TextButton(
                onPressed: () => context.go(RoutePaths.latest),
                child: Text(l10n.authContinueGuest),
              ),
              const SizedBox(height: Space.sm),
              Text(
                l10n.authDemoNotice,
                textAlign: TextAlign.center,
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .signIn(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      context.go(RoutePaths.profile);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is AppFailure
            ? error.message(l10n)
            : l10n.stateErrorGeneric;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: WingsAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(Space.xl),
        children: <Widget>[
          Text(l10n.authLogin, style: context.text.headlineSmall),
          const SizedBox(height: Space.xs),
          Text(
            l10n.authUnavailableBody,
            style: context.text.bodySmall?.copyWith(
              color: context.palette.textMuted,
            ),
          ),
          const SizedBox(height: Space.xl),
          Form(
            key: _formKey,
            child: Column(
              children: <Widget>[
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.authEmail),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (!text.contains('@') || !text.contains('.')) {
                      return l10n.authValidationEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: Space.md),
                _PasswordField(
                  controller: _password,
                  label: l10n.authPassword,
                  validator: (value) {
                    if ((value ?? '').length < 8) {
                      return l10n.authValidationPassword;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: Space.md),
            Text(
              _error!,
              style: context.text.bodySmall?.copyWith(
                color: context.palette.danger,
              ),
            ),
          ],
          const SizedBox(height: Space.lg),
          WingsButton(
            label: l10n.authLogin,
            expand: true,
            loading: _loading,
            onPressed: _loading ? null : _submit,
          ),
          Row(
            children: <Widget>[
              TextButton(
                onPressed: () => context.push(RoutePaths.forgot),
                child: Text(l10n.authForgot),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.pushReplacement(RoutePaths.register),
                child: Text(l10n.authRegister),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _acceptedTerms = false;
  bool _termsError = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final valid = _formKey.currentState?.validate() ?? false;
    setState(() => _termsError = !_acceptedTerms);
    if (!valid || !_acceptedTerms) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authProvider.notifier)
          .register(
            displayName: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
          );
      if (!mounted) return;
      context.go(RoutePaths.verify);
    } on Object {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showSnack(l10n.stateErrorGeneric, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: WingsAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(Space.xl),
        children: <Widget>[
          Text(l10n.authRegister, style: context.text.headlineSmall),
          const SizedBox(height: Space.xs),
          Text(
            l10n.authUnavailableBody,
            style: context.text.bodySmall?.copyWith(
              color: context.palette.textMuted,
            ),
          ),
          const SizedBox(height: Space.xl),
          Form(
            key: _formKey,
            child: Column(
              children: <Widget>[
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.authName),
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? l10n.authValidationName
                      : null,
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.authEmail),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (!text.contains('@') || !text.contains('.')) {
                      return l10n.authValidationEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: Space.md),
                _PasswordField(
                  controller: _password,
                  label: l10n.authPassword,
                  validator: (value) => (value ?? '').length < 8
                      ? l10n.authValidationPassword
                      : null,
                ),
                const SizedBox(height: Space.md),
                _PasswordField(
                  controller: _confirm,
                  label: l10n.authConfirmPassword,
                  validator: (value) => value != _password.text
                      ? l10n.authValidationConfirm
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          InkWell(
            onTap: () => setState(() {
              _acceptedTerms = !_acceptedTerms;
              _termsError = false;
            }),
            child: Row(
              children: <Widget>[
                Checkbox(
                  value: _acceptedTerms,
                  onChanged: (value) => setState(() {
                    _acceptedTerms = value ?? false;
                    _termsError = false;
                  }),
                ),
                Expanded(
                  child: Text(
                    l10n.authAcceptTerms,
                    style: context.text.bodySmall?.copyWith(
                      color: _termsError ? context.palette.danger : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          WingsButton(
            label: l10n.authRegister,
            expand: true,
            loading: _loading,
            onPressed: _loading ? null : _submit,
          ),
          const SizedBox(height: Space.md),
          Center(
            child: TextButton(
              onPressed: () => context.pushReplacement(RoutePaths.login),
              child: Text(l10n.authHaveAccount),
            ),
          ),
        ],
      ),
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final TextEditingController _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!_email.text.contains('@')) {
      context.showSnack(l10n.authValidationEmail, isError: true);
      return;
    }
    setState(() => _loading = true);
    await ref
        .read(authRepositoryProvider)
        .sendPasswordReset(_email.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    context.showSnack(l10n.authResetSent);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: WingsAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(Space.xl),
        children: <Widget>[
          Text(l10n.authForgot, style: context.text.headlineSmall),
          const SizedBox(height: Space.xl),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: l10n.authEmail),
          ),
          const SizedBox(height: Space.lg),
          WingsButton(
            label: l10n.authSendReset,
            expand: true,
            loading: _loading,
            onPressed: _loading ? null : _submit,
          ),
          Center(
            child: TextButton(
              onPressed: () => context.pushReplacement(RoutePaths.login),
              child: Text(l10n.authBackToLogin),
            ),
          ),
        ],
      ),
    );
  }
}

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Scaffold(
      appBar: WingsAppBar(showBack: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surfaceAlt,
                  border: Border.all(color: palette.border),
                ),
                child: Icon(
                  Icons.mark_email_read_outlined,
                  color: palette.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: Space.lg),
              Text(l10n.authVerifyTitle, style: context.text.titleLarge),
              const SizedBox(height: Space.sm),
              Text(
                l10n.authVerifyBody,
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: Space.xl),
              WingsButton(
                label: l10n.authContinueGuest,
                expand: true,
                onPressed: () => context.go(RoutePaths.profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscured,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
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
    );
  }
}
