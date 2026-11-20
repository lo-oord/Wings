import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:media_kit/media_kit.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/services/community_media_service.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/anime.dart';
import '../../data/models/community.dart';
import '../../data/models/user_profile.dart';
import 'community_video.dart';
import 'suggestion_panel.dart';

/// Writes one post: text, pictures, a video, or a Reel.
///
/// One screen and one document for every kind of content. Media goes to Tigris
/// through short-lived signed URLs issued by the media Worker, and the post is
/// written only after every upload succeeded, so a failed upload can never leave
/// a post pointing at a missing object. Objects uploaded for a post whose save
/// failed are deleted again.
class PostComposerScreen extends ConsumerStatefulWidget {
  const PostComposerScreen({super.key, this.initialReel = false});

  /// Opens in Reel mode (the Reels screen "create" action).
  final bool initialReel;

  @override
  ConsumerState<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends ConsumerState<PostComposerScreen> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final List<_DraftImage> _images = <_DraftImage>[];
  final List<MentionRef> _mentions = <MentionRef>[];
  final List<AnimeRef> _animeRefs = <AnimeRef>[];

  final bool _reel = false;
  String _category = '';
  bool _allowComments = true;
  _DraftVideo? _video;
  _DraftImage? _cover;

  bool _publishing = false;
  String? _stage;
  double? _progress;
  String? _failure;

  /// Keys that already reached Tigris, reused by a retry so a failed save never
  /// re-uploads tens of megabytes.
  String? _uploadedVideoKey;
  String? _uploadedCoverKey;
  List<String> _uploadedImages = const <String>[];

  Timer? _debounce;
  ActiveTrigger? _trigger;

  static const int _maxImages = 4;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasVideo => _video != null;

  bool get _canPublish =>
      !_publishing &&
      (_text.text.trim().isNotEmpty || _images.isNotEmpty || _hasVideo) &&
      (!_reel || _hasVideo);

