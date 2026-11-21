import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/community.dart';
import '../../core/storage/local_store.dart';

/// One unpublished post kept on this device.
@immutable
class CommunityDraft {
  const CommunityDraft({
    required this.uid,
    this.text = '',
    this.imagePaths = const <String>[],
    this.mentions = const <MentionRef>[],
    this.animeRefs = const <AnimeRef>[],
    this.episodeRef,
    this.category = '',
    this.savedAt,
  });

  factory CommunityDraft.fromJson(Map<String, dynamic> json) => CommunityDraft(
    uid: json['uid'] as String? ?? '',
    text: json['text'] as String? ?? '',
    imagePaths: <String>[
      for (final item in (json['imagePaths'] as List? ?? const <dynamic>[]))
        if (item is String) item,
    ],
    mentions: <MentionRef>[
      for (final item in (json['mentions'] as List? ?? const <dynamic>[]))
        if (item is Map)
          MentionRef(
            uid: item['uid'] as String? ?? '',
            username: item['username'] as String? ?? '',
          ),
    ],
    animeRefs: <AnimeRef>[
      for (final item in (json['animeRefs'] as List? ?? const <dynamic>[]))
        if (item is Map)
          AnimeRef(
            id: item['id'] as String? ?? '',
            title: item['title'] as String? ?? '',
            imageUrl: item['imageUrl'] as String? ?? '',
          ),
    ],
    episodeRef: json['episodeRef'] is Map
        ? EpisodeRef.fromMap(json['episodeRef'])
        : null,
    category: json['category'] as String? ?? '',
    savedAt: json['savedAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(json['savedAt'] as int)
        : null,
  );

  final String uid;
  final String text;
  final List<String> imagePaths;
  final List<MentionRef> mentions;
  final List<AnimeRef> animeRefs;
  final EpisodeRef? episodeRef;
  final String category;
  final DateTime? savedAt;

  bool get isEmpty =>
      text.trim().isEmpty &&
      imagePaths.isEmpty &&
      mentions.isEmpty &&
      animeRefs.isEmpty &&
      episodeRef == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uid': uid,
    'text': text,
    'imagePaths': imagePaths,
    'mentions': <Map<String, dynamic>>[
      for (final item in mentions)
        <String, dynamic>{'uid': item.uid, 'username': item.username},
    ],
    'animeRefs': <Map<String, dynamic>>[
      for (final item in animeRefs)
        <String, dynamic>{
          'id': item.id,
          'title': item.title,
          'imageUrl': item.imageUrl,
        },
    ],
    if (episodeRef != null) 'episodeRef': episodeRef!.toMap(),
    'category': category,
    'savedAt': DateTime.now().millisecondsSinceEpoch,
  };
}

/// Drafts live in their own key, never in the published feed: saving one makes
/// no network request and creates no document.
///
/// Pictures are copied into the application documents directory before being
/// referenced, because the picker hands back cache files Android may delete.
class CommunityDraftRepository {
  CommunityDraftRepository(this._store);

  final LocalStore _store;

  static const String _box = LocalStore.cacheBox;
  String _key(String uid) => 'community_draft_v1_$uid';

  CommunityDraft? load(String uid) {
    final raw = _store.getJson(_box, _key(uid));
    if (raw is! Map) return null;
    final draft = CommunityDraft.fromJson(raw.cast<String, dynamic>());
    return draft.isEmpty ? null : draft;
  }

  Future<CommunityDraft> save({
    required String uid,
    required String text,
    required List<String> sourcePaths,
    required List<MentionRef> mentions,
    required List<AnimeRef> animeRefs,
    EpisodeRef? episodeRef,
    String category = '',
  }) async {
    final draft = CommunityDraft(
      uid: uid,
      text: text,
      imagePaths: await _persistPictures(uid, sourcePaths),
      mentions: mentions,
      animeRefs: animeRefs,
      episodeRef: episodeRef,
      category: category,
    );
    await _store.putJson(_box, _key(uid), draft.toJson());
    return draft;
  }

  Future<void> clear(String uid) => _store.delete(_box, _key(uid));

  Future<List<String>> _persistPictures(String uid, List<String> paths) async {
    if (paths.isEmpty) return const <String>[];
    try {
      final root = await getApplicationDocumentsDirectory();
      final directory = Directory('${root.path}/drafts/$uid');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final kept = <String>[];
      for (var index = 0; index < paths.length; index++) {
        final source = File(paths[index]);
        if (!await source.exists()) continue;
        final extension = source.path.split('.').last.toLowerCase();
        final target = File(
          '${directory.path}/${DateTime.now().millisecondsSinceEpoch}_$index.'
          '${extension.length <= 5 ? extension : 'jpg'}',
        );
        await source.copy(target.path);
        kept.add(target.path);
      }
      return kept;
    } on Object {
      // A device without writable storage keeps the in-memory list; the draft
      // still restores its text.
      return const <String>[];
    }
  }

  Future<List<Uint8List>> readPictures(List<String> paths) async {
    final result = <Uint8List>[];
    for (final path in paths) {
      try {
        result.add(await File(path).readAsBytes());
      } on Object {
        // One missing file must not throw the whole draft away.
      }
    }
    return result;
  }

  /// Removes the pictures a cleared draft owns.
  Future<void> deletePictures(List<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } on Object {
        // Already gone.
      }
    }
  }

  String encode(CommunityDraft draft) => jsonEncode(draft.toJson());
}
