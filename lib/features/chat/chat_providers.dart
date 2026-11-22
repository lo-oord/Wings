import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/services/chat_local_store.dart';
import '../../data/models/chat.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/chat_repository.dart';

final chatLocalStoreProvider = Provider<ChatLocalStore>(
  (ref) => ChatLocalStore(ref.watch(localStoreProvider)),
);

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(
    FirebaseFirestore.instance,
    ref.watch(chatLocalStoreProvider),
  ),
);

/// One listener for the whole list. The cached list is shown first, so opening
/// the app offline never shows an empty screen while Firestore reconnects.
final chatsProvider = StreamProvider<List<Chat>>((ref) {
  final uid = ref.watch(authProvider)?.id;
  if (uid == null) return Stream<List<Chat>>.value(const <Chat>[]);
  return ref.watch(chatRepositoryProvider).watchChats(uid);
});

final chatProvider = StreamProvider.autoDispose.family<Chat?, String>(
  (ref, chatId) => ref.watch(chatRepositoryProvider).watchChat(chatId),
);

final chatPrivacyProvider = StreamProvider.autoDispose
    .family<ChatPrivacy, String>(
      (ref, uid) => ref.watch(chatRepositoryProvider).watchPrivacy(uid),
    );

final presenceProvider = StreamProvider.autoDispose
    .family<ChatPresence, String>(
      (ref, uid) => ref.watch(chatRepositoryProvider).watchPresence(uid),
    );

final unreadMessagesProvider = Provider<int>((ref) {
  final uid = ref.watch(authProvider)?.id;
  final chats = ref.watch(chatsProvider).value ?? const <Chat>[];
  if (uid == null) return 0;
  var total = 0;
  for (final chat in chats) {
    if (!chat.deletedFor(uid) && !chat.mutedFor(uid)) {
      total += chat.unreadFor(uid);
    }
  }
  return total.clamp(0, 999);
});