  void _onTextChanged() {
    final trigger = detectTrigger(_text);
    if (trigger == null) {
      _debounce?.cancel();
      if (_trigger != null) setState(() => _trigger = null);
      setState(() {});
      return;
    }
    // The panel only re-queries after the member pauses typing.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _trigger = trigger);
    });
    setState(() {});
  }

  void _pickMention(UserProfile user) {
    final trigger = _trigger;
    if (trigger == null) return;
    applySuggestion(_text, trigger, '@${user.username}');
    if (!_mentions.any((item) => item.uid == user.uid)) {
      _mentions.add(MentionRef(uid: user.uid, username: user.username));
    }
    setState(() => _trigger = null);
  }

  void _pickAnime(Anime anime) {
    final trigger = _trigger;
    if (trigger == null) return;
    applySuggestion(_text, trigger, '#${anime.title}');
    if (!_animeRefs.any((item) => item.id == anime.id)) {
      _animeRefs.add(
        AnimeRef(
          id: anime.id,
          title: anime.title,
          imageUrl: anime.imageUrl ?? '',
        ),
      );
    }
    setState(() => _trigger = null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final profile = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: palette.background,
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
            focusNode: _focus,
            autofocus: !widget.initialReel,
            maxLines: null,
            minLines: 4,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
            style: context.text.bodyMedium?.copyWith(height: 1.7),
            decoration: InputDecoration(
              hintText: Tr.of(
                context,
                ar: 'شارك شيئًا مع المجتمع… اكتب @ لذكر مستخدم أو # لأنمي',
                en: 'Share something… type @ to mention someone or # for an anime',
              ),
              border: InputBorder.none,
              counterStyle: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
          if (_trigger != null)
            SuggestionPanel(
              trigger: _trigger!,
              onPickUser: _pickMention,
              onPickAnime: _pickAnime,
            ),
          if (_category.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    _category,
                    style: context.text.labelSmall?.copyWith(
                      color: palette.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          if (_mentions.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.sm),
            _Chips(
              items: <Widget>[
                for (final mention in _mentions)
                  _RefChip(
                    label: '@${mention.username}',
                    icon: Icons.alternate_email_rounded,
                    onRemove: _publishing
                        ? null
                        : () => setState(() => _mentions.remove(mention)),
                  ),
              ],
            ),
          ],
          if (_animeRefs.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.sm),
            _Chips(
              items: <Widget>[
                for (final anime in _animeRefs)
                  _RefChip(
                    label: anime.title,
                    icon: Icons.tag_rounded,
                    onRemove: _publishing
                        ? null
                        : () => setState(() => _animeRefs.remove(anime)),
                  ),
              ],
            ),
          ],
          if (_hasVideo) ...<Widget>[
            const SizedBox(height: Space.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: CommunityVideo(
                localPath: _video!.file.path,
                aspectRatio: _video!.aspect,
                startMuted: true,
                showChrome: false,
              ),
            ),
            const SizedBox(height: Space.xs),
            Row(
              children: <Widget>[
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  _video!.label,
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _publishing ? null : _pickCover,
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: Text(
                    _cover == null
                        ? Tr.of(context, ar: 'غلاف', en: 'Cover')
                        : Tr.of(
                            context,
                            ar: 'تغيير الغلاف',
                            en: 'Change cover',
                          ),
                    style: context.text.labelSmall,
                  ),
                ),
                if (!_publishing)
                  IconButton(
                    tooltip: Tr.of(context, ar: 'إزالة', en: 'Remove'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() {
                      _video = null;
                      _cover = null;
                    }),
                  ),
              ],
            ),
          ],
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
          Text(
            Tr.of(context, ar: 'نوع المنشور', en: 'Post type'),
            style: context.text.labelSmall?.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final category in const <String>[
                'نقاش',
                'سؤال',
                'خبر',
                'إبداع',
                'أنمي',
              ])
                ChoiceChip(
                  label: Text(category),
                  selected: _category == category,
                  onSelected: _publishing
                      ? null
                      : (selected) => setState(
                          () => _category = selected ? category : '',
                        ),
                  labelStyle: const TextStyle(fontSize: 10),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: <Widget>[
              FilterChip(
                avatar: const Icon(Icons.mode_comment_outlined, size: 14),
                label: Text(
                  Tr.of(context, ar: 'السماح بالتعليقات', en: 'Allow comments'),
                  style: const TextStyle(fontSize: 10),
                ),
                selected: _allowComments,
                onSelected: _publishing
                    ? null
                    : (value) => setState(() => _allowComments = value),
                visualDensity: VisualDensity.compact,
              ),
              if (!_hasVideo && !_reel)
                OutlinedButton.icon(
                  onPressed: _publishing || _images.length >= _maxImages
                      ? null
                      : _pickImages,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: Text(
                    Tr.of(
                      context,
                      ar: 'صور (${_images.length}/$_maxImages)',
                      en: 'Pictures (${_images.length}/$_maxImages)',
                    ),
                    style: context.text.labelSmall,
                  ),
                ),
              if (_images.isEmpty)
                OutlinedButton.icon(
                  onPressed: _publishing ? null : _pickVideo,
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: Text(
                    _hasVideo
                        ? Tr.of(
                            context,
                            ar: 'تغيير الفيديو',
                            en: 'Change video',
                          )
                        : Tr.of(context, ar: 'فيديو', en: 'Video'),
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
                Expanded(
                  child: Text(
                    _stage!,
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (_progress != null) ...<Widget>[
              const SizedBox(height: Space.xs),
              LinearProgressIndicator(value: _progress),
            ],
          ],
          if (_failure != null) ...<Widget>[
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: palette.danger,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      _failure!,
                      style: context.text.labelSmall?.copyWith(height: 1.5),
                    ),
                  ),
                  TextButton(
                    onPressed: _publishing ? null : _publish,
                    child: Text(Tr.of(context, ar: 'إعادة', en: 'Retry')),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          Text(
            Tr.of(
              context,
              ar:
                  'الصور والفيديوهات تُرفع بأمان إلى مساحة Wings وتُحذف مع المنشور. '
                  'الحد: ٤ صور (٥ ميجابايت) أو فيديو MP4/MOV حتى ٦٠ ثانية و٥٠ ميجابايت.',
              en:
                  'Pictures and videos upload securely to Wings storage and are removed with the post. '
                  'Limits: 4 pictures (5 MB) or one MP4/MOV video up to 60 seconds and 50 MB.',
            ),
            style: context.text.labelSmall?.copyWith(
              color: palette.textMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
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
      setState(() {
        _images.addAll(drafts);
        _video = null;
        _cover = null;
      });
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _pickCover() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (picked == null || !mounted) return;
      final compressed = await _compress(picked);
      if (compressed == null || !mounted) return;
      setState(() => _cover = compressed);
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _pickVideo() async {
    if (_publishing) return;
    try {
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 60),
      );
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      if (!file.existsSync()) {
        throw const MediaRejectedException('missing-file');
      }
      final length = await file.length();
      if (length <= 0 || length > CommunityMediaService.maxVideoBytes) {
        if (mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: 'حجم الفيديو أكبر من ٥٠ ميجابايت. اختر مقطعًا أقصر أو بجودة أقل.',
              en: 'This video is larger than 50 MB. Pick a shorter or lighter clip.',
            ),
            isError: true,
          );
        }
        return;
      }
      final probe = await _probe(file.path);
      if (!mounted) return;
      if (probe == null) {
        context.showSnack(
          Tr.of(
            context,
            ar: 'تعذّر قراءة هذا الفيديو. جرّب ملف MP4.',
            en: 'This video could not be read. Try an MP4 file.',
          ),
          isError: true,
        );
        return;
      }
      if (probe.duration > Duration(seconds: 60)) {
        context.showSnack(
          Tr.of(
            context,
            ar: 'مدة الفيديو تتجاوز ٦٠ ثانية.',
            en: 'The video is longer than 60 seconds.',
          ),
          isError: true,
        );
        return;
      }
      setState(() {
        _video = _DraftVideo(
          file: file,
          durationMs: probe.duration.inMilliseconds,
          width: probe.width,
          height: probe.height,
        );
        _images.clear();
        _cover = null;
        _uploadedVideoKey = null;
        _uploadedCoverKey = null;
      });
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  /// Reads duration and pixel size locally so the limits are enforced before
  /// anything is uploaded, and so the feed can reserve the right space.
  Future<_Probe?> _probe(String path) async {
    final player = Player();
    try {
      await player.open(Media(Uri.file(path).toString()), play: false);
      final duration = await player.stream.duration
          .firstWhere(
            (value) => value > Duration.zero,
            orElse: () => Duration.zero,
          )
          .timeout(const Duration(seconds: 8), onTimeout: () => Duration.zero);
      final width = player.state.width;
      final height = player.state.height;
      return _Probe(duration: duration, width: width ?? 0, height: height ?? 0);
    } on Object {
      return null;
    } finally {
      unawaited(player.dispose());
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
    if (_reel && !_hasVideo) {
      context.showSnack(
        Tr.of(context, ar: 'الريل يحتاج فيديو.', en: 'A reel needs a video.'),
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
      _failure = null;
      _progress = null;
      _stage = _hasVideo
          ? Tr.of(
              context,
              ar: 'جارٍ تجهيز الفيديو…',
              en: 'Preparing the video…',
            )
          : _images.isEmpty
          ? Tr.of(context, ar: 'جارٍ النشر…', en: 'Publishing…')
          : Tr.of(context, ar: 'جارٍ تجهيز الصور…', en: 'Preparing pictures…');
    });

    try {
      if (_hasVideo) {
        if (!media.available) throw const MediaUnavailableException();
        var videoKey = _uploadedVideoKey;
        if (videoKey == null) {
          final extension = _video!.file.path.toLowerCase().endsWith('.mov')
              ? 'mov'
              : 'mp4';
          final uploads = await media.createUploads(
            postId: postId,
            files: <MediaFile>[
              MediaFile(
                bytes: Uint8List(0),
                contentType: extension == 'mov'
                    ? 'video/quicktime'
                    : 'video/mp4',
                extension: extension,
                declaredSize: await _video!.file.length(),
              ),
            ],
          );
          final bytes = await _video!.file.readAsBytes();
          await media.upload(
            uploads.first,
            bytes,
            onProgress: (sent, total) {
              if (!mounted || total <= 0) return;
              setState(() {
                _stage = Tr.of(
                  context,
                  ar: 'جارٍ رفع الفيديو… ${((sent / total) * 100).round()}%',
                  en: 'Uploading the video… ${((sent / total) * 100).round()}%',
                );
                _progress = (sent / total).clamp(0.0, 1.0);
              });
            },
          );
          videoKey = uploads.first.key;
          _uploadedVideoKey = videoKey;
          uploaded.add(videoKey);
        }
        String? coverKey = _uploadedCoverKey;
        if (coverKey == null && _cover != null) {
          final uploads = await media.createUploads(
            postId: postId,
            files: <MediaFile>[
              MediaFile(
                bytes: _cover!.bytes,
                contentType: 'image/jpeg',
                extension: 'jpg',
              ),
            ],
          );
          await media.upload(uploads.first, _cover!.bytes);
          coverKey = uploads.first.key;
          _uploadedCoverKey = coverKey;
          uploaded.add(coverKey);
        }
        if (!mounted) return;
        setState(() {
          _stage = Tr.of(context, ar: 'جارٍ النشر…', en: 'Publishing…');
          _progress = null;
        });
        final id = await repo.createPost(
          author: profile,
          text: _text.text,
          id: postId,
          kind: _reel ? PostKind.reel : PostKind.post,
          videoKey: videoKey,
          videoThumbnailKey: coverKey,
          videoDurationMs: _video!.durationMs,
          videoWidth: _video!.width,
          videoHeight: _video!.height,
          mentions: List<MentionRef>.unmodifiable(_mentions),
          animeRefs: List<AnimeRef>.unmodifiable(_animeRefs),
          category: _category,
          allowComments: _allowComments,
        );
        final post = await repo.fetchPost(id);
        if (!mounted) return;
        Navigator.of(context).pop(post);
        return;
      }

      if (_images.isNotEmpty) {
        if (!media.available) throw const MediaUnavailableException();
        var keys = _uploadedImages;
        if (keys.isEmpty) {
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
          keys = <String>[];
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
            keys.add(uploads[index].key);
            uploaded.add(uploads[index].key);
          }
          _uploadedImages = keys;
        }
      }
      if (!mounted) return;
      setState(() {
        _stage = Tr.of(context, ar: 'جارٍ النشر…', en: 'Publishing…');
      });
      final id = await repo.createPost(
        author: profile,
        text: _text.text,
        imageKeys: _images.isEmpty ? const <String>[] : _uploadedImages,
        id: postId,
        mentions: List<MentionRef>.unmodifiable(_mentions),
        animeRefs: List<AnimeRef>.unmodifiable(_animeRefs),
        category: _category,
        allowComments: _allowComments,
      );
      final post = await repo.fetchPost(id);
      if (!mounted) return;
      Navigator.of(context).pop(post);
    } on Object catch (error) {
      // The post was never written, so the objects uploaded so far are orphans.
      final orphans = <String>[
        ...uploaded,
        if (_uploadedVideoKey != null && !uploaded.contains(_uploadedVideoKey))
          _uploadedVideoKey!,
        if (_uploadedCoverKey != null && !uploaded.contains(_uploadedCoverKey))
          _uploadedCoverKey!,
        if (_images.isEmpty) ..._uploadedImages,
      ];
      if (orphans.isNotEmpty) {
        unawaited(media.deleteObjects(orphans).catchError((Object _) {}));
        _uploadedVideoKey = null;
        _uploadedCoverKey = null;
        _uploadedImages = const <String>[];
      }
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _stage = null;
        _progress = null;
        _failure = _publishError(error);
      });
    }
  }

  String _publishError(Object error) {
    if (error is MediaUnavailableException) {
      return Tr.of(
        context,
        ar: 'خدمة رفع الوسائط غير متاحة الآن. أعد المحاولة لاحقًا أو انشر نصًا فقط.',
        en: 'Media upload is unavailable right now. Retry later or publish text only.',
      );
    }
    if (error is MediaRejectedException) {
      return Tr.of(
        context,
        ar: 'لم يُقبل الملف. تحقق من النوع والحجم (صور ٥ ميجابايت، فيديو ٥٠ ميجابايت).',
        en: 'The file was rejected. Check the type and size (pictures 5 MB, video 50 MB).',
      );
    }
    return userFacingError(context, error);
  }
}

class _Probe {
  const _Probe({
    required this.duration,
    required this.width,
    required this.height,
  });

  final Duration duration;
  final int width;
  final int height;
}

class _DraftVideo {
  const _DraftVideo({
    required this.file,
    required this.durationMs,
    required this.width,
    required this.height,
  });

  final File file;
  final int durationMs;
  final int width;
  final int height;

  double get aspect => (width > 0 && height > 0) ? width / height : 16 / 9;

  String get label {
    final seconds = Duration(milliseconds: durationMs).inSeconds;
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    final mb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
    return '$minutes:$rest · $mb MB';
  }
}

class _DraftImage {
  const _DraftImage({required this.bytes, required this.file});

  final Uint8List bytes;
  final File file;
}

class _Chips extends StatelessWidget {
  const _Chips({required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 6, runSpacing: 6, children: items);
}

class _RefChip extends StatelessWidget {
  const _RefChip({
    required this.label,
    required this.icon,
    required this.onRemove,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 8, end: 4, top: 3),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: palette.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: palette.primary),
          ),
          if (onRemove != null)
            InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: palette.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
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
