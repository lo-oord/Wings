import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Non-destructive description of one picture edit.
///
/// The original bytes are never modified: this object is the only source of
/// truth, it can be undone, saved with a draft, and rendered again later.
/// Nothing here depends on a widget, so it is cheap to serialise and compare.
@immutable
class PhotoEdits {
  const PhotoEdits({
    this.crop = const ui.Rect.fromLTRB(0, 0, 1, 1),
    this.quarterTurns = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.filter = PhotoFilter.none,
    this.filterStrength = 1,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.exposure = 0,
    this.temperature = 0,
    this.tint = 0,
    this.texts = const <PhotoText>[],
    this.strokes = const <PhotoStroke>[],
    this.stickers = const <PhotoSticker>[],
  });

  factory PhotoEdits.fromJson(Map<String, dynamic> json) {
    final crop = json['crop'];
    return PhotoEdits(
      crop: crop is List && crop.length == 4
          ? ui.Rect.fromLTRB(
              (crop[0] as num).toDouble(),
              (crop[1] as num).toDouble(),
              (crop[2] as num).toDouble(),
              (crop[3] as num).toDouble(),
            )
          : const ui.Rect.fromLTRB(0, 0, 1, 1),
      quarterTurns: (json['quarterTurns'] as num?)?.toInt() ?? 0,
      flipHorizontal: json['flipHorizontal'] == true,
      flipVertical: json['flipVertical'] == true,
      filter: PhotoFilter.values.firstWhere(
        (value) => value.name == json['filter'],
        orElse: () => PhotoFilter.none,
      ),
      filterStrength: (json['filterStrength'] as num?)?.toDouble() ?? 1,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      tint: (json['tint'] as num?)?.toDouble() ?? 0,
      texts: <PhotoText>[
        for (final item in (json['texts'] as List? ?? const <dynamic>[]))
          if (item is Map) PhotoText.fromJson(item.cast<String, dynamic>()),
      ],
      strokes: <PhotoStroke>[
        for (final item in (json['strokes'] as List? ?? const <dynamic>[]))
          if (item is Map) PhotoStroke.fromJson(item.cast<String, dynamic>()),
      ],
      stickers: <PhotoSticker>[
        for (final item in (json['stickers'] as List? ?? const <dynamic>[]))
          if (item is Map) PhotoSticker.fromJson(item.cast<String, dynamic>()),
      ],
    );
  }

  /// Visible part of the original picture, in normalised coordinates.
  final ui.Rect crop;
  final int quarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;
  final PhotoFilter filter;
  final double filterStrength;

  /// Each adjustment is -1…1 and 0 means "unchanged".
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final double temperature;
  final double tint;

  final List<PhotoText> texts;
  final List<PhotoStroke> strokes;
  final List<PhotoSticker> stickers;

  bool get isIdentity =>
      crop == const ui.Rect.fromLTRB(0, 0, 1, 1) &&
      quarterTurns % 4 == 0 &&
      !flipHorizontal &&
      !flipVertical &&
      filter == PhotoFilter.none &&
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      exposure == 0 &&
      temperature == 0 &&
      tint == 0 &&
      texts.isEmpty &&
      strokes.isEmpty &&
      stickers.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'crop': <double>[crop.left, crop.top, crop.right, crop.bottom],
    'quarterTurns': quarterTurns,
    'flipHorizontal': flipHorizontal,
    'flipVertical': flipVertical,
    'filter': filter.name,
    'filterStrength': filterStrength,
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'exposure': exposure,
    'temperature': temperature,
    'tint': tint,
    'texts': <Map<String, dynamic>>[for (final item in texts) item.toJson()],
    'strokes': <Map<String, dynamic>>[
      for (final item in strokes) item.toJson(),
    ],
    'stickers': <Map<String, dynamic>>[
      for (final item in stickers) item.toJson(),
    ],
  };

  PhotoEdits copyWith({
    ui.Rect? crop,
    int? quarterTurns,
    bool? flipHorizontal,
    bool? flipVertical,
    PhotoFilter? filter,
    double? filterStrength,
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? temperature,
    double? tint,
    List<PhotoText>? texts,
    List<PhotoStroke>? strokes,
    List<PhotoSticker>? stickers,
  }) => PhotoEdits(
    crop: crop ?? this.crop,
    quarterTurns: quarterTurns ?? this.quarterTurns,
    flipHorizontal: flipHorizontal ?? this.flipHorizontal,
    flipVertical: flipVertical ?? this.flipVertical,
    filter: filter ?? this.filter,
    filterStrength: filterStrength ?? this.filterStrength,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    exposure: exposure ?? this.exposure,
    temperature: temperature ?? this.temperature,
    tint: tint ?? this.tint,
    texts: texts ?? this.texts,
    strokes: strokes ?? this.strokes,
    stickers: stickers ?? this.stickers,
  );
}

