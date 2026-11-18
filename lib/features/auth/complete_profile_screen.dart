import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/auth/auth_error_text.dart';
import 'auth_screens.dart' show kAgeGroups, kCountries;
import 'username_field.dart';

/// Shown right after a Google sign-up, and again on any later start where the
/// account still has no profile.
///
/// A Google account arrives without a handle, so the reader chooses the display
/// name, username, country and age group here; the profile — and the username
/// reservation — are only written when the form is submitted. Nothing can be
/// skipped: the router keeps this screen until a profile exists.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _username = TextEditingController();

  String _country = 'SA';
  String _ageGroup = '18-24';
  bool _usernameAvailable = false;
  bool _acceptedTerms = false;
  bool _termsError = false;
  bool _loading = false;
  String? _avatarPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Google already knows a display name; offer it instead of asking twice.
    final user = ref.read(authProvider);
    final suggested = (user?.displayName ?? '').trim();
    if (suggested.isNotEmpty) _name.text = suggested;
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
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

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    setState(() => _termsError = !_acceptedTerms);
    if (!valid || !_acceptedTerms) return;
    if (!_usernameAvailable) {
      setState(
        () => _error = Tr.of(
          context,
          ar: 'اختر اسم مستخدم متاحًا للمتابعة.',
          en: 'Choose an available username to continue.',
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .completeProfile(
            displayName: _name.text.trim(),
            username: _username.text.trim(),
            country: _country,
            ageGroup: _ageGroup,
            avatarPath: _avatarPath,
          );
      await ref.read(settingsProvider.notifier).leaveGuestMode();
      if (!mounted) return;
      context.showSnack(
        Tr.of(
          context,
          ar: 'مرحبًا بك في Wings! تم تجهيز حسابك.',
          en: 'Welcome to Wings! Your account is ready.',
        ),
      );
      context.go(RoutePaths.latest);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = authErrorText(context, error);
      });
    }
  }

  /// Leaves the unfinished Google account alone and returns to the sign-in
  /// gate; the reader can finish the same account later, from any device.
  Future<void> _signOut() async {
    await ref.read(authProvider.notifier).signOut();
    if (mounted) context.go(RoutePaths.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final user = ref.watch(authProvider);

    return Scaffold(
      appBar: WingsAppBar(
        showBack: false,
        title: Text(
          Tr.of(context, ar: 'إكمال إنشاء الحساب', en: 'Finish your account'),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.settingsSignOut,
            onPressed: _loading ? null : _signOut,
            icon: const Icon(Icons.logout_rounded, size: 20),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
          children: <Widget>[
            _AccountCreatedBanner(email: user?.email ?? ''),
            const SizedBox(height: Space.lg),
            Center(
              child: GestureDetector(
                onTap: _loading ? null : _pickAvatar,
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surfaceAlt,
                        border: Border.all(color: palette.border, width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _avatarPath == null
                          ? Icon(
                              Icons.add_a_photo_outlined,
                              size: 26,
                              color: palette.textMuted,
                            )
                          : Image.file(File(_avatarPath!), fit: BoxFit.cover),
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      Tr.of(
                        context,
                        ar: 'إضافة صورة شخصية (اختياري)',
                        en: 'Add a profile picture (optional)',
                      ),
                      style: context.text.labelSmall?.copyWith(
                        color: palette.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.xl),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.authName,
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
              ),
              validator: (value) => (value?.trim().length ?? 0) < 2
                  ? l10n.authValidationName
                  : null,
            ),
            const SizedBox(height: Space.md),
            UsernameField(
              controller: _username,
              enabled: !_loading,
              onAvailabilityChanged: (value) =>
                  setState(() => _usernameAvailable = value),
            ),
            const SizedBox(height: Space.md),
            DropdownButtonFormField<String>(
              initialValue: _country,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.authCountry,
                prefixIcon: const Icon(Icons.public_rounded, size: 18),
              ),
              items: <DropdownMenuItem<String>>[
                for (final item in kCountries)
                  DropdownMenuItem<String>(
                    value: item.$1,
                    child: Text(item.$2),
                  ),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value != null) setState(() => _country = value);
                    },
            ),
            const SizedBox(height: Space.md),
            DropdownButtonFormField<String>(
              initialValue: _ageGroup,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'الفئة العمرية', en: 'Age group'),
                prefixIcon: const Icon(Icons.cake_outlined, size: 18),
              ),
              items: <DropdownMenuItem<String>>[
                for (final item in kAgeGroups)
                  DropdownMenuItem<String>(
                    value: item.$1,
                    child: Text(item.$2),
                  ),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value != null) setState(() => _ageGroup = value);
                    },
            ),
            const SizedBox(height: Space.lg),
            InkWell(
              onTap: _loading
                  ? null
                  : () => setState(() {
                      _acceptedTerms = !_acceptedTerms;
                      _termsError = false;
                    }),
              borderRadius: BorderRadius.circular(Radii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Row(
                  children: <Widget>[
                    Checkbox(
                      value: _acceptedTerms,
                      onChanged: _loading
                          ? null
                          : (value) => setState(() {
                              _acceptedTerms = value ?? false;
                              _termsError = false;
                            }),
                    ),
                    Expanded(
                      child: Text(
                        l10n.authAcceptTerms,
                        style: context.text.bodySmall?.copyWith(
                          color: _termsError
                              ? palette.danger
                              : palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: Motion.normal,
              curve: Motion.standard,
              alignment: AlignmentDirectional.topCenter,
              child: AnimatedSwitcher(
                duration: Motion.normal,
                child: _error == null
                    ? const SizedBox.shrink(key: ValueKey<String>('no-error'))
                    : Padding(
                        key: ValueKey<String>(_error!),
                        padding: const EdgeInsets.only(top: Space.md),
                        child: _ErrorBanner(message: _error!),
                      ),
              ),
            ),
            const SizedBox(height: Space.lg),
            WingsButton(
              label: Tr.of(context, ar: 'إنشاء الحساب', en: 'Create account'),
              icon: Icons.check_circle_outline_rounded,
              expand: true,
              loading: _loading,
              onPressed: _loading ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCreatedBanner extends StatelessWidget {
  const _AccountCreatedBanner({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: palette.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.6, end: 1),
            duration: Motion.slow,
            curve: Curves.easeOutBack,
            builder: (context, value, child) =>
                Transform.scale(scale: value, child: child),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.success,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Tr.of(context, ar: 'تم إنشاء الحساب', en: 'Account created'),
                  style: context.text.labelLarge?.copyWith(
                    color: palette.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                Text(
                  Tr.of(
                    context,
                    ar: 'بقيت خطوة واحدة: اختر اسمك واسم المستخدم.',
                    en: 'One more step: pick your name and username.',
                  ),
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: palette.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 16, color: palette.danger),
          const SizedBox(width: Space.xs + 2),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(
                color: palette.danger,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
