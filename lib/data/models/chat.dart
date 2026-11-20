import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'user_profile.dart';

/// One-to-one conversations only. There is no group model in Wings.
enum ChatMessageType { text, image, video, audio, file, share }

enum ChatShareKind { anime, episode, post, reel }

/// What a shared card points at. Only ids and a small preview are stored; the
/// original content is never copied, so opening the card opens the real screen.
@immutable
class ChatShare {
  const ChatShare({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.imageUrl = '',
    this.imageKey = '',
    this.route = '',
    this.extraId = '',
  });

  final ChatShareKind kind;
  final String id;
  final String title;
  final String subtitle;

  /// A public poster URL (anime artwork) or a Tigris object key for community
  /// media. Exactly one of the two is normally set.
  final String imageUrl;
  final String imageKey;
  final String route;

  /// Episode id, anime id or original post id when the card needs two ids.
  final String extraId;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'kind': kind.name,
    'id': id,
    'title': title,
    'subtitle': subtitle,
    if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
    if (imageKey.isNotEmpty) 'imageKey': imageKey,
    if (route.isNotEmpty) 'route': route,
    if (extraId.isNotEmpty) 'extraId': extraId,
  };

  factory ChatShare.fromMap(Object? raw) {
    if (raw is! Map) {
      return const ChatShare(kind: ChatShareKind.post, id: '', title: '');
    }
    final kind = raw['kind'] as String? ?? '';
    return ChatShare(
      kind: ChatShareKind.values.firstWhere(
        (value) => value.name == kind,
        orElse: () => ChatShareKind.post,
      ),
      id: raw['id'] as String? ?? '',
      title: raw['title'] as String? ?? '',
      subtitle: raw['subtitle'] as String? ?? '',
      imageUrl: raw['imageUrl'] as String? ?? '',
      imageKey: raw['imageKey'] as String? ?? '',
      route: raw['route'] as String? ?? '',
      extraId: raw['extraId'] as String? ?? '',
    );
  }

  /// The in-app destination of this card. Unknown or missing routes are
  /// rejected instead of being handed to the router.
  String get destination {
    if (route.startsWith('/anime/') ||
        route.startsWith('/watch/') ||
        route.startsWith('/community/post/')) {
      return route;
    }
    return switch (kind) {
      ChatShareKind.anime => '/anime/$id',
      ChatShareKind.episode => '/watch/$id/$extraId',
      ChatShareKind.post || ChatShareKind.reel => '/community/post/$id',
    };
  }
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderUid,
    required this.type,
    this.text = '',
    this.mediaKey = '',
    this.mediaMime = '',
    this.mediaName = '',
    this.mediaSize = 0,
    this.mediaDurationMs = 0,
    this.thumbKey = '',
    this.mediaWidth = 0,
    this.mediaHeight = 0,
    this.replyToId = '',
    this.replyToSender = '',
    this.replyToPreview = '',
    this.replyToType = ChatMessageType.text,
    this.share,
    this.reactions = const <String, List<String>>{},
    required this.createdAt,
    this.editedAt,
    this.deleted = false,
    this.status = ChatMessageStatus.sent,
    this.failure = '',
  });

  final String id;
  final String chatId;
  final String senderUid;
  final ChatMessageType type;
  final String text;

  /// Tigris object key, never a public URL.
  final String mediaKey;
  final String mediaMime;
  final String mediaName;
  final int mediaSize;
  final int mediaDurationMs;
  final String thumbKey;
  final int mediaWidth;
  final int mediaHeight;

  final String replyToId;
  final String replyToSender;
  final String replyToPreview;
  final ChatMessageType replyToType;

  final ChatShare? share;
  final Map<String, List<String>> reactions;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool deleted;

  /// Local delivery state; server messages get their state from the chat's
  /// delivered/lastRead maps, so this is never trusted from Firestore.
  final ChatMessageStatus status;
  final String failure;

  bool get isPending =>
      status == ChatMessageStatus.sending || status == ChatMessageStatus.failed;

  bool get hasMedia =>
      mediaKey.isNotEmpty &&
      (type == ChatMessageType.image ||
          type == ChatMessageType.video ||
          type == ChatMessageType.audio ||
          type == ChatMessageType.file);

  String get preview => switch (type) {
    ChatMessageType.text => text,
    ChatMessageType.image => '📷 صورة',
    ChatMessageType.video => '🎬 فيديو',
    ChatMessageType.audio => '🎤 رسالة صوتية',
    ChatMessageType.file => '📎 ${mediaName.isEmpty ? 'ملف' : mediaName}',
    ChatMessageType.share => '🔗 ${share?.title ?? 'محتوى'}',
  };

  ChatMessage copyWith({
    String? text,
    ChatMessageType? type,
    String? mediaKey,
    String? mediaMime,
    String? mediaName,
    int? mediaSize,
    int? mediaDurationMs,
    String? thumbKey,
    int? mediaWidth,
    int? mediaHeight,
    String? replyToId,
    String? replyToSender,
    String? replyToPreview,
    ChatMessageType? replyToType,
    ChatShare? share,
    Map<String, List<String>>? reactions,
    DateTime? createdAt,
    DateTime? editedAt,
    bool? deleted,
    ChatMessageStatus? status,
    String? failure,
  }) => ChatMessage(
    id: id,
    chatId: chatId,
    senderUid: senderUid,
    type: type ?? this.type,
    text: text ?? this.text,
    mediaKey: mediaKey ?? this.mediaKey,
    mediaMime: mediaMime ?? this.mediaMime,
    mediaName: mediaName ?? this.mediaName,
    mediaSize: mediaSize ?? this.mediaSize,
    mediaDurationMs: mediaDurationMs ?? this.mediaDurationMs,
    thumbKey: thumbKey ?? this.thumbKey,
    mediaWidth: mediaWidth ?? this.mediaWidth,
    mediaHeight: mediaHeight ?? this.mediaHeight,
    replyToId: replyToId ?? this.replyToId,
    replyToSender: replyToSender ?? this.replyToSender,
    replyToPreview: replyToPreview ?? this.replyToPreview,
    replyToType: replyToType ?? this.replyToType,
    share: share ?? this.share,
    reactions: reactions ?? this.reactions,
    createdAt: createdAt ?? this.createdAt,
    editedAt: editedAt ?? this.editedAt,
    deleted: deleted ?? this.deleted,
    status: status ?? this.status,
    failure: failure ?? this.failure,
  );

  Map<String, dynamic> toMap() => <String, dynamic>{
    'senderUid': senderUid,
    'type': type.name,
    'text': text,
    'mediaKey': mediaKey,
    'mediaMime': mediaMime,
    'mediaName': mediaName,
    'mediaSize': mediaSize,
    'mediaDurationMs': mediaDurationMs,
    'thumbKey': thumbKey,
    'mediaWidth': mediaWidth,
    'mediaHeight': mediaHeight,
    'replyToId': replyToId,
    'replyToSender': replyToSender,
    'replyToPreview': replyToPreview,
    'replyToType': replyToType.name,
    if (share != null) 'share': share!.toMap(),
    'reactions': reactions.map(
      (key, value) => MapEntry<String, dynamic>(key, value),
    ),
    'createdAt': FieldValue.serverTimestamp(),
    'editedAt': editedAt == null ? null : Timestamp.fromDate(editedAt!),
    'deleted': deleted,
  };

  Map<String, dynamic> toLocalJson() => <String, dynamic>{
    'id': id,
    'chatId': chatId,
    'senderUid': senderUid,
    'type': type.name,
    'text': text,
    'mediaKey': mediaKey,
    'mediaMime': mediaMime,
    'mediaName': mediaName,
    'mediaSize': mediaSize,
    'mediaDurationMs': mediaDurationMs,
    'thumbKey': thumbKey,
    'mediaWidth': mediaWidth,
    'mediaHeight': mediaHeight,
    'replyToId': replyToId,
    'replyToSender': replyToSender,
    'replyToPreview': replyToPreview,
    'replyToType': replyToType.name,
    if (share != null) 'share': share!.toMap(),
    'reactions': reactions,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'editedAt': editedAt?.millisecondsSinceEpoch,
    'deleted': deleted,
    'status': status.name,
    'failure': failure,
  };

  factory ChatMessage.fromLocalJson(Map<String, dynamic> raw) => ChatMessage(
    id: raw['id'] as String? ?? '',
    chatId: raw['chatId'] as String? ?? '',
    senderUid: raw['senderUid'] as String? ?? '',
    type: _typeFrom(raw['type']),
    text: raw['text'] as String? ?? '',
    mediaKey: raw['mediaKey'] as String? ?? '',
    mediaMime: raw['mediaMime'] as String? ?? '',
    mediaName: raw['mediaName'] as String? ?? '',
    mediaSize: (raw['mediaSize'] as num?)?.toInt() ?? 0,
    mediaDurationMs: (raw['mediaDurationMs'] as num?)?.toInt() ?? 0,
    thumbKey: raw['thumbKey'] as String? ?? '',
    mediaWidth: (raw['mediaWidth'] as num?)?.toInt() ?? 0,
    mediaHeight: (raw['mediaHeight'] as num?)?.toInt() ?? 0,
    replyToId: raw['replyToId'] as String? ?? '',
    replyToSender: raw['replyToSender'] as String? ?? '',
    replyToPreview: raw['replyToPreview'] as String? ?? '',
    replyToType: _typeFrom(raw['replyToType']),
    share: raw['share'] == null ? null : ChatShare.fromMap(raw['share']),
    reactions: _reactionsFrom(raw['reactions']),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (raw['createdAt'] as num?)?.toInt() ?? 0,
    ),
    editedAt: raw['editedAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch((raw['editedAt'] as num).toInt())
        : null,
    deleted: raw['deleted'] == true,
    status: ChatMessageStatus.values.firstWhere(
      (value) => value.name == raw['status'],
      orElse: () => ChatMessageStatus.sent,
    ),
    failure: raw['failure'] as String? ?? '',
  );

  factory ChatMessage.fromDoc(
    String chatId,
    String id,
    Map<String, dynamic> raw,
  ) => ChatMessage(
    id: id,
    chatId: chatId,
    senderUid: raw['senderUid'] as String? ?? '',
    type: _typeFrom(raw['type']),
    text: raw['text'] as String? ?? '',
    mediaKey: raw['mediaKey'] as String? ?? '',
    mediaMime: raw['mediaMime'] as String? ?? '',
    mediaName: raw['mediaName'] as String? ?? '',
    mediaSize: (raw['mediaSize'] as num?)?.toInt() ?? 0,
    mediaDurationMs: (raw['mediaDurationMs'] as num?)?.toInt() ?? 0,
    thumbKey: raw['thumbKey'] as String? ?? '',
    mediaWidth: (raw['mediaWidth'] as num?)?.toInt() ?? 0,
    mediaHeight: (raw['mediaHeight'] as num?)?.toInt() ?? 0,
    replyToId: raw['replyToId'] as String? ?? '',
    replyToSender: raw['replyToSender'] as String? ?? '',
    replyToPreview: raw['replyToPreview'] as String? ?? '',
    replyToType: _typeFrom(raw['replyToType']),
    share: raw['share'] == null ? null : ChatShare.fromMap(raw['share']),
    reactions: _reactionsFrom(raw['reactions']),
    createdAt: raw['createdAt'] is Timestamp
        ? (raw['createdAt'] as Timestamp).toDate()
        : DateTime.fromMillisecondsSinceEpoch(0),
    editedAt: raw['editedAt'] is Timestamp
        ? (raw['editedAt'] as Timestamp).toDate()
        : null,
    deleted: raw['deleted'] == true,
    status: ChatMessageStatus.sent,
  );

  static ChatMessageType _typeFrom(Object? raw) =>
      ChatMessageType.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => ChatMessageType.text,
      );

  static Map<String, List<String>> _reactionsFrom(Object? raw) {
    if (raw is! Map) return const <String, List<String>>{};
    final result = <String, List<String>>{};
    raw.forEach((key, value) {
      if (value is List) {
        final uids = value.whereType<String>().toList(growable: false);
        if (uids.isNotEmpty) result['$key'] = uids;
      }
    });
    return result;
  }
}

