import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/chat.dart';
import 'package:wings/features/chat/chat_providers.dart';

Chat _chat({
  Map<String, DateTime> lastRead = const <String, DateTime>{},
  Map<String, DateTime> delivered = const <String, DateTime>{},
}) => Chat(
  id: 'a_b',
  members: const <String>['a', 'b'],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  lastRead: lastRead,
  delivered: delivered,
);

ChatMessage _message({
  DateTime? createdAt,
  ChatMessageStatus status = ChatMessageStatus.sent,
}) => ChatMessage(
  id: 'm1',
  chatId: 'a_b',
  senderUid: 'a',
  type: ChatMessageType.text,
  text: 'hello',
  createdAt: createdAt ?? DateTime(2026, 1, 1, 12),
  status: status,
);

void main() {
  group('ChatShare', () {
    test('round-trips through its stored map', () {
      const share = ChatShare(
        kind: ChatShareKind.episode,
        id: 'ep-1',
        title: 'Frieren',
        subtitle: 'الحلقة 3',
        imageUrl: 'https://example.com/poster.jpg',
        route: '/watch/anime-1/ep-1',
        extraId: 'anime-1',
      );

      final restored = ChatShare.fromMap(share.toMap());

      expect(restored.kind, ChatShareKind.episode);
      expect(restored.id, 'ep-1');
      expect(restored.extraId, 'anime-1');
      expect(restored.route, '/watch/anime-1/ep-1');
      expect(restored.destination, '/watch/anime-1/ep-1');
    });

    test('falls back to a safe route and ignores foreign routes', () {
      const post = ChatShare(kind: ChatShareKind.post, id: 'p1', title: 'x');
      const reel = ChatShare(kind: ChatShareKind.reel, id: 'p2', title: 'y');
      const anime = ChatShare(
        kind: ChatShareKind.anime,
        id: 'a1',
        title: 'z',
        route: 'javascript:alert(1)',
      );

      expect(post.destination, '/community/post/p1');
      expect(reel.destination, '/community/post/p2');
      expect(anime.destination, '/anime/a1');
    });

    test('a missing or malformed map never throws', () {
      final share = ChatShare.fromMap(<String, dynamic>{'kind': 'unknown'});
      expect(share.kind, ChatShareKind.post);
      expect(share.id, '');
    });
  });

  group('ChatMessage', () {
    test('maps media, reply and share from a Firestore document', () {
      final message = ChatMessage.fromDoc('a_b', 'm9', <String, dynamic>{
        'senderUid': 'a',
        'type': 'share',
        'text': 'look',
        'mediaKey': 'chat/a_b/m9.jpg',
        'mediaMime': 'image/jpeg',
        'mediaName': 'photo.jpg',
        'mediaSize': 1200,
        'mediaDurationMs': 0,
        'thumbKey': '',
        'mediaWidth': 800,
        'mediaHeight': 600,
        'replyToId': 'm1',
        'replyToSender': 'b',
        'replyToPreview': 'hi',
        'replyToType': 'text',
        'share': <String, dynamic>{
          'kind': 'anime',
          'id': 'a1',
          'title': 'Frieren',
          'route': '/anime/a1',
        },
        'reactions': <String, dynamic>{
          'heart': <String>['b'],
        },
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 2)),
        'deleted': false,
      });

      expect(message.type, ChatMessageType.share);
      expect(message.mediaKey, 'chat/a_b/m9.jpg');
      expect(message.mediaWidth, 800);
      expect(message.replyToPreview, 'hi');
      expect(message.share?.kind, ChatShareKind.anime);
      expect(message.reactions['heart'], <String>['b']);
      expect(message.hasMedia, isFalse);
      expect(message.status, ChatMessageStatus.sent);
    });

    test('a deleted tombstone drops its preview text', () {
      final message = ChatMessage.fromDoc('a_b', 'm9', <String, dynamic>{
        'senderUid': 'a',
        'type': 'image',
        'text': '',
        'mediaKey': '',
        'deleted': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 2)),
      });
      expect(message.deleted, isTrue);
      expect(message.hasMedia, isFalse);
      expect(message.preview, '📷 صورة');
    });

    test('local JSON keeps the pending state and media metadata', () {
      final original = _message(status: ChatMessageStatus.failed).copyWith(
        mediaKey: 'chat/a_b/voice.m4a',
        mediaName: 'voice.m4a',
        mediaDurationMs: 4200,
        type: ChatMessageType.audio,
      );
      final restored = ChatMessage.fromLocalJson(original.toLocalJson());

      expect(restored.id, original.id);
      expect(restored.type, ChatMessageType.audio);
      expect(restored.mediaDurationMs, 4200);
      expect(restored.status, ChatMessageStatus.failed);
    });
  });

  group('Chat', () {
    test('per-member maps and peer typing are scoped to the reader', () {
      final now = DateTime(2026, 3, 3, 10);
      final chat = Chat(
        id: 'a_b',
        members: const <String>['a', 'b'],
        createdAt: now,
        updatedAt: now,
        unread: const <String, int>{'a': 3, 'b': 1},
        typing: <String, DateTime>{'b': now},
        pinned: const <String, bool>{'a': true},
        muted: const <String, bool>{'b': true},
      );

      expect(chat.peerOf('a'), 'b');
      expect(chat.unreadFor('a'), 3);
      expect(chat.pinnedFor('a'), isTrue);
      expect(chat.pinnedFor('b'), isFalse);
      expect(chat.mutedFor('b'), isTrue);
      expect(chat.peerTyping('a', now.add(const Duration(seconds: 3))), isTrue);
      expect(
        chat.peerTyping('a', now.add(const Duration(seconds: 9))),
        isFalse,
      );
    });

    test('fromDoc reads the last-message summary and flags', () {
      final chat = Chat.fromDoc('a_b', <String, dynamic>{
        'members': <String>['a', 'b'],
        'createdAt': Timestamp.fromDate(DateTime(2026)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
        'lastMessage': <String, dynamic>{
          'text': 'مرحبا',
          'type': 'text',
          'senderUid': 'b',
          'messageId': 'm2',
          'at': Timestamp.fromDate(DateTime(2026, 1, 2)),
        },
        'unread': <String, dynamic>{'a': 2},
        'deleted': <String, dynamic>{'a': true},
      });

      expect(chat.lastMessageText, 'مرحبا');
      expect(chat.lastSenderUid, 'b');
      expect(chat.lastMessageId, 'm2');
      expect(chat.unreadFor('a'), 2);
      expect(chat.deletedFor('a'), isTrue);
      expect(chat.deletedFor('b'), isFalse);
    });
  });

  group('messageStatus', () {
    final sentAt = DateTime(2026, 5, 5, 12);
    final chat = _chat();

    test('shows sent until the peer receives it', () {
      expect(
        messageStatus(
          _message(createdAt: sentAt),
          chat: chat,
          uid: 'a',
        ),
        ChatMessageStatus.sent,
      );
    });

    test('shows delivered, then read, from the chat timestamps', () {
      final delivered = _chat(
        delivered: <String, DateTime>{
          'b': sentAt.add(const Duration(seconds: 1)),
        },
      );
      final read = _chat(
        delivered: <String, DateTime>{
          'b': sentAt.add(const Duration(seconds: 1)),
        },
        lastRead: <String, DateTime>{
          'b': sentAt.add(const Duration(seconds: 2)),
        },
      );

      expect(
        messageStatus(
          _message(createdAt: sentAt),
          chat: delivered,
          uid: 'a',
        ),
        ChatMessageStatus.delivered,
      );
      expect(
        messageStatus(
          _message(createdAt: sentAt),
          chat: read,
          uid: 'a',
        ),
        ChatMessageStatus.read,
      );
    });

    test('a read time before the message does not mark it read', () {
      final stale = _chat(
        lastRead: <String, DateTime>{
          'b': sentAt.subtract(const Duration(minutes: 1)),
        },
      );
      expect(
        messageStatus(
          _message(createdAt: sentAt),
          chat: stale,
          uid: 'a',
        ),
        ChatMessageStatus.sent,
      );
    });

    test('a failed message keeps its failure even with receipts', () {
      final read = _chat(
        lastRead: <String, DateTime>{
          'b': sentAt.add(const Duration(minutes: 1)),
        },
      );
      expect(
        messageStatus(
          _message(createdAt: sentAt, status: ChatMessageStatus.failed),
          chat: read,
          uid: 'a',
        ),
        ChatMessageStatus.failed,
      );
    });

    test('messages from the other member are not outgoing', () {
      expect(
        messageStatus(
          _message(createdAt: sentAt),
          chat: chat,
          uid: 'b',
        ),
        ChatMessageStatus.read,
      );
    });
  });
}
