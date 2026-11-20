import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/chat_local_store.dart';
import '../models/chat.dart';
import '../models/user_profile.dart';
import 'notification_repository.dart';

/// One-to-one chat storage.
///
/// * `chats/{chatId}` — one document for both members. Per-member state lives
///   in uid-keyed maps (unread, lastRead, typing, pinned, archived, muted,
///   deleted), so pinning or muting never writes a second collection and the
///   list needs exactly one listener.
/// * `chats/{chatId}/messages/{messageId}` — paginated, client-generated ids.
/// * `presence/{uid}` and `chatPrivacy/{uid}` — public presence and the
///   per-account privacy switches.
///
/// Nothing here trusts a client-supplied identity: every read and write is
/// checked by the rules against the conversation members.
final class ChatRepository {
  ChatRepository(this._db, this._local);

  final FirebaseFirestore _db;
  final ChatLocalStore _local;

  static const int pageSize = 30;
  static const Set<String> reactionIds = <String>{
    'heart',
    'like',
    'haha',
    'wow',
    'sad',
  };

  static const Map<String, String> reactionEmoji = <String, String>{
    'heart': '❤️',
    'like': '👍',
    'haha': '😂',
    'wow': '😮',
    'sad': '😢',
  };

  final Random _random = Random.secure();
  final Map<String, DateTime> _typingWrites = <String, DateTime>{};

  late final NotificationRepository _notifications = NotificationRepository(
    _db,
  );

  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection('chats');

  DocumentReference<Map<String, dynamic>> _chat(String id) => _chats.doc(id);

  CollectionReference<Map<String, dynamic>> _messages(String chatId) =>
      _chat(chatId).collection('messages');

  String chatIdFor(String a, String b) {
    final pair = <String>[a, b]..sort();
    return '${pair[0]}_${pair[1]}';
  }