enum ChatMessageStatus { sending, sent, delivered, read, failed }

/// One conversation document. All per-member state lives in uid-keyed maps so
/// opening, reading, pinning or muting never creates a second collection and
/// never needs an extra listener.
@immutable
class Chat {
  const Chat({
    required this.id,
    required this.members,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageText = '',
    this.lastMessageType = ChatMessageType.text,
    this.lastSenderUid = '',
    this.lastMessageAt,
    this.lastMessageId = '',
    this.unread = const <String, int>{},
    this.typing = const <String, DateTime>{},
    this.lastRead = const <String, DateTime>{},
    this.delivered = const <String, DateTime>{},
    this.pinned = const <String, bool>{},
    this.archived = const <String, bool>{},
    this.muted = const <String, bool>{},
    this.deleted = const <String, bool>{},
    this.peer,
  });

  final String id;
  final List<String> members;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastMessageText;
  final ChatMessageType lastMessageType;
  final String lastSenderUid;
  final DateTime? lastMessageAt;
  final String lastMessageId;
  final Map<String, int> unread;
  final Map<String, DateTime> typing;
  final Map<String, DateTime> lastRead;
  final Map<String, DateTime> delivered;
  final Map<String, bool> pinned;
  final Map<String, bool> archived;
  final Map<String, bool> muted;
  final Map<String, bool> deleted;

