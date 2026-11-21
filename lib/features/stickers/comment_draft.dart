import 'package:flutter/foundation.dart';

import '../../data/models/community.dart';

/// One comment being written: optional text plus an optional sticker.
///
/// The three supported shapes are:
/// * text only,
/// * sticker only,
/// * text above a sticker.
///
/// An empty draft is never sendable, and the text length limit is shared with
/// the repository so the composer, the reply dialog and Firestore agree.
@immutable
class CommentDraft {
  const CommentDraft({
    this.text = '',
    this.stickerId,
    this.mentions = const <MentionRef>[],
    this.animeRefs = const <AnimeRef>[],
  });

  final String text;
  final String? stickerId;
  final List<MentionRef> mentions;
  final List<AnimeRef> animeRefs;

  String get trimmedText => text.trim();

  String? get normalizedStickerId {
    final id = stickerId?.trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  bool get hasText => trimmedText.isNotEmpty;

  bool get hasSticker => normalizedStickerId != null;

  /// A sticker alone is a complete comment.
  bool get canSend => hasText || hasSticker;

  bool fits(int maxLength) => trimmedText.length <= maxLength;
}
