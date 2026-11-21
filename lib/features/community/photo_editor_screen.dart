import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/services/photo_editing.dart';
import '../../core/utils/tr.dart';
import '../../data/models/sticker_catalog.dart';
import '../stickers/sticker_providers.dart';

/// The result of an edit: the encoded bytes and the temporary file that holds
/// them. Callers keep the bytes for the upload and the file for previews.
class EditedPhoto {
  const EditedPhoto({required this.bytes, required this.file});

  final Uint8List bytes;
  final File file;
}

/// Opens the Wings photo editor. Returns null when the member leaves without
/// saving anything.
Future<EditedPhoto?> openPhotoEditor(
  BuildContext context, {
  required Uint8List bytes,
  PhotoEdits? initial,
  String title = 'تعديل الصورة',
}) {
  return Navigator.of(context).push<EditedPhoto>(
    MaterialPageRoute<EditedPhoto>(
      fullscreenDialog: true,
      builder: (_) =>
          PhotoEditorScreen(bytes: bytes, initial: initial, title: title),
    ),
  );
}

enum _Tool { adjust, filters, crop, text, draw, stickers }

/// A real editor: every control changes the same [PhotoEdits] object that the
/// export renders, so the saved file is exactly the preview. Undo/redo keeps
/// the whole history, and leaving with unsaved edits asks first.
class PhotoEditorScreen extends ConsumerStatefulWidget {
  const PhotoEditorScreen({
    super.key,
    required this.bytes,
    this.initial,
    this.title = 'تعديل الصورة',
  });

  final Uint8List bytes;
  final PhotoEdits? initial;
  final String title;

