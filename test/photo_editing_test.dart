import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:wings/core/services/photo_editing.dart';
import 'package:wings/data/models/community.dart';
import 'package:wings/data/repositories/community_draft_repository.dart';

ui.Image fakeImage(int width, int height) => throw UnimplementedError();

void main() {
  group('PhotoEdits', () {
    test('round-trips every layer through JSON', () {
      const edits = PhotoEdits(
        crop: ui.Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
        quarterTurns: 1,
        flipHorizontal: true,
        filter: PhotoFilter.cinematic,
        filterStrength: 0.6,
        brightness: 0.2,
        contrast: -0.3,
        saturation: 0.4,
        temperature: -0.1,
        tint: 0.05,
        texts: <PhotoText>[
          PhotoText(id: 't1', text: 'أنمي', x: 0.3, y: 0.4, size: 0.1),
        ],
        strokes: <PhotoStroke>[
          PhotoStroke(
            points: <ui.Offset>[ui.Offset(0.1, 0.1), ui.Offset(0.4, 0.5)],
            color: 0xFFFF0000,
            width: 0.02,
          ),
        ],
        stickers: <PhotoSticker>[
          PhotoSticker(
            id: 's1',
            stickerId: 'cb_love',
            assetPath: 'assets/stickers/chibi/cb_love.webp',
          ),
        ],
      );
      final copy = PhotoEdits.fromJson(edits.toJson());
      expect(copy.crop, edits.crop);
      expect(copy.quarterTurns, 1);
      expect(copy.flipHorizontal, isTrue);
      expect(copy.filter, PhotoFilter.cinematic);
      expect(copy.filterStrength, closeTo(0.6, 0.0001));
      expect(copy.texts.single.text, 'أنمي');
      expect(copy.strokes.single.points.length, 2);
      expect(copy.stickers.single.stickerId, 'cb_love');
    });

    test('identity detection and reset', () {
      expect(const PhotoEdits().isIdentity, isTrue);
      expect(const PhotoEdits(brightness: 0.1).isIdentity, isFalse);
      expect(
        const PhotoEdits(
          texts: <PhotoText>[PhotoText(id: 'a', text: 'x')],
        ).isIdentity,
        isFalse,
      );
    });
  });

  group('render maths', () {
    test('identity matrix changes nothing', () {
      expect(colorMatrixFor(const PhotoEdits()), identityMatrix);
    });

    test('black & white equalises the channels', () {
      final matrix = colorMatrixFor(const PhotoEdits(filter: PhotoFilter.mono));
      final red = <double>[255, 0, 0, 1];
      final out = <double>[
        for (var row = 0; row < 3; row++)
          matrix[row * 5] * red[0] +
              matrix[row * 5 + 1] * red[1] +
              matrix[row * 5 + 2] * red[2] +
              matrix[row * 5 + 3] * red[3] +
              matrix[row * 5 + 4],
      ];
      expect(out[0], closeTo(out[1], 1));
      expect(out[1], closeTo(out[2], 1));
    });

    test('odd rotations swap the exported size', () {
      final size = editedSize(
        _SizeImage(1000, 500),
        const PhotoEdits(quarterTurns: 1),
      );
      expect(size.width, 500);
      expect(size.height, 1000);
    });

    test('crop narrows the exported size', () {
      final size = editedSize(
        _SizeImage(1000, 500),
        const PhotoEdits(crop: ui.Rect.fromLTRB(0, 0, 0.5, 0.5)),
      );
      expect(size.width, 500);
      expect(size.height, 250);
    });
  });

  group('CommunityDraft', () {
    test('round-trips text, pictures and references', () {
      const draft = CommunityDraft(
        uid: 'u1',
        text: 'منشور',
        imagePaths: <String>['/tmp/a.jpg'],
        mentions: <MentionRef>[MentionRef(uid: 'u2', username: 'sara')],
        animeRefs: <AnimeRef>[AnimeRef(id: 'a1', title: 'One Piece')],
        episodeRef: EpisodeRef(
          animeId: 'a1',
          episodeId: 'e4',
          animeTitle: 'One Piece',
          episodeNumber: 4,
          season: 2,
        ),
        category: 'أنمي',
      );
      final copy = CommunityDraft.fromJson(draft.toJson());
      expect(copy.text, 'منشور');
      expect(copy.imagePaths.single, '/tmp/a.jpg');
      expect(copy.mentions.single.username, 'sara');
      expect(copy.animeRefs.single.title, 'One Piece');
      expect(copy.episodeRef?.season, 2);
      expect(copy.category, 'أنمي');
      expect(copy.isEmpty, isFalse);
    });

    test('an empty draft is reported as empty', () {
      expect(const CommunityDraft(uid: 'u1').isEmpty, isTrue);
    });
  });
}

/// `editedSize` only reads the pixel size, so a tiny stand-in keeps the test
/// free of real decoding.
class _SizeImage implements ui.Image {
  _SizeImage(this.width, this.height);

  @override
  final int width;

  @override
  final int height;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