/// A text placed on the picture. Positions and sizes are normalised to the
/// visible picture, so the same values render identically at every scale.
@immutable
class PhotoText {
  const PhotoText({
    required this.id,
    required this.text,
    this.x = 0.5,
    this.y = 0.5,
    this.size = 0.08,
    this.rotation = 0,
    this.color = 0xFFFFFFFF,
    this.background = 0x00000000,
    this.backgroundOpacity = 0.45,
    this.align = PhotoTextAlign.center,
    this.shadow = true,
  });

  factory PhotoText.fromJson(Map<String, dynamic> json) => PhotoText(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    x: (json['x'] as num?)?.toDouble() ?? 0.5,
    y: (json['y'] as num?)?.toDouble() ?? 0.5,
    size: (json['size'] as num?)?.toDouble() ?? 0.08,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    color: (json['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
    background: (json['background'] as num?)?.toInt() ?? 0x00000000,
    backgroundOpacity: (json['backgroundOpacity'] as num?)?.toDouble() ?? 0.45,
    align: PhotoTextAlign.values.firstWhere(
      (value) => value.name == json['align'],
      orElse: () => PhotoTextAlign.center,
    ),
    shadow: json['shadow'] != false,
  );

  final String id;
  final String text;
  final double x;
  final double y;
  final double size;
  final double rotation;
  final int color;
  final int background;
  final double backgroundOpacity;
  final PhotoTextAlign align;
  final bool shadow;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'text': text,
    'x': x,
    'y': y,
    'size': size,
    'rotation': rotation,
    'color': color,
    'background': background,
    'backgroundOpacity': backgroundOpacity,
    'align': align.name,
    'shadow': shadow,
  };

  PhotoText copyWith({
    String? text,
    double? x,
    double? y,
    double? size,
    double? rotation,
    int? color,
    int? background,
    double? backgroundOpacity,
    PhotoTextAlign? align,
    bool? shadow,
  }) => PhotoText(
    id: id,
    text: text ?? this.text,
    x: x ?? this.x,
    y: y ?? this.y,
    size: size ?? this.size,
    rotation: rotation ?? this.rotation,
    color: color ?? this.color,
    background: background ?? this.background,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    align: align ?? this.align,
    shadow: shadow ?? this.shadow,
  );
}

enum PhotoTextAlign { left, center, right }

/// One freehand stroke. Points are normalised; the width is a fraction of the
/// picture width so the line keeps its weight on every export size.
@immutable
class PhotoStroke {
  const PhotoStroke({
    required this.points,
    required this.color,
    required this.width,
  });

  factory PhotoStroke.fromJson(Map<String, dynamic> json) => PhotoStroke(
    points: <ui.Offset>[
      for (final item in (json['points'] as List? ?? const <dynamic>[]))
        if (item is List && item.length == 2)
          ui.Offset((item[0] as num).toDouble(), (item[1] as num).toDouble()),
    ],
    color: (json['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
    width: (json['width'] as num?)?.toDouble() ?? 0.012,
  );

  final List<ui.Offset> points;
  final int color;
  final double width;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'points': <List<double>>[
      for (final point in points) <double>[point.dx, point.dy],
    ],
    'color': color,
    'width': width,
  };
}

/// A sticker from the bundled catalogue placed on the picture.
@immutable
class PhotoSticker {
  const PhotoSticker({
    required this.id,
    required this.stickerId,
    required this.assetPath,
    this.x = 0.5,
    this.y = 0.5,
    this.size = 0.3,
    this.rotation = 0,
  });

  factory PhotoSticker.fromJson(Map<String, dynamic> json) => PhotoSticker(
    id: json['id'] as String? ?? '',
    stickerId: json['stickerId'] as String? ?? '',
    assetPath: json['assetPath'] as String? ?? '',
    x: (json['x'] as num?)?.toDouble() ?? 0.5,
    y: (json['y'] as num?)?.toDouble() ?? 0.5,
    size: (json['size'] as num?)?.toDouble() ?? 0.3,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
  );

