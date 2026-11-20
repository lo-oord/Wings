import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/chat.dart';
import '../auth/sign_in_prompt.dart';
import '../community/report_sheet.dart';
import '../profile/avatar_view.dart';
import 'chat_providers.dart';

/// The conversation list. One Firestore listener feeds the whole screen; no
/// per-chat listener is opened, and cached chats render immediately offline.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  int _tab = 0;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final uid = ref.watch(authProvider)?.id;
    final stream = ref.watch(chatsProvider);
    final cached = uid == null
        ? const <Chat>[]
        : ref.read(chatRepositoryProvider).cachedChats(uid);
    final chats = stream.value ?? cached;
    final visible = chats.where((chat) {
      if (uid == null || chat.deletedFor(uid)) return false;
      if (_tab == 3 && !chat.archivedFor(uid)) return false;
      if (_tab != 3 && chat.archivedFor(uid)) return false;
      if (_tab == 1 && chat.unreadFor(uid) == 0) return false;
      if (_tab == 2 && !chat.pinnedFor(uid)) return false;
      if (_query.isNotEmpty) {
        final name =
            '${chat.peer?.displayName ?? ''} ${chat.peer?.username ?? ''}'
                .toLowerCase();
        if (!name.contains(_query.toLowerCase())) return false;
      }
      return true;
    }).toList();
    visible.sort((a, b) {
      final pinned = (b.pinnedFor(uid!) ? 1 : 0).compareTo(
        a.pinnedFor(uid) ? 1 : 0,
      );
      if (pinned != 0) return pinned;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return Scaffold(
      backgroundColor: palette.background,
      appBar: WingsAppBar(
        showBack: true,
        title: Text(
          Tr.of(context, ar: 'المحادثات', en: 'Chats'),
          style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          WingsIconButton(
            icon: Icons.lock_outline_rounded,
            tooltip: Tr.of(context, ar: 'الخصوصية', en: 'Privacy'),
            onPressed: () => context.push(RoutePaths.chatPrivacy),
          ),
          const SizedBox(width: Space.xs),
          WingsIconButton(
            icon: Icons.edit_square,
            tooltip: Tr.of(context, ar: 'محادثة جديدة', en: 'New chat'),
            onPressed: () => _newChat(uid),
          ),
          const SizedBox(width: Space.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _newChat(uid),
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        child: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
      ),
      body: uid == null
          ? _SignedOutChats()
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.xs,
                    Space.lg,
                    Space.xs,
                  ),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value.trim()),
                    style: context.text.bodySmall,
                    decoration: InputDecoration(
                      hintText: Tr.of(
                        context,
                        ar: 'ابحث في المحادثات',
                        en: 'Search chats',
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: palette.surfaceAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    children: <Widget>[
                      for (final entry in <(int, String)>[
                        (0, Tr.of(context, ar: 'الكل', en: 'All')),
                        (1, Tr.of(context, ar: 'غير مقروءة', en: 'Unread')),
                        (2, Tr.of(context, ar: 'مثبتة', en: 'Pinned')),
                        (3, Tr.of(context, ar: 'مؤرشفة', en: 'Archived')),
                      ])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            label: Text(entry.$2),
                            selected: _tab == entry.$1,
                            onSelected: (_) => setState(() => _tab = entry.$1),
                            labelStyle: const TextStyle(fontSize: 10),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ),
                if (stream.hasError && chats.isEmpty)
                  Expanded(
                    child: WingsEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: Tr.of(
                        context,
                        ar: 'تعذّر تحميل المحادثات',
                        en: 'Chats could not load',
                      ),
                      message: loadFailedText(context),
                      actionLabel: Tr.of(context, ar: 'إعادة', en: 'Retry'),
                      onAction: () => ref.invalidate(chatsProvider),
                    ),
                  )
                else if (visible.isEmpty)
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async => ref.invalidate(chatsProvider),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: <Widget>[
                          const SizedBox(height: Space.xxxl),
                          WingsEmptyState(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: _tab == 1
                                ? Tr.of(
                                    context,
                                    ar: 'لا رسائل غير مقروءة',
                                    en: 'No unread messages',
                                  )
                                : Tr.of(
                                    context,
                                    ar: 'لا محادثات بعد',
                                    en: 'No chats yet',
                                  ),
                            message: Tr.of(
                              context,
                              ar: 'ابدأ محادثة من ملف أي عضو أو من زر المحادثة الجديدة.',
                              en: 'Start a chat from a member profile or the new-chat button.',
                            ),
                            actionLabel: Tr.of(
                              context,
                              ar: 'محادثة جديدة',
                              en: 'New chat',
                            ),
                            onAction: () => _newChat(uid),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async => ref.invalidate(chatsProvider),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: visible.length,
                        itemBuilder: (context, index) => _ChatTile(
                          chat: visible[index],
                          uid: uid,
                          onTap: () =>
                              context.push(RoutePaths.chat(visible[index].id)),
                          onMenu: (action) =>
                              _menu(visible[index], action, uid),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _newChat(String? uid) async {
    if (uid == null) {
      showSignInPrompt(
        context,
        message: Tr.of(
          context,
          ar: 'سجّل الدخول لبدء محادثة.',
          en: 'Sign in to start a chat.',
        ),
      );
      return;
    }
    final chatId = await context.push<String>(RoutePaths.chatNew);
    if (chatId != null && mounted) context.push(RoutePaths.chat(chatId));
  }

  Future<void> _menu(Chat chat, String action, String uid) async {
    final repo = ref.read(chatRepositoryProvider);
    try {
      switch (action) {
        case 'pin':
          await repo.setFlag(
            chat.id,
            uid,
            flag: 'pinned',
            value: !chat.pinnedFor(uid),
          );
        case 'archive':
          await repo.setFlag(
            chat.id,
            uid,
            flag: 'archived',
            value: !chat.archivedFor(uid),
          );
        case 'mute':
          await repo.setFlag(
            chat.id,
            uid,
            flag: 'muted',
            value: !chat.mutedFor(uid),
          );
        case 'delete':
          final confirmed = await WingsDialog.confirm(
            context,
            title: Tr.of(context, ar: 'حذف المحادثة؟', en: 'Delete this chat?'),
            message: Tr.of(
              context,
              ar: 'ستُخفى من قائمتك فقط. تبقى الرسائل عند الطرف الآخر، وتعود المحادثة إذا وصلت رسالة جديدة.',
              en: 'It is hidden from your list only. The other side keeps the messages, and a new message brings it back.',
            ),
            confirmLabel: Tr.of(context, ar: 'حذف', en: 'Delete'),
            destructive: true,
          );
          if (confirmed) await repo.deleteForMe(chat.id, uid);
        case 'unblock':
          await ref
              .read(communityRepositoryProvider)
              .unblock(uid: uid, target: chat.peerOf(uid));
        case 'block':
          await ref
              .read(communityRepositoryProvider)
              .block(uid: uid, target: chat.peerOf(uid));
        case 'report':
          await showReportSheet(
            context,
            ref,
            targetType: 'user',
            targetId: chat.peerOf(uid),
            targetUid: chat.peerOf(uid),
            preview: chat.lastMessageText,
          );
      }
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.uid,
    required this.onTap,
    required this.onMenu,
  });

  final Chat chat;
  final String uid;
  final VoidCallback onTap;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final peer = chat.peer;
    final name = (peer?.displayName.trim().isNotEmpty ?? false)
        ? peer!.displayName
        : (peer?.username.isNotEmpty ?? false)
        ? '@${peer!.username}'
        : Tr.of(context, ar: 'عضو', en: 'Member');
    final unread = chat.unreadFor(uid);
    final muted = chat.mutedFor(uid);
    final mine = chat.lastSenderUid == uid;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.sm,
          Space.sm,
        ),
        child: Row(
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                UserAvatar(
                  uid: chat.peerOf(uid),
                  photoVersion: peer?.photoVersion ?? 0,
                  name: name,
                  size: 46,
                ),
                if (chat.pinnedFor(uid))
                  PositionedDirectional(
                    bottom: -2,
                    end: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.border),
                      ),
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 10,
                        color: palette.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: Space.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelMedium?.copyWith(
                            fontWeight: unread > 0
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        relativeTime(
                          chat.lastMessageAt ?? chat.updatedAt,
                          context.l10n,
                        ),
                        style: context.text.labelSmall?.copyWith(
                          color: unread > 0
                              ? palette.primary
                              : palette.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      if (mine)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 3),
                          child: Icon(
                            Icons.done_all_rounded,
                            size: 13,
                            color: palette.textMuted,
                          ),
                        ),
                      if (muted)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 3),
                          child: Icon(
                            Icons.volume_off_rounded,
                            size: 12,
                            color: palette.textMuted,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          chat.peerTyping(uid, DateTime.now())
                              ? Tr.of(context, ar: 'يكتب…', en: 'typing…')
                              : (chat.lastMessageText.isEmpty
                                    ? Tr.of(
                                        context,
                                        ar: 'ابدأ المحادثة',
                                        en: 'Say hello',
                                      )
                                    : chat.lastMessageText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelSmall?.copyWith(
                            color: chat.peerTyping(uid, DateTime.now())
                                ? palette.primary
                                : palette.textSecondary,
                          ),
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsetsDirectional.only(start: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: muted ? palette.textMuted : palette.primary,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text(
                            formatCount(unread),
                            style: TextStyle(
                              color: muted
                                  ? palette.background
                                  : palette.onPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 18,
                          color: palette.textMuted,
                        ),
                        onSelected: onMenu,
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'pin',
                            child: Text(
                              chat.pinnedFor(uid)
                                  ? Tr.of(
                                      context,
                                      ar: 'إلغاء التثبيت',
                                      en: 'Unpin',
                                    )
                                  : Tr.of(context, ar: 'تثبيت', en: 'Pin'),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'archive',
                            child: Text(
                              chat.archivedFor(uid)
                                  ? Tr.of(
                                      context,
                                      ar: 'إلغاء الأرشفة',
                                      en: 'Unarchive',
                                    )
                                  : Tr.of(context, ar: 'أرشفة', en: 'Archive'),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'mute',
                            child: Text(
                              chat.mutedFor(uid)
                                  ? Tr.of(
                                      context,
                                      ar: 'إلغاء الكتم',
                                      en: 'Unmute',
                                    )
                                  : Tr.of(context, ar: 'كتم', en: 'Mute'),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text(
                              Tr.of(
                                context,
                                ar: 'حذف من قائمتي',
                                en: 'Delete for me',
                              ),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'report',
                            child: Text(
                              Tr.of(context, ar: 'إبلاغ', en: 'Report'),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'block',
                            child: Text(Tr.of(context, ar: 'حظر', en: 'Block')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedOutChats extends StatelessWidget {
  const _SignedOutChats();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.forum_outlined, size: 38, color: palette.primary),
            const SizedBox(height: Space.md),
            Text(
              Tr.of(
                context,
                ar: 'سجّل الدخول لفتح محادثاتك',
                en: 'Sign in to open your chats',
              ),
              style: context.text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              Tr.of(
                context,
                ar: 'محادثات فردية آمنة مع أعضاء Wings، مع إمكانية مشاركة الأنمي والمنشورات.',
                en: 'Private one-to-one chats with Wings members, including anime and post sharing.',
              ),
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: palette.textSecondary,
                height: 1.7,
              ),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: () => showSignInPrompt(
                context,
                message: Tr.of(
                  context,
                  ar: 'سجّل الدخول لبدء المحادثات.',
                  en: 'Sign in to start chatting.',
                ),
              ),
              child: Text(Tr.of(context, ar: 'تسجيل الدخول', en: 'Sign in')),
            ),
          ],
        ),
      ),
    );
  }
}