class ChatMessagesState {
  const ChatMessagesState({
    this.messages = const <ChatMessage>[],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<ChatMessage> messages;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  ChatMessagesState copyWith({
    List<ChatMessage>? messages,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) => ChatMessagesState(
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Messages of exactly one open conversation.
///
/// The local cache is rendered before the first Firestore snapshot, the active
/// chat has the only message listener in the app, and older pages are fetched
/// only when the member scrolls up.
class ChatMessagesController extends Notifier<ChatMessagesState> {
  ChatMessagesController(this.chatId);

  final String chatId;
  StreamSubscription<List<ChatMessage>>? _subscription;
  String? _uid;
  bool _loadingMore = false;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  ChatMessagesState build() {
    final uid = ref.watch(authProvider)?.id;
    _uid = uid;
    if (uid == null) return const ChatMessagesState(loading: false);
    final cached = _repo.cachedMessages(uid, chatId);
    _listen(uid);
    return ChatMessagesState(
      messages: _withPending(cached, uid),
      loading: cached.isEmpty,
    );
  }

  void _listen(String uid) {
    _subscription?.cancel();
    _subscription = _repo
        .watchMessages(chatId)
        .listen(
          (server) {
            final current = state.messages;
            final merged = _merge(server, current, uid);
            unawaited(
              ref
                  .read(chatLocalStoreProvider)
                  .saveMessages(uid, chatId, merged),
            );
            state = state.copyWith(
              messages: merged,
              loading: false,
              clearError: true,
            );
            if (server.length < ChatRepository.pageSize) {
              state = state.copyWith(hasMore: false);
            }
          },
          onError: (Object error) {
            // Keep every cached message; only surface the failure.
            state = state.copyWith(loading: false, error: error);
          },
        );
    ref.onDispose(() => unawaited(_subscription?.cancel()));
  }

  List<ChatMessage> _withPending(List<ChatMessage> base, String uid) {
    final result = <ChatMessage>[...base];
    for (final pending in _repo.pending(uid)) {
      if (pending.chatId != chatId) continue;
      if (!result.any((item) => item.id == pending.id)) result.add(pending);
    }
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  List<ChatMessage> _merge(
    List<ChatMessage> server,
    List<ChatMessage> current,
    String uid,
  ) {
    final result = <String, ChatMessage>{};
    for (final message in server) {
      // A snapshot of a just-written message can still carry a null server
      // timestamp. Keeping the optimistic copy avoids a jump to 1970 and a
      // duplicate bubble.
      final ready = message.createdAt.year > 2000;
      result[message.id] = ready
          ? message
          : _localFor(message.id, current) ?? message;
    }
    for (final message in current) {
      result.putIfAbsent(message.id, () => message);
    }
    for (final pending in _repo.pending(uid)) {
      if (pending.chatId != chatId) continue;
      result[pending.id] = pending;
    }
    final messages = result.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  ChatMessage? _localFor(String id, List<ChatMessage> current) {
    for (final message in current) {
      if (message.id == id) return message;
    }
    return null;
  }

  Future<void> loadMore() async {
    if (_loadingMore || !state.hasMore || state.messages.isEmpty) return;
    final uid = _uid;
    if (uid == null) return;
    _loadingMore = true;
    state = state.copyWith(loadingMore: true);
    try {
      final older = await _repo.fetchBefore(
        chatId,
        state.messages.first.createdAt,
      );
      final merged = _merge(state.messages, older, uid);
      state = state.copyWith(
        messages: merged,
        loadingMore: false,
        hasMore: older.length >= ChatRepository.pageSize,
      );
      await ref.read(chatLocalStoreProvider).saveMessages(uid, chatId, merged);
    } on Object catch (error) {
      state = state.copyWith(loadingMore: false, error: error);
    } finally {
      _loadingMore = false;
    }
  }

  Future<ChatMessage?> send({
    required Chat chat,
    required UserProfile author,
    required ChatMessage draft,
    required bool peerMuted,
  }) async {
    final message = draft.copyWith(status: ChatMessageStatus.sending);
    state = state.copyWith(
      messages: <ChatMessage>[
        ...state.messages.where((item) => item.id != message.id),
        message,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    );
    await ref.read(chatLocalStoreProvider).upsertMessage(author.uid, message);
    await ref.read(chatLocalStoreProvider).addPending(author.uid, message);
    try {
      await _repo.queueSend(
        chat: chat,
        author: author,
        message: message,
        peerMuted: peerMuted,
      );
      final sent = message.copyWith(status: ChatMessageStatus.sent);
      state = state.copyWith(
        messages: state.messages
            .map((item) => item.id == message.id ? sent : item)
            .toList(growable: false),
      );
      await ref.read(chatLocalStoreProvider).upsertMessage(author.uid, sent);
      return sent;
    } on Object catch (error) {
      final failed = message.copyWith(
        status: ChatMessageStatus.failed,
        failure: '$error',
      );
      state = state.copyWith(
        messages: state.messages
            .map((item) => item.id == message.id ? failed : item)
            .toList(growable: false),
      );
      await ref.read(chatLocalStoreProvider).upsertMessage(author.uid, failed);
      return failed;
    }
  }

  Future<void> retry({
    required Chat chat,
    required UserProfile author,
    required ChatMessage message,
    required bool peerMuted,
  }) async {
    final updated = message.copyWith(status: ChatMessageStatus.sending);
    state = state.copyWith(
      messages: state.messages
          .map((item) => item.id == message.id ? updated : item)
          .toList(growable: false),
    );
    try {
      await _repo.retry(
        chat: chat,
        author: author,
        message: updated,
        peerMuted: peerMuted,
      );
    } on Object {
      state = state.copyWith(
        messages: state.messages
            .map(
              (item) => item.id == message.id
                  ? updated.copyWith(status: ChatMessageStatus.failed)
                  : item,
            )
            .toList(growable: false),
      );
    }
  }

  Future<void> edit(ChatMessage message, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _repo.editMessage(chatId, message.id, text: trimmed);
    state = state.copyWith(
      messages: state.messages
          .map(
            (item) => item.id == message.id
                ? item.copyWith(text: trimmed, editedAt: DateTime.now())
                : item,
          )
          .toList(growable: false),
    );
  }

  Future<void> delete(ChatMessage message) async {
    await _repo.deleteMessage(chatId, message.id);
    final tombstone = message.copyWith(
      deleted: true,
      text: '',
      mediaKey: '',
      thumbKey: '',
      reactions: const <String, List<String>>{},
      editedAt: DateTime.now(),
    );
    final uid = _uid;
    if (uid != null) {
      await ref.read(chatLocalStoreProvider).upsertMessage(uid, tombstone);
    }
    state = state.copyWith(
      messages: state.messages
          .map((item) => item.id == message.id ? tombstone : item)
          .toList(growable: false),
    );
  }

  Future<void> react(ChatMessage message, String reaction) async {
    final uid = _uid;
    if (uid == null) return;
    await _repo.react(chatId, message.id, uid: uid, reaction: reaction);
  }
}

final chatMessagesProvider =
    NotifierProvider.family<ChatMessagesController, ChatMessagesState, String>(
      ChatMessagesController.new,
    );

/// Delivery ticks are derived from the conversation document, not stored on
/// every message, so read receipts cost no extra writes per bubble.
ChatMessageStatus messageStatus(
  ChatMessage message, {
  required Chat chat,
  required String uid,
}) {
  if (message.senderUid != uid) return ChatMessageStatus.read;
  if (message.status == ChatMessageStatus.sending ||
      message.status == ChatMessageStatus.failed) {
    return message.status;
  }
  final peer = chat.peerOf(uid);
  final readAt = chat.lastRead[peer];
  if (readAt != null && !readAt.isBefore(message.createdAt)) {
    return ChatMessageStatus.read;
  }
  final deliveredAt = chat.delivered[peer];
  if (deliveredAt != null && !deliveredAt.isBefore(message.createdAt)) {
    return ChatMessageStatus.delivered;
  }
  return ChatMessageStatus.sent;
}