  /// Filled in by the list provider from batched public profiles.
  final UserProfile? peer;

  String peerOf(String uid) =>
      members.firstWhere((member) => member != uid, orElse: () => '');

  int unreadFor(String uid) => unread[uid] ?? 0;

  bool pinnedFor(String uid) => pinned[uid] == true;
  bool archivedFor(String uid) => archived[uid] == true;
  bool mutedFor(String uid) => muted[uid] == true;
  bool deletedFor(String uid) => deleted[uid] == true;

  bool peerTyping(String uid, DateTime now) {
    final peer = peerOf(uid);
    final at = typing[peer];
    return at != null && now.difference(at).inSeconds < 7;
  }

  Chat copyWith({
    String? lastMessageText,
    ChatMessageType? lastMessageType,
    String? lastSenderUid,
    DateTime? lastMessageAt,
    String? lastMessageId,
    Map<String, int>? unread,
    Map<String, DateTime>? typing,
    Map<String, DateTime>? lastRead,
    Map<String, DateTime>? delivered,
    Map<String, bool>? pinned,
    Map<String, bool>? archived,
    Map<String, bool>? muted,
    Map<String, bool>? deleted,
    UserProfile? peer,
  }) => Chat(
    id: id,
    members: members,
    createdAt: createdAt,
    updatedAt: updatedAt,
    lastMessageText: lastMessageText ?? this.lastMessageText,
    lastMessageType: lastMessageType ?? this.lastMessageType,
    lastSenderUid: lastSenderUid ?? this.lastSenderUid,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    lastMessageId: lastMessageId ?? this.lastMessageId,
    unread: unread ?? this.unread,
    typing: typing ?? this.typing,
    lastRead: lastRead ?? this.lastRead,
    delivered: delivered ?? this.delivered,
    pinned: pinned ?? this.pinned,
    archived: archived ?? this.archived,
    muted: muted ?? this.muted,
    deleted: deleted ?? this.deleted,
    peer: peer ?? this.peer,
  );

