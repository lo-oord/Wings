import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';

/// Explains a blocked email or handle and lets the person ask Wings to review
/// it, together with the reason and the other half of the identity they tried.
Future<void> showBlockedIdentitySheet(
  BuildContext context,
  WidgetRef ref, {
  required bool email,
  required String value,
  String counterpart = '',
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _BlockedIdentityDialog(
      email: email,
      value: value,
      counterpart: counterpart,
      container: ProviderScope.containerOf(context),
    ),
  );
}

class _BlockedIdentityDialog extends StatefulWidget {
  const _BlockedIdentityDialog({
    required this.email,
    required this.value,
    required this.counterpart,
    required this.container,
  });

  final bool email;
  final String value;
  final String counterpart;
  final ProviderContainer container;

  @override
  State<_BlockedIdentityDialog> createState() => _BlockedIdentityDialogState();
}

class _BlockedIdentityDialogState extends State<_BlockedIdentityDialog> {
  final TextEditingController _reason = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason.text.trim();
    if (reason.length < 5) {
      setState(
        () => _error = Tr.of(
          context,
          ar: 'اكتب سببًا واضحًا للمراجعة (٥ أحرف على الأقل).',
          en: 'Write a clear reason for the review (at least 5 characters).',
        ),
      );
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final uid = widget.container.read(authProvider)?.id ?? '';
      await widget.container
          .read(identityRepositoryProvider)
          .requestReview(
            email: widget.email,
            value: widget.value,
            reason: reason,
            counterpart: widget.counterpart,
            requesterUid: uid,
          );
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sending = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = Tr.of(
          context,
          ar: 'تعذر إرسال الطلب الآن. حاول مرة أخرى.',
          en: 'The request could not be sent. Please try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = widget.email
        ? Tr.of(context, ar: 'البريد الإلكتروني', en: 'Email')
        : Tr.of(context, ar: 'اسم المستخدم', en: 'Username');

    return AlertDialog(
      icon: Icon(
        _sent ? Icons.mark_email_read_outlined : Icons.shield_outlined,
        color: _sent ? palette.success : palette.warning,
      ),
      title: Text(
        _sent
            ? Tr.of(context, ar: 'تم إرسال طلبك', en: 'Request sent')
            : Tr.of(
                context,
                ar: 'هذا الحساب محظور',
                en: 'This identity is blocked',
              ),
      ),
      content: _sent
          ? Text(
              Tr.of(
                context,
                ar: 'وصل طلبك إلى فريق Wings. سنراجع الحالة ونرد عبر حسابك إن أمكن.',
                en: 'Your request reached the Wings team. We will review it and reply through your account when possible.',
              ),
              style: context.text.bodySmall?.copyWith(
                color: palette.textSecondary,
                height: 1.6,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Tr.of(
                    context,
                    ar: 'لا يمكن استخدام $label التالي في Wings:',
                    en: 'This $label cannot be used on Wings:',
                  ),
                  style: context.text.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    widget.value,
                    textDirection: TextDirection.ltr,
                    style: context.text.bodySmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.counterpart.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Space.sm),
                  Text(
                    widget.email
                        ? Tr.of(
                            context,
                            ar: 'سنراجع أيضًا اسم المستخدم الذي أدخلته: ${widget.counterpart}',
                            en: 'We will also review the username you entered: ${widget.counterpart}',
                          )
                        : Tr.of(
                            context,
                            ar: 'سنراجع أيضًا البريد الذي أدخلته: ${widget.counterpart}',
                            en: 'We will also review the email you entered: ${widget.counterpart}',
                          ),
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: Space.md),
                TextField(
                  controller: _reason,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    labelText: Tr.of(
                      context,
                      ar: 'سبب طلب المراجعة',
                      en: 'Reason for the review',
                    ),
                    hintText: Tr.of(
                      context,
                      ar: 'اشرح لماذا تريد مراجعة هذا الحظر…',
                      en: 'Explain why this block should be reviewed…',
                    ),
                    counterText: '',
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: Space.xs),
                  Text(
                    _error!,
                    style: context.text.labelSmall?.copyWith(
                      color: palette.danger,
                    ),
                  ),
                ],
              ],
            ),
      actions: _sent
          ? <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(Tr.of(context, ar: 'إغلاق', en: 'Close')),
              ),
            ]
          : <Widget>[
              TextButton(
                onPressed: _sending ? null : () => Navigator.of(context).pop(),
                child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
              ),
              WingsButton(
                label: Tr.of(
                  context,
                  ar: 'إرسال للمراجعة',
                  en: 'Send for review',
                ),
                height: Sizes.buttonCompact,
                loading: _sending,
                onPressed: _sending ? null : _send,
              ),
            ],
      contentPadding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        0,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.xs,
        Space.lg,
        Space.md,
      ),
    );
  }
}
