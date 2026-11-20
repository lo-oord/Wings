import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/chat.dart';
import '../../data/models/user_profile.dart';
import '../community/community_providers.dart';
import '../profile/avatar_view.dart';
import '../social/user_handle.dart';
import 'chat_providers.dart';

/// Starts a one-to-one chat. It searches the existing public profiles and
/// respects blocks and the peer's `whoCanMessage` setting before creating the
/// conversation.
class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<UserProfile> _results = const <UserProfile>[];
  bool _searching = false;
  bool _starting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final uid = ref.watch(authProvider)?.id;
    final chats = ref.watch(chatsProvider).value ?? const <Chat>[];
    final recent = chats
        .where(
          (chat) => uid != null && !chat.deletedFor(uid) && chat.peer != null,
        )
        .take(8)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: WingsAppBar(
        showBack: true,
        title: Text(Tr.of(context, ar: 'محادثة جديدة', en: 'New chat')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: <Widget>[
          TextField(
            controller: _search,
            onChanged: _onChanged,
            autofocus: true,
            style: context.text.bodySmall,
            decoration: InputDecoration(
              hintText: Tr.of(
                context,
                ar: 'ابحث باسم المستخدم',
                en: 'Search by username',
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: palette.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.pill),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(Space.lg),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_search.text.trim().isNotEmpty && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Text(
                Tr.of(context, ar: 'لا نتائج.', en: 'No results.'),
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            )
          else if (_results.isNotEmpty) ...<Widget>[
            Text(
              Tr.of(context, ar: 'أعضاء', en: 'Members'),
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            for (final profile in _results)
              _UserTile(profile: profile, onTap: () => _start(profile)),
          ] else if (recent.isNotEmpty) ...<Widget>[
            Text(
              Tr.of(context, ar: 'محادثات حديثة', en: 'Recent chats'),
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            for (final chat in recent)
              _UserTile(profile: chat.peer!, onTap: () => context.pop(chat.id)),
          ] else
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Text(
                Tr.of(
                  context,
                  ar: 'اكتب اسم المستخدم للعثور على عضو',
                  en: 'Type a username to find a member',
                ),
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const <UserProfile>[];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final results = await ref
          .read(communityRepositoryProvider)
          .suggestUsers(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  Future<void> _start(UserProfile profile) async {
    final uid = ref.read(authProvider)?.id;
    if (uid == null || _starting) return;
    if (uid == profile.uid) return;
    _starting = true;
    try {
      final following =
          ref.read(followingIdsProvider(uid)).value ?? const <String>{};
      final allowed = await ref
          .read(chatRepositoryProvider)
          .canMessage(
            uid: uid,
            peerUid: profile.uid,
            following: following.contains(profile.uid),
          );
      if (!allowed) {
        if (mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: 'لا يمكن بدء محادثة مع هذا الحساب وفق إعدادات الخصوصية أو الحظر.',
              en: 'A chat cannot be started with this account because of privacy settings or a block.',
            ),
            isError: true,
          );
        }
        return;
      }
      final chatId = await ref
          .read(chatRepositoryProvider)
          .ensureChat(uid: uid, peerUid: profile.uid);
      // Keeps the peer's public snapshot available before the list reloads.
      if (mounted) context.pop(chatId);
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    } finally {
      _starting = false;
    }
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.profile, required this.onTap});

  final UserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
      leading: UserAvatar(
        uid: profile.uid,
        photoVersion: profile.photoVersion,
        name: profile.displayName,
        size: 40,
      ),
      title: UserHandle(
        uid: profile.uid,
        username: profile.username,
        badges: profile.badges,
      ),
      subtitle: Text(
        profile.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.labelSmall?.copyWith(
          color: context.palette.textMuted,
        ),
      ),
      trailing: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
    );
  }
}