  Map<String, dynamic> toLocalJson(String uid) => <String, dynamic>{
    'id': id,
    'members': members,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'lastMessageText': lastMessageText,
    'lastMessageType': lastMessageType.name,
    'lastSenderUid': lastSenderUid,
    'lastMessageAt': lastMessageAt?.millisecondsSinceEpoch,
    'lastMessageId': lastMessageId,
    'unread': unreadFor(uid),
    'typing': typing.map((k, v) => MapEntry(k, v.millisecondsSinceEpoch)),
    'lastRead': lastRead.map((k, v) => MapEntry(k, v.millisecondsSinceEpoch)),
    'delivered': delivered.map((k, v) => MapEntry(k, v.millisecondsSinceEpoch)),
    'pinned': pinnedFor(uid),
    'archived': archivedFor(uid),
    'muted': mutedFor(uid),
    'deleted': deletedFor(uid),
    'peerUid': peerOf(uid),
    if (peer != null)
      'peer': <String, dynamic>{
        'username': peer!.username,
        'normalizedUsername': peer!.normalizedUsername,
        'displayName': peer!.displayName,
        'badges': peer!.badges.toMap(),
        'photoVersion': peer!.photoVersion,
        'private': peer!.profileHidden,
      },
  };

  factory Chat.fromLocalJson(Map<String, dynamic> raw, String uid) {
    DateTime? read(Object? value) => value is num
        ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
        : null;
    final peerUid = raw['peerUid'] as String? ?? '';
    final peerMap = raw['peer'];
    return Chat(
      id: raw['id'] as String? ?? '',
      members: <String>[uid, if (peerUid.isNotEmpty) peerUid],
      createdAt: read(raw['createdAt']) ?? DateTime.now(),
      updatedAt: read(raw['updatedAt']) ?? DateTime.now(),
      lastMessageText: raw['lastMessageText'] as String? ?? '',
      lastMessageType: ChatMessage._typeFrom(raw['lastMessageType']),
      lastSenderUid: raw['lastSenderUid'] as String? ?? '',
      lastMessageAt: read(raw['lastMessageAt']),
      lastMessageId: raw['lastMessageId'] as String? ?? '',
      unread: <String, int>{uid: (raw['unread'] as num?)?.toInt() ?? 0},
      typing: <String, DateTime>{
        for (final entry
            in (raw['typing'] as Map? ?? const <String, dynamic>{}).entries)
          '${entry.key}': read(entry.value) ?? DateTime.now(),
      },
      lastRead: <String, DateTime>{
        for (final entry
            in (raw['lastRead'] as Map? ?? const <String, dynamic>{}).entries)
          '${entry.key}': read(entry.value) ?? DateTime.now(),
      },
      delivered: <String, DateTime>{
        for (final entry
            in (raw['delivered'] as Map? ?? const <String, dynamic>{}).entries)
          '${entry.key}': read(entry.value) ?? DateTime.now(),
      },
      pinned: <String, bool>{uid: raw['pinned'] == true},
      archived: <String, bool>{uid: raw['archived'] == true},
      muted: <String, bool>{uid: raw['muted'] == true},
      deleted: <String, bool>{uid: raw['deleted'] == true},
      peer: peerMap is Map
          ? UserProfile.fromPublicMap(
              peerUid,
              Map<String, dynamic>.from(peerMap),
            )
          : null,
    );
  }

