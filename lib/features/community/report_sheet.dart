import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/community.dart';
import '../admin/owner_guard.dart';

/// One report flow for posts, comments and profiles.
///
/// The report lands in the existing `reports` collection, which the Owner and
/// the moderators already read in the console; no parallel moderation queue is
/// created. The account that files it is taken from the session, never from a
/// field the caller could choose.
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String targetType,
  required String targetId,
  String? targetUid,
  String? preview,
}) async {
  final uid = ref.read(authProvider)?.id;
  if (uid == null) {
    context.showSnack(
      Tr.of(context, ar: 'سجّل الدخول للإبلاغ.', en: 'Sign in to report.'),
    );
    return;
  }
  if (targetUid != null &&
      await ref.read(ownerUidProvider.future) == targetUid) {
    if (context.mounted) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'لا يمكن الإبلاغ عن حساب المالك.',
          en: 'The owner account cannot be reported.',
        ),
        isError: true,
      );
    }
    return;
  }
  if (!context.mounted) return;
  final result = await WingsPopup.show<String>(
    context: context,
    heightFactor: 0.8,
    builder: (context) =>
        _ReportSheet(targetType: targetType, targetId: targetId),
  );
  if (result == null || !context.mounted) return;
  try {
    await ref
        .read(communityRepositoryProvider)
        .report(
          reporterUid: uid,
          targetType: targetType,
          targetId: targetId,
          targetUid: targetUid,
          targetPreview: preview,
          reason: result,
        );
    if (context.mounted) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'تم إرسال البلاغ إلى الإدارة.',
          en: 'Your report was sent to the team.',
        ),
      );
    }
  } on Object catch (error) {
    if (context.mounted) {
      context.showSnack(userFacingError(context, error), isError: true);
    }
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.targetType, required this.targetId});

  final String targetType;
  final String targetId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason _reason = ReportReason.spam;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.lg,
          Space.lg,
          Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              Tr.of(context, ar: 'إبلاغ', en: 'Report'),
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xxs),
            Text(
              Tr.of(
                context,
                ar: 'اختر السبب الأقرب. البلاغ سري.',
                en: 'Pick the closest reason. Your report stays private.',
              ),
              style: context.text.bodySmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: Space.md),
            for (final reason in ReportReason.values)
              InkWell(
                onTap: () => setState(() => _reason = reason),
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        _reason == reason
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: _reason == reason
                            ? palette.primary
                            : palette.textMuted,
                      ),
                      const SizedBox(width: Space.sm + 2),
                      Expanded(
                        child: Text(
                          reason.label(arabic: arabic),
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Space.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_reason.id),
                child: Text(
                  Tr.of(context, ar: 'إرسال البلاغ', en: 'Send report'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
