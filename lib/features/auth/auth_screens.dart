import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_palette.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../data/auth/auth_error_text.dart';
import 'username_field.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';

const List<(String, String)> kCountries = <(String, String)>[
  ('SA', 'السعودية'),
  ('AE', 'الإمارات'),
  ('EG', 'مصر'),
  ('KW', 'الكويت'),
  ('QA', 'قطر'),
  ('BH', 'البحرين'),
  ('OM', 'عُمان'),
  ('JO', 'الأردن'),
  ('IQ', 'العراق'),
  ('SY', 'سوريا'),
  ('LB', 'لبنان'),
  ('PS', 'فلسطين'),
  ('YE', 'اليمن'),
  ('SD', 'السودان'),
  ('LY', 'ليبيا'),
  ('TN', 'تونس'),
  ('DZ', 'الجزائر'),
  ('MA', 'المغرب'),
  ('MR', 'موريتانيا'),
  ('SO', 'الصومال'),
  ('DJ', 'جيبوتي'),
  ('KM', 'جزر القمر'),
  ('TR', 'تركيا'),
];

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _googleLoading = false;
  bool _guestLoading = false;

  Future<void> _continueAsGuest() async {
    if (_guestLoading) return;
    setState(() => _guestLoading = true);
    await ref.read(settingsProvider.notifier).enterGuestMode();
    if (mounted) context.go(RoutePaths.latest);
  }

  Future<void> _google() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authProvider.notifier).signInWithGoogle();
      await ref.read(settingsProvider.notifier).leaveGuestMode();
      if (!mounted) return;
      context.go(RoutePaths.profile);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() => _googleLoading = false);
      if (error.kind != FailureKind.cancelled) {
        context.showSnack(authErrorText(context, error), isError: true);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _googleLoading = false);
      context.showSnack(authErrorText(context, error), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    final busy = _googleLoading || _guestLoading;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                children: <Widget>[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: WingsIconButton(
                      icon: Icons.close_rounded,
                      // Closing the sign-in gate continues as a guest: simply
                      // going home would bounce straight back to this screen.
                      onPressed: busy ? null : _continueAsGuest,
                    ),
                  ),
                  const Spacer(),
                  WingsMark(size: 116),
                  const SizedBox(height: Space.xl),
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
                      height: 1.7,
                    ),
                  ),
                  const Spacer(),
                  GoogleSignInButton(
                    loading: _googleLoading,
                    onPressed: busy ? null : _google,
                  ),
                  const SizedBox(height: Space.sm),
                  WingsButton(
                    label: l10n.authRegister,
                    expand: true,
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: busy
                        ? null
                        : () => context.push(RoutePaths.register),
                  ),
                  const SizedBox(height: Space.sm),
                  WingsButton(
                    label: l10n.authLogin,
                    variant: WingsButtonVariant.outline,
                    expand: true,
                    loading: _guestLoading,
                    onPressed: busy
                        ? null
                        : () => context.push(RoutePaths.login),
                  ),
                  const SizedBox(height: Space.sm),
                  TextButton(
                    onPressed: busy ? null : _continueAsGuest,
                    child: Text(l10n.authContinueGuest),
                  ),
                ],
              ),
            ),
          ),
          if (_googleLoading)
            const _AuthBusyOverlay(
              message: 'جارٍ تسجيل الدخول…',
              messageEn: 'Signing you in…',
            ),
        ],
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
  bool _remember = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .signIn(email: _email.text.trim(), password: _password.text);
      await ref.read(settingsProvider.notifier).leaveGuestMode();
      if (!mounted) return;
      final verified = ref.read(authProvider)?.emailVerified ?? false;
      context.go(verified ? RoutePaths.profile : RoutePaths.verify);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = authErrorText(context, error);
      });
    }
  }

  Future<void> _google() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).signInWithGoogle();
      await ref.read(settingsProvider.notifier).leaveGuestMode();
      if (!mounted) return;
      context.go(RoutePaths.profile);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.kind == FailureKind.cancelled
            ? null
            : authErrorText(context, error);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = authErrorText(context, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: WingsAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        children: <Widget>[
          const WingsMark(size: 64),
          const SizedBox(height: Space.lg),
          Text(l10n.authLogin, style: context.text.headlineSmall),
          const SizedBox(height: Space.xl),
          Form(
            key: _formKey,
            child: Column(
              children: <Widget>[
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: l10n.authEmail,
                    prefixIcon: const Icon(
                      Icons.alternate_email_rounded,
                      size: 18,
                    ),
                  ),
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
          const SizedBox(height: Space.sm),
          Row(
            children: <Widget>[
              Checkbox(
                value: _remember,
                onChanged: (value) => setState(() => _remember = value ?? true),
              ),
              Text(l10n.authRemember, style: context.text.bodySmall),
              const Spacer(),
              TextButton(
                onPressed: () => context.push(RoutePaths.forgot),
                child: Text(l10n.authForgot),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          AnimatedSize(
            duration: Motion.fast,
            curve: Motion.standard,
            alignment: AlignmentDirectional.topCenter,
            child: AnimatedSwitcher(
              duration: Motion.fast,
              child: _error == null
                  ? const SizedBox.shrink(key: ValueKey<String>('no-error'))
                  : Padding(
                      key: ValueKey<String>(_error!),
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                          vertical: Space.sm,
                        ),
                        decoration: BoxDecoration(
                          color: context.palette.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(Radii.sm),
                          border: Border.all(
                            color: context.palette.danger.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              Icons.error_outline_rounded,
                              size: 16,
                              color: context.palette.danger,
                            ),
                            const SizedBox(width: Space.xs + 2),
                            Expanded(
                              child: Text(
                                _error!,
                                style: context.text.bodySmall?.copyWith(
                                  color: context.palette.danger,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: Space.md),
          WingsButton(
            label: l10n.authLogin,
            expand: true,
            loading: _loading,
            onPressed: _loading ? null : _submit,
          ),
          const SizedBox(height: Space.md),
          GoogleSignInButton(
            loading: _loading,
            onPressed: _loading ? null : _google,
          ),
          const SizedBox(height: Space.md),
          Center(
            child: TextButton(
              onPressed: () => context.pushReplacement(RoutePaths.register),
              child: Text(l10n.authNoAccount),
            ),
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
  static const int _stepCount = 3;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  int _step = 0;
  String _country = 'SA';
  String _ageGroup = '18-24';
  bool _usernameAvailable = false;
  String? _avatarPath;
  bool _acceptedTerms = false;
  bool _termsError = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 640,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _avatarPath = file.path);
  }

  void _next() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_step == 0 && !_usernameAvailable) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'اختر اسم مستخدم متاحًا للمتابعة.',
          en: 'Choose an available username to continue.',
        ),
        isError: true,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step = (_step + 1).clamp(0, _stepCount - 1));
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _step -= 1);
  }

  Future<void> _google() async {
    setState(() => _loading = true);
    try {
      await ref.read(authProvider.notifier).signInWithGoogle();
      await ref.read(settingsProvider.notifier).leaveGuestMode();
      if (!mounted) return;
      context.go(RoutePaths.profile);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (error.kind != FailureKind.cancelled) {
        context.showSnack(authErrorText(context, error), isError: true);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showSnack(authErrorText(context, error), isError: true);
    }
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    setState(() => _termsError = !_acceptedTerms);
    if (!valid || !_acceptedTerms) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await ref
          .read(authProvider.notifier)
          .register(
            displayName: _name.text.trim(),
            username: _username.text.trim(),
            country: _country,
            ageGroup: _ageGroup,
            email: _email.text.trim(),
            password: _password.text,
            avatarPath: _avatarPath,
          );
      await ref.read(settingsProvider.notifier).leaveGuestMode();
      if (!mounted) return;
      context.go(RoutePaths.verify);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showSnack(authErrorText(context, error), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    return Scaffold(
      appBar: WingsAppBar(showBack: true),
      body: Stack(
        children: <Widget>[
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                0,
                Space.xl,
                Space.xl,
              ),
              children: <Widget>[
                Text(l10n.authRegister, style: context.text.headlineSmall),
                const SizedBox(height: Space.sm),
                Text(
                  l10n.authStepOf('${_step + 1}', '$_stepCount'),
                  style: context.text.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: Space.md),
                Row(
                  children: <Widget>[
                    for (var index = 0; index < _stepCount; index++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: Motion.normal,
                          curve: Motion.standard,
                          height: 4,
                          margin: EdgeInsetsDirectional.only(
                            end: index == _stepCount - 1 ? 0 : Space.xs,
                          ),
                          decoration: BoxDecoration(
                            color: index <= _step
                                ? palette.primary
                                : palette.surfaceHigh,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Space.xl),
                AnimatedSize(
                  duration: Motion.normal,
                  curve: Motion.standard,
                  alignment: AlignmentDirectional.topCenter,
                  child: AnimatedSwitcher(
                    duration: Motion.normal,
                    switchInCurve: Motion.enter,
                    switchOutCurve: Motion.exit,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<int>(_step),
                      child: switch (_step) {
                        0 => _IdentityStep(
                          name: _name,
                          username: _username,
                          onNext: _next,
                          onAvailability: (value) =>
                              setState(() => _usernameAvailable = value),
                        ),
                        1 => _CredentialsStep(
                          email: _email,
                          password: _password,
                          confirm: _confirm,
                        ),
                        _ => _ProfileStep(
                          country: _country,
                          onCountry: (value) =>
                              setState(() => _country = value),
                          ageGroup: _ageGroup,
                          onAgeGroup: (value) =>
                              setState(() => _ageGroup = value),
                          avatarPath: _avatarPath,
                          onPickAvatar: _pickAvatar,
                          acceptedTerms: _acceptedTerms,
                          termsError: _termsError,
                          onTerms: (value) => setState(() {
                            _acceptedTerms = value;
                            _termsError = false;
                          }),
                        ),
                      },
                    ),
                  ),
                ),
                const SizedBox(height: Space.lg),
                Row(
                  children: <Widget>[
                    if (_step > 0) ...<Widget>[
                      Expanded(
                        child: WingsButton(
                          label: l10n.commonBack,
                          variant: WingsButtonVariant.outline,
                          onPressed: _loading ? null : _back,
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                    ],
                    Expanded(
                      flex: 2,
                      child: WingsButton(
                        label: _step == _stepCount - 1
                            ? l10n.authRegister
                            : l10n.commonNext,
                        expand: true,
                        loading: _loading,
                        onPressed: _loading
                            ? null
                            : (_step == _stepCount - 1 ? _submit : _next),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.md),
                GoogleSignInButton(
                  loading: _loading,
                  onPressed: _loading ? null : _google,
                ),
                const SizedBox(height: Space.sm),
                Center(
                  child: TextButton(
                    onPressed: _loading
                        ? null
                        : () => context.pushReplacement(RoutePaths.login),
                    child: Text(l10n.authHaveAccount),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const _AuthBusyOverlay(
              message: 'جارٍ إنشاء حسابك…',
              messageEn: 'Creating your account…',
            ),
        ],
      ),
    );
  }
}

class _IdentityStep extends StatelessWidget {
  const _IdentityStep({
    required this.name,
    required this.username,
    required this.onNext,
    required this.onAvailability,
  });

  final TextEditingController name;
  final TextEditingController username;
  final VoidCallback onNext;
  final ValueChanged<bool> onAvailability;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        TextFormField(
          controller: name,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.authName,
            prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
          ),
          validator: (value) =>
              (value?.trim().length ?? 0) < 2 ? l10n.authValidationName : null,
        ),
        const SizedBox(height: Space.md),
        UsernameField(
          controller: username,
          onAvailabilityChanged: onAvailability,
        ),
      ],
    );
  }
}

class _CredentialsStep extends StatelessWidget {
  const _CredentialsStep({
    required this.email,
    required this.password,
    required this.confirm,
  });

  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController confirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Column(
      children: <Widget>[
        TextFormField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.authEmail,
            prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18),
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (!text.contains('@') || !text.contains('.')) {
              return l10n.authValidationEmail;
            }
            return null;
          },
        ),
        const SizedBox(height: Space.md),
        StatefulBuilder(
          builder: (context, setState) {
            final current = _strength(password.text);
            return Column(
              children: <Widget>[
                _PasswordField(
                  controller: password,
                  label: l10n.authPassword,
                  onChanged: (_) => setState(() {}),
                  validator: (value) => (value ?? '').length < 8
                      ? l10n.authValidationPassword
                      : null,
                ),
                const SizedBox(height: Space.sm),
                Row(
                  children: <Widget>[
                    for (var index = 0; index < 3; index++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            end: index == 2 ? 0 : Space.xs,
                          ),
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: index < current.score
                                  ? current.color(palette)
                                  : palette.surfaceHigh,
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: Space.sm),
                    Text(
                      current.score == 0
                          ? ''
                          : (current.score == 1
                                ? l10n.authPasswordWeak
                                : (current.score == 2
                                      ? l10n.authPasswordMedium
                                      : l10n.authPasswordStrong)),
                      style: context.text.labelSmall?.copyWith(
                        color: current.color(palette),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: Space.md),
        _PasswordField(
          controller: confirm,
          label: l10n.authConfirmPassword,
          validator: (value) =>
              value != password.text ? l10n.authValidationConfirm : null,
        ),
      ],
    );
  }

  _Strength _strength(String value) {
    var score = 0;
    if (value.length >= 8) score++;
    if (RegExp(r'[A-Za-z]').hasMatch(value) &&
        RegExp(r'[0-9]').hasMatch(value)) {
      score++;
    }
    if (value.length >= 12 ||
        (RegExp(r'[^A-Za-z0-9]').hasMatch(value) && value.length >= 10)) {
      score++;
    }
    return _Strength(score.clamp(0, 3));
  }
}

class _Strength {
  const _Strength(this.score);

  final int score;

  Color color(WingsPalette palette) => switch (score) {
    <= 1 => palette.danger,
    2 => palette.warning,
    _ => palette.success,
  };
}

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({
    required this.country,
    required this.onCountry,
    required this.ageGroup,
    required this.onAgeGroup,
    required this.avatarPath,
    required this.onPickAvatar,
    required this.acceptedTerms,
    required this.termsError,
    required this.onTerms,
  });

  final String country;
  final ValueChanged<String> onCountry;
  final String ageGroup;
  final ValueChanged<String> onAgeGroup;
  final String? avatarPath;
  final VoidCallback onPickAvatar;
  final bool acceptedTerms;
  final bool termsError;
  final ValueChanged<bool> onTerms;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    return Column(
      children: <Widget>[
        GestureDetector(
          onTap: onPickAvatar,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.surfaceAlt,
              border: Border.all(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: avatarPath == null
                ? Icon(
                    Icons.add_a_photo_outlined,
                    color: palette.textMuted,
                    size: 26,
                  )
                : Image.file(File(avatarPath!), fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          l10n.authChoosePhoto,
          style: context.text.labelMedium?.copyWith(color: palette.primary),
        ),
        const SizedBox(height: Space.xl),
        DropdownButtonFormField<String>(
          initialValue: country,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.authCountry,
            prefixIcon: const Icon(Icons.public_rounded, size: 18),
          ),
          items: <DropdownMenuItem<String>>[
            for (final item in kCountries)
              DropdownMenuItem<String>(value: item.$1, child: Text(item.$2)),
          ],
          onChanged: (value) {
            if (value != null) onCountry(value);
          },
        ),
        const SizedBox(height: Space.md),
        DropdownButtonFormField<String>(
          initialValue: ageGroup,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: Tr.of(context, ar: 'الفئة العمرية', en: 'Age group'),
            prefixIcon: const Icon(Icons.cake_outlined, size: 18),
          ),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: 'under-13',
              child: Text('أقل من 13'),
            ),
            DropdownMenuItem<String>(value: '13-17', child: Text('13 - 17')),
            DropdownMenuItem<String>(value: '18-24', child: Text('18 - 24')),
            DropdownMenuItem<String>(value: '25-34', child: Text('25 - 34')),
            DropdownMenuItem<String>(value: '35+', child: Text('35+')),
          ],
          onChanged: (value) {
            if (value != null) onAgeGroup(value);
          },
        ),
        const SizedBox(height: Space.lg),
        InkWell(
          onTap: () => onTerms(!acceptedTerms),
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Row(
              children: <Widget>[
                Checkbox(
                  value: acceptedTerms,
                  onChanged: (value) => onTerms(value ?? false),
                ),
                Expanded(
                  child: Text(
                    l10n.authAcceptTerms,
                    style: context.text.bodySmall?.copyWith(
                      color: termsError
                          ? palette.danger
                          : palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  static const Duration _cooldown = Duration(seconds: 45);

  bool _sending = false;
  bool _checking = false;
  bool _autoChecked = false;
  DateTime? _lastSent;
  String? _message;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // The account verifies in the background while the reader is on another
    // device or app. A quiet poll moves them on as soon as the link is used,
    // instead of leaving them on a screen that looks stuck.
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (!mounted || _checking || _sending || _autoChecked) return;
    _autoChecked = true;
    try {
      final verified = await ref
          .read(authProvider.notifier)
          .refreshEmailVerification();
      if (verified && mounted) {
        context.go(RoutePaths.profile);
        return;
      }
    } on Object {
      // Offline: the next tick tries again.
    } finally {
      _autoChecked = false;
    }
  }

  Future<void> _resend() async {
    final last = _lastSent;
    if (last != null && DateTime.now().difference(last) < _cooldown) {
      final wait = _cooldown - DateTime.now().difference(last);
      setState(() {
        _message = Tr.of(
          context,
          ar: 'انتظر ${wait.inSeconds} ثانية قبل إعادة الإرسال.',
          en: 'Wait ${wait.inSeconds}s before resending.',
        );
      });
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await ref.read(authProvider.notifier).sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _lastSent = DateTime.now();
        _message = Tr.of(
          context,
          ar: 'تم إرسال رابط التحقق إلى بريدك.',
          en: 'A verification link was sent to your email.',
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = authErrorText(context, error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      final verified = await ref
          .read(authProvider.notifier)
          .refreshEmailVerification();
      if (!mounted) return;
      setState(() {
        _checking = false;
        _message = verified
            ? Tr.of(
                context,
                ar: 'تم تأكيد بريدك بنجاح.',
                en: 'Your email is verified.',
              )
            : Tr.of(
                context,
                ar: 'لم يتم تأكيد البريد بعد. افتح الرابط ثم اضغط تحديث.',
                en: 'Not verified yet. Open the link, then refresh.',
              );
      });
      if (verified) context.go(RoutePaths.profile);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _message = authErrorText(context, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final user = ref.watch(authProvider);
    return Scaffold(
      appBar: WingsAppBar(showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(Space.xl),
        children: <Widget>[
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.primary.withValues(alpha: 0.12),
              ),
              child: Icon(
                Icons.mark_email_read_outlined,
                color: palette.primary,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(
            l10n.authVerifyTitle,
            textAlign: TextAlign.center,
            style: context.text.titleLarge,
          ),
          const SizedBox(height: Space.sm),
          Text(
            l10n.authVerifyBody,
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: palette.textSecondary,
              height: 1.6,
            ),
          ),
          if (user?.email.isNotEmpty ?? false) ...<Widget>[
            const SizedBox(height: Space.sm),
            Text(
              user!.email,
              textAlign: TextAlign.center,
              style: context.text.labelMedium?.copyWith(color: palette.primary),
            ),
          ],
          if (_message != null) ...<Widget>[
            const SizedBox(height: Space.md),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: Space.xl),
          WingsButton(
            label: Tr.of(
              context,
              ar: 'تحديث حالة التحقق',
              en: 'Refresh status',
            ),
            expand: true,
            loading: _checking,
            icon: Icons.refresh_rounded,
            onPressed: _checking ? null : _refresh,
          ),
          const SizedBox(height: Space.sm),
          WingsButton(
            label: Tr.of(context, ar: 'إعادة إرسال الرابط', en: 'Resend link'),
            variant: WingsButtonVariant.outline,
            expand: true,
            loading: _sending,
            onPressed: _sending ? null : _resend,
          ),
          const SizedBox(height: Space.sm),
          Center(
            child: TextButton(
              onPressed: () => context.go(RoutePaths.profile),
              child: Text(l10n.authContinueGuest),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Continue with Google" button used on the login and welcome screens.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, this.onPressed, this.loading = false});

  final VoidCallback? onPressed;

  /// A Google sign-in can take a few seconds (account picker, profile repair),
  /// so the button shows its own spinner instead of silently ignoring taps.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: onPressed,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: palette.borderStrong),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (loading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.primary,
                    ),
                  )
                else
                  Text(
                    'G',
                    style: context.text.titleMedium?.copyWith(
                      color: const Color(0xFF4285F4),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: Text(
                    loading
                        ? Tr.of(
                            context,
                            ar: 'جارٍ المتابعة…',
                            en: 'Continuing…',
                          )
                        : Tr.of(
                            context,
                            ar: 'المتابعة باستخدام Google',
                            en: 'Continue with Google',
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge?.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dimmed, non-interactive layer shown while an authentication request is in
/// flight, so a second tap can never start a parallel sign-in.
class _AuthBusyOverlay extends StatelessWidget {
  const _AuthBusyOverlay({required this.message, required this.messageEn});

  final String message;
  final String messageEn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: palette.overlay.withValues(alpha: 0.45),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.xl,
                vertical: Space.lg,
              ),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.primary,
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Text(
                    Tr.of(context, ar: message, en: messageEn),
                    style: context.text.bodySmall?.copyWith(
                      color: palette.textPrimary,
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

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.validator,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;
  final ValueChanged<String>? onChanged;

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
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
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
    );
  }
}