  final String id;
  final String stickerId;
  final String assetPath;
  final double x;
  final double y;
  final double size;
  final double rotation;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'stickerId': stickerId,
    'assetPath': assetPath,
    'x': x,
    'y': y,
    'size': size,
    'rotation': rotation,
  };

  PhotoSticker copyWith({
    double? x,
    double? y,
    double? size,
    double? rotation,
  }) => PhotoSticker(
    id: id,
    stickerId: stickerId,
    assetPath: assetPath,
    x: x ?? this.x,
    y: y ?? this.y,
    size: size ?? this.size,
    rotation: rotation ?? this.rotation,
  );
}

/// Built-in looks. Each preset is only a colour matrix, which is why a preview
/// costs nothing: the very same matrix is applied when the file is exported.
enum PhotoFilter {
  none('بدون', 'None'),
  natural('طبيعي', 'Natural'),
  warm('دافئ', 'Warm'),
  cool('بارد', 'Cool'),
  vintage('قديم', 'Vintage'),
  cinematic('سينمائي', 'Cinematic'),
  mono('أبيض وأسود', 'Black & white'),
  soft('ناعم', 'Soft'),
  punch('حيوي', 'Vivid');

  const PhotoFilter(this.arabic, this.english);

  final String arabic;
  final String english;

