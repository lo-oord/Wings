import '../storage/local_store.dart';
import '../../data/models/chat.dart';
import '../../data/models/user_profile.dart';

/// Offline-first storage for chats. Hive already powers the rest of Wings, so
/// this adds no database engine and no generated adapters.
///
/// Every key is scoped to the signed-in uid: signing out clears that account's
/// cache, and a second account on the same device can never read the first
/// one's conversations.
class ChatLocalStore {
  ChatLocalStore(this._store);

  final LocalStore _store;

  static const int maxCachedMessages = 120;
  static const Duration profileTtl = Duration(hours: 24);

  String _chatsKey(String uid) => 'chats_$uid';
  String _messagesKey(String uid, String chatId) => 'msgs_${uid}_$chatId';
  String _pendingKey(String uid) => 'pending_$uid';

  List<Chat> loadChats(String uid) {
    final raw = _store.getJson(LocalStore.chatsBox, _chatsKey(uid));
    if (raw is! List) return const <Chat>[];
    return <Chat>[
      for (final item in raw)
        if (item is Map)
          Chat.fromLocalJson(Map<String, dynamic>.from(item), uid),
    ];
  }

  Future<void> saveChats(String uid, List<Chat> chats) => _store.putJson(
    LocalStore.chatsBox,
    _chatsKey(uid),
    <Map<String, dynamic>>[
      for (final chat in chats.take(60)) chat.toLocalJson(uid),
    ],
  );

  Future<void> upsertChat(String uid, Chat chat) async {
    final chats = loadChats(uid);
    final next =
        <Chat>[
          chat,
          for (final item in chats)
            if (item.id != chat.id) item,
        ]..sort((a, b) {
          final pinned = b
              .pinnedFor(uid)
              .toString()
              .compareTo(a.pinnedFor(uid).toString());
          if (pinned != 0) return pinned;
          return b.updatedAt.compareTo(a.updatedAt);
        });
    await saveChats(uid, next);
  }

  List<ChatMessage> loadMessages(String uid, String chatId) {
    final raw = _store.getJson(LocalStore.chatsBox, _messagesKey(uid, chatId));
    if (raw is! List) return const <ChatMessage>[];
    final messages = <ChatMessage>[
      for (final item in raw)
        if (item is Map)
          ChatMessage.fromLocalJson(Map<String, dynamic>.from(item)),
    ];
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  Future<void> saveMessages(
    String uid,
    String chatId,
    List<ChatMessage> messages,
  ) {
    final sorted = <ChatMessage>[...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final kept = sorted.length > maxCachedMessages
        ? sorted.sublist(sorted.length - maxCachedMessages)
        : sorted;
    return _store.putJson(
      LocalStore.chatsBox,
      _messagesKey(uid, chatId),
      <Map<String, dynamic>>[for (final item in kept) item.toLocalJson()],
    );
  }

  Future<void> upsertMessage(String uid, ChatMessage message) async {
    final messages = loadMessages(uid, message.chatId);
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      messages[index] = message;
    } else {
      messages.add(message);
    }
    await saveMessages(uid, message.chatId, messages);
  }

  Future<void> removeMessage(
    String uid,
    String chatId,
    String messageId,
  ) async {
    final messages = loadMessages(uid, chatId)
      ..removeWhere((item) => item.id == messageId);
    await saveMessages(uid, chatId, messages);
  }

  /// Messages written locally but not yet acknowledged by Firestore.
  List<ChatMessage> loadPending(String uid) {
    final raw = _store.getJson(LocalStore.chatsBox, _pendingKey(uid));
    if (raw is! List) return const <ChatMessage>[];
    return <ChatMessage>[
      for (final item in raw)
        if (item is Map)
          ChatMessage.fromLocalJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<void> savePending(String uid, List<ChatMessage> messages) => _store
      .putJson(LocalStore.chatsBox, _pendingKey(uid), <Map<String, dynamic>>[
        for (final item in messages.take(100)) item.toLocalJson(),
      ]);

  Future<void> addPending(String uid, ChatMessage message) async {
    final pending = loadPending(uid)
      ..removeWhere((item) => item.id == message.id)
      ..add(message);
    await savePending(uid, pending);
  }

  Future<void> removePending(String uid, String messageId) async {
    final pending = loadPending(uid)
      ..removeWhere((item) => item.id == messageId);
    await savePending(uid, pending);
  }

  UserProfile? readProfile(String uid, String peerUid) {
    final raw = _store.readCache('chat_profile_${uid}_$peerUid');
    if (raw is! Map) return null;
    return UserProfile.fromPublicMap(peerUid, Map<String, dynamic>.from(raw));
  }

  Future<void> cacheProfile(String uid, UserProfile profile) =>
      _store.putCache('chat_profile_${uid}_${profile.uid}', <String, dynamic>{
        'username': profile.username,
        'normalizedUsername': profile.normalizedUsername,
        'displayName': profile.displayName,
        'badges': profile.badges.toMap(),
        'photoVersion': profile.photoVersion,
        'private': profile.profileHidden,
      }, ttl: profileTtl);

  ChatShare? readShare(String key) {
    final raw = _store.readCache('chat_share_$key');
    return raw is Map ? ChatShare.fromMap(raw) : null;
  }

  Future<void> cacheShare(String key, ChatShare share) =>
      _store.putCache('chat_share_$key', share.toMap(), ttl: profileTtl);

  /// Removes every cached key of one account. Called on sign-out so no message
  /// survives into the next session.
  Future<void> clearAccount(String uid) async {
    final prefixes = <String>['chats_$uid', 'msgs_${uid}_', 'pending_$uid'];
    for (final key in _store.keys(LocalStore.chatsBox)) {
      if (prefixes.any(key.startsWith)) {
        await _store.delete(LocalStore.chatsBox, key);
      }
    }
    for (final key in _store.keys(LocalStore.cacheBox)) {
      if (key.startsWith('chat_profile_${uid}_') ||
          key.startsWith('chat_share_')) {
        await _store.delete(LocalStore.cacheBox, key);
      }
    }
  }
}
