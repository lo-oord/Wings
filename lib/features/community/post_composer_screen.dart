import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/services/community_media_service.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_layout.dart';

/// Writes a post: text, up to four pictures, preview before publishing.
///
/// Pictures go to Tigris through short-lived signed URLs issued by the media
/// Worker; the post document is written only after every upload succeeded, so a
/// failed upload can never leave a post pointing at missing files. The objects
/// uploaded for a post whose save failed are deleted again.
class PostComposerScreen extends ConsumerStatefulWidget {
  const PostComposerScreen({super.key});

  @override
  ConsumerState<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends ConsumerState<PostComposerScreen> {
  final TextEditingController _text = TextEditingController();
  final List<_DraftImage> _images = <_DraftImage>[];
  bool _publishing = false;
  String? _stage;

  static const int _maxImages = 4;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      !_publishing && (_text.text.trim().isNotEmpty || _images.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Text(Tr.of(context, ar: 'منشور جديد', en: 'New post')),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(end: Space.sm),
            child: TextButton(
              onPressed: _canPublish ? _publish : null,
              child: _publishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      Tr.of(context, ar: 'نشر', en: 'Publish'),
                      style: context.text.labelMedium?.copyWith(
                        color: _canPublish
                            ? palette.primary
                            : palette.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 120),
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: palette.surfaceAlt,
                child: Text(
                  (profile?.displayName.trim().isNotEmpty ?? false)
                      ? profile!.displayName.trim().characters.first
                      : '?',
                  style: context.text.titleSmall?.copyWith(
                    color: palette.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: Space.sm + 2),
              Expanded(
                child: Text(
                  profile?.displayName ?? '',
                  style: context.text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _text,
            autofocus: true,
            maxLines: null,
            minLines: 5,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
            onChanged: (_) => setState(() {}),
            style: context.text.bodyMedium?.copyWith(height: 1.7),
            decoration: InputDecoration(
              hintText: Tr.of(
                context,
                ar: 'بماذا تفكر؟ شارك المجتمع…',
                en: 'What is on your mind? Share with the community…',
              ),
              border: InputBorder.none,
              counterStyle: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
          if (_images.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.sm),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: Space.sm,
              crossAxisSpacing: Space.sm,
              children: <Widget>[
                for (var index = 0; index < _images.length; index++)
                  _PreviewTile(
                    image: _images[index],
                    onRemove: _publishing
                        ? null
                        : () => setState(() => _images.removeAt(index)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.md),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _publishing || _images.length >= _maxImages
                    ? null
                    : _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(
                  Tr.of(
                    context,
                    ar: 'إضافة صور (${_images.length}/$_maxImages)',
                    en: 'Add pictures (${_images.length}/$_maxImages)',
                  ),
                  style: context.text.labelSmall,
                ),
              ),
            ],
          ),
          if (_stage != null) ...<Widget>[
            const SizedBox(height: Space.md),
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: Space.sm),
                Text(
                  _stage!,
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Space.md),
          Text(
            Tr.of(
              context,
              ar: 'الصور تُرفع بأمان إلى مساحة Wings. تُحذف تلقائيًا مع المنشور.',
              en: 'Pictures are uploaded securely to Wings storage and are removed with the post.',
            ),
            style: context.text.labelSmall?.copyWith(
              color: palette.textMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
      backgroundColor: palette.background,
    );
  }

  Future<void> _pickImages() async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) return;
    try {
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 88,
        maxWidth: 1600,
      );
      if (picked.isEmpty || !mounted) return;
      final drafts = <_DraftImage>[];
      for (final file in picked.take(remaining)) {
        final compressed = await _compress(file);
        if (compressed == null) continue;
        drafts.add(compressed);
      }
      if (!mounted) return;
      setState(() => _images.addAll(drafts));
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  /// Keeps an upload comfortably under the Worker's 5 MiB limit without
  /// touching the original quality more than necessary.
  Future<_DraftImage?> _compress(XFile file) async {
    const target = 900 * 1024;
    var quality = 82;
    var width = 1440;
    for (var attempt = 0; attempt < 5; attempt++) {
      final bytes = await FlutterImageCompress.compressWithFile(
        file.path,
        minWidth: width,
        minHeight: width,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (bytes == null) return null;
      if (bytes.length <= target) {
        return _DraftImage(bytes: bytes, file: File(file.path));
      }
      quality = (quality - 10).clamp(45, 88);
      width = (width * 0.8).round();
      if (width < 640) break;
    }
    return null;
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final profile = ref.read(profileProvider);
    final uid = ref.read(authProvider)?.id;
    if (profile == null || uid == null) {
      context.showSnack(
        Tr.of(context, ar: 'سجّل الدخول أولًا.', en: 'Sign in first.'),
        isError: true,
      );
      return;
    }
    final repo = ref.read(communityRepositoryProvider);
    final media = ref.read(communityMediaProvider);
    final postId = repo.newPostId();
    final uploaded = <String>[];
    setState(() {
      _publishing = true;
      _stage = _images.isEmpty
          ? Tr.of(context, ar: 'جارٍ النشر…', en: 'Publishing…')
          : Tr.of(context, ar: 'جارٍ تجهيز الصور…', en: 'Preparing pictures…');
    });
    try {
      if (_images.isNotEmpty) {
        if (!media.available) {
          throw const MediaUnavailableException();
        }
        final uploads = await media.createUploads(
          postId: postId,
          files: <MediaFile>[
            for (final image in _images)
              MediaFile(
                bytes: image.bytes,
                contentType: 'image/jpeg',
                extension: 'jpg',
              ),
          ],
        );
        for (var index = 0; index < uploads.length; index++) {
          if (!mounted) return;
          setState(() {
            _stage = Tr.of(
              context,
              ar: 'جارٍ رفع الصورة ${index + 1} من ${uploads.length}…',
              en: 'Uploading picture ${index + 1} of ${uploads.length}…',
            );
          });
          await media.upload(uploads[index], _images[index].bytes);
          uploaded.add(uploads[index].key);
        }
      }
      if (!mounted) return;
      setState(() {
        _stage = Tr.of(context, ar: 'جارٍ النشر…', en: 'Publishing…');
      });
      final id = await repo.createPost(
        author: profile,
        text: _text.text,
        imageKeys: uploaded,
        id: postId,
      );
      final post = await repo.fetchPost(id);
      if (!mounted) return;
      Navigator.of(context).pop(post);
    } on Object catch (error) {
      // The post was never written, so the uploaded objects are orphans.
      if (uploaded.isNotEmpty) {
        unawaited(media.deleteObjects(uploaded).catchError((Object _) {}));
      }
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _stage = null;
      });
      context.showSnack(_publishError(error), isError: true);
    }
  }

  String _publishError(Object error) {
    if (error is MediaUnavailableException) {
      return Tr.of(
        context,
        ar: 'خدمة رفع الصور غير متاحة الآن. جرّب النشر بدون صور أو أعد المحاولة لاحقًا.',
        en: 'Picture upload is unavailable right now. Try publishing without pictures or retry later.',
      );
    }
    if (error is MediaRejectedException) {
      return Tr.of(
        context,
        ar: 'لم تُقبل إحدى الصور. اختر صورة أصغر (حتى 5 ميجابايت) بصيغة JPG أو PNG.',
        en: 'One of the pictures was rejected. Choose a smaller JPG or PNG (up to 5 MB).',
      );
    }
    return userFacingError(context, error);
  }
}

class _DraftImage {
  const _DraftImage({required this.bytes, required this.file});

  final Uint8List bytes;

  /// Kept so the preview reads the freshly compressed bytes.
  final File file;
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.image, this.onRemove});

  final _DraftImage image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Image.memory(image.bytes, fit: BoxFit.cover),
        ),
        if (onRemove != null)
          PositionedDirectional(
            top: 4,
            end: 4,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