  List<double> get matrix => switch (this) {
    PhotoFilter.none => identityMatrix,
    PhotoFilter.natural => const <double>[
      1.05,
      0,
      0,
      0,
      2,
      0,
      1.04,
      0,
      0,
      2,
      0,
      0,
      1.02,
      0,
      2,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoFilter.warm => const <double>[
      1.10,
      0.02,
      0,
      0,
      8,
      0.01,
      1.03,
      0,
      0,
      2,
      0,
      0,
      0.92,
      0,
      -4,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoFilter.cool => const <double>[
      0.92,
      0,
      0,
      0,
      -4,
      0,
      1.02,
      0,
      0,
      2,
      0.02,
      0.02,
      1.10,
      0,
      8,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoFilter.vintage => const <double>[
      0.90,
      0.10,
      0.05,
      0,
      10,
      0.05,
      0.88,
      0.06,
      0,
      4,
      0.04,
      0.10,
      0.78,
      0,
      -6,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoFilter.cinematic => const <double>[
      1.06,
      0,
      -0.04,
      0,
      -6,
      -0.02,
      1.02,
      0.02,
      0,
      0,
      0.02,
      -0.04,
      1.08,
      0,
      4,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoFilter.mono => const <double>[
      0.30,
      0.59,
      0.11,
      0,
      4,
      0.30,
      0.59,
      0.11,
      0,
      4,
      0.30,
      0.59,
      0.11,
      0,
      4,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoFilter.soft => const <double>[
      0.94,
      0.04,
      0.04,
      0,
      12,
      0.04,
      0.94,
      0.04,
      0,
      12,
      0.04,
      0.04,
      0.94,
      0,
      12,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoFilter.punch => const <double>[
      1.16,
      -0.06,
      -0.02,
      0,
      -6,
      -0.04,
      1.14,
      -0.04,
      0,
      -6,
      -0.02,
      -0.06,
      1.16,
      0,
      -6,
      0,
      0,
      0,
      1,
      0,
    ],
  };
}

const List<double> identityMatrix = <double>[
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

/// Multiplies two 4×5 colour matrices (the right one runs first).
List<double> multiplyColorMatrix(List<double> a, List<double> b) {
  final result = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var column = 0; column < 4; column++) {
      var value = 0.0;
      for (var index = 0; index < 4; index++) {
        value += a[row * 5 + index] * b[index * 5 + column];
      }
      result[row * 5 + column] = value;
    }
    var offset = a[row * 5 + 4];
    for (var index = 0; index < 4; index++) {
      offset += a[row * 5 + index] * b[index * 5 + 4];
    }
    result[row * 5 + 4] = offset;
  }
  return result;
}

List<double> _saturationMatrix(double value) {
  final s = value + 1;
  final lr = 0.2126, lg = 0.7152, lb = 0.0722;
  return <double>[
    lr * (1 - s) + s,
    lg * (1 - s),
    lb * (1 - s),
    0,
    0,
    lr * (1 - s),
    lg * (1 - s) + s,
    lb * (1 - s),
    0,
    0,
    lr * (1 - s),
    lg * (1 - s),
    lb * (1 - s) + s,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

/// The single matrix used by both the preview and the exported file.
List<double> colorMatrixFor(PhotoEdits edits) {
  var matrix = List<double>.of(identityMatrix);
  if (edits.filter != PhotoFilter.none && edits.filterStrength > 0) {
    final strength = edits.filterStrength.clamp(0.0, 1.0);
    final preset = edits.filter.matrix;
    matrix = multiplyColorMatrix(<double>[
      for (var index = 0; index < 20; index++)
        identityMatrix[index] +
            (preset[index] - identityMatrix[index]) * strength,
    ], matrix);
  }
  if (edits.brightness != 0) {
    final offset = edits.brightness * 90;
    matrix = multiplyColorMatrix(<double>[
      1,
      0,
      0,
      0,
      offset,
      0,
      1,
      0,
      0,
      offset,
      0,
      0,
      1,
      0,
      offset,
      0,
      0,
      0,
      1,
      0,
    ], matrix);
  }
  if (edits.exposure != 0) {
    final factor = math.pow(2, edits.exposure * 1.5).toDouble();
    matrix = multiplyColorMatrix(<double>[
      factor,
      0,
      0,
      0,
      0,
      0,
      factor,
      0,
      0,
      0,
      0,
      0,
      factor,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ], matrix);
  }
  if (edits.contrast != 0) {
    final factor = 1 + edits.contrast * 0.8;
    final offset = 128 * (1 - factor);
    matrix = multiplyColorMatrix(<double>[
      factor,
      0,
      0,
      0,
      offset,
      0,
      factor,
      0,
      0,
      offset,
      0,
      0,
      factor,
      0,
      offset,
      0,
      0,
      0,
      1,
      0,
    ], matrix);
  }
  if (edits.saturation != 0) {
    matrix = multiplyColorMatrix(_saturationMatrix(edits.saturation), matrix);
  }
  if (edits.temperature != 0) {
    matrix = multiplyColorMatrix(<double>[
      1 + edits.temperature * 0.18,
      0,
      0,
      0,
      edits.temperature * 10,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1 - edits.temperature * 0.18,
      0,
      -edits.temperature * 10,
      0,
      0,
      0,
      1,
      0,
    ], matrix);
  }
  if (edits.tint != 0) {
    matrix = multiplyColorMatrix(<double>[
      1,
      0,
      0,
      0,
      edits.tint * 8,
      0,
      1 + edits.tint * 0.14,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      edits.tint * 8,
      0,
      0,
      0,
      1,
      0,
    ], matrix);
  }
  return matrix;
}

/// Pixel size of the result after crop and rotation.
ui.Size editedSize(ui.Image image, PhotoEdits edits) {
  var width = image.width * edits.crop.width;
  var height = image.height * edits.crop.height;
  if (edits.quarterTurns % 2 != 0) {
    final swap = width;
    width = height;
    height = swap;
  }
  return ui.Size(width, height);
}

/// Source rectangle selected by [PhotoEdits.crop].
ui.Rect sourceRect(ui.Image image, PhotoEdits edits) => ui.Rect.fromLTRB(
  image.width * edits.crop.left,
  image.height * edits.crop.top,
  image.width * edits.crop.right,
  image.height * edits.crop.bottom,
);

/// Draws the whole composition in [size] — the preview and the export share
/// this code, so what the member sees is what gets encoded.
void paintPhotoEdits({
  required ui.Canvas canvas,
  required ui.Size size,
  required ui.Image image,
  required PhotoEdits edits,
  required Map<String, ui.Image> stickerImages,
}) {
  final output = editedSize(image, edits);
  if (output.width <= 0 || output.height <= 0) return;
  final scale = size.width / output.width;
  canvas.save();
  canvas.scale(scale, size.height / output.height);

  canvas.save();
  canvas.translate(output.width / 2, output.height / 2);
  canvas.rotate(edits.quarterTurns * math.pi / 2);
  canvas.scale(edits.flipHorizontal ? -1 : 1, edits.flipVertical ? -1 : 1);
  final source = sourceRect(image, edits);
  final destination = ui.Rect.fromCenter(
    center: ui.Offset.zero,
    width: source.width,
    height: source.height,
  );
  final paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.medium
    ..colorFilter = ui.ColorFilter.matrix(colorMatrixFor(edits));
  canvas.drawImageRect(image, source, destination, paint);
  canvas.restore();

  for (final stroke in edits.strokes) {
    if (stroke.points.length < 2) continue;
    final path = ui.Path()
      ..moveTo(
        stroke.points.first.dx * output.width,
        stroke.points.first.dy * output.height,
      );
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx * output.width, point.dy * output.height);
    }
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = ui.Color(stroke.color)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = stroke.width * output.width
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round,
    );
  }

  for (final sticker in edits.stickers) {
    final asset = stickerImages[sticker.assetPath];
    if (asset == null) continue;
    final width = sticker.size * output.width;
    final height = width * asset.height / asset.width;
    canvas.save();
    canvas.translate(sticker.x * output.width, sticker.y * output.height);
    canvas.rotate(sticker.rotation);
    canvas.drawImageRect(
      asset,
      ui.Rect.fromLTWH(0, 0, asset.width.toDouble(), asset.height.toDouble()),
      ui.Rect.fromCenter(center: ui.Offset.zero, width: width, height: height),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    canvas.restore();
  }

  for (final text in edits.texts) {
    _paintText(canvas, text, output);
  }
  canvas.restore();
}

void _paintText(ui.Canvas canvas, PhotoText layer, ui.Size output) {
  if (layer.text.trim().isEmpty) return;
  final fontSize = layer.size * output.width;
  final painter =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: switch (layer.align) {
              PhotoTextAlign.left => ui.TextAlign.left,
              PhotoTextAlign.center => ui.TextAlign.center,
              PhotoTextAlign.right => ui.TextAlign.right,
            },
            fontSize: fontSize,
            textDirection: ui.TextDirection.rtl,
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: ui.Color(layer.color),
            fontSize: fontSize,
            height: 1.2,
            shadows: layer.shadow
                ? const <ui.Shadow>[
                    ui.Shadow(
                      color: ui.Color(0x99000000),
                      blurRadius: 8,
                      offset: ui.Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        )
        ..addText(layer.text);
  final paragraph = painter.build()
    ..layout(ui.ParagraphConstraints(width: output.width * 0.86));
  final width = paragraph.longestLine.clamp(1.0, output.width * 0.9).toDouble();
  final height = paragraph.height;
  canvas.save();
  canvas.translate(layer.x * output.width, layer.y * output.height);
  canvas.rotate(layer.rotation);
  if (layer.backgroundOpacity > 0) {
    final background = ui.Color(layer.background)
        .withValues(alpha: layer.backgroundOpacity);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: ui.Offset.zero,
          width: width + fontSize * 0.5,
          height: height + fontSize * 0.3,
        ),
        ui.Radius.circular(fontSize * 0.25),
      ),
      ui.Paint()..color = background,
    );
  }
  canvas.translate(-width / 2, -height / 2);
  canvas.drawParagraph(paragraph, ui.Offset.zero);
  canvas.restore();
}

/// Renders the edit to PNG bytes at [maxDimension] on the long side.
///
/// Decoding and rasterising are handed to the engine, so the interface keeps
/// responding while a large picture is prepared.
Future<Uint8List> encodePhotoEdits({
  required Uint8List sourceBytes,
  required PhotoEdits edits,
  required Map<String, Uint8List> stickerAssets,
  int maxDimension = 2048,
}) async {
  final codec = await ui.instantiateImageCodec(
    sourceBytes,
    targetWidth: maxDimension,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final output = editedSize(image, edits);
  if (output.width <= 0 || output.height <= 0) {
    image.dispose();
    throw StateError('empty-crop');
  }
  final ratio = maxDimension / math.max(output.width, output.height);
  final width = (output.width * (ratio < 1 ? ratio : 1)).round().clamp(1, 8192);
  final height = (output.height * (ratio < 1 ? ratio : 1)).round().clamp(
    1,
    8192,
  );
  final stickers = <String, ui.Image>{};
  for (final entry in stickerAssets.entries) {
    final stickerCodec = await ui.instantiateImageCodec(entry.value);
    stickers[entry.key] = (await stickerCodec.getNextFrame()).image;
  }
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paintPhotoEdits(
    canvas: canvas,
    size: ui.Size(width.toDouble(), height.toDouble()),
    image: image,
    edits: edits,
    stickerImages: stickers,
  );
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(width, height);
  final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  rendered.dispose();
  for (final sticker in stickers.values) {
    sticker.dispose();
  }
  image.dispose();
  if (data == null) throw StateError('encode-failed');
  return data.buffer.asUint8List();
}