  factory Chat.fromDoc(String id, Map<String, dynamic> raw) {
    DateTime? read(Object? value) => value is Timestamp ? value.toDate() : null;
    Map<String, DateTime> times(Object? value) {
      if (value is! Map) return const <String, DateTime>{};
      final result = <String, DateTime>{};
      value.forEach((key, item) {
        if (item is Timestamp) result['$key'] = item.toDate();
      });
      return result;
    }

    Map<String, bool> flags(Object? value) {
      if (value is! Map) return const <String, bool>{};
      final result = <String, bool>{};
      value.forEach((key, item) {
        if (item == true) result['$key'] = true;
      });
      return result;
    }

    Map<String, int> numbers(Object? value) {
      if (value is! Map) return const <String, int>{};
      final result = <String, int>{};
      value.forEach((key, item) {
        if (item is num) result['$key'] = item.toInt();
      });
      return result;
    }

    final last = raw['lastMessage'];
    final lastMap = last is Map ? last : const <String, dynamic>{};
    return Chat(
      id: id,
      members:
          (raw['members'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[],
      createdAt: read(raw['createdAt']) ?? DateTime.now(),
      updatedAt: read(raw['updatedAt']) ?? DateTime.now(),
      lastMessageText: lastMap['text'] as String? ?? '',
      lastMessageType: ChatMessage._typeFrom(lastMap['type']),
      lastSenderUid: lastMap['senderUid'] as String? ?? '',
      lastMessageAt: lastMap['at'] is Timestamp
          ? (lastMap['at'] as Timestamp).toDate()
          : null,
      lastMessageId: lastMap['messageId'] as String? ?? '',
      unread: numbers(raw['unread']),
      typing: times(raw['typing']),
      lastRead: times(raw['lastRead']),
      delivered: times(raw['delivered']),
      pinned: flags(raw['pinned']),
      archived: flags(raw['archived']),
      muted: flags(raw['muted']),
      deleted: flags(raw['deleted']),
    );
  }
}

/// Per-account chat privacy. The defaults are the friendly ones, and the
/// document is optional: an account that never opened the settings keeps the
/// defaults.
@immutable
class ChatPrivacy {
  const ChatPrivacy({
    this.showLastSeen = true,
    this.showOnline = true,
    this.readReceipts = true,
    this.whoCanMessage = 'everyone',
  });

  static const ChatPrivacy defaults = ChatPrivacy();

  final bool showLastSeen;
  final bool showOnline;
  final bool readReceipts;

  /// `everyone` or `following`.
  final String whoCanMessage;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'showLastSeen': showLastSeen,
    'showOnline': showOnline,
    'readReceipts': readReceipts,
    'whoCanMessage': whoCanMessage,
  };

  factory ChatPrivacy.fromDoc(Map<String, dynamic>? raw) {
    if (raw == null) return defaults;
    return ChatPrivacy(
      showLastSeen: raw['showLastSeen'] != false,
      showOnline: raw['showOnline'] != false,
      readReceipts: raw['readReceipts'] != false,
      whoCanMessage: raw['whoCanMessage'] == 'following'
          ? 'following'
          : 'everyone',
    );
  }
}

@immutable
class ChatPresence {
  const ChatPresence({this.online = false, this.lastSeen});

  final bool online;
  final DateTime? lastSeen;

  factory ChatPresence.fromDoc(Map<String, dynamic>? raw) => ChatPresence(
    online: raw?['online'] == true,
    lastSeen: raw?['lastSeen'] is Timestamp
        ? (raw!['lastSeen'] as Timestamp).toDate()
        : null,
  );
}