  @override
  ConsumerState<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends ConsumerState<PhotoEditorScreen> {
  late PhotoEdits _edits = widget.initial ?? const PhotoEdits();
  final List<PhotoEdits> _undo = <PhotoEdits>[];
  final List<PhotoEdits> _redo = <PhotoEdits>[];
  final Map<String, ui.Image> _stickerImages = <String, ui.Image>{};

  ui.Image? _image;
  Object? _loadError;
  bool _saving = false;
  _Tool _tool = _Tool.adjust;

  String? _selectedText;
  String? _selectedSticker;
  PhotoEdits? _gestureStart;
  List<Offset>? _stroke;

  int _counter = 0;

  @override
  void initState() {
    super.initState();
    _decode();
    _primeStickers();
  }

  @override
  void dispose() {
    _image?.dispose();
    for (final image in _stickerImages.values) {
      image.dispose();
    }
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(
        widget.bytes,
        targetWidth: 1600,
      );
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } on Object catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Decodes the stickers already on the picture so the preview shows them.
  Future<void> _primeStickers() async {
    for (final sticker in _edits.stickers) {
      await _loadSticker(sticker.assetPath);
    }
  }

  Future<void> _loadSticker(String path) async {
    if (_stickerImages.containsKey(path)) return;
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 512,
      );
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _stickerImages[path] = frame.image);
    } on Object {
      // A retired sticker asset simply is not drawn.
    }
  }

  void _remember(PhotoEdits next, {bool snapshot = true}) {
    if (next == _edits) return;
    if (snapshot) {
      _undo.add(_edits);
      if (_undo.length > 40) _undo.removeAt(0);
      _redo.clear();
    }
    setState(() => _edits = next);
  }

  void _undoEdit() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_edits);
      _edits = _undo.removeLast();
    });
  }

  void _redoEdit() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_edits);
      _edits = _redo.removeLast();
    });
  }

  void _beginGesture() {
    _gestureStart = _edits;
  }

  void _endGesture() {
    final start = _gestureStart;
    _gestureStart = null;
    if (start == null || start == _edits) return;
    _undo.add(start);
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  Future<bool> _confirmDiscard() async {
    if (_edits == (widget.initial ?? const PhotoEdits())) return true;
    final keep = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          Tr.of(context, ar: 'تجاهل التعديلات؟', en: 'Discard edits?'),
        ),
        content: Text(
          Tr.of(
            context,
            ar: 'لم تحفظ التعديلات بعد. سيتم فقدانها إذا خرجت الآن.',
            en: 'Your edits are not saved yet and will be lost.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(
              Tr.of(context, ar: 'متابعة التعديل', en: 'Keep editing'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(Tr.of(context, ar: 'تجاهل', en: 'Discard')),
          ),
        ],
      ),
    );
    return keep ?? false;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final stickers = <String, Uint8List>{};
      for (final sticker in _edits.stickers) {
        final data = await rootBundle.load(sticker.assetPath);
        stickers[sticker.assetPath] = data.buffer.asUint8List();
      }
      final encoded = await encodePhotoEdits(
        sourceBytes: widget.bytes,
        edits: _edits,
        stickerAssets: stickers,
      );
      // The publishing pipeline only accepts pictures under 5 MiB, so the
      // editor encodes a JPEG that already fits instead of handing the upload
      // a PNG it would reject.
      var quality = 90;
      var width = 1440;
      var bytes = encoded;
      for (var attempt = 0; attempt < 3; attempt++) {
        final compressed = await FlutterImageCompress.compressWithList(
          encoded,
          minWidth: width,
          minHeight: width,
          quality: quality,
          format: CompressFormat.jpeg,
        );
        if (compressed.length <= 4 * 1024 * 1024) {
          bytes = compressed;
          break;
        }
        quality -= 12;
        width = (width * 0.8).round();
      }
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/wings_edit_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      Navigator.of(context).pop(EditedPhoto(bytes: bytes, file: file));
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Tr.of(
                context,
                ar: 'تعذّر حفظ الصورة. حاول مرة أخرى.',
                en: 'The picture could not be saved. Try again.',
              ),
            ),
          ),
        );
        debugPrint('photo editor save failed: $error');
      }
    }
  }

  // ------------------------------------------------------------------ crop

  void _cropPreset(double? aspect) {
    final image = _image;
    if (image == null) return;
    if (aspect == null) {
      _remember(_edits.copyWith(crop: const ui.Rect.fromLTRB(0, 0, 1, 1)));
      return;
    }
    final width = image.width * _edits.crop.width;
    // Keep the selected area inside the original picture.
    var w = width;
    var h = w / aspect;
    if (h > image.height) {
      h = image.height.toDouble();
      w = h * aspect;
    }
    final cx = _edits.crop.center.dx * image.width;
    final cy = _edits.crop.center.dy * image.height;
    final rect = ui.Rect.fromCenter(center: Offset(cx, cy), width: w, height: h)
        .intersect(
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
        );
    _remember(
      _edits.copyWith(
        crop: ui.Rect.fromLTRB(
          rect.left / image.width,
          rect.top / image.height,
          rect.right / image.width,
          rect.bottom / image.height,
        ),
      ),
    );
  }

  void _cropZoom(double factor) {
    final image = _image;
    if (image == null) return;
    final crop = _edits.crop;
    final center = crop.center;
    final halfW = (crop.width * factor / 2).clamp(0.05, 0.5);
    final halfH = (crop.height * factor / 2).clamp(0.05, 0.5);
    final rect = ui.Rect.fromLTRB(
      (center.dx - halfW).clamp(0.0, 1.0),
      (center.dy - halfH).clamp(0.0, 1.0),
      (center.dx + halfW).clamp(0.0, 1.0),
      (center.dy + halfH).clamp(0.0, 1.0),
    );
    _remember(_edits.copyWith(crop: rect));
  }

  void _moveCrop(Offset delta, Size box) {
    final crop = _edits.crop;
    final dx = delta.dx / math.max(box.width, 1) * crop.width;
    final dy = delta.dy / math.max(box.height, 1) * crop.height;
    final newLeft = (crop.left - dx).clamp(0.0, 1.0 - crop.width);
    final newTop = (crop.top - dy).clamp(0.0, 1.0 - crop.height);
    _remember(
      _edits.copyWith(
        crop: ui.Rect.fromLTWH(newLeft, newTop, crop.width, crop.height),
      ),
      snapshot: false,
    );
  }

  // ------------------------------------------------------------------ text

  Future<void> _addText() async {
    final text = await _textDialog();
    if (text == null || text.trim().isEmpty) return;
    final layer = PhotoText(id: _newId('text'), text: text.trim());
    _remember(_edits.copyWith(texts: <PhotoText>[..._edits.texts, layer]));
    setState(() {
      _selectedText = layer.id;
      _selectedSticker = null;
      _tool = _Tool.text;
    });
  }

  Future<String?> _textDialog([String initial = '']) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          Tr.of(context, ar: 'نص على الصورة', en: 'Text on the picture'),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 120,
          decoration: InputDecoration(
            hintText: Tr.of(context, ar: 'اكتب النص…', en: 'Type the text…'),
          ),
          onSubmitted: (value) => Navigator.of(dialog).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(controller.text),
            child: Text(Tr.of(context, ar: 'إضافة', en: 'Add')),
          ),
        ],
      ),
    );
  }

  PhotoText? get _activeText {
    for (final layer in _edits.texts) {
      if (layer.id == _selectedText) return layer;
    }
    return null;
  }

  PhotoSticker? get _activeSticker {
    for (final sticker in _edits.stickers) {
      if (sticker.id == _selectedSticker) return sticker;
    }
    return null;
  }

  void _updateText(
    PhotoText Function(PhotoText value) transform, {
    bool snapshot = true,
  }) {
    final index = _edits.texts.indexWhere((item) => item.id == _selectedText);
    if (index < 0) return;
    final texts = List<PhotoText>.of(_edits.texts);
    texts[index] = transform(texts[index]);
    _remember(_edits.copyWith(texts: texts), snapshot: snapshot);
  }

  void _updateSticker(
    PhotoSticker Function(PhotoSticker value) transform, {
    bool snapshot = true,
  }) {
    final index = _edits.stickers.indexWhere(
      (item) => item.id == _selectedSticker,
    );
    if (index < 0) return;
    final stickers = List<PhotoSticker>.of(_edits.stickers);
    stickers[index] = transform(stickers[index]);
    _remember(_edits.copyWith(stickers: stickers), snapshot: snapshot);
  }

  void _removeText() {
    if (_activeText == null) return;
    _remember(
      _edits.copyWith(
        texts: _edits.texts.where((item) => item.id != _selectedText).toList(),
      ),
    );
    setState(() => _selectedText = null);
  }

  void _removeSticker() {
    if (_activeSticker == null) return;
    _remember(
      _edits.copyWith(
        stickers: _edits.stickers
            .where((item) => item.id != _selectedSticker)
            .toList(),
      ),
    );
    setState(() => _selectedSticker = null);
  }

  void _reorder(bool forward) {
    final sticker = _activeSticker;
    if (sticker == null) return;
    final list = List<PhotoSticker>.of(_edits.stickers);
    final index = list.indexWhere((item) => item.id == sticker.id);
    final target = forward ? index + 1 : index - 1;
    if (target < 0 || target >= list.length) return;
    list.removeAt(index);
    list.insert(target, sticker);
    _remember(_edits.copyWith(stickers: list));
  }

  Future<void> _addSticker() async {
    final sticker = await showModalBottomSheet<Sticker>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => _StickerPicker(sheetContext: sheet),
    );
    if (sticker == null || !mounted) return;
    await _loadSticker(sticker.assetPath);
    final layer = PhotoSticker(
      id: _newId('sticker'),
      stickerId: sticker.id,
      assetPath: sticker.assetPath,
    );
    _remember(
      _edits.copyWith(stickers: <PhotoSticker>[..._edits.stickers, layer]),
    );
    setState(() {
      _selectedSticker = layer.id;
      _selectedText = null;
      _tool = _Tool.stickers;
    });
  }

  // ------------------------------------------------------------------ draw

  void _startStroke(Offset local, Size box) {
    _beginGesture();
    _stroke = <Offset>[Offset(local.dx / box.width, local.dy / box.height)];
    setState(() {});
  }

  void _extendStroke(Offset local, Size box) {
    final points = _stroke;
    if (points == null) return;
    points.add(Offset(local.dx / box.width, local.dy / box.height));
    setState(() {});
  }

  void _endStroke() {
    final points = _stroke;
    _stroke = null;
    if (points == null || points.length < 2) {
      setState(() {});
      return;
    }
    final stroke = PhotoStroke(
      points: points,
      color: _drawColor,
      width: _drawWidth,
    );
    if (_erasing) {
      // The eraser removes whole strokes it passes over; the original picture is
      // untouched.
      final remaining = <PhotoStroke>[];
      for (final existing in _edits.strokes) {
        final hit = existing.points.any(
          (point) => points.any((erased) => (point - erased).distance < 0.06),
        );
        if (!hit) remaining.add(existing);
      }
      _remember(_edits.copyWith(strokes: remaining));
    } else {
      _remember(
        _edits.copyWith(strokes: <PhotoStroke>[..._edits.strokes, stroke]),
      );
    }
  }

  int _drawColor = 0xFFFFFFFF;
  double _drawWidth = 0.012;
  bool _erasing = false;

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final image = _image;
    return PopScope<EditedPhoto>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (!context.mounted || !discard) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              final discard = await _confirmDiscard();
              if (!context.mounted || !discard) return;
              Navigator.of(context).pop();
            },
          ),
          title: Text(
            Tr.of(context, ar: widget.title, en: 'Edit picture'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: Tr.of(context, ar: 'تراجع', en: 'Undo'),
              onPressed: _undo.isEmpty ? null : _undoEdit,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: Tr.of(context, ar: 'إعادة', en: 'Redo'),
              onPressed: _redo.isEmpty ? null : _redoEdit,
              icon: const Icon(Icons.redo_rounded),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.sm),
              child: FilledButton(
                onPressed: _saving || image == null ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.primary,
                  foregroundColor: palette.onPrimary,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        Tr.of(context, ar: 'حفظ', en: 'Save'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: _loadError != null
                  ? Center(
                      child: Text(
                        Tr.of(
                          context,
                          ar: 'تعذّر فتح هذه الصورة.',
                          en: 'This picture could not be opened.',
                        ),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : image == null
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _preview(image),
            ),
            _toolbar(context),
          ],
        ),
      ),
    );
  }

  Widget _preview(ui.Image image) {
    final output = editedSize(image, _edits);
    final ratio = output.width <= 0 || output.height <= 0
        ? 1.0
        : output.width / output.height;
    return Center(
      child: AspectRatio(
        aspectRatio: ratio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final box = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) => _onPanStart(details.localPosition, box),
              onPanUpdate: (details) =>
                  _onPanUpdate(details.localPosition, details.delta, box),
              onPanEnd: (_) => _onPanEnd(),
              onTapUp: (details) => _onTap(details.localPosition, box),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CustomPaint(
                    painter: _EditorPainter(
                      image: image,
                      edits: _edits,
                      drawCrop: _tool == _Tool.crop,
                      liveStroke: _stroke,
                      liveColor: _drawColor,
                      liveWidth: _drawWidth,
                      stickerImages: _stickerImages,
                    ),
                  ),
                  if (_tool == _Tool.crop)
                    CustomPaint(painter: _CropOverlayPainter(_edits.crop)),
                  if (_activeText != null || _activeSticker != null)
                    CustomPaint(
                      painter: _SelectionPainter(
                        text: _activeText,
                        sticker: _activeSticker,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _onPanStart(Offset local, Size box) {
    if (_tool == _Tool.draw) {
      _startStroke(local, box);
      return;
    }
    if (_tool == _Tool.crop) {
      _beginGesture();
      return;
    }
    final sticker = _activeSticker;
    if (sticker != null && _tool == _Tool.stickers) {
      _beginGesture();
      return;
    }
    final text = _activeText;
    if (text != null && _tool == _Tool.text) {
      _beginGesture();
    }
  }

  void _onPanUpdate(Offset local, Offset delta, Size box) {
    if (_tool == _Tool.draw) {
      _extendStroke(local, box);
      return;
    }
    if (_tool == _Tool.crop) {
      _moveCrop(delta, box);
      return;
    }
    if (_tool == _Tool.text && _activeText != null) {
      _updateText(
        (value) => value.copyWith(
          x: (value.x + delta.dx / box.width).clamp(0.02, 0.98),
          y: (value.y + delta.dy / box.height).clamp(0.02, 0.98),
        ),
        snapshot: false,
      );
    } else if (_tool == _Tool.stickers && _activeSticker != null) {
      _updateSticker(
        (value) => value.copyWith(
          x: (value.x + delta.dx / box.width).clamp(0.02, 0.98),
          y: (value.y + delta.dy / box.height).clamp(0.02, 0.98),
        ),
        snapshot: false,
      );
    }
  }

  void _onPanEnd() {
    if (_tool == _Tool.draw) {
      _endStroke();
      return;
    }
    _endGesture();
  }

  void _onTap(Offset local, Size box) {
    if (_tool != _Tool.text && _tool != _Tool.stickers) return;
    final nx = local.dx / box.width;
    final ny = local.dy / box.height;
    String? textId;
    var best = 0.12;
    for (final layer in _edits.texts) {
      final distance = (Offset(layer.x, layer.y) - Offset(nx, ny)).distance;
      if (distance < best) {
        best = distance;
        textId = layer.id;
      }
    }
    String? stickerId;
    best = 0.18;
    for (final sticker in _edits.stickers.reversed) {
      final distance = (Offset(sticker.x, sticker.y) - Offset(nx, ny)).distance;
      if (distance < best) {
        best = distance;
        stickerId = sticker.id;
      }
    }
    setState(() {
      if (stickerId != null) {
        _selectedSticker = stickerId;
        _selectedText = null;
      } else if (textId != null) {
        _selectedText = textId;
        _selectedSticker = null;
      }
    });
  }

  Widget _toolbar(BuildContext context) {
    final palette = context.palette;
    return Container(
      color: const Color(0xFF101312),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_tool == _Tool.adjust) _adjustPanel(palette),
            if (_tool == _Tool.filters) _filtersPanel(palette),
            if (_tool == _Tool.crop) _cropPanel(palette),
            if (_tool == _Tool.text) _textPanel(palette),
            if (_tool == _Tool.draw) _drawPanel(palette),
            if (_tool == _Tool.stickers) _stickerPanel(palette),
            const Divider(height: 1, color: Colors.white12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: 6,
              ),
              child: Row(
                children: <Widget>[
                  _toolChip('ضبط', 'Adjust', Icons.tune_rounded, _Tool.adjust),
                  _toolChip(
                    'فلاتر',
                    'Filters',
                    Icons.auto_awesome_rounded,
                    _Tool.filters,
                  ),
                  _toolChip('قص', 'Crop', Icons.crop_rounded, _Tool.crop),
                  _toolChip(
                    'نص',
                    'Text',
                    Icons.text_fields_rounded,
                    _Tool.text,
                  ),
                  _toolChip('رسم', 'Draw', Icons.brush_rounded, _Tool.draw),
                  _toolChip(
                    'ملصقات',
                    'Stickers',
                    Icons.emoji_emotions_outlined,
                    _Tool.stickers,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolChip(String ar, String en, IconData icon, _Tool tool) {
    final palette = context.palette;
    final active = _tool == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: () => setState(() => _tool = tool),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? palette.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 20,
                color: active ? palette.primary : Colors.white70,
              ),
              const SizedBox(height: 3),
              Text(
                Tr.of(context, ar: ar, en: en),
                style: TextStyle(
                  fontSize: 9,
                  color: active ? palette.primary : Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required VoidCallback onStart,
    required VoidCallback onEnd,
    String Function(double value)? format,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChangeStart: (_) => onStart(),
              onChanged: onChanged,
              onChangeEnd: (_) => onEnd(),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              format?.call(value) ?? value.toStringAsFixed(2),
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adjustPanel(WingsPalette palette) {
    Widget adjustment(
      String ar,
      String en,
      double value,
      PhotoEdits Function(double value) apply,
    ) => _slider(
      label: Tr.of(context, ar: ar, en: en),
      value: value,
      min: -1,
      max: 1,
      onStart: _beginGesture,
      onChanged: (next) => _remember(apply(next), snapshot: false),
      onEnd: _endGesture,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        adjustment(
          'السطوع',
          'Brightness',
          _edits.brightness,
          (value) => _edits.copyWith(brightness: value),
        ),
        adjustment(
          'التباين',
          'Contrast',
          _edits.contrast,
          (value) => _edits.copyWith(contrast: value),
        ),
        adjustment(
          'التشبع',
          'Saturation',
          _edits.saturation,
          (value) => _edits.copyWith(saturation: value),
        ),
        adjustment(
          'التعريض',
          'Exposure',
          _edits.exposure,
          (value) => _edits.copyWith(exposure: value),
        ),
        adjustment(
          'الحرارة',
          'Temperature',
          _edits.temperature,
          (value) => _edits.copyWith(temperature: value),
        ),
        adjustment(
          'الميل اللوني',
          'Tint',
          _edits.tint,
          (value) => _edits.copyWith(tint: value),
        ),
      ],
    );
  }

  Widget _filtersPanel(WingsPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 74,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: 8,
            ),
            itemCount: PhotoFilter.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final filter = PhotoFilter.values[index];
              final active = filter == _edits.filter;
              return InkWell(
                borderRadius: BorderRadius.circular(Radii.sm),
                onTap: () => _remember(_edits.copyWith(filter: filter)),
                child: Container(
                  width: 62,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: active ? palette.primary : Colors.white24,
                    ),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        height: 26,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: filter == PhotoFilter.none
                                ? const <Color>[
                                    Color(0xFF3A3F3C),
                                    Color(0xFF6E756F),
                                  ]
                                : <Color>[
                                    Color.fromARGB(
                                      255,
                                      (60 + (filter.index * 25) % 160).clamp(
                                        0,
                                        255,
                                      ),
                                      (140 - filter.index * 9).clamp(0, 255),
                                      (120 + filter.index * 13) % 200,
                                    ),
                                    Color.fromARGB(
                                      255,
                                      (150 - filter.index * 7).clamp(0, 255),
                                      (90 + filter.index * 15) % 210,
                                      (60 + filter.index * 19).clamp(0, 255),
                                    ),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Tr.of(context, ar: filter.arabic, en: filter.english),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8,
                          color: active ? palette.primary : Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _slider(
          label: Tr.of(context, ar: 'شدة الفلتر', en: 'Strength'),
          value: _edits.filterStrength,
          min: 0,
          max: 1,
          onStart: _beginGesture,
          onChanged: (value) => _remember(
            _edits.copyWith(filterStrength: value),
            snapshot: false,
          ),
          onEnd: _endGesture,
          format: (value) => '${(value * 100).round()}%',
        ),
        TextButton.icon(
          onPressed: () => _remember(
            _edits.copyWith(filter: PhotoFilter.none, filterStrength: 1),
          ),
          icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
          label: Text(Tr.of(context, ar: 'إزالة الفلتر', en: 'Remove filter')),
        ),
      ],
    );
  }

  Widget _cropPanel(WingsPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: 6,
          ),
          child: Row(
            children: <Widget>[
              _chip('حر', 'Free', () => _cropPreset(null)),
              _chip('1:1', '1:1', () => _cropPreset(1)),
              _chip('4:5', '4:5', () => _cropPreset(4 / 5)),
              _chip('16:9', '16:9', () => _cropPreset(16 / 9)),
              _chip('9:16', '9:16', () => _cropPreset(9 / 16)),
              const SizedBox(width: 8),
              IconButton(
                tooltip: Tr.of(context, ar: 'تدوير', en: 'Rotate'),
                onPressed: () => _remember(
                  _edits.copyWith(quarterTurns: (_edits.quarterTurns + 1) % 4),
                ),
                icon: const Icon(
                  Icons.rotate_90_degrees_cw_rounded,
                  color: Colors.white70,
                ),
              ),
              IconButton(
                tooltip: Tr.of(
                  context,
                  ar: 'قلب أفقي',
                  en: 'Flip horizontally',
                ),
                onPressed: () => _remember(
                  _edits.copyWith(flipHorizontal: !_edits.flipHorizontal),
                ),
                icon: const Icon(Icons.flip_rounded, color: Colors.white70),
              ),
              IconButton(
                tooltip: Tr.of(context, ar: 'قلب رأسي', en: 'Flip vertically'),
                onPressed: () => _remember(
                  _edits.copyWith(flipVertical: !_edits.flipVertical),
                ),
                icon: const Icon(
                  Icons.flip_camera_android_rounded,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              Tr.of(context, ar: 'تكبير القص', en: 'Crop zoom'),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            IconButton(
              tooltip: Tr.of(context, ar: 'أوسع', en: 'Wider'),
              onPressed: () => _cropZoom(1.15),
              icon: const Icon(Icons.zoom_out_rounded, color: Colors.white70),
            ),
            IconButton(
              tooltip: Tr.of(context, ar: 'أضيق', en: 'Tighter'),
              onPressed: () => _cropZoom(0.87),
              icon: const Icon(Icons.zoom_in_rounded, color: Colors.white70),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            Tr.of(
              context,
              ar: 'اسحب داخل الصورة لتحريك إطار القص.',
              en: 'Drag inside the picture to move the crop frame.',
            ),
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
        ),
      ],
    );
  }

  Widget _chip(String ar, String en, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: Colors.white24),
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(
          Tr.of(context, ar: ar, en: en),
          style: const TextStyle(fontSize: 10),
        ),
      ),
    );
  }

  Widget _textPanel(WingsPalette palette) {
    final text = _activeText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(width: Space.md),
            FilledButton.icon(
              onPressed: _addText,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(Tr.of(context, ar: 'إضافة نص', en: 'Add text')),
            ),
            const Spacer(),
            if (text != null) ...<Widget>[
              IconButton(
                tooltip: Tr.of(context, ar: 'تعديل النص', en: 'Edit text'),
                onPressed: () async {
                  final value = await _textDialog(text.text);
                  if (value == null || value.trim().isEmpty) return;
                  _updateText((layer) => layer.copyWith(text: value.trim()));
                },
                icon: const Icon(Icons.edit_rounded, color: Colors.white70),
              ),
              IconButton(
                tooltip: Tr.of(context, ar: 'حذف', en: 'Delete'),
                onPressed: _removeText,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
        if (text == null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md, top: 4),
            child: Text(
              Tr.of(
                context,
                ar: 'أضف نصًا ثم اسحبه على الصورة.',
                en: 'Add a text, then drag it on the picture.',
              ),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          )
        else ...<Widget>[
          _slider(
            label: Tr.of(context, ar: 'الحجم', en: 'Size'),
            value: text.size,
            min: 0.03,
            max: 0.3,
            onStart: _beginGesture,
            onChanged: (value) => _updateText(
              (layer) => layer.copyWith(size: value),
              snapshot: false,
            ),
            onEnd: _endGesture,
            format: (value) => '${(value * 100).round()}',
          ),
          _slider(
            label: Tr.of(context, ar: 'الدوران', en: 'Rotation'),
            value: text.rotation,
            min: -math.pi,
            max: math.pi,
            onStart: _beginGesture,
            onChanged: (value) => _updateText(
              (layer) => layer.copyWith(rotation: value),
              snapshot: false,
            ),
            onEnd: _endGesture,
            format: (value) => '${(value * 180 / math.pi).round()}°',
          ),
          _slider(
            label: Tr.of(context, ar: 'الشفافية', en: 'Background'),
            value: text.backgroundOpacity,
            min: 0,
            max: 1,
            onStart: _beginGesture,
            onChanged: (value) => _updateText(
              (layer) => layer.copyWith(backgroundOpacity: value),
              snapshot: false,
            ),
            onEnd: _endGesture,
            format: (value) => '${(value * 100).round()}%',
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              children: <Widget>[
                for (final color in _paletteColors)
                  GestureDetector(
                    onTap: () =>
                        _updateText((layer) => layer.copyWith(color: color)),
                    child: Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      decoration: BoxDecoration(
                        color: Color(color),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: text.color == color
                              ? palette.primary
                              : Colors.white24,
                          width: text.color == color ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static const List<int> _paletteColors = <int>[
    0xFFFFFFFF,
    0xFF111111,
    0xFF5BE38A,
    0xFFFFD54F,
    0xFFFF6B6B,
    0xFF64B5F6,
    0xFFBA68C8,
  ];

  Widget _drawPanel(WingsPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(width: Space.md),
            for (final color in _paletteColors)
              GestureDetector(
                onTap: () => setState(() {
                  _drawColor = color;
                  _erasing = false;
                }),
                child: Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _drawColor == color && !_erasing
                          ? palette.primary
                          : Colors.white24,
                      width: 2,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            IconButton(
              tooltip: Tr.of(context, ar: 'ممحاة', en: 'Eraser'),
              onPressed: () => setState(() => _erasing = !_erasing),
              icon: Icon(
                Icons.cleaning_services_rounded,
                color: _erasing ? palette.primary : Colors.white70,
              ),
            ),
            IconButton(
              tooltip: Tr.of(context, ar: 'مسح الرسم', en: 'Clear drawing'),
              onPressed: () =>
                  _remember(_edits.copyWith(strokes: const <PhotoStroke>[])),
              icon: const Icon(
                Icons.layers_clear_rounded,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        _slider(
          label: Tr.of(context, ar: 'سماكة القلم', en: 'Brush'),
          value: _drawWidth,
          min: 0.004,
          max: 0.05,
          onStart: () {},
          onChanged: (value) => setState(() => _drawWidth = value),
          onEnd: () {},
          format: (value) => '${(value * 1000).round()}',
        ),
      ],
    );
  }

  Widget _stickerPanel(WingsPalette palette) {
    final sticker = _activeSticker;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(width: Space.md),
            FilledButton.icon(
              onPressed: _addSticker,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(Tr.of(context, ar: 'إضافة ملصق', en: 'Add sticker')),
            ),
            const Spacer(),
            if (sticker != null) ...<Widget>[
              IconButton(
                tooltip: Tr.of(context, ar: 'للأمام', en: 'Bring forward'),
                onPressed: () => _reorder(true),
                icon: const Icon(
                  Icons.flip_to_front_rounded,
                  color: Colors.white70,
                ),
              ),
              IconButton(
                tooltip: Tr.of(context, ar: 'للخلف', en: 'Send backward'),
                onPressed: () => _reorder(false),
                icon: const Icon(
                  Icons.flip_to_back_rounded,
                  color: Colors.white70,
                ),
              ),
              IconButton(
                tooltip: Tr.of(context, ar: 'حذف', en: 'Delete'),
                onPressed: _removeSticker,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
        if (sticker == null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md, top: 4),
            child: Text(
              Tr.of(
                context,
                ar: 'اختر ملصقًا ثم اسحبه أو غيّر حجمه.',
                en: 'Pick a sticker, then drag, scale or rotate it.',
              ),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          )
        else ...<Widget>[
          _slider(
            label: Tr.of(context, ar: 'الحجم', en: 'Size'),
            value: sticker.size,
            min: 0.1,
            max: 0.9,
            onStart: _beginGesture,
            onChanged: (value) => _updateSticker(
              (layer) => layer.copyWith(size: value),
              snapshot: false,
            ),
            onEnd: _endGesture,
            format: (value) => '${(value * 100).round()}%',
          ),
          _slider(
            label: Tr.of(context, ar: 'الدوران', en: 'Rotation'),
            value: sticker.rotation,
            min: -math.pi,
            max: math.pi,
            onStart: _beginGesture,
            onChanged: (value) => _updateSticker(
              (layer) => layer.copyWith(rotation: value),
              snapshot: false,
            ),
            onEnd: _endGesture,
            format: (value) => '${(value * 180 / math.pi).round()}°',
          ),
        ],
      ],
    );
  }
}

class _EditorPainter extends CustomPainter {
  _EditorPainter({
    required this.image,
    required this.edits,
    required this.drawCrop,
    required this.stickerImages,
    this.liveStroke,
    this.liveColor = 0xFFFFFFFF,
    this.liveWidth = 0.012,
  });

  final ui.Image image;
  final PhotoEdits edits;
  final bool drawCrop;
  final Map<String, ui.Image> stickerImages;
  final List<Offset>? liveStroke;
  final int liveColor;
  final double liveWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (drawCrop) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF101312),
      );
      final output = editedSize(
        image,
        edits.copyWith(crop: const ui.Rect.fromLTRB(0, 0, 1, 1)),
      );
      final scale = math.min(
        size.width / math.max(output.width, 1),
        size.height / math.max(output.height, 1),
      );
      canvas.save();
      canvas.translate(
        (size.width - output.width * scale) / 2,
        (size.height - output.height * scale) / 2,
      );
      paintPhotoEdits(
        canvas: canvas,
        size: Size(output.width * scale, output.height * scale),
        image: image,
        edits: edits.copyWith(crop: const ui.Rect.fromLTRB(0, 0, 1, 1)),
        stickerImages: stickerImages,
      );
      canvas.restore();
    } else {
      paintPhotoEdits(
        canvas: canvas,
        size: size,
        image: image,
        edits: edits,
        stickerImages: stickerImages,
      );
    }
    final stroke = liveStroke;
    if (stroke != null && stroke.length > 1) {
      final path = Path()
        ..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Color(liveColor)
          ..style = PaintingStyle.stroke
          ..strokeWidth = liveWidth * size.width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_EditorPainter old) =>
      old.edits != edits ||
      old.stickerImages.length != stickerImages.length ||
      old.liveStroke != liveStroke ||
      old.liveColor != liveColor ||
      old.liveWidth != liveWidth ||
      old.drawCrop != drawCrop;
}

class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter(this.crop);

  final ui.Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) => old.crop != crop;
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter({this.text, this.sticker});

  final PhotoText? text;
  final PhotoSticker? sticker;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF5BE38A);
    if (sticker != null) {
      final box = sticker!.size;
      final rect = Rect.fromCenter(
        center: Offset(sticker!.x * size.width, sticker!.y * size.height),
        width: box * size.width,
        height: box * size.width,
      );
      canvas.drawRect(rect, paint);
    }
    if (text != null) {
      final center = Offset(text!.x * size.width, text!.y * size.height);
      final width = math.max(
        60.0,
        text!.size * size.width * math.max(text!.text.length, 1) * 0.5,
      );
      final height = math.max(24.0, text!.size * size.width * 1.4);
      canvas.drawRect(
        Rect.fromCenter(center: center, width: width, height: height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => true;
}

class _StickerPicker extends ConsumerStatefulWidget {
  const _StickerPicker({required this.sheetContext});

  final BuildContext sheetContext;

  @override
  ConsumerState<_StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends ConsumerState<_StickerPicker> {
  String _query = '';
  String _category = StickerCatalog.allCategoryId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final catalog = ref.watch(stickerCatalogProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.lg),
          ),
        ),
        child: catalog.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (_, _) => Center(
            child: Text(
              Tr.of(
                context,
                ar: 'تعذّر تحميل الملصقات.',
                en: 'Stickers could not be loaded.',
              ),
              style: TextStyle(color: palette.textMuted),
            ),
          ),
          data: (data) {
            final items = data.search(
              _query,
              arabic: context.isRtl,
              categoryId: _category,
            );
            return Column(
              children: <Widget>[
                const SizedBox(height: Space.sm),
                Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.sm),
                  child: TextField(
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: Tr.of(
                        context,
                        ar: 'ابحث عن ملصق',
                        en: 'Search stickers',
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    children: <Widget>[
                      for (final category in data.categories)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            label: Text(
                              category.name(context.isRtl),
                              style: const TextStyle(fontSize: 10),
                            ),
                            selected: _category == category.id,
                            onSelected: (_) =>
                                setState(() => _category = category.id),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            Tr.of(context, ar: 'لا نتائج.', en: 'No results.'),
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        )
                      : GridView.builder(
                          controller: controller,
                          padding: const EdgeInsets.all(Space.sm),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                              ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final sticker = items[index];
                            return InkWell(
                              borderRadius: BorderRadius.circular(Radii.sm),
                              onTap: () =>
                                  Navigator.of(widget.sheetContext)
                                      .pop(sticker),
                              child: Image.asset(
                                sticker.assetPath,
                                fit: BoxFit.contain,
                                cacheWidth: 160,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
