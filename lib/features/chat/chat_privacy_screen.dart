import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/chat.dart';
import 'chat_providers.dart';

/// Chat privacy lives on its own document (`chatPrivacy/{uid}`) instead of
/// weakening the private account document. The defaults are friendly, and a
/// missing document reads as the defaults.
class ChatPrivacyScreen extends ConsumerWidget {
  const ChatPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final uid = ref.watch(authProvider)?.id;
    final stream = uid == null
        ? const AsyncValue<ChatPrivacy>.data(ChatPrivacy.defaults)
        : ref.watch(chatPrivacyProvider(uid));
    final privacy = stream.value ?? ChatPrivacy.defaults;

    Future<void> save(ChatPrivacy next) async {
      if (uid == null) return;
      try {
        await ref.read(chatRepositoryProvider).savePrivacy(uid, next);
      } on Object catch (error) {
        if (context.mounted) {
          context.showSnack(userFacingError(context, error), isError: true);
        }
      }
    }

    return Scaffold(
      backgroundColor: palette.background,
      appBar: WingsAppBar(
        showBack: true,
        title: Text(Tr.of(context, ar: 'خصوصية المحادثات', en: 'Chat privacy')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: <Widget>[
          Text(
            Tr.of(
              context,
              ar: 'تتحكم هذه الخيارات فيما يراه الآخرون في المحادثات. لا تُشارك كلمة المرور أو بياناتك مع أي طرف.',
              en: 'These options control what others see in chats. Your password and private data are never shared with anyone.',
            ),
            style: context.text.labelSmall?.copyWith(
              color: palette.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: Space.lg),
          SwitchListTile(
            value: privacy.showLastSeen,
            onChanged: (value) => save(
              ChatPrivacy(
                showLastSeen: value,
                showOnline: privacy.showOnline,
                readReceipts: privacy.readReceipts,
                whoCanMessage: privacy.whoCanMessage,
              ),
            ),
            title: Text(Tr.of(context, ar: 'آخر ظهور', en: 'Last seen')),
            subtitle: Text(
              Tr.of(
                context,
                ar: 'يظهر وقت آخر تواجد لك في المحادثات.',
                en: 'Shows when you were last active in chats.',
              ),
              style: const TextStyle(fontSize: 11),
            ),
          ),
          SwitchListTile(
            value: privacy.showOnline,
            onChanged: (value) => save(
              ChatPrivacy(
                showLastSeen: privacy.showLastSeen,
                showOnline: value,
                readReceipts: privacy.readReceipts,
                whoCanMessage: privacy.whoCanMessage,
              ),
            ),
            title: Text(
              Tr.of(context, ar: 'حالة الاتصال', en: 'Online status'),
            ),
            subtitle: Text(
              Tr.of(
                context,
                ar: 'يظهر أنك متصل الآن.',
                en: 'Shows that you are online now.',
              ),
              style: const TextStyle(fontSize: 11),
            ),
          ),
          SwitchListTile(
            value: privacy.readReceipts,
            onChanged: (value) => save(
              ChatPrivacy(
                showLastSeen: privacy.showLastSeen,
                showOnline: privacy.showOnline,
                readReceipts: value,
                whoCanMessage: privacy.whoCanMessage,
              ),
            ),
            title: Text(
              Tr.of(context, ar: 'إشعارات القراءة', en: 'Read receipts'),
            ),
            subtitle: Text(
              Tr.of(
                context,
                ar: 'عند الإيقاف لن يعرف الطرف الآخر أنك قرأت رسائله. يبقى «تم الاستلام» ظاهرًا.',
                en: 'When off, the other side will not see that you read their messages. Delivered status stays visible.',
              ),
              style: const TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(
            Tr.of(context, ar: 'من يستطيع مراسلتك', en: 'Who can message you'),
            style: context.text.labelSmall?.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: 6,
            children: <Widget>[
              ChoiceChip(
                label: Text(Tr.of(context, ar: 'الجميع', en: 'Everyone')),
                selected: privacy.whoCanMessage == 'everyone',
                onSelected: (_) => save(
                  ChatPrivacy(
                    showLastSeen: privacy.showLastSeen,
                    showOnline: privacy.showOnline,
                    readReceipts: privacy.readReceipts,
                  ),
                ),
              ),
              ChoiceChip(
                label: Text(Tr.of(context, ar: 'المتابَعون', en: 'Following')),
                selected: privacy.whoCanMessage == 'following',
                onSelected: (_) => save(
                  ChatPrivacy(
                    showLastSeen: privacy.showLastSeen,
                    showOnline: privacy.showOnline,
                    readReceipts: privacy.readReceipts,
                    whoCanMessage: 'following',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: palette.border),
            ),
            child: Text(
              Tr.of(
                context,
                ar: 'الحظر يمنع الرسائل في الاتجاهين، وتحققه قواعد Firestore نفسها وليس الواجهة فقط.',
                en: 'Blocking prevents messages in both directions, and Firestore rules enforce it, not just the interface.',
              ),
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