  String newMessageId() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final noise = _random.nextInt(1 << 32).toRadixString(36);
    return 'm$micros$noise';
  }

  // ------------------------------------------------------------------- list

  /// One listener for the whole chat list, never one per conversation.
  Stream<List<Chat>> watchChats(String uid) => _chats
      .where('members', arrayContains: uid)
      .orderBy('updatedAt', descending: true)
      .limit(50)
      .snapshots()
      .asyncMap((snapshot) async {
        final chats = snapshot.docs
            .map((doc) => Chat.fromDoc(doc.id, doc.data()))
            .toList(growable: false);
        final peers = <String>{for (final chat in chats) chat.peerOf(uid)}
          ..remove('');
        final profiles = await profilesFor(uid, peers);
        final filled = <Chat>[
          for (final chat in chats)
            chat.copyWith(peer: profiles[chat.peerOf(uid)]),
        ];
        await _local.saveChats(uid, filled);
        return filled;
      });

  List<Chat> cachedChats(String uid) => _local.loadChats(uid);

  Stream<Chat?> watchChat(String chatId) =>
      _chat(chatId)
          .snapshots()
          .map((doc) => doc.exists ? Chat.fromDoc(doc.id, doc.data()!) : null);

  Future<Chat?> fetchChat(String chatId) async {
    final doc = await _chat(chatId).get();
    return doc.exists ? Chat.fromDoc(doc.id, doc.data()!) : null;
  }

  /// Batch profile lookup for the visible conversations. Cached for a day so
  /// opening the list repeatedly costs no Firestore reads.
  Future<Map<String, UserProfile>> profilesFor(
    String uid,
    Set<String> peers,
  ) async {
    final result = <String, UserProfile>{};
    final missing = <String>[];
    for (final peer in peers) {
      final cached = _local.readProfile(uid, peer);
      if (cached != null) {
        result[peer] = cached;
      } else {
        missing.add(peer);
      }
    }
    if (missing.isEmpty) return result;
    final list = missing.toList(growable: false);
    for (var i = 0; i < list.length; i += 10) {
      final chunk = list.sublist(i, min(i + 10, list.length));
      try {
        final docs = await _db
            .collection('profiles')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in docs.docs) {
          final profile = UserProfile.fromPublicMap(doc.id, doc.data());
          result[doc.id] = profile;
          await _local.cacheProfile(uid, profile);
        }
      } on Object {
        // Offline: the cached names already in the result are enough.
      }
    }
    return result;
  }

  Future<String> ensureChat({
    required String uid,
    required String peerUid,
  }) async {
    final id = chatIdFor(uid, peerUid);
    final ref = _chat(id);
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set(<String, dynamic>{
        'members': <String>[uid, peerUid]..sort(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'unread': <String, dynamic>{},
      });
    }
    return id;
  }

  // --------------------------------------------------------------- messages

  Stream<List<ChatMessage>> watchMessages(String chatId, {int limit = 40}) =>
      _messages(chatId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => ChatMessage.fromDoc(chatId, doc.id, doc.data()))
                .toList(growable: false),
          );

  Future<List<ChatMessage>> fetchBefore(
    String chatId,
    DateTime before, {
    int limit = pageSize,
  }) async {
    final snapshot = await _messages(chatId)
        .orderBy('createdAt', descending: true)
        .startAfter(<Object>[Timestamp.fromDate(before)])
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => ChatMessage.fromDoc(chatId, doc.id, doc.data()))
        .toList(growable: false);
  }

  List<ChatMessage> cachedMessages(String uid, String chatId) =>
      _local.loadMessages(uid, chatId);

  List<ChatMessage> pending(String uid) => _local.loadPending(uid);

  /// Writes the message and the conversation summary together. The message id
  /// is generated by the client, so a retry or a reconnect can never create a
  /// second copy.
  Future<void> send({
    required Chat chat,
    required UserProfile author,
    required ChatMessage message,
    required bool peerMuted,
  }) async {
    final chatRef = _chat(chat.id);
    final messageRef = _messages(chat.id).doc(message.id);
    final peer = chat.peerOf(author.uid);
    final batch = _db.batch();
    batch.set(messageRef, message.toMap());
    batch.update(chatRef, <String, dynamic>{
      'lastMessage': <String, dynamic>{
        // The list row only needs a short preview, and the rules cap this
        // field, so a long message never fails to send because of it.
        'text': message.preview.length > 180
            ? '${message.preview.substring(0, 180)}…'
            : message.preview,
        'type': message.type.name,
        'senderUid': author.uid,
        'messageId': message.id,
        'at': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
      'unread.$peer': FieldValue.increment(1),
      'typing.${author.uid}': FieldValue.delete(),
      'deleted.${author.uid}': false,
    });
    await batch.commit();

    // One deterministic alert per message. Muted conversations are skipped,
    // and the rules let only the signed-in sender write this document.
    if (!peerMuted) {
      try {
        await _notifications.sendSocial(
          toUid: peer,
          actor: author,
          type: 'message',
          id: 'message_${message.id}',
          chatId: chat.id,
          text: message.preview,
        );
      } on Object {
        // The message is saved; a missing alert never fails it.
      }
    }
  }

  /// Writes a message through Firestore's offline queue and keeps a local copy
  /// so it survives the app being closed before the connection returns.
  Future<void> queueSend({
    required Chat chat,
    required UserProfile author,
    required ChatMessage message,
    required bool peerMuted,
  }) async {
    await _local.addPending(author.uid, message);
    await send(
      chat: chat,
      author: author,
      message: message,
      peerMuted: peerMuted,
    );
    await _local.removePending(author.uid, message.id);
  }

  Future<void> retry({
    required Chat chat,
    required UserProfile author,
    required ChatMessage message,
    required bool peerMuted,
  }) => queueSend(
    chat: chat,
    author: author,
    message: message.copyWith(status: ChatMessageStatus.sending),
    peerMuted: peerMuted,
  );

  Future<void> editMessage(
    String chatId,
    String messageId, {
    required String text,
  }) => _messages(chatId).doc(messageId).update(<String, dynamic>{
    'text': text.trim(),
    'editedAt': FieldValue.serverTimestamp(),
  });

  Future<void> deleteMessage(String chatId, String messageId) =>
      _messages(chatId).doc(messageId).update(<String, dynamic>{
        'deleted': true,
        'text': '',
        'mediaKey': '',
        'thumbKey': '',
        'share': FieldValue.delete(),
        'reactions': <String, dynamic>{},
        'editedAt': FieldValue.serverTimestamp(),
      });

  /// One reaction id per account per message. The transaction removes the
  /// previous reaction and adds the new one, so a double tap cannot duplicate.
  Future<void> react(
    String chatId,
    String messageId, {
    required String uid,
    required String reaction,
  }) async {
    if (!reactionIds.contains(reaction)) return;
    final ref = _messages(chatId).doc(messageId);
    await _db.runTransaction((transaction) async {
      final doc = await transaction.get(ref);
      if (!doc.exists) throw StateError('missing-message');
      final raw = doc.data()?['reactions'];
      final reactions = <String, List<String>>{};
      if (raw is Map) {
        raw.forEach((key, value) {
          if (value is List) {
            reactions['$key'] = value.whereType<String>().toList();
          }
        });
      }
      var alreadyMine = reactions[reaction]?.contains(uid) ?? false;
      for (final entry in reactions.entries) {
        entry.value.remove(uid);
      }
      if (!alreadyMine) {
        reactions.putIfAbsent(reaction, () => <String>[]).add(uid);
        alreadyMine = true;
      }
      final cleaned = <String, dynamic>{
        for (final entry in reactions.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      };
      transaction.update(ref, <String, dynamic>{'reactions': cleaned});
    });
  }

  // ---------------------------------------------------------- read/typing

  /// Marks delivered and read in a single write. Read receipts are only
  /// written when the account allows them; unread is always cleared.
  Future<void> markRead(
    String chatId, {
    required String uid,
    bool receipts = true,
  }) => _chat(chatId).update(<String, dynamic>{
    'unread.$uid': 0,
    'delivered.$uid': FieldValue.serverTimestamp(),
    if (receipts) 'lastRead.$uid': FieldValue.serverTimestamp(),
  });

  /// Throttled by the caller to at most one write every three seconds.
  Future<void> setTyping(String chatId, String uid) async {
    final key = '$chatId:$uid';
    final now = DateTime.now();
    final last = _typingWrites[key];
    if (last != null && now.difference(last).inSeconds < 3) return;
    _typingWrites[key] = now;
    try {
      await _chat(
        chatId,
      ).update(<String, dynamic>{'typing.$uid': FieldValue.serverTimestamp()});
    } on Object {
      // Offline; the next keystroke retries after the throttle window.
    }
  }

  Future<void> clearTyping(String chatId, String uid) async {
    _typingWrites.remove('$chatId:$uid');
    try {
      await _chat(chatId)
          .update(<String, dynamic>{'typing.$uid': FieldValue.delete()});
    } on Object {
      // Best effort.
    }
  }

  // --------------------------------------------------------------- flags

  Future<void> setFlag(
    String chatId,
    String uid, {
    String flag = '',
    bool value = false,
  }) async {
    if (!const <String>{'pinned', 'archived', 'muted'}.contains(flag)) return;
    await _chat(chatId).update(<String, dynamic>{'$flag.$uid': value});
  }

  Future<void> deleteForMe(String chatId, String uid) =>
      _chat(chatId).update(<String, dynamic>{
        'deleted.$uid': true,
        'unread.$uid': 0,
        'pinned.$uid': false,
        'archived.$uid': false,
      });

  Future<void> restoreForMe(String chatId, String uid) =>
      _chat(chatId).update(<String, dynamic>{'deleted.$uid': false});

  Future<void> report({
    required String reporterUid,
    required String chatId,
    required String targetUid,
    required String reason,
    String preview = '',
  }) => _db.collection('reports').add(<String, dynamic>{
    'reporterUid': reporterUid,
    'targetType': 'chat',
    'targetId': chatId,
    'targetUid': targetUid,
    'reason': reason,
    if (preview.isNotEmpty) 'preview': preview,
    'status': 'open',
    'createdAt': FieldValue.serverTimestamp(),
  });

  // ------------------------------------------------------------- privacy

  Stream<ChatPrivacy> watchPrivacy(String uid) => _db
      .collection('chatPrivacy')
      .doc(uid)
      .snapshots()
      .map((doc) => ChatPrivacy.fromDoc(doc.data()));

  Future<ChatPrivacy> fetchPrivacy(String uid) async {
    final doc = await _db.collection('chatPrivacy').doc(uid).get();
    return ChatPrivacy.fromDoc(doc.data());
  }

  Future<void> savePrivacy(String uid, ChatPrivacy privacy) =>
      _db.collection('chatPrivacy').doc(uid).set(privacy.toMap());

  Stream<ChatPresence> watchPresence(String uid) => _db
      .collection('presence')
      .doc(uid)
      .snapshots()
      .map((doc) => ChatPresence.fromDoc(doc.data()));

  Future<void> setPresence(
    String uid, {
    required bool online,
    bool writeLastSeen = true,
  }) async {
    try {
      await _db.collection('presence').doc(uid).set(<String, dynamic>{
        'online': online,
        // Hiding last-seen removes the old value instead of leaving a stale
        // timestamp behind that another client could still read.
        'lastSeen': writeLastSeen
            ? FieldValue.serverTimestamp()
            : FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on Object {
      // Presence is cosmetic; it must never break a conversation.
    }
  }

  /// Honours blocks in both directions and the peer's `whoCanMessage` choice.
  Future<bool> canMessage({
    required String uid,
    required String peerUid,
    required bool following,
  }) async {
    if (uid == peerUid) return false;
    try {
      final blocked = await Future.wait(<Future<bool>>[
        _db
            .collection('users')
            .doc(uid)
            .collection('blocked')
            .doc(peerUid)
            .get()
            .then((value) => value.exists),
        _db
            .collection('users')
            .doc(peerUid)
            .collection('blocked')
            .doc(uid)
            .get()
            .then((value) => value.exists),
      ]);
      if (blocked.any((value) => value)) return false;
      final privacy = await fetchPrivacy(peerUid);
      if (privacy.whoCanMessage == 'following' && !following) return false;
      return true;
    } on Object {
      // Offline: the rules still enforce the block on write.
      return true;
    }
  }

  Future<void> clearAccount(String uid) => _local.clearAccount(uid);
}
