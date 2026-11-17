import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../data/repositories/username_repository.dart';
import '../../data/username/username_rules.dart';

/// Username input with live, debounced availability.
///
/// * one request per settled value (450 ms debounce, identical values cached),
/// * empty or invalid values never reach Firestore,
/// * outdated responses are ignored through a generation counter,
/// * taken handles offer checked alternatives the user can tap.
class UsernameField extends ConsumerStatefulWidget {
  const UsernameField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onAvailabilityChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<bool>? onAvailabilityChanged;

  @override
  ConsumerState<UsernameField> createState() => _UsernameFieldState();
}

class _UsernameFieldState extends ConsumerState<UsernameField> {
  static const Duration _debounceDelay = Duration(milliseconds: 450);

  Timer? _debounce;
  int _generation = 0;
  UsernameAvailability? _result;
  bool _checking = false;
  String? _checkedValue;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    if (widget.controller.text.isNotEmpty) _onChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged() {
    final raw = widget.controller.text;
    final validation = UsernameRules.validate(raw);
    _debounce?.cancel();
    _generation++;

    if (raw.trim().isEmpty) {
      setState(() {
        _result = null;
        _checking = false;
      });
      widget.onAvailabilityChanged?.call(false);
      return;
    }
    if (!validation.ok) {
      setState(() {
        _checking = false;
        _result = UsernameAvailability(
          UsernameStatus.invalid,
          normalized: validation.normalized,
          problem: validation.problem,
        );
      });
      widget.onAvailabilityChanged?.call(false);
      return;
    }
    if (_checkedValue == validation.normalized &&
        _result?.status == UsernameStatus.available) {
      widget.onAvailabilityChanged?.call(true);
      return;
    }
    setState(() => _checking = true);
    final generation = _generation;
    _debounce = Timer(
      _debounceDelay,
      () => _runCheck(validation.normalized, generation),
    );
  }

  Future<void> _runCheck(String normalized, int generation) async {
    if (!ref.read(firebaseReadyProvider)) {
      // Local-only build: availability is decided by the validation rules.
      if (!mounted || generation != _generation) return;
      setState(() {
        _checking = false;
        _checkedValue = normalized;
        _result = UsernameAvailability(
          UsernameStatus.available,
          normalized: normalized,
        );
      });
      widget.onAvailabilityChanged?.call(true);
      return;
    }
    try {
      final result = await ref
          .read(usernameRepositoryProvider)
          .check(normalized);
      if (!mounted || generation != _generation) return;
      setState(() {
        _checking = false;
        _checkedValue = normalized;
        _result = result;
      });
      widget.onAvailabilityChanged?.call(
        result.status == UsernameStatus.available,
      );
    } on Object catch (error) {
      if (kDebugMode) {
        // The generic message below is intentional; the real reason (rules not
        // published, database missing, offline) is only useful in the console.
        debugPrint('username availability check failed: $error');
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _checking = false;
        _result = const UsernameAvailability(UsernameStatus.error);
      });
      widget.onAvailabilityChanged?.call(false);
    }
  }

  void _useSuggestion(String suggestion) {
    widget.controller.text = suggestion;
    widget.controller.selection = TextSelection.collapsed(
      offset: suggestion.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: Tr.of(context, ar: 'اسم المستخدم', en: 'Username'),
            prefixText: '@',
            prefixIcon: const Icon(Icons.alternate_email_rounded, size: 18),
          ),
          validator: (value) {
            final validation = UsernameRules.validate(value ?? '');
            return validation.ok
                ? null
                : usernameProblemText(context, validation.problem);
          },
        ),
        const SizedBox(height: Space.xs + 2),
        _Status(
          result: _result,
          checking: _checking,
          onSuggestion: _useSuggestion,
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.result,
    required this.checking,
    required this.onSuggestion,
  });

  final UsernameAvailability? result;
  final bool checking;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (checking) {
      return Row(
        children: <Widget>[
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.8),
          ),
          const SizedBox(width: Space.xs + 2),
          Text(
            Tr.of(context, ar: 'جارٍ التحقق…', en: 'Checking…'),
            style: context.text.labelSmall?.copyWith(color: palette.textMuted),
          ),
        ],
      );
    }
    final value = result;
    if (value == null) return const SizedBox.shrink();

    if (value.status == UsernameStatus.available) {
      return Row(
        children: <Widget>[
          Icon(Icons.check_circle_rounded, size: 14, color: palette.primary),
          const SizedBox(width: 4),
          Text(
            Tr.of(context, ar: 'اسم المستخدم متاح', en: 'Username available'),
            style: context.text.labelSmall?.copyWith(
              color: palette.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    if (value.status == UsernameStatus.taken) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_rounded, size: 14, color: palette.danger),
              const SizedBox(width: 4),
              Text(
                Tr.of(
                  context,
                  ar: 'اسم المستخدم مستخدم بالفعل',
                  en: 'This username is already taken',
                ),
                style: context.text.labelSmall?.copyWith(color: palette.danger),
              ),
            ],
          ),
          if (value.suggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.xs + 2),
            Wrap(
              spacing: Space.xs + 2,
              runSpacing: Space.xs,
              children: <Widget>[
                for (final suggestion in value.suggestions)
                  InkWell(
                    onTap: () => onSuggestion(suggestion),
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        border: Border.all(
                          color: palette.primary.withValues(alpha: 0.45),
                        ),
                        color: palette.primary.withValues(alpha: 0.08),
                      ),
                      child: Text(
                        '@$suggestion',
                        style: context.text.labelSmall?.copyWith(
                          color: palette.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      );
    }

    if (value.status == UsernameStatus.invalid) {
      return Text(
        usernameProblemText(context, value.problem),
        style: context.text.labelSmall?.copyWith(color: palette.danger),
      );
    }

    return Text(
      Tr.of(
        context,
        ar: 'تعذر التحقق من الاسم الآن، حاول مرة أخرى.',
        en: 'Could not check the username now. Try again.',
      ),
      style: context.text.labelSmall?.copyWith(color: palette.textMuted),
    );
  }
}

/// Shared Arabic/English copy for the username problems.
String usernameProblemText(BuildContext context, UsernameProblem? problem) =>
    switch (problem) {
      UsernameProblem.empty => Tr.of(
        context,
        ar: 'أدخل اسم مستخدم.',
        en: 'Enter a username.',
      ),
      UsernameProblem.tooShort => Tr.of(
        context,
        ar: 'اسم المستخدم قصير جدًا (3 أحرف على الأقل).',
        en: 'Too short (at least 3 characters).',
      ),
      UsernameProblem.tooLong => Tr.of(
        context,
        ar: 'اسم المستخدم طويل جدًا (20 حرفًا كحد أقصى).',
        en: 'Too long (20 characters maximum).',
      ),
      UsernameProblem.invalidCharacters => Tr.of(
        context,
        ar: 'حروف إنجليزية وأرقام وشرطة سفلية فقط، بدون مسافات.',
        en: 'English letters, numbers and underscores only, no spaces.',
      ),
      UsernameProblem.reserved => Tr.of(
        context,
        ar: 'هذا الاسم محجوز. اختر اسمًا آخر.',
        en: 'This name is reserved. Pick another one.',
      ),
      null => '',
    };
