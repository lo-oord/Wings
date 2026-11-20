import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart';
import 'admin_actions.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../core/errors/user_facing_error.dart';

/// Global announcements: composed, previewed and published from here.
class AdminAnnouncementsScreen extends ConsumerWidget {
  const AdminAnnouncementsScreen({super.key});

  Future<void> _compose(BuildContext context, WidgetRef ref) async {
    final actor = AdminActor.of(ref);
    final decision =
        await showDialog<(String, String, AnnouncementType, DateTime?)>(
          context: context,
          builder: (_) => const _AnnouncementDialog(),
        );
    if (decision == null || !context.mounted) return;
    final preview = await WingsDialog.confirm(
      context,
      title: decision.$1,
      message: decision.$2,
      confirmLabel: Tr.of(context, ar: 'نشر', en: 'Publish'),
    );
    if (!preview || !context.mounted) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .publishAnnouncement(
            announcement: Announcement(
              id: '',
              title: decision.$1,
              body: decision.$2,
              type: decision.$3,
              publishedAt: DateTime.now(),
              expiresAt: decision.$4,
            ),
            actorUid: actor.uid,
            actorName: actor.name,
          );
      ref.invalidate(announcementsProvider);
      ref.invalidate(liveAnnouncementsProvider);
      if (context.mounted) {
        context.showSnack(Tr.of(context, ar: 'تم النشر.', en: 'Published.'));
      }
    } on Object catch (error) {
      if (context.mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(announcementsProvider);
    return AdminGuard(
      child: Scaffold(
        appBar: WingsAppBar(
          showBack: true,
          title: Text(
            Tr.of(context, ar: 'الإشعارات العامة', en: 'Announcements'),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: Tr.of(context, ar: 'إعلان جديد', en: 'New announcement'),
              icon: const Icon(Icons.add_rounded, size: 22),
              onPressed: () => _compose(context, ref),
            ),
          ],
        ),
        body: page.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => WingsEmptyState(
            icon: Icons.cloud_off_rounded,
            title: Tr.of(context, ar: 'تعذّر التحميل', en: 'Failed to load'),
            message: loadFailedText(context),
          ),
          data: (data) {
            if (data.items.isEmpty) {
              return WingsEmptyState(
                icon: Icons.campaign_outlined,
                title: Tr.of(
                  context,
                  ar: 'لا توجد إعلانات',
                  en: 'No announcements',
                ),
                message: Tr.of(
                  context,
                  ar: 'يظهر الإعلان لكل عضو داخل مركز الإشعارات، وتُحفظ قراءته في حسابه.',
                  en: 'An announcement appears in every member notification centre and its read state is stored on their account.',
                ),
                actionLabel: Tr.of(
                  context,
                  ar: 'إنشاء إعلان',
                  en: 'Create one',
                ),
                onAction: () => _compose(context, ref),
              );
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: Space.xxxl),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    Space.xs,
                  ),
                  child: WingsButton(
                    label: Tr.of(
                      context,
                      ar: 'إعلان جديد',
                      en: 'New announcement',
                    ),
                    icon: Icons.add_rounded,
                    expand: true,
                    onPressed: () => _compose(context, ref),
                  ),
                ),
                for (final item in data.items)
                  AdminCard(
                    title: item.title,
                    trailing: Text(
                      adminDateShort(item.publishedAt),
                      style: context.text.labelSmall?.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
                    children: <Widget>[
                      Text(item.body, style: context.text.bodySmall),
                      const SizedBox(height: Space.xs),
                      Row(
                        children: <Widget>[
                          Text(
                            _typeLabel(context, item.type),
                            style: context.text.labelSmall?.copyWith(
                              color: context.palette.primary,
                            ),
                          ),
                          const Spacer(),
                          if (item.expiresAt != null)
                            Text(
                              '${Tr.of(context, ar: 'ينتهي', en: 'Expires')}: '
                              '${adminDateShort(item.expiresAt)}',
                              style: context.text.labelSmall?.copyWith(
                                color: context.palette.textMuted,
                              ),
                            ),
                          IconButton(
                            tooltip: Tr.of(context, ar: 'حذف', en: 'Delete'),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            onPressed: () async {
                              final confirmed = await WingsDialog.confirm(
                                context,
                                title: Tr.of(
                                  context,
                                  ar: 'حذف الإعلان',
                                  en: 'Delete announcement',
                                ),
                                message: item.title,
                                confirmLabel: Tr.of(
                                  context,
                                  ar: 'حذف',
                                  en: 'Delete',
                                ),
                                destructive: true,
                              );
                              if (!confirmed || !context.mounted) return;
                              final actor = AdminActor.of(ref);
                              try {
                                await ref
                                    .read(adminRepositoryProvider)
                                    .deleteAnnouncement(
                                      id: item.id,
                                      title: item.title,
                                      actorUid: actor.uid,
                                      actorName: actor.name,
                                    );
                                ref.invalidate(announcementsProvider);
                                ref.invalidate(liveAnnouncementsProvider);
                              } on Object catch (error) {
                                if (context.mounted) {
                                  context.showSnack(
                                    userFacingError(context, error),
                                    isError: true,
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _typeLabel(BuildContext context, AnnouncementType type) {
    return switch (type) {
      AnnouncementType.general => Tr.of(
        context,
        ar: 'إعلان عام',
        en: 'General',
      ),
      AnnouncementType.important => Tr.of(
        context,
        ar: 'تنبيه مهم',
        en: 'Important',
      ),
      AnnouncementType.maintenance => Tr.of(
        context,
        ar: 'صيانة',
        en: 'Maintenance',
      ),
      AnnouncementType.update => Tr.of(context, ar: 'تحديث', en: 'Update'),
    };
  }
}

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog();

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  AnnouncementType _type = AnnouncementType.general;
  DateTime? _expiresAt;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Tr.of(context, ar: 'إعلان عام', en: 'Announcement')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'العنوان', en: 'Title'),
                errorText: _error != null && _title.text.trim().isEmpty
                    ? _error
                    : null,
              ),
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _body,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'النص', en: 'Message'),
              ),
            ),
            const SizedBox(height: Space.md),
            DropdownButtonFormField<AnnouncementType>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: Tr.of(context, ar: 'النوع', en: 'Type'),
              ),
              items: <DropdownMenuItem<AnnouncementType>>[
                for (final type in AnnouncementType.values)
                  DropdownMenuItem<AnnouncementType>(
                    value: type,
                    child: Text(type.id),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _type = value ?? AnnouncementType.general),
            ),
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 15),
              label: Text(
                _expiresAt == null
                    ? Tr.of(context, ar: 'بلا انتهاء', en: 'No expiry')
                    : adminDate(_expiresAt),
              ),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                  initialDate: now.add(const Duration(days: 14)),
                );
                if (picked == null) return;
                setState(
                  () => _expiresAt = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    23,
                    59,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
        ),
        TextButton(
          onPressed: () {
            final title = _title.text.trim();
            final body = _body.text.trim();
            if (title.isEmpty || body.isEmpty) {
              setState(
                () => _error = Tr.of(
                  context,
                  ar: 'العنوان والنص مطلوبان',
                  en: 'Title and message are required',
                ),
              );
              return;
            }
            Navigator.of(context).pop((title, body, _type, _expiresAt));
          },
          child: Text(Tr.of(context, ar: 'معاينة', en: 'Preview')),
        ),
      ],
    );
  }
}
