import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/tr.dart';
import '../../data/models/chat.dart';
import '../../data/models/user_profile.dart';
import '../auth/sign_in_prompt.dart';
import '../community/community_providers.dart';
import '../profile/avatar_view.dart';
import 'chat_providers.dart';

/// Opens the in-app share sheet for any content card.
///
/// The sheet is independent of the chat screen, so it can be opened from anime,
/// episode, post and Reel pages. Only content ids and a small preview are sent;
/// the receiver opens the original screen.
Future<void> shareToChats(
  BuildContext context,
  WidgetRef ref,
  ChatShare share,
) async {
  if (ref.read(authProvider) == null) {
    showSignInPrompt(
      context,
      message: Tr.of(
        context,
        ar: 'سجّل الدخول لإرسال المحتوى إلى محادثة.',
        en: 'Sign in to send content to a chat.',
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ShareSheet(share: share),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.share});

  final ChatShare share;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final TextEditingController _note = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final Set<String> _selected = <String>{};
  final String _token = _newToken();
  Timer? _debounce;
  List<UserProfile> _users = const <UserProfile>[];
  bool _sending = false;
  String? _status;

  static String _newToken() {
    final random = Random.secure();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${random.nextInt(1 << 32).toRadixString(36)}';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _note.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final uid = ref.watch(authProvider)?.id ?? '';
    final chats = (ref.watch(chatsProvider).value ?? const <Chat>[])
        .where((chat) => !chat.deletedFor(uid))
        .toList(growable: false);
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? chats
        : chats
              .where(
                (chat) =>
                    '${chat.peer?.displayName ?? ''} '
                            '${chat.peer?.username ?? ''}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      Tr.of(
                        context,
                        ar: 'إرسال إلى محادثة',
                        en: 'Send to chat',
                      ),
                      style: context.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_sending)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    FilledButton(
                      onPressed: _selected.isEmpty ? null : _send,
                      child: Text(
                        _selected.isEmpty
                            ? Tr.of(context, ar: 'إرسال', en: 'Send')
                            : '${Tr.of(context, ar: 'إرسال', en: 'Send')} '
                                  '(${_selected.length})',
                      ),
                    ),
                ],
              ),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: 4,
                ),
                child: Text(
                  _status!,
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                Space.xs,
              ),
              child: TextField(
                controller: _search,
                onChanged: (_) => _onSearch(),
                style: context.text.bodySmall,
                decoration: InputDecoration(
                  hintText: Tr.of(
                    context,
                    ar: 'ابحث عن محادثة أو عضو',
                    en: 'Search chats or members',
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                children: <Widget>[
                  for (final chat in visible)
                    CheckboxListTile(
                      value: _selected.contains(chat.id),
                      onChanged: _sending
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                _selected.add(chat.id);
                              } else {
                                _selected.remove(chat.id);
                              }
                            }),
                      secondary: UserAvatar(
                        uid: chat.peerOf(uid),
                        photoVersion: chat.peer?.photoVersion ?? 0,
                        name: chat.peer?.displayName ?? '',
                        size: 38,
                      ),
                      title: Text(
                        chat.peer?.displayName.isNotEmpty == true
                            ? chat.peer!.displayName
                            : '@${chat.peer?.username ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        chat.lastMessageText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                  if (_users.isNotEmpty) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.all(Space.sm),
                      child: Text(
                        Tr.of(context, ar: 'أعضاء جدد', en: 'New members'),
                        style: context.text.labelSmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                    for (final user in _users)
                      ListTile(
                        leading: UserAvatar(
                          uid: user.uid,
                          photoVersion: user.photoVersion,
                          name: user.displayName,
                          size: 38,
                        ),
                        title: Text('@${user.username}'),
                        subtitle: Text(
                          user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.add_rounded, size: 18),
                        onTap: _sending ? null : () => _startChat(user),
                      ),
                  ],
                  if (visible.isEmpty && _users.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: Text(
                        Tr.of(
                          context,
                          ar: 'لا محادثات مطابقة. ابحث باسم المستخدم لبدء محادثة.',
                          en: 'No matching chats. Search a username to start one.',
                        ),
                        style: context.text.labelSmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.xs,
                  Space.lg,
                  Space.sm,
                ),
                child: TextField(
                  controller: _note,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 500,
                  style: context.text.bodySmall,
                  decoration: InputDecoration(
                    hintText: Tr.of(
                      context,
                      ar: 'أضف رسالة (اختياري)',
                      en: 'Add a message (optional)',
                    ),
                    counterText: '',
                    filled: true,
                    fillColor: palette.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSearch() {
    _debounce?.cancel();
    final query = _search.text.trim();
    if (query.isEmpty) {
      setState(() {
        _users = const <UserProfile>[];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () async {
      final users = await ref
          .read(communityRepositoryProvider)
          .suggestUsers(query);
      if (!mounted) return;
      setState(() {
        _users = users
            .where((user) => user.uid != ref.read(authProvider)?.id)
            .toList(growable: false);
      });
    });
  }

  Future<void> _startChat(UserProfile user) async {
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return;
    try {
      final following =
          ref.read(followingIdsProvider(uid)).value ?? const <String>{};
      final allowed = await ref
          .read(chatRepositoryProvider)
          .canMessage(
            uid: uid,
            peerUid: user.uid,
            following: following.contains(user.uid),
          );
      if (!allowed) {
        if (mounted) {
          setState(
            () => _status = Tr.of(
              context,
              ar: 'لا يمكن مراسلة هذا الحساب وفق الخصوصية أو الحظر.',
              en: 'This account cannot be messaged because of privacy or a block.',
            ),
          );
        }
        return;
      }
      final chatId = await ref
          .read(chatRepositoryProvider)
          .ensureChat(uid: uid, peerUid: user.uid);
      if (!mounted) return;
      setState(() {
        _selected.add(chatId);
        _search.clear();
        _users = const <UserProfile>[];
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = userFacingError(context, error));
    }
  }

  Future<void> _send() async {
    final uid = ref.read(authProvider)?.id;
    final author = ref.read(profileProvider);
    if (uid == null || author == null || _sending) return;
    setState(() {
      _sending = true;
      _status = Tr.of(context, ar: 'جارٍ الإرسال…', en: 'Sending…');
    });
    final repo = ref.read(chatRepositoryProvider);
    final chatMap = <String, Chat>{
      for (final chat in ref.read(chatsProvider).value ?? const <Chat>[])
        chat.id: chat,
    };
    var sent = 0;
    final failures = <String>[];
    for (final chatId in _selected.toList(growable: false)) {
      try {
        var chat = chatMap[chatId];
        chat ??= await repo.fetchChat(chatId);
        if (chat == null) throw StateError('missing-chat');
        await repo.send(
          chat: chat,
          author: author,
          peerMuted: chat.mutedFor(chat.peerOf(uid)) == true,
          message: ChatMessage(
            id: 's${_token}_$chatId',
            chatId: chatId,
            senderUid: uid,
            type: ChatMessageType.share,
            text: _note.text.trim(),
            share: widget.share,
            createdAt: DateTime.now(),
            status: ChatMessageStatus.sending,
          ),
        );
        sent++;
      } on Object catch (error) {
        if (!mounted) return;
        failures.add(userFacingError(context, error));
      }
    }
    if (!mounted) return;
    if (failures.isEmpty) {
      Navigator.of(context).pop();
      context.showSnack(
        Tr.of(
          context,
          ar: 'تم الإرسال إلى $sent محادثة.',
          en: 'Sent to $sent chat(s).',
        ),
      );
      return;
    }
    setState(() {
      _sending = false;
      _status = sent == 0
          ? failures.first
          : '${Tr.of(context, ar: 'أُرسل إلى $sent، وفشل بعضها.', en: 'Sent to $sent, some failed.')} '
                '${failures.first}';
    });
  }
}
